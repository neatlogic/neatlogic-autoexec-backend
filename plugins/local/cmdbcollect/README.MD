# 本地运行的CMDBCOLLECT README

------
## 主要功能
各种在本地运行进行软硬件的CMDB信息采集，采集后会存储到中转存储DB中，然后完成后续的关系计算，CMDB根据模型与数据Mapping设置从中转DB抽取需要的数据。

## 数据单位标准（采集插件必须按此标准提供数据）
- 磁盘空间为数值格式（非字符串），单位是GB
- 内存大小数值格式（非字符串），单位是MB
- 网卡或HBA板卡端口速率为数值格式（非字符串），单位是Mb/s

## 采集标准说明
- 网络设备采集标准属性
- OBJECT_TYPE: SWITCH
- APP_TYPE: Cisco #交换机品牌
- MGMT_IP: 采集此交换机信息使用的交换机管理IP
- RESOURCE_ID: CMDB的ID（主机发现需要依赖CMDB中存在所有的主机IP和相关的登录账户信息）
- SN: chassis serial number

* 交换机样例
```json
    {
          'SN'     => 'SDF978934',
          'UPTIME' => '41 days, 17:12:05.00',
          'PK' => [
                    'SN'
                  ],
          'MAC_TABLE' => [
                           {
                             'REMOTE_MAC' => '00:0c:29:28:ef:ed',
                             'PORT' => 'Ethernet0/2'
                           },
                           {
                             'REMOTE_MAC' => '00:0c:29:39:e3:9e',
                             'PORT' => 'Ethernet0/2'
                           },
                           {
                             'REMOTE_MAC' => '00:0c:29:47:e2:03',
                             'PORT' => 'Ethernet0/2'
                           }
                         ],
          'PORTS_COUNT' => 28,
          'PORTS' => [
                       {
                         'NAME' => 'Ethernet0/24',
                         'OPER_STATUS' => 'down',
                         'SPEED' => '0',
                         'ADMIN_STATUS' => 'up',
                         'TYPE' => 'ethernet-csmacd(6)',
                         'MAC' => '00:0f:e2:55:d9:30',
                         'MTU' => 1500,
                         'INDEX' => '3458',
                         'NO' => '24'
                       },
                       {
                         'NAME' => 'Ethernet0/20',
                         'OPER_STATUS' => 'down',
                         'SPEED' => '0',
                         'ADMIN_STATUS' => 'up',
                         'TYPE' => 'ethernet-csmacd(6)',
                         'MAC' => '00:0f:e2:55:d9:30',
                         'MTU' => 1500,
                         'INDEX' => '2946',
                         'NO' => '20'
                       }
                     ],
          'IOS_INFO' => 'Huawei Versatile Routing Platform Software Version 3.10',
          'BRAND' => 'HuaWei',
          'DEV_NAME' => 'hw-sw02',
          'APP_TYPE' => 'HuaWei',
          'MODEL' => 'S2403H-EI-0020P02',
          'VENDOR' => 'wangtc',
          'NEIGHBORS' => []
        };
```

## switchcollector
- switchcollector 不通品牌交换机都统一使用此工具进行采集
- 会根据交换机设备的品牌调用各自的设置类进行OID修正和采集后的数据处理补充。
- 支持通过json参数输入密码设置
- 支持只对某一类别的对象进行发现和收集

## f5collector
- 通过SNMP完成对F5的序列号型号等信息以及VS、POOL、MEMBER的信息采集

## a10collector
- 通过SNMP完成对A10的序列号型号等信息以及VS、POOL、MEMBER的信息采集
