## Spark任务调度策略

### 摘要

Spark的调度策略目前有两种，一种是FIFO即先到先得，一种是Fair即使公平策略。所谓的调度策略实际上是对待调度的对象进行排序，按照优先级来进行调度。调度的接口顺序如下所示，就是对两个可调度的对象进行比较。

下面从源码的角度对调度策略进行说明:

### 本地性
当触发调度时，会调用TaskSchedulImpl的resourceOffers, 方法中会依照调度策略选出要执行的taskSet，然后取出适合（考虑本地性）的task交由Executor执行，其代码如下：
```
	 /**
   * Called by cluster manager to offer resources on slaves. We respond by asking our active task
   * sets for tasks in order of priority. We fill each node with tasks in a round-robin manner so
   * that tasks are balanced across the cluster.
   */
  def resourceOffers(offers: Seq[WorkerOffer]): Seq[Seq[TaskDescription]] = synchronized {
    // Mark each slave as alive and remember its hostname
    // Also track if new executor is added
    var newExecAvail = false
    for (o <- offers) {
      executorIdToHost(o.executorId) = o.host
      activeExecutorIds += o.executorId
      if (!executorsByHost.contains(o.host)) {
        executorsByHost(o.host) = new HashSet[String]()
        executorAdded(o.executorId, o.host)
        newExecAvail = true
      }
      for (rack <- getRackForHost(o.host)) {
        hostsByRack.getOrElseUpdate(rack, new HashSet[String]()) += o.host
      }
    }

    // Randomly shuffle offers to avoid always placing tasks on the same set of workers.
    val shuffledOffers = Random.shuffle(offers)
    // Build a list of tasks to assign to each worker.
    val tasks = shuffledOffers.map(o => new ArrayBuffer[TaskDescription](o.cores))
    val availableCpus = shuffledOffers.map(o => o.cores).toArray
    val sortedTaskSets = rootPool.getSortedTaskSetQueue
    for (taskSet <- sortedTaskSets) {
      logDebug("parentName: %s, name: %s, runningTasks: %s".format(
        taskSet.parent.name, taskSet.name, taskSet.runningTasks))
      if (newExecAvail) {
        taskSet.executorAdded()
      }
    }

    // Take each TaskSet in our scheduling order, and then offer it each node in increasing order
    // of locality levels so that it gets a chance to launch local tasks on all of them.
    // NOTE: the preferredLocality order: PROCESS_LOCAL, NODE_LOCAL, NO_PREF, RACK_LOCAL, ANY
    var launchedTask = false
    for (taskSet <- sortedTaskSets; maxLocality <- taskSet.myLocalityLevels) {
      do {
        launchedTask = resourceOfferSingleTaskSet(
            taskSet, maxLocality, shuffledOffers, availableCpus, tasks)
      } while (launchedTask)
    }

    if (tasks.size > 0) {
      hasLaunchedTask = true
    }
    return tasks
  }

```

经分析可知，通过rootPool.getSortedTaskSetQueue对队列中的TaskSet进行排序，getSortedTaskSetQueue的具体实现如下：
```
  override def getSortedTaskSetQueue: ArrayBuffer[TaskSetManager] = {
    var sortedTaskSetQueue = new ArrayBuffer[TaskSetManager]
    val sortedSchedulableQueue =
      schedulableQueue.toSeq.sortWith(`taskSetSchedulingAlgorithm.comparator`)
    for (schedulable <- sortedSchedulableQueue) {
      sortedTaskSetQueue ++= schedulable.getSortedTaskSetQueue
    }
    sortedTaskSetQueue
  }
```
有上述代码可知，其通过算法作为比较器对taskSet进行排序，其中调度算法有FIFO和FAIR两种，下面分别进行介绍



SchedulableBuilder有FIFO和Fair两种实现，addTaskSetManager会把TaskSetManager加到pool中。FIFO的话只有一个pool，Fair有多个pool，Pool也分FIFO和Fair两种模式。

 ```
	/**
	 * An interface to build Schedulable tree
	 * buildPools: build the tree nodes(pools)
	 * addTaskSetManager: build the leaf nodes(TaskSetManagers)
	 */
	private[spark] trait SchedulableBuilder {
	  def rootPool: Pool

	  def buildPools()

	  def addTaskSetManager(manager: Schedulable, properties: Properties)
	}

 ```

下面是排序的算法：
```
private[spark] trait SchedulingAlgorithm {
	def comparator(s1: Schedulable, s2: Schedulable): Boolean
}
```
其实现类为FIFOSchedulingAlgorithm、FairSchedulingAlgorithm


### FIFO
FIFO(先进先出)方式调度job，如下图所示，每个job被切分成多个Stage，第一个job优先获取所有可用资源，接下来第二个job再获取剩余可用资源。（`每个Stage对应一个TaskSetManager`）
	
	优先级（Priority）：在DAGScheduler创建TaskSet时使用JobId作为优先级的值
	FIFO调度算法如下所示：

```
// FIFO排序的实现，主要因素是优先级、其次是对应的StageId
// priority（jobId）小的靠前，优先级相同，则靠前的Stage优先
private[spark] class FIFOSchedulingAlgorithm extends SchedulingAlgorithm {
  override def comparator(s1: Schedulable, s2: Schedulable): Boolean = {
  	// priority实际上是jobid，越早提交的作业，id越小，优先级越高
    val priority1 = s1.priority
    val priority2 = s2.priority
    var res = math.signum(priority1 - priority2)
    if (res == 0) {
    	// 如果优先级相同，那么Stage靠前的优先
      val stageId1 = s1.stageId
      val stageId2 = s2.stageId
      res = math.signum(stageId1 - stageId2)
    }
    if (res < 0) {
      true
    } else {
      false
    }
  }
}

```

### FAIR
FAIR在共享模式下，Spark以多Job之间轮询的方式为任务分配资源，所有任务拥有大致相当的优先级来共享集群的资源。FAIR调度模型如下图：
Fair调度队列相比FIFO较复杂，其可存在多个调度队列，且队列呈树型结构(现阶段Spark的Fair调度只支持两层树结构)，每用户可以使用sc.setLocalProperty(“spark.scheduler.pool”, “poolName”)来指定要加入的队列，默认情况下会加入到buildDefaultPool。每个队列中还可指定自己内部的调度策略，且Fair还存在一些特殊的属性：

```
private[spark] class FairSchedulingAlgorithm extends SchedulingAlgorithm {
  override def comparator(s1: Schedulable, s2: Schedulable): Boolean = {
  	// 最小共享，可以理解为执行需要的最小资源（cpu核数）
    val minShare1 = s1.minShare
    val minShare2 = s2.minShare
    // 正在运行的任务的数量
    val runningTasks1 = s1.runningTasks
    val runningTasks2 = s2.runningTasks
    // 是否饥饿状态 = 正在运行task数 < 最小共享数量
    val s1Needy = runningTasks1 < minShare1
    val s2Needy = runningTasks2 < minShare2

    // 最小资源占用比例，这里可以理解为偏向任务较轻的
    val minShareRatio1 = runningTasks1.toDouble / math.max(minShare1, 1.0).toDouble
    val minShareRatio2 = runningTasks2.toDouble / math.max(minShare2, 1.0).toDouble

    // 权重，任务数量相同，权重高的优先
    val taskToWeightRatio1 = runningTasks1.toDouble / s1.weight.toDouble
    val taskToWeightRatio2 = runningTasks2.toDouble / s2.weight.toDouble
    var compare: Int = 0

    // 挨饿的优先
    if (s1Needy && !s2Needy) {
      return true
    } else if (!s1Needy && s2Needy) {
      return false
    } else if (s1Needy && s2Needy) {
    	// 都处于挨饿状态，则需要资源占用比 小的优先（如果min1 > min2 返回1，则compare > 0，）
      compare = minShareRatio1.compareTo(minShareRatio2)
    } else {
    	// 都不挨饿， 则按照权重比选择，先行调度权重比小的（这里如果权重比相同，也会选择StageId小的进行调度，name="TaskSet_" + taskSet.StageId.toString）
      compare = taskToWeightRatio1.compareTo(taskToWeightRatio2)
    }

    if (compare < 0) {
      true
    } else if (compare > 0) {
      false
    } else {
    	// 如果都一样，那么比较名字，按照字母顺序比较，不考虑长度，所以名字比较重要
      s1.name < s2.name
    }
  }
}
```


## 参考资料	
[Spark的调度策略详解](https://yq.aliyun.com/articles/6041)
[Spark任务调度策略](http://www.cnblogs.com/barrenlake/p/4891589.html)