### 部署过程详解 {#24}

Spark布置环境中组件构成如下图所示。

![](http://spark.apache.org/docs/latest/img/cluster-overview.png "Spark cluster components")

* **Driver Program**
  简要来说在spark-shell中输入的wordcount语句对应于上图的Driver Program.
* **Cluster Manager **
  就是对应于上面提到的master，主要起到deploy management的作用
* **Worker Node **
  与Master相比，这是slave node。上面运行各个executor，executor可以对应于线程。executor处理两种基本的业务逻辑，一种就是driver programme,另一种就是job在提交之后拆分成各个stage，每个stage可以运行一到多个task

**Notes:**

在集群\(cluster\)方式下, Cluster Manager运行在一个**jvm**进程之中，而worker运行在另一个**jvm**进程中。在local cluster中，这些jvm进程都在同一台机器中，如果是真正的standalone或Mesos及Yarn集群，worker与master或分布于不同的主机之上。

### Job Stage划分算法

1. Spark Application中可以为不同的Action触发众

job的生成的简单流程如下：

* 首先应用程序创建SparkContext的实例，如实例为sc
* 利用SparkContext 的实例来创建生成RDD
* 经过一连串的transformation操作，原始的RDD转换成其它类型的RDD
* 当action作用于转换之后的RDD时，会调用SparkContext的runJob方法
* sc.runJobd的调用是后面一连串的反应的起点，关键性的跃变就发生在此处

调用过程大致如下：

* sc.runJob -&gt; dagScheduler.runJob -&gt; submitJob
  * SparkContext.runJob\(rdd, cleanedFunc, partitions, callSite, resultHandler, localProperties.get\),首先获取rdd的partitions.length，来得到finalRDD中应该存在的partition的个数和类型：Array\[Partition\]
  * cleanedFunc是partition经过闭包清理后的结果，这样可以被序列化后传递给不同的节点的task.
* dagScheduler.runJob -&gt; submitJob
   首先获取一个jobId，并返回JobWaiter对象用于监听job的执行状态（Submit a job to the job scheduler and get a JobWaiter object back. The JobWaiter object can be use to block until the job finishes executing or can be used to cancen the job）然后再次包装func。
* DAGSchedulerEventProcessLoop.onReceive
  * 引入事件机制DAGSchedulerEventProcessLoop\(this\)实例
* DAGScheduler.handleJobSubmitted\(\)
  * job到Staged的转换，生成了findStage并提交运行，关键是调用submitStage
* dagScheduler.submitStage -&gt; 计算Stage之间的依赖关系，依赖关系分为宽依赖和窄依赖。并且会递归提交缺失依赖的父Stage；
* dagScheduler.submitMissingTasks -&gt; 如果计算中发现当前Stage1父依赖是可用的，并且我们现在可以调用它的tasks；
* TaskSchedulerImpl.submitTasks -&gt; TaskSchedulerImpl会根据Spark当前运行模式来创建对应的backend，如果是在单机运行则创建LocalBackend，如果是集群运行创建SparkDeploySchedulerBackend，如果是spark-submit方式创建YarnSchedulerBackend；
* 这里需要说下task任务的启动流程，Backend收到TaskSchedulerImpl传递进来的ReceiveOffers事件

  * LocalBackend：  
    executor.launchTask -&gt; 实际上声明了一个ConcurrHashMap来存放taskId和新创建的TaskRunner =&gt;  
      TaskRunner.run\(\)

    receiveOffers-&gt;executor.launchTask-&gt;TaskRunner.run  
    代码片段executor.lauchTask

    ```
    def launchTask(context: ExecutorBackend, taskId: Long, serializedTask: ByteBuffer) {

      val tr = new TaskRunner(context, taskId, serializedTask)
        runningTasks.put(taskId, tr)
        threadPool.execute(tr)
     }
    }
    ```

  * SparkDeploySchedulerBackend：见TaskScheduler

  * YarnSchedulerBackend: 见TaskScheduler

说了这么一大通，也就是讲最终的逻辑处理切切实实是发生在TaskRunner这么一个executor之内。

运算结果是包装成为MapStatus然后通过一系列的内部消息传递，反馈到DAGScheduler，这一个消息传递路径不是过于复杂，有兴趣可以自行勾勒。

---

ShuffleMapTask，ResultTask计算结果的传递

* ShuffleMapTask将计算的状态（注意不是具体的数据）包装为MapStatus返回给DAGScheduler

* DAGScheduler将MapStatus保存到MapOutputTrackerMaster中

* ResultTask在执行到ShuffleRDD时会调用BlockStoreShuffle的fetch方法

  * ResultTask在执行到ShuffleRDD时会调用BlockStoreShffleTetcher的fetch方法获取数据。

  * 第一件事就是咨询MapOutputTrackerMaster所要取的数据的location

  * 根据返回的结果调用BlockManager.getMultiple获取真正的数据



