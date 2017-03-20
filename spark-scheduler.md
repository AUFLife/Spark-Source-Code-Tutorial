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
AppClient启动之后就会去向Master注册Applicatoin了，后面的过程用图来表达

![](/assets/230152156429883.png)

