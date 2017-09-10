### BlockManager架构原理、运行流程图和源码解密

#### 引言

BlockManager是管理整个Spark运行时数据读写的，当然也包含数据存储本身，在这个基础之上进行读写操作，由于Spark本身是分布式的，所以BlockManager的。

* BlockManager运行实例
* BlockManager原理流程图
* BlockManager源码解析

### BlockManager原理流程图

\[下图是BlockManager原理流程图\]

![](/assets/import_blockmanager.png)BlockManager 运行實例

**从 Application 启动的角度来观察BlockManager**

1. 在 Application 启动的时候会在 spark-env.sh 中注册 BlockMangerMaster 以及 MapOutputTracker，其中：
   * BlockManagerMaster：对整集群的 Block 数据进行管理；
   * MapOutputTracker：跟踪所有的 Mapper 的输出；
2. BlockManagerMasterEndpoint 本身是一个消息体，会负责通过远程消息通信的方式去管理所有节点的 BlockManager；
3. 每个启动一个 ExecutorBackend 都会实例化 BlockManager 并通过远程通信的方式注册给 BlockMangerMaster；实际上是 Executor 中的 BlockManager 注册给 Driver 上的 BlockMangerMasterEndpoiont；\(BlockManger 是 Driver 中的一个普通的对象而己，所以无法直接对一个对象做HA\)
4. MemoryStore 是 BlockManager 中专门负责内存数据存储和读写的类，MemoryStore 是以 一个又一个 Block 为单位的
5. DiskStore 是 BlockManager 中专门负责磁盘数据存储和读写的类；
6. DiskBlockManager：管理 LogicalBlock 与 Disk 上的 PhysicalBlock 之间的映射关联并负责磁盘的文件的创建，读写等;

\[下图是 Spark-Shell 启动时的日志信息-1\]

![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170305223419313-437294750.png)  
\[下图是 Spark-Shell 启动时的日志信息-2\]

![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170305225635751-1295725377.png)

**从 Job 运行的角度来观察BlockManager**

1. 首先通过 MemoryStore 来存储广播变量
2. 在 Driver 中是通过 BlockManagerInfo 来管理集群中每个 ExecutorBackend 中的 BlockManager 中的元数据信息的;
3. 当改变了具体的 ExecutorBackend 上的 Block 的信息后就必需发消息给 Driver 中的 BlockManagerMaster 来更新相应的 BlockManagerInfo 的信息
4. 当执行第二个 Stage 之后，第二个 Stage 会向 Driver 中的 MapOutputTrackerMasterEndpoint 发消息请求上一個 Stage 中相应的输出，此時 MapOutputTrackerMaster 会把上一個 Stage 的输出数据的元数据信息发送给当前请求的 Stage  

\[下图是 Spark-Shell 作业运行时的日志信息-1\]

![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170305230827157-512381953.png)

\[下图是 Spark-Shell 作业运行时的日志信息-2\]

![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170305230908048-543117547.png)



## BlockManager 源码解析

1. BlockManager 会运行在 driver 和 Executor 上面，在 driver 上面的 BlockManager 是负责管理整个集群所有 Executor 中的 BlockManager，BlockManager 本身也是 Master-Slave 结构的，所谓Master-Slave 结构就是一切的调度和工作都是由 Master 去触发的，Slave本身就是专注于干活的，而 Executor 在启动的时候，一定会实例化 BlockManager。
    \[下图是 Executor.scala 中调用 blockManager.initialize 方法的实现\]![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170306002349407-1830788010.png) 
   \[下图是 SparkContext.scala 中调用 blockManager.initialize 方法的实现\]![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170306013334141-206334728.png)
   BlockManager主要提供了读取和写数据的接口，可以从本地或者是远程读取和写数据，读写数据可以基于
   **内存、磁盘或者是堆外空间**
   \(OffHeap\)。如果想使用 BlockManager 的话，必须调用 initialize 方法。
   程序进行 Shuffle 的时候是通过 BlockManager 去管理的。

   \[下图是 BlockManager.scala 中 BlockManager 类\]![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170306000935141-1514081872.png)
2. 基于应用程序的 AppId 去初始化 BlockManager，这个 initialize 方法也会启动 BlockTransferService 和 ShuffleClient，同时注册 BlockManagerMaster，启动 BlockManagerWorker endpoint，
   **当 Executor 实例化的时候会通过 BlockManager.initialize 来实例化 Executor 上的 BlockManager**
   并且会创建 BlockManagerSlaveEndpoint 这个消息循环体来接受 Driver 中的 BlockManagerMaster 发过来的指令，例如删除 Block 的指令。 当 BlockManagerSlaveEndpoint 实例化后，Executor 上的 BlockManager 需要向 Driver 上的 BlockManagerMasterEndpoint 注册
    \[下图是 BlockManager.scala 中 initialize 方法\]![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170306002826548-1475629642.png) 
   \[下图是 BlockManager.scala 中 slaveEndpoint 变量\]![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170306003016360-699183491.png)
   \[下图是 BlockManagerMaster.scala 中 registerBlockManager 方法\]![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170306001932329-5664030.png) 
   \[下图是 BlockManagerMessage.scala 中 RegisterBlockManager case class\]
   ![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170306003452329-288177614.png)
3. 发送消息到 BlockManagerSlaveEndpoint
    \[下图是 BlockManagerSlaveEndpoint.scala 中 reveiceAndReply 方法\]![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170306003739516-1699331965.png)
4. BlockManagerMasterEndpoint 接受到 Executor 上的注册信息并进行处理，每一个 BlockManager 都会对应一个 BlockManagerInfo，然后通过 executorId 看看能不能找到 BlockManagerId，BlockManagerMaster 包含了集群中整个 BlockManager 注册的信息。经过了这几个步骤后完成了注册的工作，这跟 Spark-Shell 启动时的日志信息是一致的。

   \[下图是 BlockManagerMasterEndpoint.scala 中 reveiceAndReply 方法\]![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170306004438329-1956215423.png)
   \[下图是 BlockManagerMasterEndpoint.scala 中 register 方法\]![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170306005152438-2098750806.png)_ _
   \[下图是 BlockManagerMasterEndpoint.scala 中 blockManagerInfo 数据结构\]![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170306005139907-1569165479.png)_ _
   \[下图是 BlockManagerMasterEndpoint.scala 中 removeExecutor 方法\]![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170306005711923-915021068.png)_ _
   \[下图是 BlockManagerMasterEndpoint.scala 中 removeBlockManager 方法\]![](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170306005853001-1025087510.png)_ _
5. BlockManagerMaster 只有一个 dropFromMemory 是指当我们内存不够的话，我们尝试释放一些内存给要使用的应用程序。
6. 当注册本身没有问题之后接下来的事情就把相关的功能完成



