# CMDBCOLLECT README

------
## 主要功能
各种软硬件的CMDB信息采集，采集后会存储到中转存储DB中，然后完成后续的关系计算，CMDB根据模型与数据Mapping设置从中转DB抽取需要的数据。

## 数据单位标准（采集插件必须按此标准提供数据）
- 磁盘空间为数值格式（非字符串），单位是GB
- 内存大小数值格式（非字符串），单位是MB
- 网卡或HBA板卡端口速率为数值格式（非字符串），单位是Mb/s

## 采集标准说明
- HOST主机硬件采集标准属性
- OBJECT_TYPE: HOST
- IS_VIRTUAL: 值是0|1，表明是否是虚拟机
- MGMT_IP: 连入SSH或者Agent使用的本主机的服务IP
- MGMT_PORT: 连入SSH或者Agent使用的本主机的服务PORT
- OS_ID: CMDB的ID（主机发现需要依赖CMDB中存在所有的主机IP和相关的登录账户信息）
- SN: 主板序列号
> 上述属性都可以用于关联OS

* 样例
```json
{
        "MGMT_IP": "",
        "CPU_FREQUENCY": "2.60GHz",
        "CPU_COUNT": 2,
        "MEM_MAXIMUM_CAPACITY": "17 GB",
        "CPU_ARCH": "x86_64",
        "POWER_CORDS_COUNT": "Unspecified",
        "MACHINE_ID": "99eebc4953394a6f8b5ae644778cbb1a",
        "MGMT_PORT": "",
        "PRODUCT_NAME": "VMware Virtual Platform",
        "MODEL_NAME": "Intel(R) Xeon(R) CPU E5-2670 0",
        "NET_INTERFACES": [{
            "LINK_STATE": "yes",
            "NAME": "ens160",
            "SPEED": "10000Mb/s",
            "MAC": "00:50:56:a1:eb:d2"
        }],
        "IS_VIRTUAL": 1,
        "PK": ["MGMT_IP"],
        "CPU_CORES": 4,
        "MEM_SPEED": "Unknown",
        "MEM_SLOTS": "64",
        "HBA_INTERFACES": [],
        "DISKS": [{
            "NAME": "/dev/sda",
            "TYPE": "local",
            "CAPACITY": "53.7"
        }, {
            "NAME": "/dev/sdb",
            "TYPE": "local",
            "CAPACITY": "107.4"
        }],
        "MICROCODE": "0x71a",
        "SN": "VMware-42 21 38 14 a3 bc 23 93-76 25 fe d8 61 56 c6 c2",
        "MANUFACTURER": "6.00",
        "OS_ID": "",
        "OBJECT_TYPE": "HOST"
    }
```

- OS采集标准属性
- OBJECT_TYPE: OS
- IS_VIRTUAL: 值是0|1，表明是否是虚拟机
- MGMT_IP: 连入SSH或者Agent使用的本主机的服务IP
- MGMT_PORT: 连入SSH或者Agent使用的本主机的服务PORT
- OS_ID: CMDB的ID（主机发现需要依赖CMDB中存在所有的主机IP和相关的登录账户信息）
- SN: 主板序列号
> 上述属性都可以用于关联HOST硬件

* 样例
```json
{
        "SWAP_SIZE": "2047M",
        "IPV6_ADDRS": ["fe80::250:56ff:fea1:ebd2"],
        "MEM_BUFFERS": "0.02M",
        "MEM_AVAILABLE": "7516.41M",
        "MACHINE_ID": "99eebc4953394a6f8b5ae644778cbb1a",
        "OS_TYPE": "Linux",
        "BOARD_SERIAL": "None",
        "PRODUCT_NAME": "VMware Virtual Platform",
        "NTP_ENABLE": 1,
        "SWAP_FREE": "2047.33M",
        "PRODUCT_UUID": "42213814-A3BC-2393-7625-FED86156C6C2",
        "CPU_CORES": "4",
        "SSH_VERSION": "OpenSSH_6.6.1p1",
        "USERS": [{
            "HOME": "/root",
            "NAME": "root",
            "SHELL": "/bin/bash",
            "UID": "0",
            "GID": "0"
        }, {
            "HOME": "/",
            "NAME": "systemd-bus-proxy",
            "SHELL": "/sbin/nologin",
            "UID": "999",
            "GID": "998"
        }, {
            "HOME": "/",
            "NAME": "polkitd",
            "SHELL": "/sbin/nologin",
            "UID": "998",
            "GID": "997"
        }, {
            "HOME": "/var/lib/chrony",
            "NAME": "chrony",
            "SHELL": "/sbin/nologin",
            "UID": "997",
            "GID": "995"
        }, {
            "HOME": "/var/lib/nfs",
            "NAME": "nfsnobody",
            "SHELL": "/sbin/nologin",
            "UID": "65534",
            "GID": "65534"
        }, {
            "HOME": "/home/app",
            "NAME": "app",
            "SHELL": "/bin/bash",
            "UID": "500",
            "GID": "500"
        }, {
            "HOME": "/home/nginx",
            "NAME": "nginx",
            "SHELL": "/sbin/nologin",
            "UID": "1000",
            "GID": "1000"
        }, {
            "HOME": "/home/postgres",
            "NAME": "postgres",
            "SHELL": "/bin/bash",
            "UID": "1001",
            "GID": "1001"
        }, {
            "HOME": "/home/deploydemo",
            "NAME": "deploydemo",
            "SHELL": "/bin/bash",
            "UID": "1002",
            "GID": "1002"
        }, {
            "HOME": "/home/wenhb",
            "NAME": "wenhb",
            "SHELL": "/bin/bash",
            "UID": "1003",
            "GID": "1003"
        }],
        "DISKS": [{
            "NAME": "/dev/sda",
            "TYPE": "local",
            "CAPACITY": "53.7"
        }, {
            "NAME": "/dev/sdb",
            "TYPE": "local",
            "CAPACITY": "107.4"
        }],
        "SYS_VENDOR": "VMware, Inc.",
        "OS_ID": "",
        "MEM_CACHED": "3121.00M",
        "NTP_SERVERS": ["202.112.10.36"],
        "NETWORKMANAGER_ENABLE": 1,
        "NFS_MOUNTED": 0,
        "OPENSSL_VERSION": "1.0.1e-fips",
        "MGMT_IP": "",
        "NIC_BOND": 0,
        "CPU_ARCH": "x86_64",
        "MGMT_PORT": "",
        "SWAP_TOTAL": "2048.00M",
        "IS_VIRTUAL": 1,
        "KERNEL_VERSION": "3.10.0-514.el7.x86_64",
        "PK": ["MGMT_IP"],
        "DNS_SERVERS": ["192.168.1.188"],
        "FIREWALL_ENABLE": 0,
        "HOSTNAME": "centos7base",
        "MEM_TOTAL": "15886.96M",
        "MOUNT_POINTS": [{
            "USED%": "79%",
            "MOUNT_POINT": "/",
            "FS_TYPE": "xfs",
            "USED": 117470,
            "AVAILABLE": 33037,
            "CAPACITY": 150506,
            "DEVICE": "/dev/mapper/cl-root"
        }, {
            "USED%": "14%",
            "MOUNT_POINT": "/boot",
            "FS_TYPE": "xfs",
            "USED": 139,
            "AVAILABLE": 876,
            "CAPACITY": 1014,
            "DEVICE": "/dev/sdb1"
        }],
        "IP_ADDRS": ["192.168.0.26"],
        "VERSION": "CentOS Linux release 7.3.1611 (Core) ",
        "MEM_FREE": "4475.05M",
        "SELINUX_STATUS": "permissive",
        "MAX_OPEN_FILES": "1610558",
        "OBJECT_TYPE": "OS"
    }
```

- 应用采集标准属性
- OBJECT_TYPE: APP
- APP_TYPE: Tomcat|Apache|Weblogic|Websphere|Oracle|Mysql|PostGresql...等
- MGMT_IP: 连入SSH或者Agent使用的本主机的服务IP
- MGMT_PORT: 连入SSH或者Agent使用的本主机的服务PORT
- OS_ID: CMDB的ID（主机发现需要依赖CMDB中存在所有的主机IP和相关的登录账户信息）
> 上述属性都可以用于关联OS
- INSTALL_PATH: 安装路径
- SERVER_NAME: 应用实例名
- CONN_INFO: (LISTEN: 监听端口，包括IPV4，IPV6), (PEER: 出方向的连接)，用于计算应用调用关系
- PORT: 主服务端口
- SSL_PORT: ssl|https服务端口，，如果没有就为null
- ADMIN_PORT: 管理端口，，如果没有就为null
- ADMIN_SSL_PORT: ssl|https管理端口，如果没有就为null
- MON_PORT: 监控端口，如果没有就为null
- JMX_PORT: Java的jmx的监听端口，如果没有就为null
- PORC_INFO: 进程信息（CMDB中不需要，只是参考）

* 样例
```json
{
        "INSTALL_PATH": "/app/servers/bsmwechat",
        "SERVER_NAME": "bsmwechat",
        "MGMT_IP": "",
        "CATALINA_BASE": "/app/servers/bsmwechat",
        "JMX_PORT": null,
        "MAX_HEAP_SIZE": "1024M",
        "JVM_VENDER": "Oracle Corporation",
        "CATALINA_HOME": "/app/servers/bsmwechat",
        "MGMT_PORT": "",
        "MIN_HEAP_SIZE": null,
        "CONFIG_PATH": "/app/servers/bsmwechat",
        "PORT": "8190",
        "JRE_HOME": "/app/serverware/jdk",
        "MON_PORT": null,
        "CONN_INFO": {
            "PEER": [],
            "LISTEN": ["41544", "9977", "::ffff:127.0.0.1:9347", "8190", "::ffff:127.0.0.1:9234"]
        },
        "PK": ["MGMT_IP", "PORT"],
        "JMX_SSL": "false",
        "PROC_INFO": {
            "%MEM": "2.5",
            "MGMT_IP": "",
            "RUSER": "app",
            "RGROUP": "apps",
            "COMMAND": "/app/serverware/jdk/bin/java -Dinstance.name=bsmwechat -Xdebug -Xnoagent -Xrunjdwp:transport=dt_socket,address=9977,server=y,suspend=n -Xmx1024M -XX:MaxPermSize=256M -XX:+UseConcMarkSweepGC -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+HeapDumpOnOutOfMemoryError -verbose:gc -Xloggc:logs/gc.log -Dlog4j.home=app/logs/bsmwechat -Dlog4j.priority=ERROR -Djava.io.tmpdir=/app/servers/bsmwechat/tmp -Djava.awt.headless=true -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -DINSTANCE_NAME=bsmwechat -Dtechsure.home=/app -Dhttp.port=8190 -Dhttps.port=9135 -Dshutdown.port=9234 -Dajp.port=9347 -Drmi.reg.port=9456 -Drmi.server.port=9598 -Dbind.ip= -Dvip= -Djava.endorsed.dirs=/app/serverware/tomcat/common/endorsed -Dcatalina.base=/app/servers/bsmwechat -Dcatalina.home=/app/servers/bsmwechat -Djava.io.tmpdir=/app/servers/bsmwechat/tmp org.apache.catalina.startup.Bootstrap start",
            "OS_TYPE": "Linux",
            "MGMT_PORT": "",
            "PGID": "5038",
            "USER": "app",
            "EXECUTABLE_FILE": "/app/serverware/jdk1.8.0_77/bin/java",
            "PID": "5040",
            "GROUP": "apps",
            "PPID": "5038",
            "TIME": "00:06:07",
            "ELAPSED": "4-10:58:58",
            "%CPU": "0.0",
            "HOST_NAME": "centos7base",
            "APP_TYPE": "Tomcat",
            "ENVRIONMENT": {
                "JAVA_HOME": "/app/serverware/jdk",
                "SERVER_NAME": "bsmwechat",
                "tmpdir": "/app/servers/bsmwechat/tmp org.apache.catalina.startup.Bootstrap start",
                "LD_LIBRARY_PATH": "/app/serverware/tomcat/lib/",
                "LC_ALL": "",
                "MEDIA_HOME": "/app/serverware/tomcat",
                "AJP_PORT": "9347",
                "ASM_HOME": "/app",
                "PWD": "/app/serveradmin/bin",
                "INSTANCE_NAME": "bsmwechat",
                "LANG": "zh_CN.UTF-8",
                "APPDIR": "/app/servers",
                "ssl": "false",
                "SHLVL": "3",
                "APP_SYSTEM_HOME": "/app/systems/bsmwechat",
                "OLDPWD": "/app",
                "APP_SERVER_HOME": "/app/servers/bsmwechat",
                "HTTP_PORT": "8190",
                "port": "9598",
                "TECHSURE_HOME": "/app",
                "_": "/app/serveradmin/bin/serveradmin",
                "RMI_REG_PORT": "9456",
                "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin",
                "RMI_SERVER_PORT": "9598",
                "SHUTDOWN_PORT": "9234",
                "SYSTEM_NAME": "bsmwechat",
                "CLASSPATH": "/app/systems/bsmwechat/config/::/app/servers/bsmwechat/lib/:/app/servers/bsmwechat/lib/annotations-api.jar:/app/servers/bsmwechat/lib/catalina-ant.jar:/app/servers/bsmwechat/lib/catalina-ha.jar:/app/servers/bsmwechat/lib/catalina.jar:/app/servers/bsmwechat/lib/catalina-ssi.jar:/app/servers/bsmwechat/lib/catalina-storeconfig.jar:/app/servers/bsmwechat/lib/catalina-tribes.jar:/app/servers/bsmwechat/lib/ecj-4.18.jar:/app/servers/bsmwechat/lib/el-api.jar:/app/servers/bsmwechat/lib/jasper-el.jar:/app/servers/bsmwechat/lib/jasper.jar:/app/servers/bsmwechat/lib/jaspic-api.jar:/app/servers/bsmwechat/lib/jsp-api.jar:/app/servers/bsmwechat/lib/mysql-connector-java-5.1.25.jar:/app/servers/bsmwechat/lib/servlet-api.jar:/app/servers/bsmwechat/lib/techsure-balantrealm8.jar:/app/servers/bsmwechat/lib/techsure-valve8.jar:/app/servers/bsmwechat/lib/tomcat-api.jar:/app/servers/bsmwechat/lib/tomcat-coyote.jar:/app/servers/bsmwechat/lib/tomcat-dbcp.jar:/app/servers/bsmwechat/lib/tomcat-i18n-cs.jar:/app/servers/bsmwechat/lib/tomcat-i18n-de.jar:/app/servers/bsmwechat/lib/tomcat-i18n-es.jar:/app/servers/bsmwechat/lib/tomcat-i18n-fr.jar:/app/servers/bsmwechat/lib/tomcat-i18n-ja.jar:/app/servers/bsmwechat/lib/tomcat-i18n-ko.jar:/app/servers/bsmwechat/lib/tomcat-i18n-pt-BR.jar:/app/servers/bsmwechat/lib/tomcat-i18n-ru.jar:/app/servers/bsmwechat/lib/tomcat-i18n-zh-CN.jar:/app/servers/bsmwechat/lib/tomcat-jdbc.jar:/app/servers/bsmwechat/lib/tomcat-jni.jar:/app/servers/bsmwechat/lib/tomcat-util.jar:/app/servers/bsmwechat/lib/tomcat-util-scan.jar:/app/servers/bsmwechat/lib/tomcat-websocket.jar:/app/servers/bsmwechat/lib/websocket-api.jar::/app/servers/bsmwechat/bin/bootstrap.jar:/app/servers/bsmwechat/bin/commons-daemon.jar:/app/servers/bsmwechat/bin/tomcat-juli.jar:",
                "HTTPS_PORT": "9135"
            },
            "COMM": "java",
            "OS_ID": ""
        }
```


