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
  --abort, -k           abort the job
  --register REGISTER, -r REGISTER
                        register all tools to tenent
  --devmode, -d         develope test in command line
  
```

## 使用
###测试
使用测试专用参数--devmode，使用此参数后不会对控制端进行查询和回调，所以需要参数--paramsfile指定参数文件的路径，--nodesfile指定运行目标节点。
```shell
python3 bin/autoexec --paramsfile /Users/wenhb/git/autoexec/test/params.json --n /Users/wenhb/git/autoexec/test/nodes.json --devmode
```
