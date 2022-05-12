# AUTOEXEC README

------
## 主要功能
autoexec是自动化runner上的backend执行工具。用于执行自动化作业，接收控制服务端的作业调度指令，并根据控制端提供的作业参数和执行目标节点执行参数给出的操作，并回调服务端回写状态。

## 参数
```shell
usage: autoexec [-h] [-v] [--jobid JOBID] [--execuser EXECUSER] [--paramsfile PARAMSFILE]
                [--nodesfile NODESFILE] [--force] [--firstfire] [--abort] [--pause]
                [--register REGISTER] [--cleanstatus] [--purgejobdata PURGEJOBDATA] [--devmode]
                [--nofirenext] [--passthroughenv PASSTHROUGHENV] [--phasegroups PHASEGROUPS]
                [--phases PHASES] [--nodes NODES] [--sqlfiles SQLFILES]

optional arguments:
  -h, --help            show this help message and exit
  -v, --verbose         Automation Runner
  --jobid JOBID, -j JOBID
                        Job id for this execution
  --execuser EXECUSER, -u EXECUSER
                        Operator
  --paramsfile PARAMSFILE, -p PARAMSFILE
                        Params file path for this execution
  --nodesfile NODESFILE, -n NODESFILE
                        Nodes file path for this execution
  --force, -f           Force to run all nodes regardless the node status
  --firstfire, -i       the first phase fired, create new log file
  --abort, -k           abort the job
  --pause, -s           puase the job
  --register REGISTER, -r REGISTER
                        register all tools to tenent
  --cleanstatus, -c     clean all stats of job
  --purgejobdata PURGEJOBDATA
                        Job reserve days
  --devmode, -d         develope test in command line
  --nofirenext          do not fire next job phase
  --passthroughenv PASSTHROUGHENV
                        Additinal json parameter while callback to console
  --phasegroups PHASEGROUPS
                        Just execute specify group
  --phases PHASES       Just execute defined phases, Example:phase1,phase2
  --nodes NODES         Just execute defined node ids, Example:463104705880067,463104705880068
  --sqlfiles SQLFILES   Just execute defined sql files,
                        Example:["mydb.myuser/1.test.sql","mydb.myuser1/2.test.sql"]
```

## 使用
### python3 在Linux上的安装后，更改python3位默认的python执行程序
执行autoexec目录下的setup.sh切换python3位默认python
```shell
cd autoexec
./setup.sh
```
### 安装python3第三方库
```
cd autoexec/media
./ins-modules.sh
```
python3第三方库会安装到目录autoexec/plib下

### 安装本地工具需要的perl的第三方库
```shell
cd autoexec/plugins/local/media
./setup.sh
```

### 重新安装本地工具需要的perl的某些第三方库
- 以安装Config-Tiny-2.28和XML-Simple-2.22.tar为例
```shell
cd autoexec/plugins/local/media
./setupone.sh Config-Tiny-2.28 XML-Simple-2.22
```
perl第三方库会安装到autoexec/plugins/local/pllib

### VSCode设置
- 设置.vscode/settings.json（参考test/examples-files/settings.json)
- 设置.vscode/launch.json (用python和perl的单步调试，参考test/examples-files/launch.json))
- 设置python环境变量（参考test/examples-files/.penv，此文件会被settings.json引用）
- 需要把上述三个文件拷贝到工程的.vscode目录下，根据实际目录进行修改

### 开发调试模式
- 运行调试
```shell
#设置环境变量
#设置租户环境变量tenant，以测试租户develop为例
export TENANT=develop
#设置Passthrough的json，runnerId属性是必须的，通过页面的runner管理查询当前runner对应的ID
export PASSTHROUGH_ENV='{"runnerId":1}'
#设置Python的lib目录
export AUTOEXEC_HOME=/app/autoexec
export PYTHONPATH=$AUTOEXEC_HOME/plugins/local/lib:$AUTOEXEC_HOME/lib:$AUTOEXEC_HOME/plib
export PERL5LIB=$AUTOEXEC_HOME/plugins/local/lib:$AUTOEXEC_HOME/plugins/local/lib/perl-lib/lib/perl5
```

```shell
#使用devmode则不会回调服务端更新或者获取数据，仅仅使用作业目录下的nodes.json，params.json文件里的信息执行作业
$ python3 bin/autoexec --devmode --paramsfile test/params.json --n test/nodes.json

$ python3 bin/autoexec --devmode --jobid 97867868 --n test/nodes.json

$ python3 bin/autoexec --devmode --jobid 97867868 --paramsfile test/params.json
```
> 注意:
> 
>* 如果没有指定jobid，则使用默认的jobid 0
>* 如果没有设置参数paramsfile，需要指定jobid，告诉autoexec下载哪个作业的运行参数。
>* 如果没有设置参数nodes.json，而且paramsfile中没有"runNode"属性，需要指定jobid，告诉autoexec下载哪个作业的运行的目标节点。否则，autoexec就会认为没有运行目标节点。 
>* 如果在测试模式下或者当前进程关联了TTY，autoexec的console输出日志回直接打印到console。如果在生产模式下运行，console输出会写入日志文件中。运行目标相关的日志，不管在哪个模式下都会写入每个运行目标独立的日志文件中。

- VSCode lauch.json配置样例
```json
{
    "version": "0.2.0",
    "configurations": [{
            "name": "autoexec",
            "type": "python",
            "request": "launch",
            "program": "${workspaceFolder}/bin/autoexec",
            "env": {
                "RUNNER_ID": "1",
                "TENANT": "develop",
                "PASSTHROUGH_ENV": "{\"runnerId\":1}",
            },
            "args": ["--jobid",
                "623789909794820",
                "--firstfire",
                "--execuser",
                "fccf704231734072a1bf80d90b2d1de2",
                "--passthroughenv",
                "{\"runnerId\":1}",
                "--paramsfile",
                "${workspaceFolder}/test/params.json",
                "--nodesfile", "${workspaceFolder}/test/nodes.json"
            ],

            "console": "integratedTerminal"
        },
        {
            "name": "autoexec-abort",
            "type": "python",
            "request": "launch",
            "program": "${workspaceFolder}/bin/autoexec",
            "env": {
                "RUNNER_ID": "1",
                "TENANT": "develop",
                "PASSTHROUGH_ENV": "{\"runnerId\":1}",
            },
            "args": ["--jobid",
                "623907543244820",
                "--execuser",
                "fccf704231734072a1bf80d90b2d1de2",
                "--passthroughenv",
                "{\"runnerId\":1}",
                "--abort"
            ],

            "console": "integratedTerminal"
        }
    ]
}
```
- .vscode/settings.json配置样例
```json
{
    "python.envFile": "/Users/wenhb/git/autoexec/.vscode/.env",
    "perltidy.profile": "/Users/wenhb/git/autoexec/.vscode/.perltidyrc",
    "perl.perlInc": [
        ".",
        "/Users/wenhb/git/autoexec/plugins/remote/wastool/bin",
        "/Users/wenhb/git/autoexec/plugins/local/build/lib",
        "/Users/wenhb/git/autoexec/plugins/local/deploy/lib",
        "/Users/wenhb/git/autoexec/plugins/local/pllib/lib/perl5",
        "/Users/wenhb/git/autoexec/plugins/local/lib",
        "/Users/wenhb/git/autoexec/plugins/remote/lib",
        "/Users/wenhb/git/autoexec/plugins/remote/cmdbcollect/lib"
    ],
    "java.configuration.updateBuildConfiguration": "interactive",
}
```

### 生产模式
- 注册内置工具

```shell
$ python3 bin/autoexec --register tenant_name
```

*注册autoexec下的local和remote工具到某个租户下，tenant_name是租户的名称*

- 运行作业

```shell
$ python3 bin/autoexec --jobid "2983676" --execuser "admin" --paramsfile "params.json"
```
*生产模式需要提供--jobid、--execuser、--paramsfile参数，作业运行过程中，某个节点运行结束、某个阶段运行结束，都会对后端服务进行callback，更新对应的状态。*

- 中止作业

```shell
python3 bin/autoexec --jobid "2983676" --abort
```
*停止某个作业的运行，使用--jobid指定需要停止的作业号，被中止的节点会以状态"已中止"callback后台服务。*
*进程返回值：0:停止成功；1:停止失败；2:作业不存在*

- 暂停作业

```shell
python3 bin/autoexec --jobid "2983676" --pause
```
*暂停某个作业的运行，使用--jobid指定需要停止的作业号，调度器会等到最近发起的节点运行完成。*
*进程返回值：0:停止成功；1:停止失败；2:作业不存在*

- 清理作业的运行状态记录
```shell
python3 bin/autoexec --jobid "374288003424256" --cleanstatus
```
*作业运行后会存储了各个节点的状态，运行成功的不会再运行，如为了测试需要，则可以执行此命令清除状态记录*

## 文件目录介绍
### 程序文件
- bin/autoexec 

*主程序，进行参数处理和初始化作业运行需要的目录环境变量等信息*

- lib/VContext.py
- lib/Context.py
*VContext.py是Context.py的父亲类*
*保存所有运行相关的信息，在各个环境进行传递。信息包括:作业ID、执行用户、日志和状态等相关路径信息、各个阶段的运行状态、MongoDB的连接等等*

- lib/AutoexecError.py

*运行异常封装类*

- lib/NodeStatus.py

*节点状态的枚举类*

- lib/Operation.py

*操作信息类，用于记录操作相关的属性，完成对操作的运行准备:包括文件参数的文件下载、参数引用的解决，操作命令行生成等。*

- lib/OutputStoe.py

*用于保存每个运行节点的output保存到MongoDB，以及从MongoDB加载。*

- lib/PhaseExecutor.py

*每个阶段的执行器，每个阶段会实例化一个执行器，执行器创建线程池，读取Node节点信息生成RunNode对象，交由线程池的线程进行执行。*

- lib/PhaseStatus.py

*用于记录每个阶段的执行状态:成功、失败、忽略的节点数量。*

- lib/RunNode.py

*运行节点，节点运行的主程序，根据参数和节点类型选择正确的运行方式运行某个阶段的所有操作，并完成节点的状态、output记录。*

- lib/RunNodeFactory.py

*节点信息文件的Iterator*

- lib/ServerAdapter.py

*后台控制端的接口的Adapter类，到后台控制端的所有调用都经过它。*

- lib/TagentClient.py

*Tagent Client的python实现*

- lib/Utils.pm

*工具类，所有小的可以共享的方法存放在这*

### 运行时数据日志目录
- data

*目录，保存所有作业数据的根目录*

- data/cache

*文件类型参数下载文件的cache目录，以文件id作为保存的名字，下载文件是会传送lastModified属性到服务端，如果没有修改，服务端返回304。作业会建立hard link到这个目录中的文件。*

- data/job/xxx/yyy/zzz

*作业的运行目录，xxx/yyy/zzz是作业ID以3个字节切分得到的子目录，这样做是为了避免一个子目录下的文件目录数量太多，影响性能。*

- data/job/xxx/yyy/zzz/file

*作业运行需要的文件参数的文件存放目录，均是hard link到上述的cache目录*

- data/job/xxx/yyy/zzz/log

*各个阶段运行的日志保存的地方，每个节点保存一个日志。*</br>
*譬如:data/job/xxx/yyy/zzz/log/post，post就是阶段名，data/job/xxx/yyy/zzz/log/post/192.168.0.1-22.txt，192.168.0.1是节点的IP，22是节点的端；data/job/xxx/yyy/zzz/log/post/192.168.0.1-22.hislog/20210521-112018.anonymous.txt是节点的历史日志，历史日志名称包括了执行开始时间，执行用户，文件的最后修改时间就是执行的结束时间。*

- data/job/xxx/yyy/zzz/output

*节点运行的output目录，保存每个节点的output文件。每个节点一个output文件，譬如:192.168.0.22-3939.json。内容样例子:*

- i18n

*存放cmdb自动采集的各种对象的数据结构描述
*导入cmdb和巡检对象描述的方法
```shell
cd autoexec
source ./setenv.sh
cd autoexec/i18n/cmdbcollect
python3 dicttool 
```

- plugins/local

* 在Runner上运行的内置工具目录，一个子目录是一个工具组，工具组中存放多个工具，每个工具包括实现的程序和json描述文件

- plugins/remote

* 在目标OS上运行的内置工具目录，一个子目录是一个工具组，工具组中存放多个工具，每个工具包括实现的程序和json描述文件

```json
{
    "localdemo": {
        "outtext": "this is the text out value",
        "outfile": "this is the output file name",
        "outjson": "{\"key1\":\"value1\", \"key2\":\"value2\"}",
        "outcsv": "\"name\",\"sex\",\"age\"\\n\"\u5f20\u4e09\u201c,\"\u7537\u201c,\"30\"\\n\"\u674e\u56db\",\"\u5973\u201c,\"35\"",
        "outpassword": "{RC4}xxxxxxxxxx"
    },
    "localremotedemo_tttt": {
        "outfile": "this is the output file name",
        "outtext": "this is the text out value",
        "outpassword": "{RC4}xxxxxxxxxx",
        "outcsv": "\"name\",\"sex\",\"age\"\\n\"\u5f20\u4e09\u201c,\"\u7537\u201c,\"30\"\\n\"\u674e\u56db\",\"\u5973\u201c,\"35\"",
        "outjson": "{\"key1\":\"value1\", \"key2\":\"value2\"}"
    },
    "remotedemo_34234": {
        "outcsv": "\"name\",\"sex\",\"age\"\\n\"\u00e5\u00bc\u00a0\u00e4\u00b8\u0089\u00e2\u0080\u009c,\"\u00e7\u0094\u00b7\u00e2\u0080\u009c,\"30\"\\n\"\u00e6\u009d\u008e\u00e5\u009b\u009b\",\"\u00e5\u00a5\u00b3\u00e2\u0080\u009c,\"35\"",
        "outjson": "{\"key1\":\"value1\", \"key2\":\"value2\"}",
        "outfile": "this is the output file name",
        "outpassword": "{RC4}xxxxxxxxxx",
        "outtext": "this is the text out value"
    }
}
```

- data/job/xxx/yyy/zzz/status
保存每个节点和节点关联操作运行状态的目录。每个节点一个status文件，譬如:post/192.168.0.22-3939.json（post阶段的节点192.168.0.22:3939的执行状态）。内容样例子:

```json
{
    "status": "succeed",
    "localremotedemo_tttt": "succeed",
    "remotedemo_34234": "succeed"
}
```

## 参数文件样例

```json
{
    "jobId": 624490098515988,
    "roundCount": 64,
    "opt": {},
    "runFlow": [
        {
            "execStrategy": "oneShot",
            "groupNo": 0,
            "phases": [
                {
                    "operations": [
                        {
                            "output": {},
                            "opt": {},
                            "opName": "shell倒计时",
                            "opType": "runner",
                            "isScript": 1,
                            "opId": "shell倒计时_624490098515994",
                            "interpreter": "bash",
                            "failIgnore": 1,
                            "desc": {}
                        }
                    ],
                    "phaseName": "oneshot_local"
                },
                {
                    "operations": [
                        {
                            "output": {},
                            "opt": {},
                            "opName": "shell倒计时_target",
                            "opType": "target",
                            "isScript": 1,
                            "opId": "shell倒计时_target_624490098515998",
                            "interpreter": "bash",
                            "failIgnore": 1,
                            "desc": {}
                        }
                    ],
                    "phaseName": "oneshot_target"
                }
            ]
        },
        {
            "execStrategy": "grayScale",
            "groupNo": 1,
            "phases": [
                {
                    "operations": [
                        {
                            "output": {},
                            "opt": {},
                            "opName": "shell倒计时",
                            "opType": "runner",
                            "isScript": 1,
                            "opId": "shell倒计时_624490098516001",
                            "interpreter": "bash",
                            "failIgnore": 1,
                            "desc": {}
                        }
                    ],
                    "execRound": "first",
                    "phaseName": "grayscale_local"
                },
                {
                    "operations": [
                        {
                            "output": {},
                            "opt": {},
                            "opName": "shell倒计时_target",
                            "opType": "target",
                            "isScript": 1,
                            "opId": "shell倒计时_target_624490098516163",
                            "interpreter": "bash",
                            "failIgnore": 1,
                            "desc": {}
                        }
                    ],
                    "phaseName": "grayscale_target"
                }
            ]
        },
        {
            "execStrategy": "oneShot",
            "groupNo": 2,
            "phases": [
                {
                    "operations": [
                        {
                            "output": {},
                            "opt": {},
                            "opName": "shell倒计时",
                            "opType": "runner",
                            "isScript": 1,
                            "opId": "shell倒计时_624490098516166",
                            "interpreter": "bash",
                            "failIgnore": 1,
                            "desc": {}
                        }
                    ],
                    "phaseName": "oneshot_local2"
                }
            ]
        }
    ],
    "arg": {},
    "execUser": "system",
    "tenant": "develop"
}
```

说明:

- "jobId": 作业Id，如果定义的跟autoexec的命令行参数--jobid不一致，会强行改成一致。
- "roundCount": 分组运行分组的数量
- "preJobId": 前一个作业的Id，用于在ITSM流程串接多个作业时传入，会在callback时回传到控制后台。(deprecated)
- "runNode":如果含有此属性，运行目标就以此为准，autoexec不会再调用接口获取运行需要的目标节点。
- "opt": 整个作业的输入参数列表，结构是key value结构
- "runFlow": 数组结构，包括多个运行组，一个数组元素是一个运行组，autoexec会按顺序执行运行组。运行组是key value结构，key是运行阶段（phase）的名称，运行阶段内容由多个操作组成的数组。一个运行组内的多个阶段会并发运行。
- 操作内的参数"isScript": 表示此操作是自定义脚本，如果isScript是1，那么必须有另外一个参数"scriptId"给出script的Id，这样autoexec才能根据scriptId到控制端下载脚本。

## nodes文件样例

```json
{ "resourceId": 456, "nodeName":"myhost", "nodeType": "host", "host": "192.168.0.27", "protocol":"ssh", "protocolPort":22, "username": "root", "password": "xxxxxx" }
{ "resourceId": 567,"nodeName":"tomcat1", "nodeType": "tomcat", "host": "192.168.0.22", "protocol":"tagent", "protocolPort":3939, "port": 8080, "username": "root", "password": "{RC4}xxxxxxx" }
{ "resourceId": 458, "nodeName":"tomcat2", "nodeType": "tomcat", "host": "192.168.0.26", "protocol":"tagent", "protocolPort":3939, "port": 8080, "username": "root", "password": "xxxxxxxx" }

```

补充说明:

- "resourceId": 运行目标节点的UUID
- "nodeName": 节点名称（不一定唯一）
- "nodeType": 表示连接节点的方式
- "host": 连接目标的IP
- "port": 目标节点的端口（IP+服务端口确定一个目标节点）
- "protocol": 连接节点远程操作的协议，ssh｜tagent
- "protocolPort": 连接协议对应的端口
- "username": 在目标节点运行工具的OS用户s
- "password": 连接目标节点的密码

 


