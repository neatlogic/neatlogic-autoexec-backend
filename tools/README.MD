#用于存放公用的第三方命令行工具


# mysqldictexport 导出数据字典插件说明 

## mysql数据库表与模块关系定义Map
如有新增模块或不符合规范的表单独定义，需更改此map定义
```
moduleMap = {
  "base" : "底层框架",
  "catalog" : "流程管理",
  "channel" : "流程管理",
  "process" : "流程管理",
  "processtask" : "流程管理",
  "event" : "事件管理",
  "change" : "变更管理",
  "cmdb" : "配置管理",
  "inspect" : "巡检管理",
  "autoexec" : "自动化管理",
  "discovery" : "自动化管理",
  "deploy" : "发布管理",
  "report" : "报表管理",
  "reportinstance" : "报表管理", 
  "knowledge" : "知识库管理",
  "pbc" : "监管报送",
  "custom" : "定制模块"
}
```
## 导出mysql库为Word插件帮助说明
```
./mysqldictexport --help
usage: mysqldictexport [-h] [--ip IP] [--port PORT] [--user USER]
                       [--password PASSWORD] [--dbnames DBNAMES]
                       [--outpath OUTPATH] [--modules MODULES]

optional arguments:
  -h, --help           show this help message and exit
  --ip IP              mysql db ip
  --port PORT          mysql db port
  --user USER          mysql db user
  --password PASSWORD  mysql db user password
  --dbnames DBNAMES    export databse name,default:codedriver,codedriver_demo
  --outpath OUTPATH    export output path
  --modules MODULES    export module ,default all , eg: "流程,自动化"
```
## 全量数据库表导出到问文档
./mysqldictexport --ip 192.168.0.104 --user root --password 'zanyue$2012' --outpath "/tmp"

## 选择模块导出到文档文档
默认包含底层模块
./mysqldictexport --ip 192.168.0.104 --user root --password 'zanyue$2012' --outpath "/tmp" --modules "流程,自动化"
