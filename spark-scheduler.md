## 序言

这一章我们探索了Spark作业的运行过程，这里先描绘下整个过程。

![](/assets/212359414114202.png)

首先回顾一下这个图，Driver Program是我们写的应用程序，它的核心是SparkContext，从api的使用角度，RDD都必须通过它来获得。  
下面讲一下它与其它组件是如何交互的。  
Driver向Master注册Application过程  
SparkContext实例化之后，在内部实例化两个很重要的类，DAGScheduler和TaskScheduler  
在standlone的模式下，TaskScheduler的实现类是TaskSchedulerImpl，在初始化它的时候SparkContext会传入一个SparkDeploySchedulerBackend。  
在SparkDeploySchedulerBackend的start方法里启动了一个AppClient

```
val command = Command("org.apache.spark.executor.CoarseGrainedExecutorBackend",
      args, sc.executorEnvs, classPathEntries ++ testingClassPath, libraryPathEntries, javaOpts)
    val appUIAddress = sc.ui.map(_.appUIAddress).getOrElse("")
    val coresPerExecutor = conf.getOption("spark.executor.cores").map(_.toInt)
    val appDesc = new ApplicationDescription(sc.appName, maxCores, sc.executorMemory,
      command, appUIAddress, sc.eventLogDir, sc.eventLogCodec, coresPerExecutor)
    client = new AppClient(sc.env.rpcEnv, masters, appDesc, this, conf)
    client.start()
    waitForRegistration()
```

maxCores是由参数spark.cores.max来指定的，executorMemoy是由spark.executor.memory指定的。  
AppClient启动之后就会去向Master注册Applicatoin了（`AppClient中的onStart方法`），后面的过程用下面的图来表达

![](/assets/230152156429883.png)

Driver ->RegisterApplication		RegistedApplication <- Master
															 |
														LaunchExecutor


													 ExecutorStateChange
															 ^
															 |
ExecutorBackend 		 					               Worker

上面的图中涉及到了三方通信，具体过程如下：(Driver, Master, Worker)
* Driver通过AppClient向Master发送了RegisterApplication消息来注册AppMaster，Master在接收消息并处理后湖返回RegisteredApplication消息通知Driver注册成功，`Driver的接收还是AppClient`

* Master接收RegisterApplication会触发调度过程，在资源充足的情况下会向Work和Driver`分别发送`LaunchExecutor、ExecutorAdd消息(`startExecutorOnWorkers`)

* Worker接收到LaunchExecutor消息之后，会执行消息中携带的命令，执行【CoarseGrainedExecutorBackend类】（没找到呢）（图中以它继承的接口ExecutorBackend代替），执行完毕后会发送ExecutorStateChange消息给Master

* Master接收ExecutorStateChange消息之后, 立即发送ExecutorUpdated消息通知Driver

* Driver中的AppClient接收到Master发过来的ExecutorAdd和ExecutorUpdated后进行相应处理

* 启动之后的CoraseGrainedBackend（`A pluggable interface used by the Executor to send updates to the cluster scheduler.`）的onStart方法中会向Driver发送RegisterExecutor消息
 
* Driver中的SparkdeploySchedulerBackend（具体代码在CoarseGrainedSchedulerBackend里面），接收到RegisterExecutor消息，回复注册成功消息RegisterExecutor给ExecutorBackend，并且立马准备给它发送任务

* CoarseGrainedExecutorBackend接收到RegisteredExecutor消息之后，实例化一个Executor等待任务的到来

### 资源的调度
上面讲完了整个注册Application的过程之后，其中比较重要的地方是它的调度模块，它是怎么调度的？这也是前面为什么提到maxCores和executorMemory的原因
 

### 
















### 说明
CoarseGrainedSchedulerBackend with SchedulerBackend ：A scheduler backend that waits for coarse grained executors to connect to it through Akka. This backend holds onto each executor for the duration of the Spark job rather than relinquishing executors whenever a task is done and asking the scheduler to launch a ne wexecutor for each new task. Executors may be launched in a variey of ways, such as Mesos tasks for the coarse-grained Mesos mode or standalone processes for Spark's standalone deploy mode(spark.deploy.*)
 一个schduler后端程序用于等待通过使用Akka多个粗粒度executors间的连接.'
这个后端程序紧紧保持了每个Sparkjob的持续使用每个executor，而不是放弃executos，每当一个task完成了并且请求调度启动一个新的Executor为每个新task
Executors也许被启动以多种方式，例如Mesos模式下的粗粒度任务或者Spark standlone模式下的单机处理

CoarseGrainedExecutorBackend with ExecutorBackend ：a pluggable interface used by the Executor to send updates to the cluster scheduler. 一个可插拔式的接口，被用于Executor向集群调度发送更新状态信息
DriverEndpoint
ClientEndpoint

---

#### receive和receiveAndReply的解释
  /**
   * Process messages from [[RpcEndpointRef.send]] or [[RpcCallContext.reply)]]. If receiving a
   * unmatched message, [[SparkException]] will be thrown and sent to `onError`.
   */
   // 处理来自RpcEndpointRef.send或RpcCallContext.reply. 如果接收一个不匹配的信息，将会抛出SparkExeception并发送onError消息
  def receive: PartialFunction[Any, Unit] = {
    case _ => throw new SparkException(self + " does not implement 'receive'")
  }

  /**
   * Process messages from [[RpcEndpointRef.ask]]. If receiving a unmatched message,
   * [[SparkException]] will be thrown and sent to `onError`.
   */
   // 处理来自RpcEndpointRef.ask. 如果接收一个不匹配的信息，将会抛出SparkExeception并发送onError消息
  def receiveAndReply(context: RpcCallContext): PartialFunction[Any, Unit] = {
    case _ => context.sendFailure(new SparkException(self + " won't reply anything"))
  }