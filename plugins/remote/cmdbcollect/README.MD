# 远程OS运行的CMDBCOLLECT README

------
## 主要功能
各种软硬件的CMDB信息采集，采集后会存储到中转存储DB中，然后完成后续的关系计算，CMDB根据模型与数据Mapping设置从中转DB抽取需要的数据。

## 数据单位标准（采集插件必须按此标准提供数据）
- 磁盘空间为数值格式（非字符串），单位是GB
- 内存大小数值格式（非字符串），单位是MB
- 网卡或HBA板卡端口速率为数值格式（非字符串），单位是Mb/s

## 采集标准说明
- HOST主机硬件采集标准属性
- _OBJ_CATEGORY: HOST
- IS_VIRTUAL: 值是0|1，表明是否是虚拟机
- MGMT_IP: 连入SSH或者Agent使用的本主机的服务IP
- MGMT_PORT: 连入SSH或者Agent使用的本主机的服务PORT
- OS_ID: CMDB的ID（主机发现需要依赖CMDB中存在所有的主机IP和相关的登录账户信息）
- BOARD_SERIAL: 主板序列号
> 上述属性都可以用于关联OS
> 为了便于检索，如果某个属性的值是一个数组，数组元素必须也是Object，譬如：IP地址列表：[{"VALUE":"192.168.0.1"}, {"VALUE":"10.168.0.1"}]

* 样例
```json
    {
        "MGMT_IP": "",
        "CPU_FREQUENCY": "2.60GHz",
        "CPU_COUNT": 2,
        "MEM_MAXIMUM_CAPACITY": 17408,
        "CPU_ARCH": "x86_64",
        "POWER_CORDS_COUNT": "Unspecified",
        "MACHINE_ID": "99eebc4953394a6f8b5ae644778cbb1a",
        "MGMT_PORT": "",
        "PRODUCT_NAME": "VMware Virtual Platform",
        "MODEL_NAME": "Intel(R) Xeon(R) CPU E5-2670 0",
        "ETH_INTERFACES": [{
            "STATUS": "yes",
            "UNIT": "Mb/s",
            "NAME": "ens160",
            "SPEED": 10000,
            "MAC": "00:50:56:a1:eb:d2"
        }],
        "IS_VIRTUAL": 1,
        "PK": ["MGMT_IP"],
        "CPU_CORES": 4,
        "MEM_SPEED": "Unknown",
        "MEM_SLOTS": 64,
        "HBA_INTERFACES": [],
        "DISKS": [{
            "UNIT": "GB",
            "NAME": "/dev/sda",
            "TYPE": "local",
            "CAPACITY": 53.7
        }, {
            "UNIT": "GB",
            "NAME": "/dev/sdb",
            "TYPE": "local",
            "CAPACITY": 107.4
        }, {
            "UNIT": "GB",
            "NAME": "/dev/mapper/cl-root",
            "TYPE": "lvm",
            "CAPACITY": 157.8
        }, {
            "UNIT": "GB",
            "NAME": "/dev/mapper/cl-swap",
            "TYPE": "lvm",
            "CAPACITY": 2.147
        }],
        "MICROCODE": "0x71a",
        "BOARD_SERIAL": "VMware-42 21 38 14 a3 bc 23 93-76 25 fe d8 61 56 c6 c2",
        "MANUFACTURER": "6.00",
        "OS_ID": "380303927205890",
        "_OBJ_CATEGORY": "HOST"
    }
```

- OS采集标准属性
- _OBJ_CATEGORY: OS
- IS_VIRTUAL: 值是0|1，表明是否是虚拟机
- MGMT_IP: 连入SSH或者Agent使用的本主机的服务IP
- MGMT_PORT: 连入SSH或者Agent使用的本主机的服务PORT
- OS_ID: CMDB的ID（主机发现需要依赖CMDB中存在所有的主机IP和相关的登录账户信息）
- BOARD_SERIAL: 主板序列号
> 上述属性都可以用于关联HOST硬件

* 样例
```json
    {
        "SWAP_SIZE": "2047M",
        "IPV6_ADDRS": ["fe80::250:56ff:fea1:ebd2"],
        "MEM_BUFFERS": 0.023,
        "MEM_AVAILABLE": 8214.629,
        "MACHINE_ID": "99eebc4953394a6f8b5ae644778cbb1a",
        "OS_TYPE": "Linux",
        "BOARD_SERIAL": "None",
        "PRODUCT_NAME": "VMware Virtual Platform",
        "NTP_ENABLE": 1,
        "SWAP_FREE": 2046.699,
        "PRODUCT_UUID": "42213814-A3BC-2393-7625-FED86156C6C2",
        "CPU_CORES": 4,
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
            "UNIT": "GB",
            "NAME": "/dev/sda",
            "TYPE": "local",
            "CAPACITY": 53.7
        }, {
            "UNIT": "GB",
            "NAME": "/dev/sdb",
            "TYPE": "local",
            "CAPACITY": 107.4
        }, {
            "UNIT": "GB",
            "NAME": "/dev/mapper/cl-root",
            "TYPE": "lvm",
            "CAPACITY": 157.8
        }, {
            "UNIT": "GB",
            "NAME": "/dev/mapper/cl-swap",
            "TYPE": "lvm",
            "CAPACITY": 2.147
        }],
        "SYS_VENDOR": "VMware, Inc.",
        "OS_ID": "380303927205890",
        "MEM_CACHED": 3180.586,
        "NTP_SERVERS": ["202.112.10.36"],
        "NETWORKMANAGER_ENABLE": 1,
        "NFS_MOUNTED": 0,
        "OPENSSL_VERSION": "1.0.1e-fips",
        "MGMT_IP": "",
        "NIC_BOND": 0,
        "CPU_ARCH": "x86_64",
        "MGMT_PORT": "",
        "SWAP_TOTAL": 2047.996,
        "IS_VIRTUAL": 1,
        "KERNEL_VERSION": "3.10.0-514.el7.x86_64",
        "PK": ["MGMT_IP"],
        "DNS_SERVERS": ["192.168.1.188"],
        "FIREWALL_ENABLE": 0,
        "HOSTNAME": "centos7base",
        "MEM_TOTAL": 15886.957,
        "MOUNT_POINTS": [{
            "USED": 114.731,
            "AVAILABLE": 32.248,
            "DEVICE": "/dev/mapper/cl-root",
            "MOUNT_POINT": "/",
            "USED%": 79,
            "FS_TYPE": "xfs",
            "UNIT": "GB",
            "CAPACITY": 146.979
        }, {
            "USED": 0.136,
            "AVAILABLE": 0.855,
            "DEVICE": "/dev/sdb1",
            "MOUNT_POINT": "/boot",
            "USED%": 14,
            "FS_TYPE": "xfs",
            "UNIT": "GB",
            "CAPACITY": 0.99
        }],
        "IP_ADDRS": ["192.168.0.26"],
        "VERSION": "CentOS Linux release 7.3.1611 (Core) ",
        "MEM_FREE": 5122.984,
        "SELINUX_STATUS": "permissive",
        "MAX_OPEN_FILES": 1610558,
        "_OBJ_CATEGORY": "OS"
    }
```

- 应用采集标准属性
- _OBJ_CATEGORY: APP
- _OBJ_TYPE: Tomcat|Apache|Weblogic|Websphere|Oracle|Mysql|PostGresql...等
- MGMT_IP: 连入SSH或者Agent使用的本主机的服务IP
- MGMT_PORT: 连入SSH或者Agent使用的本主机的服务PORT
- OS_ID: CMDB的ID（主机发现需要依赖CMDB中存在所有的主机IP和相关的登录账户信息）
> 上述属性都可以用于关联OS
- OS_USER: 运行用户
- INSTALL_PATH: 安装路径
- SERVER_NAME: 应用实例名
- CONN_INFO: (LISTEN: 监听端口，包括IPV4，IPV6), (PEER: 出方向的连接)，用于计算应用调用关系
- PORT: 主服务端口
- SSL_PORT: ssl|https服务端口，，如果没有就为null
- ADMIN_PORT: 管理端口，，如果没有就为null
- ADMIN_SSL_PORT: ssl|https管理端口，如果没有就为null
- MON_PORT: 监控端口，如果没有就为null
- JMX_PORT: Java的jmx的监听端口，如果没有就为null
- PORTS: 所有监听端口的列表，用于检索
- PORC_INFO: 进程信息（CMDB中不需要，只是参考）

* 样例
```json
    {
        "OS_USER":"app",
        "INSTALL_PATH": "/app/servers/balantflow",
        "SERVER_NAME": "balantflow",
        "MGMT_IP": "",
        "CATALINA_BASE": "/app/servers/balantflow",
        "JMX_PORT": "10099",
        "MAX_HEAP_SIZE": 4,
        "JVM_VENDER": "Oracle Corporation",
        "CATALINA_HOME": "/app/servers/balantflow",
        "MGMT_PORT": "",
        "MIN_HEAP_SIZE": 2,
        "CONFIG_PATH": "/app/servers/balantflow",
        "PORT": "8080",
        "JRE_HOME": "/app/serverware/jdk",
        "MON_PORT": "10099",
        "CONN_INFO": {
            "PEER": ["::ffff:127.0.0.1:3306"],
            "LISTEN": ["10099", "::ffff:127.0.0.1:9184", "36404", "43539", "9345", "9999", "8080"]
        },
        "PK": ["MGMT_IP", "PORT"],
        "JMX_SSL": "false",
        "PROC_INFO": {
            "%MEM": "9.7",
            "MGMT_IP": "",
            "RUSER": "app",
            "RGROUP": "apps",
            "COMMAND": "/app/serverware/jdk/bin/java -Dinstance.name=balantflow -Dfastjson.parser.safeMode=true -Xdebug -Xnoagent -Xrunjdwp:transport=dt_socket,address=9999,server=y,suspend=n -Xms2G -Xmx4G -XX:+UseConcMarkSweepGC -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+HeapDumpOnOutOfMemoryError -verbose:gc -Xloggc:logs/gc.log -Dlog4j.home=/app/logs/balantflow -Dlog4j.priority=ERROR -Djava.io.tmpdir=/app/servers/balantflow/tmp -Djava.awt.headless=true -Dcom.sun.management.jmxremote.port=10099 -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -DINSTANCE_NAME=balantflow -Dtechsure.home=/app -Dhttp.port=8080 -Dhttps.port=9345 -Dshutdown.port=9184 -Dajp.port=9185 -Drmi.reg.port=9285 -Drmi.server.port=9286 -javaagent:/app/systems/balantflow/javaagent/tsapm-javaagent.jar -Dbind.ip= -Dvip= -Djava.endorsed.dirs=/app/serverware/tomcat/common/endorsed -Dcatalina.base=/app/servers/balantflow -Dcatalina.home=/app/servers/balantflow -Djava.io.tmpdir=/app/servers/balantflow/tmp org.apache.catalina.startup.Bootstrap start",
            "OS_TYPE": "Linux",
            "MGMT_PORT": "",
            "PGID": "19157",
            "USER": "app",
            "EXECUTABLE_FILE": "/app/serverware/jdk1.8.0_77/bin/java",
            "PID": "19159",
            "GROUP": "apps",
            "PPID": "19157",
            "TIME": "00:26:39",
            "ELAPSED": "1-05:17:01",
            "%CPU": "1.5",
            "HOST_NAME": "centos7base",
            "_OBJ_TYPE": "Tomcat",
            "ENVRIONMENT": {
                "SSH_CLIENT": "192.168.0.123 49422 22",
                "VAR_TEST": "abcefdfdf",
                "LC_ALL": "",
                "AJP_PORT": "9185",
                "LESSOPEN": "||/usr/bin/lesspipe.sh %s",
                "ASM_HOME": "/app",
                "PWD": "/app/serveradmin/bin",
                "SELINUX_ROLE_REQUESTED": "",
                "SELINUX_USE_CURRENT_RANGE": "",
                "LANG": "zh_CN.UTF-8",
                "USER": "root",
                "LOGNAME": "root",
                "SHLVL": "2",
                "APP_SYSTEM_HOME": "/app/systems/balantflow",
                "HTTP_PORT": "8080",
                "SELINUX_LEVEL_REQUESTED": "",
                "port": "9286 -javaagent:/app/systems/balantflow/javaagent/tsapm-javaagent.jar",
                "RMI_REG_PORT": "9285",
                "PATH": "/usr/local/itom/java/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin:/app/serverware/node/bin",
                "RMI_SERVER_PORT": "9286",
                "SHUTDOWN_PORT": "9184",
                "SYSTEM_NAME": "balantflow",
                "HISTSIZE": "10000",
                "TERM": "ansi",
                "SSH_TTY": "/dev/pts/0",
                "JAVA_HOME": "/app/serverware/jdk",
                "HOME": "/root",
                "SERVER_NAME": "balantflow",
                "tmpdir": "/app/servers/balantflow/tmp org.apache.catalina.startup.Bootstrap start",
                "LD_LIBRARY_PATH": "/app/serverware/tomcat/lib/",
                "SSH_CONNECTION": "192.168.0.123 49422 192.168.0.26 22",
                "HISTTIMEFORMAT": "%d/%m/%y %T ",
                "MEDIA_HOME": "/app/serverware/tomcat",
                "MAIL": "/var/spool/mail/root",
                "XDG_SESSION_ID": "5297",
                "INSTANCE_NAME": "balantflow",
                "COMP_SYSTEM": "balantflow_test",
                "APPDIR": "/app/servers",
                "ssl": "false",
                "HOSTNAME": "centos7base",
                "XDG_RUNTIME_DIR": "/run/user/0",
                "OLDPWD": "/app",
                "APP_SERVER_HOME": "/app/servers/balantflow",
                "TECHSURE_HOME": "/app",
                "_": "/app/serveradmin/bin/serveradmin",
                "SHELL": "/bin/bash",
                "CLASSPATH": "/app/systems/balantflow/config/:.:/usr/local/itom/java/lib.tools.jar:/app/servers/balantflow/lib/:/app/servers/balantflow/lib/annotations-api.jar:/app/servers/balantflow/lib/catalina-ant.jar:/app/servers/balantflow/lib/catalina-ha.jar:/app/servers/balantflow/lib/catalina.jar:/app/servers/balantflow/lib/catalina-ssi.jar:/app/servers/balantflow/lib/catalina-storeconfig.jar:/app/servers/balantflow/lib/catalina-tribes.jar:/app/servers/balantflow/lib/ecj-4.18.jar:/app/servers/balantflow/lib/el-api.jar:/app/servers/balantflow/lib/jasper-el.jar:/app/servers/balantflow/lib/jasper.jar:/app/servers/balantflow/lib/jaspic-api.jar:/app/servers/balantflow/lib/jsp-api.jar:/app/servers/balantflow/lib/mysql-connector-java-5.1.25.jar:/app/servers/balantflow/lib/servlet-api.jar:/app/servers/balantflow/lib/techsure-balantrealm8.jar:/app/servers/balantflow/lib/techsure-valve8.jar:/app/servers/balantflow/lib/tomcat-api.jar:/app/servers/balantflow/lib/tomcat-coyote.jar:/app/servers/balantflow/lib/tomcat-dbcp.jar:/app/servers/balantflow/lib/tomcat-i18n-cs.jar:/app/servers/balantflow/lib/tomcat-i18n-de.jar:/app/servers/balantflow/lib/tomcat-i18n-es.jar:/app/servers/balantflow/lib/tomcat-i18n-fr.jar:/app/servers/balantflow/lib/tomcat-i18n-ja.jar:/app/servers/balantflow/lib/tomcat-i18n-ko.jar:/app/servers/balantflow/lib/tomcat-i18n-pt-BR.jar:/app/servers/balantflow/lib/tomcat-i18n-ru.jar:/app/servers/balantflow/lib/tomcat-i18n-zh-CN.jar:/app/servers/balantflow/lib/tomcat-jdbc.jar:/app/servers/balantflow/lib/tomcat-jni.jar:/app/servers/balantflow/lib/tomcat-util.jar:/app/servers/balantflow/lib/tomcat-util-scan.jar:/app/servers/balantflow/lib/tomcat-websocket.jar:/app/servers/balantflow/lib/websocket-api.jar::/app/servers/balantflow/bin/bootstrap.jar:/app/servers/balantflow/bin/commons-daemon.jar:/app/servers/balantflow/bin/tomcat-juli.jar:",
                "HTTPS_PORT": "9345",
                "HISTCONTROL": "ignoredups"
            },
            "COMM": "java",
            "OS_ID": "380303927205890"
        },
        "JVM_VERSION": "1.8.0_77-b03",
        "PORTS": ["8080", "9345"],
        "_OBJ_TYPE": "Tomcat",
        "OS_ID": "380303927205890",
        "SSL_PORT": "9345",
        "VERSION": "9.0.44.0",
        "_OBJ_CATEGORY": "APP"
    }
```

## oscollect执行说明
- oscollect会完成对OS、HOST、应用的自动发现和信息收集
- 支持通过json参数输入密码设置
- 支持只对某一类别的对象进行发现和收集
譬如只收集Mysql
```
oscollector  --class Mysql,Postgresql --defaultpassconf '{"Mysql":{"username":"root","password":"xxxxxx"},"Postgresql":{"username":"postgres","password":"xxxxxx"}}'
```
譬如收集Apache、Tomcat、Mysql
```
oscollector  --class Apache,Tomcat,Mysql
```
