
## 更新字典到mongodb
./dicttool --lang zh_CN 

```
usage: dicttool [-h] [--lang LANG] [--action ACTION] [--filter FILTER]
                [--content CONTENT]

optional arguments:
  -h, --help         show this help message and exit
  --lang LANG        Language
  --action ACTION    Actions:（savetodb|append|remove|beautify|dropcollection）
  --filter FILTER    Match filter
  --content CONTENT  Append Json

```
## 导出字典为Word
python3 dictexportword --lang zh_CN --outpath /tmp/cmdb_attr.docx --verbose 1
```
usage: dictexportword [-h] [--lang LANG] [--outpath OUTPATH] [--verbose VERBOSE]

optional arguments:
  -h, --help         show this help message and exit
  --lang LANG
  --outpath OUTPATH  output file path
  --verbose VERBOSE  verbose output

```
