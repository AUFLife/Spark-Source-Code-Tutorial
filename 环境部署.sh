1.准备Linux环境
	操作系统：CentOS 7
	1.0 设置静态IP
		http://jingyan.baidu.com/article/359911f57ca21357fe0306d8.html
	1.1 修改主机名
		# 在CentOS7 中，很多系统管理工具都被替换了，CentOS7 修改 hostname 方法如下
		1、修改 /etc/sysconfig/network
			NETWORKING=yes
			HOSTNAME=hadoop-master 
		2、使用hostnamectl命令，hostnamectl set-hostname name ，再通过hostname或者hostnamectl status命令查看更改是否生效。

		
	1.2 修改主机名和IP的映射关系
		vim /etc/hosts
			
		192.168.1.100	master
	
	1.3 关闭防火墙
		CentOS 7.0默认使用的是firewall作为防火墙，使用iptables必须重新设置一下
		# 直接关闭防火墙

		systemctl stop firewalld.service #停止firewall

		systemctl disable firewalld.service #禁止firewall开机启动

		# 设置 iptables service

		yum -y install iptables-services

		# 如果要修改防火墙配置，如增加防火墙端口3306

		vi /etc/sysconfig/iptables 

		# 增加规则

		-A INPUT -m state --state NEW -m tcp -p tcp --dport 3306 -j ACCEPT

		# 保存退出后

		systemctl restart iptables.service #重启防火墙使配置生效

		systemctl enable iptables.service #设置防火墙开机启动

		最后重启系统使设置生效即可。
	
	1.4 重启Linux
		reboot

1.2.配置ssh免登陆
	  如果 A机器链接B机器
    在A机器输入 ssh-keygen -t rsa  （直接四个回车） 生成密钥
    在A机器输入 ssh-copy-id -i ~/.ssh/id_rsa.pub root@B机器Ip  把本机的公钥追到b机器中
	SSH公钥登录原理如下：
		具体的验证过程如下：
			所谓"公钥登录"，原理很简单，就是用户将自己的公钥储存在远程主机上。
			登录的时候，远程主机会向用户发送一段随机字符串，用户用自己的私钥加密后，再发回来。
			远程主机用事先储存的公钥进行解密，如果成功，就证明用户是可信的，直接允许登录shell，不再要求密码。
2.安装JDK
	2.2解压jdk
		#创建文件夹
		mkdir /home/hadoop/app
		#解压
		tar -zxvf jdk-7xx.tar.gz -C /home/hadoop/app
		
	2.3将java添加到环境变量中
		vim /etc/profile
		#在文件最后添加
		export JAVA_HOME=/home/hadoop/app/jdk-7xx
		export PATH=$PATH:$JAVA_HOME/bin
	
		#刷新配置
		source /etc/profile

		这里需要注意，需要先卸载centOS默认的OpenJDK
		rpm -qa | grep java  		# 查看
		rpm -e --nodeps ...			# 卸载
		
	以上的步骤，所有集群机器都需要操作

3.安装hadoop2.4.1
	先上传hadoop的安装包到服务器上去/home/hadoop/app/
	tar -zxvf hadoop2.4.1.tar.gz 
	注意：hadoop2.x的配置文件$HADOOP_HOME/etc/hadoop
	伪分布式需要修改5个配置文件
	3.1配置hadoop
	第一个：hadoop-env.sh
		vim hadoop-env.sh
		#第27行
		export JAVA_HOME=/home/hadoop/app/jdk-7xx
		
	第二个：core-site.xml

		<!-- 指定HADOOP所使用的文件系统schema（URI），HDFS的老大（NameNode）的地址 -->
		<property>
			<name>fs.defaultFS</name>
			<value>hdfs://master:9000</value>
		</property>
		<!-- 指定hadoop运行时产生文件的存储目录 -->
		<property>
			<name>hadoop.tmp.dir</name>
			<!-- 这个目录可以任意制定，但是不要放到系统路径下 -->
			<value>/home/hadoop/hadoop-2.4.1/tmp</value>
    	</property>
		
	第三个：hdfs-site.xml   
		<!-- 指定HDFS副本的数量 -->
		<property>
			<name>dfs.replication</name>
			<value>2</value>
    </property>
    
    <property>
 			 <name>dfs.secondary.http.address</name>
  		 <value>master:50090</value>
    </property>
  
		
	第四个：mapred-site.xml (mv mapred-site.xml.template mapred-site.xml)
		mv mapred-site.xml.template mapred-site.xml
		vim mapred-site.xml
		<!-- 指定mr运行在yarn上 -->
	<property>
		<name>mapreduce.framework.name</name>
		<value>yarn</value>
    </property>
		
	第五个：yarn-site.xml
		<!-- 指定YARN的老大（ResourceManager）的地址 -->
		<property>
			<name>yarn.resourcemanager.hostname</name>
			<value>master</value>
    </property>
		<!-- reducer获取数据的方式 -->
    <property>
			<name>yarn.nodemanager.aux-services</name>
			<value>mapreduce_shuffle</value>
     </property>
     
	第六个：salves
	<!--这里面写其他机器的地址，也就是datanode的机器-->
	node1
	node2
	
	3.2将hadoop添加到环境变量
	
	vim /etc/proflie
		export JAVA_HOME=/home/hadoop/app/jdk-7xx
		export HADOOP_HOME=/home/hadoop/app/hadoop-2.4.1
		export PATH=$PATH:$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin

	source /etc/profile
	
	3.3复制主节点上的hadoop到其他节点，并在主节点启动集群
	scp /home/hadoop/app/hadoop-2.4.1  node1:/home/hadoop/app/
	scp /home/hadoop/app/hadoop-2.4.1  node2:/home/hadoop/app/
	并且配置JAVA_HOME HADOOP_HOME
	
	
	注意所有的机器，都要配置免密登录，JAVA_HOME HADOOP_HOME 关闭防火墙，修改ip等操作
	
	
	3.4格式化namenode（是对namenode进行初始化）
		hadoop namenode -format(在master上)
		
	3.5启动hadoop
		先启动HDFS
		sbin/start-dfs.sh
		
		再启动YARN
		sbin/start-yarn.sh
		
	3.6验证是否启动成功
		使用jps命令验证
		27408 NameNode
		28218 Jps
		27643 SecondaryNameNode
		28066 NodeManager
		27803 ResourceManager
		27512 DataNode
	
		http://master:50070 （HDFS管理界面）如果是在windows上访问，也要配置映射
		http://master:8088 （MR管理界面）
	3.7 如果启动的时候发现datanode没有启动成功
		1.检查配置文件
		
		2.删除所有集群/home/hadoop/hadoop-2.4.1/tmp目录下的东西 重新格式化

	
遇到的一些问题：
	1. CentOS7 设置163yum源
		https://app.yinxiang.com/shard/s32/nl/4984092/cf382f57-a404-4a1b-b807-7602841683a1/
	2. VMWare虚拟机NAT模式无法上网
		a) 首先确认windows中VMnet8的网关是否设置		
		b）http://www.tuicool.com/articles/Ermqmq（VMware workstation NAT方式无法连接外网）
		c) 而后再配置DNS服务器文件 /etc/resolv.conf(可选)
	3. 创建信用户
		http://www.cnblogs.com/daizhuacai/archive/2013/01/17/2865132.html
	
	
