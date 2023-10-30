安装sql Server客户端
   进入目录(/app/ezdeploy/media/rpms)sqlserer，安装3个rpm
   rpm -Uvh unixODBC-2.3.1-4.el6.x86_64.rpm #如果原来系统有这个包就不用安装
   #如果依赖报错，则用yum安装： yum install unixODBC，然后再重新执行 rpm -Uvh unixODBC-2.3.1-4.el6.x86_64.rpm
   rpm -Uvh msodbcsql-13.1.6.0-1.x86_64.rpm
   rpm -Uvh mssql-tools-14.0.5.0-1.x86_64.rpm
   #安装后，在/opt/mssql-tools/bin里有sqlcmd就是用来执行sqlserver的命令行工具
   #检查 /opt/mssql-tools/bin/sqlcmd 是否可以执行
