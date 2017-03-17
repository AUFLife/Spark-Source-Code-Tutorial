## Spark任务调度策略

### 摘要

Spark的调度策略目前有两种，一种是FIFO即先到先得，一种是Fair即使公平策略。所谓的调度策略实际上是对待调度的对象进行排序，按照优先级来进行调度。调度的接口顺序如下所示，就是对两个可调度的对象进行比较。


从代码角度看，SchedulableBuilder有FIFO和Fair两种实现，addTaskSetManager会把TaskSetManager加到pool中。FIFO的话只有一个pool，Fair有多个pool，Pool也分FIFO和Fair两种模式。

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

```
// FIFO排序的实现，主要因素是优先级、其次是对应的StageId
// 优先级
private[spark] class FIFOSchedulingAlgorithm extends SchedulingAlgorithm {
  override def comparator(s1: Schedulable, s2: Schedulable): Boolean = {
    val priority1 = s1.priority
    val priority2 = s2.priority
    var res = math.signum(priority1 - priority2)
    if (res == 0) {
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



## 参考资料	
[Spark的调度策略详解](https://yq.aliyun.com/articles/6041)
[Spark任务调度策略](http://www.cnblogs.com/barrenlake/p/4891589.html)