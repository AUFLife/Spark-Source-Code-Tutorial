## 序言

这一章我们探索了Spark作业的运行过程，这里先描绘下整个过程。

![](/assets/212359414114202.png)

首先回顾一下这个图，Driver Program是我们写的应用程序，它的核心是SparkContext，之后将作业提交给集群进行处理，而后将具体的task分发给Worker节点上的Executor去执行。

