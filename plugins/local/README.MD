# Plugins Local README
------
## 工具开发说明
此目录用于存放本地和本地远程执行的插件，插件只支持长选项参数。
本地运行就是在Runner节点上执行的工具，跟远程OS无关的工具存放此目录下。
此目录下的工具主要完成跟远程OS无关的数据、文件处理和保存的工作。
一个工具由两个文件组成，例如：mytool和mytool.json，mytool是工具的实现；mytool.json是工具的输入输出参数描述。
工具开发例子请参考子目录 demo 下的工具和工具的json文件。

## ServerAdapter.pm 接口说明
plugins/local/lib/ServerAdapter.pm
lib/ServerAdapter.py 里有getDeployIdPath的方法，与SeverAdapter.pm的getIdPath一致
```perl
        $self->{apiMap} = {
            'getIdPath'             => '',
            'getVer'                => '',
            'updateVer'             => '',
            'releaseVer'            => '',
            'getAutoCfgConf'        => '',
            'getDBConf'             => '',
            'addBuildQulity'        => '',
            'getAppPassWord'        => '',
            'getSqlFileStatuses'    => 'codedriver/public/api/rest/autoexec/job/sql/list',
            'checkInSqlFiles'       => 'codedriver/public/api/rest/autoexec/job/sql/checkin',
            'pushSqlStatus'         => 'codedriver/public/api/rest/autoexec/job/sql/update',
            'creatJob'              => '',
            'getJobStatus'          => '',
            'saveVersionDependency' => '',
            'setEnvVersion'         => '',
            'rollbackEnvVersion'    => '',
            'setInsVersion'         => '',
            'rollbackInsVersion'    => '',
            'getBuild'              => ''
        };
```
### Tenant信息
Tenant信息在HTTP header中

### 资源中心接口
### - getIdPath
#### 功能：根据应用模块的名称信息从资源中心获取ID信息
#### 输入：应用名称，模块名称，环境名(可选）
    {
        sysName    => 'MyApplication', 
        moduleName => 'MyModule',
        envName    => 'UAT'
    }
    {
        sysName    => 'MyApplication', 
        moduleName => 'MyModule'
    }
#### 输出
    {
        sysId    => 11111111,
        moduleId => 22222222,
        envId    => 3
    }

### 版本中心接口
### - getVer
#### 功能： 获取版本详细信息
    包括：repoType, repo, branch, tag, tagsDir, lastBuildNo, isFreeze，startRev, endRev;
    startRev: 如果是新版本，则获取同一个仓库地址和分支的所有版本最老的一次build的startRev；如果是现有的版本，则获取当前版本的startRev；如果获取不到则默认是0
#### 输入(JSON)：
    {
        runnerId   => Runner的ID,
        jobId      => 作业ID,
        phaseName  => 阶段名,
        sysId      => 应用ID,
        moduleId   => 模块ID,
        envId      => 环境ID,
        sysName    => 应用名,
        moduleName => 模块名,
        envName    => 环境名,
        version    => 版本号,
        buildNo    => BuildNo
    }
#### 输出(JSON):
    GIT工程样例：
    {
        version  => '1.8.0',
        buildNo  => 3,
        repoType => 'GIT',
        repo     => 'http://192.168.0.82:7070/luoyu/webTest.git',
        trunk    => 'master',
        branch   => '2.0.0',
        tag      => '',
        tagsDir  => undef,
        isFreeze => 0,
        startRev => 'bda9fb6f',
        endRev   => 'f2a9c727',
    }

    SVN工程样例：
    {
        version  => '1.8.0',
        buildNo  => 3,
        repoType => 'SVN',
        repo     => 'svn://192.168.0.88/webTest',
        trunk    => 'trunk',
        branch   => 'branches/1.0.0',
        tag      => undef,
        tagsDir  => 'tags',
        isFreeze => 0,
        startRev => '0',
        endRev   => '32',
    }

### - updateVer
#### 功能：更新版本信息（部分key）
#### 输入(JSON)：
    {
        runnerId   => Runner的ID,
        jobId      => 作业ID,
        phaseName  => 阶段名,
        sysId      => 应用ID,
        moduleId   => 模块ID,
        envId      => 环境ID,
        sysName    => 应用名,
        moduleName => 模块名,
        envName    => 环境名,
        version    => 版本号,
        buildNo    => BuildNo,
        verInfo    => {
            isFreeze => 0,
            startRev => 'bda9fb6f',
            endRev   => 'f2a9c727',
        }
    }
#### 输出(JSON):
    无

### - releaseVer
#### 功能：更新某个version的buildNo的release状态为1，build成功
#### 输入(JSON)：
    {
        runnerId   => Runner的ID,
        jobId      => 作业ID,
        phaseName  => 阶段名,
        sysId      => 应用ID,
        moduleId   => 模块ID,
        envId      => 环境ID,
        sysName    => 应用名,
        moduleName => 模块名,
        envName    => 环境名,
        version    => 版本号,
        buildNo    => BuildNo
    }
#### 输出(JSON):
    无

### AutoCfg配置接口
#### - getAutoCfgConf
#### 功能：获取某个环境的AutoCfg配置，要求在发布配置中，对每个实例重新命名（主要是为了能够按照名字排序）
#### 输入(JSON)：
    {
        runnerId   => Runner的ID,
        jobId      => 作业ID,
        phaseName  => 阶段名,
        sysId      => 应用ID,
        moduleId   => 模块ID,
        envId      => 环境ID,
        sysName    => 应用名,
        moduleName => 模块名,
        envName    => 环境名
    }
#### 输出(JSON):
    AutoCfg的配置
    {
        autoCfg => {
            basic    => 'mybasicval',
            password => 'mypasswd'
        },
        insCfgList => [
            {
                insName => "insName1",
                autoCfg => {
                    basic    => 'ins1-mybasicval',
                    password => 'ins1-mypasswd'
                }
            },
            {
                insName => "insName2",
                autoCfg => {
                    basic    => 'ins2-mybasicval',
                    password => 'ins2-mypasswd'
                }
            }
        ]
    }
    如果没有配置AutoCfg则返回空的Map
    {
        autoCfg => {
            basic    => 'mybasicval',
            password => 'mypasswd'
        },
        insCfgList => []
    }
    或者：
    {
        autoCfg => {},
        insCfgList => []
    }

### DBConf接口
- getDBConf
#### 功能：获取某个环境的AutoCfg配置
#### 输入(JSON)：
    {
        runnerId   => Runner的ID,
        jobId      => 作业ID,
        phaseName  => 阶段名,
        sysId      => 应用ID,
        moduleId   => 模块ID,
        envId      => 环境ID,
        sysName    => 应用名,
        moduleName => 模块名,
        envName    => 环境名
    }
#### 输出(JSON):
    DBCfg的配置
    {
       'dbname1.dbuser1' => {
            node => {
                resourceId     => 9823748347,
                nodeName       => 'bsm',
                accessEndpoint => '192.168.0.26:3306',
                nodeType       => 'Mysql',
                host           => '192.168.0.26',
                port           => 3306,
                username       => 'root',
                password       => '{ENCRYPTED}05a90b9d7fcd2449928041'
            },
            args => {
                locale            => 'en_US.UTF-8',
                fileCharset       => 'UTF-8',
                autocommit        => 0,
                dbVersion         => '10.3',
                dbArgs            => '',
                ignoreErrors      => 'ORA-403',
                dbaRole           => undef,           #DBA角色，如果只允许DBA操作SQL执行才需要设置这个角色名
                oraWallet         => '',              #只有oracle需要
                db2SqlTerminator  => '',              #只有DB2需要
                db2ProcTerminator => ''               #只有DB2需要
            }
        },
       'dbname1.dbuser2' => {
           ...
       }
       'dbname2.dbuser3' => {
           ...
       }
    }
    如果没有配置AutoCfg则返回空的Map
    {}

### SonarQube数据上传
- addBuildQulity
#### 移植老版本的表结构和接口


### 根据URL和IP端口等获取密码
- getAppPassWord
#### 功能：获取某个IP资源的账号
#### 输入(JSON)：
    {
        runnerId   => Runner的ID,
        jobId      => 作业ID,
        phaseName  => 阶段名,

        host       => IP地址,
        port       => 端口,
        protocol   => 协议（http|https）等,
        userName   => 用户名
    }
#### 输出（JSONArray）
    [
        {
            username => 'myuser',
            password => '{ENCRYPTED}0bad068c79dd721e'
        },
        {
            ...
        }
    ]

### SQL文件相关接口
- getSqlFileStatuses
- checkInSqlFiles
- pushSqlStatus

### 作业相关接口
- creatJob
#### 功能：创建作业或子作业（如果提供的jobId不存在则直接创建顶层作业，否则创建子作业）
#### 输入(JSON)：
    {
        jobId         => 当前作业ID,
        targetEnvPath => 目标Env路径，例如：'MYAPP/MYMODULE/UAT',
        targetVersion => 目标版本号，例如：'1.3.0',
        senario       => 目标场景，例如：'版本入基线',
        isRunNow      => 1, #马上执行
        isAuto        => 1, #如果是计划执行，自动启动作业
        planTime      => ‘2022/04/06 12:10:05’, #计划执行时间
        roundCount    => 2, #分批数量
        jobUser       => ‘system’, #作业用户
        instances     => ['192.168.0.2:8080', '192.168.0.3:8080'],
        jobArgs       => {
                             arg1 => 'xxxxx',
                             arg2 => 'yyyyy'
                         }
    }
#### 输出（JSONArray）
    {
        jobId => 3209843243
    }

- getJobStatus
#### 功能：根据作业Id，获取作业执行状态
#### 输入(JSON)：
    {
        jobId => 作业Id
    }
#### 输出（JSONArray）
    {
        status => 'running'
    }

### Maven依赖扫描接口数据上传
- saveVersionDependency
#### 移植老版本的表结构和接口


### 环境和实例版本标记接口
- setEnvVersion
#### 功能：设置某个环境的版本号
#### 输入(JSON)：
    {
        runnerId   => Runner的ID,
        jobId      => 作业ID,
        phaseName  => 阶段名,
        sysId      => 应用ID,
        moduleId   => 模块ID,
        envId      => 环境ID,
        sysName    => 应用名,
        moduleName => 模块名,
        envName    => 环境名,
        version    => 版本号,
        buildNo    => Build号
    }
### 输出：
    无

- rollbackEnvVersion
#### 功能：回退某个环境的版本到发布前的版本号
#### 输入(JSON)：
    {
        runnerId   => Runner的ID,
        jobId      => 作业ID,
        phaseName  => 阶段名,
        sysId      => 应用ID,
        moduleId   => 模块ID,
        envId      => 环境ID,
        sysName    => 应用名,
        moduleName => 模块名,
        envName    => 环境名,
        version    => 版本号,
        buildNo    => Build号
    }
### 输出：
    无

- setInsVersion
#### 功能：设置某个实例的版本号
#### 输入(JSON)：
    {
        runnerId   => Runner的ID,
        jobId      => 作业ID,
        phaseName  => 阶段名,
        sysId      => 应用ID,
        moduleId   => 模块ID,
        envId      => 环境ID,
        sysName    => 应用名,
        moduleName => 模块名,
        envName    => 环境名,
        resourceId => 实例的CMDB ID,
        version    => 版本号,
        buildNo    => Build号
    }
### 输出：
    无

- rollbackInsVersion
#### 功能：回退某个实例的版本号
#### 输入(JSON)：
    {
        runnerId   => Runner的ID,
        jobId      => 作业ID,
        phaseName  => 阶段名,
        sysId      => 应用ID,
        moduleId   => 模块ID,
        envId      => 环境ID,
        sysName    => 应用名,
        moduleName => 模块名,
        envName    => 环境名,
        resourceId => 实例的CMDB ID,
        version    => 版本号,
        buildNo    => Build号
    }
### 输出：
    无

### 跨环境（生产到测试）下载版本build物料接口
- getBuild
#### 移植老版本的表结构和接口