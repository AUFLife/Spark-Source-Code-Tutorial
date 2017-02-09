### 楔子

最近想深入学习Spark，因此尝试阅读Spark的源码。个人任务阅读源码是有一些挑战的，需要思考作者当初为什么要这样设计，设计之初解决的问题是什么。

在对Spark的源码进行具体的走读之前，如果想要对Spark有一个快速的整体认识，优先阅读matei Zaharia的Spark论文是一个非常不错的选择。

在阅读该论文的基础之上，再结合Spark作者在2012年Developer Meetup上做的演讲Introduction to Spark Internals,那么对与Spark的内部实现上会有一个整体上的了解。

### 基本概念（Basic Concepts）

RDD - resillient distributed dataset 弹性可分布式数据集

Operation - 作用于RDD的各种操作分为transformation和action

Job - 作业，一个JOB包含多个RDD及作用于RDD上的各种Operation

Stage - 一个作业分为多个阶段

Partition - 数据分区，一个RDD中的数据可以分成多个不同的区

DAG - Directed Acycle Graph 有向无环图，反应RDD之间的依赖关系

Narrow dependency - 窄依赖，子RDD依赖于父RDD中固定的data partition

Wide Dependency - 宽依赖，子RDD对父RDD中所有的data partition都有依赖

Caching Managenment - 缓存管理，对RDD的中间计算结果进行缓存管理以加快整体的处理速度

### 编程模型（Programing）

RDD是只读的数据分区集合，注意是数据集

作用于RDD上的Operation分为transformation和action。经Transformation处理之后，数据集中的内容会发生改变，由数据集A转换为数据集B；而经过Action处理之后，数据集中的内容会被归约为一个具体的数值。

只有当RDD上有action时，该RDD及其父RDD上的所有operation才会被提交到cluster中真正的被执行。

从代码到动态运行涉及到的组件如下图所示：

![](/assets/import.png)

演示代码：

```
val sc = new SparkContext("Spark://...", "MyJob", home, jars)
val file = sc.textFile("hdfs://...")
val errors = file.filter(_.contains("ERROR"))
errors.cache()
errors.count()
```

### 运行态（Runtime view）

不管什么样的静态模型，其在动态运行的时候无外乎由进程，线程组成。由Spark的术语来说，static view成为dataset view，而dynamic view称为partition view。关系如图所示：

![](/assets/import1.png)



### 部署（Deployment view）

















































