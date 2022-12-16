# 目录工具说明
## 节点账号连通性测试
- cd  /app/systems/autoexec/bin 
### ssh 测试
./nodeconntest --node '{"nodeName":"","protocol":"ssh","port":"","exitValue":1,"host":"192.168.0.26","name":"root[ssh]","nodeType":"OS","protocolPort":22,"username":"root","password":"xxxxxx"}'

### snmp 测试 
./nodeconntest --node '{"nodeName":"","protocol":"snmp","port":"","exitValue":1,"host":"192.168.0.1","name":"inspect[snmp]","nodeType":"Router","protocolPort":161,"username":"inspect","password":"Tpublic"}'

### 数据库测试
./dbconntest  --dbtype mysql  --host 192.168.0.21 --port 3306 --dbname bsm --username root --password 'zanyue$2012'

## 

