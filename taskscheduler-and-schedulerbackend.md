### TaskScheduler与SchedulerBackend之间的关系

它们两者之间的关系是一个是高层调度器、一个底层调度器；一个负责Stage的划分、一个是负责把任务发送给Executor去执行并接受运行结果。

`应用程序的资源分配在应用程序启动时已经完成，现在要考虑的是具体应用程序中每个人物到底要运行在那个ExecutorBakend上，现在是任务的分配。`TaskScheduler要负责为Task分配计算资源：此时程序已经分配好集群中的计算资源了，然后会根据计算本地性原则来确定Task具体要运行在哪个ExecutorBackend中：

* 这里会有两种不同的Task，一种是ShuffleMapTask，一种是ResultMapTask

  [下图是DAGScheduler. scala中submitMissingTasks方法中内部具体的实现]

   ![img](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170228230653704-1675206748.png)

* DAGScheduler完成面向Stage的划分之后，会按照顺序将每个Stage通过TaskSchedulerImpl的Submit Task提交给底层调度器（提交作业！）TaskSchedulerImpl.submitTasks：主要的作用是将TaskSet加入到TaskSetManager管理；

  [下图是DAGScheduler。scala中submitMissingTasks方法中内部具体的实现]

  ![img](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170228230756360-624995545.png)

* 高层调度器DAGScheduler提交了任务是通过调用submitTask方法提交TaskSet给底层调度器，然后赋值给一个变量Task，同时创建了一个TaskSetManager的实例，这个很关键，它传入了TaskSchedulerImpl对象本身、TaskSet和最大失败后自动重试的次数。

  [下图是TaskSchedulerImpl.scala中submitTasks方法]

  ![img](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170228231149720-327896470.png)

  [下图是TaskSchedulerImpl.scala中createTaskSetManager方法]

  ![img](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170228231321626-1567445621.png)

   [下图是TaskSchedulerImpl.scala中类和主构造器]

  ![img](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170228231434251-907345630.png)

* 比较关键的地方是调用了schedulableBuilder中的addTaskSetManager，SchedulableBuilder本身是应用程序级别的调度器，它自己支持两种调度模式。SchedulableBuilder会确定TaskSetManager的调度顺序，然后按照TaskSetManager的locality aware来确定每个Task具体运行在那个ExecutorBackend中；补充说明：SchedulableBuilder是在创建TaskSchedulerImpl时实例化的。

  [下图是SchedulableBuilder.scala中的方法]

  ![img](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170228232206923-2019867148.png)

  一种是FIFO;另一种是FAIR，调度策略可以通过spark-env.sh中dspark.scheduler.mode进行具体的设置，默认情况下是FIFO

  [下图是SparkContext.scala中createTaskScheduler方法内部具体的实现]

  ![img](http://images2015.cnblogs.com/blog/1005794/201703/1005794-20170305194604485-1224961741.png)

  [下图是TaskSchedulerImpl中initialize方法]

  ![img](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170228233133470-2067638390.png)

* 从第3步submitTask方法中最后调用了backend.reviveOffers方法。这是CoarseGrainedSchedulerBackend.reviveOffers：给DriverEndpoint发送Reviveoffers，DriverEndPoint是驱动程序的调度器：

  [下图是CoarseGrainedSchedulerBackend.scala中reviveOffers方法]

  ![img](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170228233753563-978633463.png)

  [下图是CoarseGrainedSchedulerBackend.scala类中的start方法，实例化时执行]

  ![img](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170228234525345-1656200617.png)

  [下图为CoarseGrainedSchedulerBackend.scala中的receive方法内部具体实现]

  ```
  override def receive: PartialFunction[Any, Unit] = {
        case StatusUpdate(executorId, taskId, state, data) =>
          scheduler.statusUpdate(taskId, state, data.value)
          if (TaskState.isFinished(state)) {
            executorDataMap.get(executorId) match {
              case Some(executorInfo) =>
                executorInfo.freeCores += scheduler.CPUS_PER_TASK
                makeOffers(executorId)
              case None =>
                // Ignoring the update since we don't know about the executor.
                logWarning(s"Ignored task status update ($taskId state $state) " +
                  s"from unknown executor with ID $executorId")
            }
          }

        case ReviveOffers =>
          makeOffers()

        case KillTask(taskId, executorId, interruptThread) =>
          executorDataMap.get(executorId) match {
            case Some(executorInfo) =>
              executorInfo.executorEndpoint.send(KillTask(taskId, executorId, interruptThread))
            case None =>
              // Ignoring the task kill since the executor is not registered.
              logWarning(s"Attempted to kill task $taskId for unknown executor $executorId.")
          }

  }
  ```

* 在DriverEndpoint接受ReviveOffers消息并路由到makOffers具体的方法中；在makeOffers方法中首先准备好所有可以用于计算的Executor，然后找出可以的workoffers（代表了所有可用的ExecutorBackend中可以使用的CPU Cores信息）WorkerOffer会告诉我们具体Executor可用的资源，比如说CPU Core，为什么不考虑内存只考虑CPU,因为在这儿之前已经分配好了。

  [下图是CoarseGrainedSchedulerBackend.scala中makerOffers方法]

  ![img](http://images2015.cnblogs.com/blog/1005794/201702/1005794-20170228234849766-1238435383.png)

  ​

  ​

[TaskScheduler ]