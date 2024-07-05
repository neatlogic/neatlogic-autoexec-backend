
#本地执行的可用的环境变量（runner、runnter-target执行）
AUTOEXEC_HOME=/app/systems/autoexec
自动化程序目录
TOOLS_PATH=/app/systems/autoexec/tools
存放自动化使用到的工具的目录

AUTOEXEC_JOBID=1192617252339719
当前作业ID
AUTOEXEC_EXECID=1192692472987648
当前执行的ID（区别于JOBID，同一个作业会执行多次，每次执行都有一个独立的执行ID）
AUTOEXEC_PID=12778
作业进程环境变量
AUTOEXEC_TENANT=develop
当前租户名（因为系统的多租户的）
AUTOEXEC_USER=fccf704231734072a1bf80d90b2d1de2
执行当前作业的登录用户ID
AUTOEXEC_WORK_PATH=/app/systems/autoexec/data/job/119/261/725/233/971/9
作业执行的工作目录，存放日志，状态，输出等数据的目录
AUTOEXEC_JOB_SOCK=/app/systems/autoexec/data/job/119/261/725/233/971/9/job1192692472987648.sock
用于跟自动化作业通讯的Unix socket文件（通过此文件，发送报文给作业进程进行通讯）

AUTOEXEC_NODE={"resourceId": 0, "protocol": "local", "host": "local", "port": 0, "username": "", "password": ""}
基于节点操作的当前执行目标，json格式
AUTOEXEC_NODES_PATH=/app/systems/autoexec/data/job/119/261/725/233/971/9/nodes-ph-构建.json
当前作业当前阶段的执行目标的节点文件，一行一个节点的json

AUTOEXEC_GROUP_NO=1
当前执行上下文的执行组号
AUTOEXEC_PHASE_NAME=构建
当前执行上下文的执行阶段
AUTOEXEC_OPERATION_ID=build/localscript_1192617260728506
当前执行的原子操作的ID

RUNNER_ID=710084241711116
当前执行器的ID
DEPLOY_RUNNERGROUP={"710084241711116": "192.168.0.21", "1": "192.168.1.140"}
所有的执行器组
JOB_PARAMS_PATH=/app/systems/autoexec/data/job/119/261/725/233/971/9/params.json
当前作业的执行参数json文件


OUTPUT_DIR=/app/systems/autoexec/data/job/119/261/725/233/971/9/output-op/local-0-0
存储输出参数文件的目录
OUTPUT_PATH=/app/systems/autoexec/data/job/119/261/725/233/971/9/output-op/local-0-0/build/localscript_1192617260728506.json
存放当前操作输出参数的json文件
NODE_OUTPUT_PATH=/app/systems/autoexec/data/job/119/261/725/233/971/9/output/local-0-0.json
存放当前节点输出参数的文件（包含所有的操作，合并当前阶段所有的操作的输出参数，以操作id作为key）
LIVEDATA_PATH=/app/systems/autoexec/data/job/119/261/725/233/971/9/livedata/构建/local-0-0/build/localscript_1192617260728506.json
存放用于个性化的展示面板的输出参数的json文件

DEPLOY_ID_PATH=669482179420161/669491121676288/481856650534925
CI&CD的应用和环境的ID
DEPLOY_PATH=TomcatTest/WebTest/SIT
CI&CD的应用和环境名
SYS_ID=669482179420161
当前执行上下文的系统的ID
SYS_NAME=TomcatTest
当前执行上下文的系统名
MODULE_ID=669491121676288
当前执行上下文的系统模块的ID
MODULE_NAME=WebTest
当前执行上下文的系统模块名
ENV_ID=481856650534925
当前执行上下文的系统环境的ID
ENV_NAME=SIT
当前执行上下文的系统环境名
VERSION=3.0.0
当前执行上下文的版本号
BUILD_NO=90
当前执行上下文的build number



DATA_PATH=/app/systems/autoexec/data/verdata/669482179420161/669491121676288
当前执行上下文的应用版本数据目录
PRJ_ROOT=/app/systems/autoexec/data/verdata/669482179420161/669491121676288/workspace
当前执行上下文的工程代码的父目录
PRJ_PATH=/app/systems/autoexec/data/verdata/669482179420161/669491121676288/workspace/project
当前执行上下文的工程代码目录
VER_ROOT=/app/systems/autoexec/data/verdata/669482179420161/669491121676288/artifact/3.0.0
当前执行上下文的版本相关制品的总目录
BUILD_ROOT=/app/systems/autoexec/data/verdata/669482179420161/669491121676288/artifact/3.0.0/build
当前执行上下文的编译存放版本制品的父目录
BUILD_PATH=/app/systems/autoexec/data/verdata/669482179420161/669491121676288/artifact/3.0.0/build/90
当前执行上下文的存放版本制品目录
MIRROR_ROOT=/app/systems/autoexec/data/verdata/669482179420161/669491121676288/artifact/mirror
当前执行上下文的同步镜像目录（只在使用环境镜像目录时会用到，relsync2mirror工具会把制品从build发布到此目录对应的环境下，属于特殊发布）
DIST_ROOT=/app/systems/autoexec/data/verdata/669482179420161/669491121676288/artifact/3.0.0/env
当前执行上下文的环境制品的父目录
APP_DIST=/app/systems/autoexec/data/verdata/669482179420161/669491121676288/artifact/3.0.0/env/481856650534925/app
当前执行上下文的环境制品应用包目录
DB_SCRIPT=/app/systems/autoexec/data/verdata/669482179420161/669491121676288/artifact/3.0.0/env/481856650534925/db
当前执行上下文的环境制品SQL脚本制品目录

#远程执行可用的环境变量（remote执行）
AUTOEXEC_JOBID=1192617252339719
当前作业ID
AUTOEXEC_NODE={"resourceId": 0, "protocol": "ssh", "host": "192.168.0.3", "port": 22, "username": "app", "password": ""}
基于节点操作的当前执行目标，json格式
NODE_HOST=192.168.0.3
远程节点的IP
NODE_PORT=8080
远程节点的端口
NODE_NAME=server1
远程节点的名称
