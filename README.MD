# AUTOEXEC README

------
## 主要功能
autoexec是自动化runner上的backend执行工具。用于执行自动化作业，接收控制服务端的作业调度指令，并根据控制端提供的作业参数和执行目标节点执行参数给出的操作，并回调服务端回写状态。

## 参数
```shell
$ python3 bin/autoexec --helpusage: autoexec [-h] [-v] [--jobid JOBID] [--execuser EXECUSER]
                [--paramsfile PARAMSFILE] [--nodesfile NODESFILE] [--force]
                [--abort] [--register REGISTER] [--devmode]

optional arguments:
  -h, --help            show this help message and exit
  --jobid JOBID, -j JOBID
                        Job id for this execution
  --execuser EXECUSER, -u EXECUSER
                        Operator
  --paramsfile PARAMSFILE, -p PARAMSFILE
                        Params file path for this execution
  --nodesfile NODESFILE, -n NODESFILE
                        Nodes file path for this execution
  --force, -f           Force to run all nodes regardless the node status
  --abort, -k           abort the job
  --register REGISTER, -r REGISTER
                        register all tools to tenent
  --devmode, -d         develope test in command line
  
```

## 使用
### 开发调试模式
- 运行调试

```shell
$ python3 bin/autoexec --devmode --paramsfile test/params.json --n test/nodes.json

$ python3 bin/autoexec --devmode --jobid 97867868 --n test/nodes.json

$ python3 bin/autoexec --devmode --jobid 97867868 --paramsfile test/params.json
```
> 注意：

>* 如果没有指定jobid，则使用默认的jobid 0

>* 如果没有设置参数paramsfile，需要指定jobid，告诉autoexec下载哪个作业的运行参数。

>* 如果没有设置参数nodes.json，而且paramsfile中没有"runNode"属性，需要指定jobid，告诉autoexec下载哪个作业的运行的目标节点。否则，autoexec就会认为没有运行目标节点。 

>* 如果在测试模式下或者当前进程关联了TTY，autoexec的console输出日志回直接打印到console。如果在生产模式下运行，console输出会写入日志文件中。运行目标相关的日志，不管在哪个模式下都会写入每个运行目标独立的日志文件中。

### 生产模式
- 运行作业

```shell
$ python3 bin/autoexec --jobid "2983676" --execuser "admin" --paramsfile "params.json"
```
> 生产模式需要提供--jobid、--execuser、--paramsfile参数

- 中止作业

```shell
python3 bin/autoexec --jobid "2983676" --abort
```
> 停止某个作业的运行，使用--jobid指定需要停止的作业号


