
## 更新字典到mongodb
./dicttool --lang zh_CN 

```
usage: dicttool [-h] [--lang LANG] [--action ACTION] [--filter FILTER]
                [--content CONTENT]

optional arguments:
  -h, --help         show this help message and exit
  --lang LANG        Language
  --action ACTION    Actions:（savetodb|append|remove|beautify|dropcollection）
  --filter FILTER    Match filter ()
  --content CONTENT  Append Json

```
## dicttool使用例子
```
dicttool --lang en_US --action remove --filter '{"collection": "COLLECT_INS"}' --content BELONG_APPLICATION
dicttool --lang en_US --action append --filter '{"collection": "COLLECT_INS"}' --content '{"name":"STATE", "desc":"Use State", "type":"String"}'
dicttool --lang en_US --action beautify
dicttool --lang zh_CN --action beautify
dicttool --lang en_US --action savetodb
dicttool --lang zh_CN --action savetodb
dicttool--action dropcollection
dicttool--action cleancollection
```
## 导出字典为Word
python3 dictexport --lang zh_CN --outpath /tmp/cmdb_attr.docx --verbose 1
```
usage: dictexport [-h] [--lang LANG] [--outpath OUTPATH] [--verbose VERBOSE]

optional arguments:
  -h, --help         show this help message and exit
  --lang LANG
  --outpath OUTPATH  output file path
  --verbose VERBOSE  verbose output

```
## cmdb采集数据自定定义
```
属性定义格式
{
    "name": "属性名称",
    "desc": "属性描述",
    "type": "数值类型：Int|Float|String|Text｜Array|JsonArray|JsonObject"
}
数值类型包括：
Int： 整数
Float：浮点数
String：子串
Text：长文本，例如进程命令行
Array：单值数组，例如：["MY","YOU"]
JsonArray：Json对象数组
JsonObject：Json对象

如果是JsonArray或者JsonObject，需要通过属性"subset"描述下游属性（可以多层嵌套）：
例如：
"subset": [
    {
        "name": "USERNAME",
        "desc": "用户名",
        "type": "String"
    },
    {
        "name": "GRNT_DBS",
        "desc": "授权DB",
        "type": "JsonArray",
        "subset": [
            {
                "name": "NAME",
                "desc": "DB名",
                "type": "String"
            }
        ]
    }
]
```