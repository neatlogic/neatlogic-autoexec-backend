# 本地运行的CMDBCOLLECT README

------
## 主要功能
各种在本地运行进行软硬件的CMDB信息采集，采集后会存储到中转存储DB中，然后完成后续的关系计算，CMDB根据模型与数据Mapping设置从中转DB抽取需要的数据。

## 数据单位标准（采集插件必须按此标准提供数据）
- 磁盘空间为数值格式（非字符串），单位是GB
- 内存大小数值格式（非字符串），单位是MB
- 网卡或HBA板卡端口速率为数值格式（非字符串），单位是Mb/s

## 交换机采集标准说明
- 网络设备采集标准属性
- _OBJ_CATEGORY: SWITCH
- _OBJ_TYPE: Cisco #交换机品牌
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
          '_OBJ_TYPE' => 'HuaWei',
          'MODEL' => 'S2403H-EI-0020P02',
          'VENDOR' => 'wangtc',
          'NEIGHBORS' => []
        };
```

## switchcollector
- switchcollector 不同品牌交换机都统一使用此工具进行采集
- 会根据交换机设备的品牌调用各自的设置类进行OID修正和采集后的数据处理补充。支持品牌设备需要修改lib/SwitchSnmp.pm增加支持识别的类型。（使用OID：sysDescrOid 1.3.6.1.2.1.1.1.0里的描述信息进行品牌型号判断）
- 支持通过json参数输入密码设置
- 支持只对某一类别的对象进行发现和收集

## f5collector
- 通过SNMP完成对F5的序列号型号等信息以及VS、POOL、MEMBER的信息采集

## a10collector
- 通过SNMP完成对A10的序列号型号等信息以及VS、POOL、MEMBER的信息采集


## 存储采集标准说明
- 网络设备采集标准属性
- _OBJ_CATEGORY: STORAGE
- _OBJ_TYPE: NetApp #交换机品牌
- MGMT_IP: 采集此存储信息使用的管理IP
- RESOURCE_ID: CMDB的ID（存储需要先在CMDB录入，然后再进行采集）
- SN: Serial number

* 交换机样例
```json
    {
          'SN'     => 'SDF978934',
          'UPTIME' => '41 days, 17:12:05.00',
          'PK' => [
                    'SN'
                  ],
          'STORAGE_GROUPS' => [
            {
                ID   => 2,
                NAME => 'Test1',
                LUNS => [
                  {
                    NAME => 'xxxx',
                    LUN_ID => '34:34:9f:34',
                    CAPACITY => 3243,
                    TYPE => 'SAS'
                  },
                  {
                    NAME => 'xxxx1',
                    LUN_ID => '33:34:9f:34',
                    CAPACITY => 3343,
                    TYPE => 'SAS'
                  }
                ]
              },
              {
                ID   => 3,
                NAME => 'Test2',
                LUNS => [
                  {
                    NAME => 'xxxx',
                    LUN_ID => '34:34:9f:34',
                    CAPACITY => 3243,
                    TYPE => 'SAS'
                  },
                  {
                    NAME => 'xxxx1',
                    LUN_ID => '33:34:9f:34',
                    CAPACITY => 3343,
                    TYPE => 'SAS'
                  }
                ]
              }
          ],
          'RAID_GROUPS' => [
            {
                ID   => 2,
                NAME => 'Test1',
                LUNS => [
                  {
                    NAME => 'xxxx',
                    LUN_ID => '34:34:9f:34',
                    CAPACITY => 3243,
                    TYPE => 'SAS'
                  },
                  {
                    NAME => 'xxxx1',
                    LUN_ID => '33:34:9f:34',
                    CAPACITY => 3343,
                    TYPE => 'SAS'
                  }
                ]
              },
              {
                ID   => 3,
                NAME => 'Test2',
                LUNS => [
                  {
                    NAME => 'xxxx',
                    LUN_ID => '34:34:9f:34',
                    CAPACITY => 3243,
                    TYPE => 'SAS'
                  },
                  {
                    NAME => 'xxxx1',
                    LUN_ID => '33:34:9f:34',
                    CAPACITY => 3343,
                    TYPE => 'SAS'
                  }
                ]
              }
          ],
          'STORAGE_POOLS' => [
              {
                ID   => 2,
                NAME => 'TestPool',
                LUNS => [
                  {
                    NAME => 'xxxx',
                    LUN_ID => '34:34:9f:34',
                    CAPACITY => 3243,
                    TYPE => 'SAS'
                  },
                  {
                    NAME => 'xxxx1',
                    LUN_ID => '33:34:9f:34',
                    CAPACITY => 3343,
                    TYPE => 'SAS'
                  }
                ]
              },
              {
                ID   => 3,
                NAME => 'PrdPool',
                LUNS => [
                  {
                    NAME => 'xxxx',
                    LUN_ID => '34:34:9f:34',
                    CAPACITY => 3243,
                    TYPE => 'SAS'
                  },
                  {
                    NAME => 'xxxx1',
                    LUN_ID => '33:34:9f:34',
                    CAPACITY => 3343,
                    TYPE => 'SAS'
                  }
                ]
              }
          ],
          'CONTROLLERS'=>[
              'NAME' => 'xxx',
              'HBA_INTERFACES' => [
                {
                  'NAME' => 'kkkk',
                  'WWN' => '34:87:33:34:89'
                },
                {
                  'NAME' => 'kkk1',
                  'WWN' => '34:87:33:34:80'
                }
              ],
              'ETH_INTERFACES' => [
                {
                  'NAME' => 'yyy',
                  'MAC'  => '34:a3:f0:30:87:27',
                  'IP'   => '192.168.0.2'
                },
                {
                  'NAME' => 'yyy1',
                  'MAC'  => '34:a3:f0:30:80:27',
                  'IP'   => '192.168.0.3'
                }
              ]
          ],
          'BRAND' => 'HuaWei',
          'DEV_NAME' => 'hw-st02',
          '_OBJ_CATEGORY' => 'STORAGE',
          '_OBJ_TYPE' => 'HuaWei',
          'MODEL' => 'S2403H-EI-0020P02',
          'VENDOR' => 'HuaWei'
    };
```
## 存储管理概念介绍
- RAID Group：简单来说，RAID Group就是将多个硬盘组合起来的一个集合，以实现更大容量、更快读写速度、更高冗余度等目的。常见的RAID Group类型有RAID 0、RAID 1、RAID 1/0、RAID 3、RAID 5、RAID 6。

- LUN：LUN是位于RAID Group之上的逻辑结构。LUN可以被添加进主机中，并被主机视作物理硬盘使用。LUN的叫法有部分存储叫Volume，譬如：FUJITSU（富士通）

- Storage Group：为了实现LUN Masking (LUN的安全屏蔽机制，即1. 仅将LUN分配给特定的主机；2. 阻止主机看到存储中所有的LUN)，需要有一个容器来”存放”LUN与主机的关系，这个容器就是Storage Group。先创建一个Storage Group，再连接进主机(Connect Hosts)，然后将LUN添加进这个Storage Group，主机就可以看到添加进去的LUN。

- Storage Pool：Pool的概念是为了实现存储虚拟化(Storage Virtualization)而诞生的。该功能可以让用户在Pool中创建Thin或者Thick LUN来分配存储资源。Thin和Thick LUN都能够以较简便地方式进行创建、扩容和压缩操作。Thin LUN允许分配比存储上实际物理占用空间更多的可用空间给主机(高存储效率)，而Thin LUN在创建时会预留占用被分配的全部空间(高且可预测的性能)。

## 补充信息
Storage pool可以看作是RAID group上面一层的逻辑结构。也就是说，Storage pool其实从底层来说也是由多个RAID group所组成。这些Storage pool下的RAID group通常被称为Private RAID group，以和用于创建Tranditional LUN的普通RAID group相区别。

引入Storage pool有诸如的好处，例如全自动存储分层(FAST)，等于是把不同应用的数据直接丢到Pool里，让系统自己去按照已有的优化算法来根据数据的使用情况做分层存储，平衡了性能和资源。使用pool里的thin LUN或thick LUN能给据实际需求在分配存储资源时带来更大的效率，灵活性，也易于管理。还有就是，单个传统RAID group会受到16个磁盘的限制，而Storage pool本身可含上百个的磁盘（很多个Private RAID group），所以在容量拓展和管理上也更方便。

并不是说有了Storage pool，传统RAID group就被完全被取代或是放弃了。从传统RAID group创建的tranditional LUN有其特殊的使用场合，特别是对性能要求严苛，并且需要物理上做到数据隔离的场合。

## storagecollector
- storagecollector 不同品牌交换机都统一使用此工具进行采集，使用参数区分品牌型号
- 支持只对某一类别的对象进行发现和收集
- 存储采集首先品牌型号和甲方是否可以配合修改存储的设置，需要结合多种方式进行，SNMP、SSH、CLI工具等。
- 例子：storagecollecotr --type NetApp --comunity public --timeout 5
