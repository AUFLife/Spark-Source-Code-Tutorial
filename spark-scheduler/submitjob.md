###  {#24}

### 部署过程详解{\#24}

Spark布置环境中组件构成如下图所示。

![](http://spark.apache.org/docs/latest/img/cluster-overview.png)

* **Driver Program**简要来说在spark-shell中输入的wordcount语句对应于上图的Driver Program.

* **Cluster Manager**就是对应于上面提到的master，主要起到deploy management的作用

* **Worker Node**与Master相比，这是slave node。上面运行各个executor，executor可以对应于线程。executor处理两种基本的业务逻辑，一种就是driver programme,另一种就是job在提交之后拆分成各个stage，每个stage可以运行一到多个task

**Notes:**

在集群\(cluster\)方式下, Cluster Manager运行在一个**jvm**进程之中，而worker运行在另一个**jvm**进程中。在local cluster中，这些jvm进程都在同一台机器中，如果是真正的standalone或Mesos及Yarn集群，worker与master或分布于不同的主机之上。

### J\# ob Stage划分算法

1. Spark Application中可以因为不同的Action触发众多的Job，也就是一个Application中可以有很多Job，每个Job是由一个或多个Stage构成的，后面的Stage依赖前面的Stage；也就是说只有前面依赖的Stage计算完毕后，后面的Stage才会运行；

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224191355445-1507007778.png)

2. Stage划分的依据就是`宽依赖`，从后往前推，遇到宽依赖，就划分为一个stage。

3. 由Action操作（例如collect）导致了SparkContext.runJob最终导致了DAGScheduler中submitJob的执行

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185032366-2008839481.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185130460-1464326176.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185451757-986646851.png)

#### DagScheduler:

![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185553491-27783972.png)

这里会等待作业提交的结果，然后判断成功或失败来进行下一步操作。

1. 其核心是通过发送一个case class JobSubmitted 对象给eventProcessLoop

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185800820-484469795.png)

   其中JobSubmitted源码如下：因为需要创建不同的示例，所以需要弄一个case class而不是case object，case object 一般是以全区唯一的变量去使用。

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185843070-1669082775.png)

2. 这里单独开了一条线程，以post的方式把消息放在队列中，由于你把它放在队列中它就会不断的去拿消息并进行处理，而后调用回掉函数onReceive\(\)， eventProcessLoop是一个消息循环器，它是DAGScheduler的具体实例，eventLoop是一个Link的blockQueue。

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185916304-1558055593.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185951226-104855772.png)

   而DAGSchedulerEventProcessLoop是EventLoop的子类，具体实现eventLoop的onReceive方法，onReceive -&gt; doOnReceive

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224190126179-2052311278.png)

3. 在doOnReceive这个类中有接收JobSubmitted的判断，进而调用handleJobSubmitted 方法

思考题：为什么要再打开一条线程搞一个消息循环器呢，因为队列可以接受多个作业提交即异步处理多job，这里背后有一个很重要的概念，就是无论是你自己发消息，还是别人发消息，你都采用一个线程处理的话，这个处理的方式是统一的，思路是清晰的。

### 处理Job的内容和逻辑

handleJobSubmitted\(\) -&gt;

1. 在handleJobSubmitted方法中首先创建finalStage，创建finalStage时会建立父Stage的依赖链条

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224190655085-2097917239.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224193937585-1908461785.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224190801304-937514731.png)

   如果之前没有visited就把rdd放在visited的数据结构中，然后判断一下它的依赖关系，如果是宽依赖的话就新增一个Stage

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224190816460-124976008.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224190944163-1185239540.png)

   因此可以发现，Stage划分是由当前触发runJob的Action操作开始，从后向前递归进行计数的过程

### 处理missingParent

1. 处理missingParent

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224195521648-756781612.png)

### Task 最佳位置算法实现

1. 从submitMissingTask开始找出它的数据本地算法

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224210817366-759206972.png)

2. 在具体算法实现时，首先会查询DAGScheduler的内存数据结构中是否存在当前partition的数据本地性的信息，如果有的话就直接返回；如果没有首先会调用rdd.getPreferredLocations。例如想让Spark运行在HBase上或者一种现在还没有直接使用的数据库上面，此时开发者需要自定义RDD，为了保证Task的数据本地性，最为关键的方法就是实现getPreferredLocations。

   在获取到taskId与数据本地位置的关系后，将任务所需资源序列化。而后根据task的类型分别新建ShuffleMapStage和ResultTask

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224210903195-1359570705.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224210933023-699015420.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224211121538-1387083487.png)

3. DAGScheduler计算数据本地性的时候，巧妙的借助了RDD自身的getPreferredLocations中的数据，最大化的优化了效率，因为getPreferredLocations中表明了每个Partition的数据本地性，虽然当前Partition可能被persists或者是checkpoint，但是persists或者是checkpoint默认情况下肯定是和getPreferredLocations中的数据本地性是一致的，（getPreferredLocations方法就更简单了，直接调用InputSplit的getLocations方法获得所在的位置。

4. ）所以这就更大的优化了Task的数据本地性算法的显现和效率的优化

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224211202523-1240376747.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224211840273-1354488752.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224212558507-1967242857.png)

---

ShuffleMapTask，ResultTask计算结果的传递

* ShuffleMapTask将计算的状态（注意不是具体的数据）包装为MapStatus返回给DAGScheduler

* DAGScheduler将MapStatus保存到MapOutputTrackerMaster中

* ResultTask在执行到ShuffleRDD时会调用BlockStoreShuffle的fetch方法

  * ResultTask在执行到ShuffleRDD时会调用BlockStoreShffleTetcher的fetch方法获取数据。

  * 第一件事就是咨询MapOutputTrackerMaster所要取的数据的location

  * 根据返回的结果调用BlockManager.getMultiple获取真正的数据

部署过程详解{\#24}

Spark布置环境中组件构成如下图所示。

![](http://spark.apache.org/docs/latest/img/cluster-overview.png)

* **Driver Program**简要来说在spark-shell中输入的wordcount语句对应于上图的Driver Program.

* **Cluster Manager**就是对应于上面提到的master，主要起到deploy management的作用

* **Worker Node**与Master相比，这是slave node。上面运行各个executor，executor可以对应于线程。executor处理两种基本的业务逻辑，一种就是driver programme,另一种就是job在提交之后拆分成各个stage，每个stage可以运行一到多个task

**Notes:**

在集群\(cluster\)方式下, Cluster Manager运行在一个**jvm**进程之中，而worker运行在另一个**jvm**进程中。在local cluster中，这些jvm进程都在同一台机器中，如果是真正的standalone或Mesos及Yarn集群，worker与master或分布于不同的主机之上。

### Job Stage划分算法

1. Spark Application中可以因为不同的Action触发众多的Job，也就是一个Application中可以有很多Job，每个Job是由一个或多个Stage构成的，后面的Stage依赖前面的Stage；也就是说只有前面依赖的Stage计算完毕后，后面的Stage才会运行；

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224191355445-1507007778.png)

2. Stage划分的依据就是`宽依赖`，从后往前推，遇到宽依赖，就划分为一个stage。

3. 由Action操作（例如collect）导致了SparkContext.runJob最终导致了DAGScheduler中submitJob的执行

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185032366-2008839481.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185130460-1464326176.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185451757-986646851.png)

#### DagScheduler:

![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185553491-27783972.png)

这里会等待作业提交的结果，然后判断成功或失败来进行下一步操作。

1. 其核心是通过发送一个case class JobSubmitted 对象给eventProcessLoop

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185800820-484469795.png)

   其中JobSubmitted源码如下：因为需要创建不同的示例，所以需要弄一个case class而不是case object，case object 一般是以全区唯一的变量去使用。

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185843070-1669082775.png)

2. 这里单独开了一条线程，以post的方式把消息放在队列中，由于你把它放在队列中它就会不断的去拿消息并进行处理，而后调用回掉函数onReceive\(\)， eventProcessLoop是一个消息循环器，它是DAGScheduler的具体实例，eventLoop是一个Link的blockQueue。

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185916304-1558055593.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224185951226-104855772.png)

   而DAGSchedulerEventProcessLoop是EventLoop的子类，具体实现eventLoop的onReceive方法，onReceive -&gt; doOnReceive

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224190126179-2052311278.png)

3. 在doOnReceive这个类中有接收JobSubmitted的判断，进而调用handleJobSubmitted 方法

思考题：为什么要再打开一条线程搞一个消息循环器呢，因为队列可以接受多个作业提交即异步处理多job，这里背后有一个很重要的概念，就是无论是你自己发消息，还是别人发消息，你都采用一个线程处理的话，这个处理的方式是统一的，思路是清晰的。

### 处理Job的内容和逻辑

handleJobSubmitted\(\) -&gt;

1. 在handleJobSubmitted方法中首先创建finalStage，创建finalStage时会建立父Stage的依赖链条

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224190655085-2097917239.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224193937585-1908461785.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224190801304-937514731.png)

   如果之前没有visited就把rdd放在visited的数据结构中，然后判断一下它的依赖关系，如果是宽依赖的话就新增一个Stage

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224190816460-124976008.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224190944163-1185239540.png)

   因此可以发现，Stage划分是由当前触发runJob的Action操作开始，从后向前递归进行计数的过程

### 处理missingParent

1. 处理missingParent

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224195521648-756781612.png)

### Task 最佳位置算法实现

1. 从submitMissingTask开始找出它的数据本地算法

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224210817366-759206972.png)

2. 在具体算法实现时，首先会查询DAGScheduler的内存数据结构中是否存在当前partition的数据本地性的信息，如果有的话就直接返回；如果没有首先会调用rdd.getPreferredLocations。例如想让Spark运行在HBase上或者一种现在还没有直接使用的数据库上面，此时开发者需要自定义RDD，为了保证Task的数据本地性，最为关键的方法就是实现getPreferredLocations。

   在获取到taskId与数据本地位置的关系后，将任务所需资源序列化。而后根据task的类型分别新建ShuffleMapStage和ResultTask

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224210903195-1359570705.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224210933023-699015420.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224211121538-1387083487.png)

3. DAGScheduler计算数据本地性的时候，巧妙的借助了RDD自身的getPreferredLocations中的数据，最大化的优化了效率，因为getPreferredLocations中表明了每个Partition的数据本地性，虽然当前Partition可能被persists或者是checkpoint，但是persists或者是checkpoint默认情况下肯定是和getPreferredLocations中的数据本地性是一致的，（getPreferredLocations方法就更简单了，直接调用InputSplit的getLocations方法获得所在的位置。

4. ）所以这就更大的优化了Task的数据本地性算法的显现和效率的优化

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224211202523-1240376747.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224211840273-1354488752.png)

   ![](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170224212558507-1967242857.png)

---

ShuffleMapTask，ResultTask计算结果的传递

* ShuffleMapTask将计算的状态（注意不是具体的数据）包装为MapStatus返回给DAGScheduler

* DAGScheduler将MapStatus保存到MapOutputTrackerMaster中

* ResultTask在执行到ShuffleRDD时会调用BlockStoreShuffle的fetch方法

  * ResultTask在执行到ShuffleRDD时会调用BlockStoreShffleTetcher的fetch方法获取数据。

  * 第一件事就是咨询MapOutputTrackerMaster所要取的数据的location

  * 根据返回的结果调用BlockManager.getMultiple获取真正的数据



