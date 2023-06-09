中文 / [English](README.en.md)
<p align="left">
    <a href="https://opensource.org/licenses/Apache-2.0" alt="License">
        <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" /></a>
<a target="_blank" href="https://join.slack.com/t/neatlogichome/shared_invite/zt-1w037axf8-r_i2y4pPQ1Z8FxOkAbb64w">
<img src="https://img.shields.io/badge/Slack-Neatlogic-orange" /></a>
</p>

---
------
## 关于
neatlogic-autoexec-backend是自动化<a href="../../../neatlogic-runner">neatlogic-runner</a>执行代理上的后端执行工具。接收服务端作业调度和控制指令，执行***组合工具***发起自动化作业，根据服务端提供的作业参数、执行目标节点、以及执行参数按阶段、分批次执行作业，并根据执行完成度回写服务端作业状态。

## 适应场景
* neatlogic-autoexec-backend本质是自动化后台的一个调度工具，理论上满足任何场景的自动化需求。

* 目前产品层面能枚举的自动化场景，包括：
<ol>
    <li>CMDB配置数据自动采集</li>
    <li>CMDB配置关系数据计算</li>
    <li>IT资产和应用系统自动巡检</li>
    <li>操作系统、应用系统等关键配置文件巡检和备份</li>
    <li>软件资源自动安装交付</li>
    <li>操作系统层面标准化配置检查和标准化配置</li>
    <li>网络层面、应用层面灾备切换</li>
    <li>业务系统数据跑批执行</li>
    <li>网络设备配置备份和比对</li>
    <li>操作系统、中间件等层面补丁安装</li>
    <li>日常运维变更批量下发</li>
    <li>运维应急操作</li>
    <li>持续集成和应用自动部署(DevOps)</li>
    <li>...</li>
</ol>

⭐️说明
* 支持的场景会不定期更新，请持续关注。

## 与scripts工程区别

* neatlogic-autoexec-backend工程出厂内置的**工具库**，是[neatlogic-autoexec](../../../neatlogic-autoexec/blob/develop3.0.0/README.md)自动化模块基础固化出厂自带工具，用户无需也无法更改的工具库。

* neatlogic-autoexec-scripts工程内自定义工具，因管理上、技术方案、架构设计上不同，可能在实际交付过程中需要导入到[neatlogic-autoexec](../../../neatlogic-autoexec/blob/develop3.0.0/README.md)模块的自定义工具中修改后使用。

* neatlogic-autoexec-scripts为用户提供可扩展工具库管理边界的入口。

## 关键讲解
### 执行方式
* runner执行
 在[neatlogic-runner](../../../neatlogic-runner/blob/develop3.0.0/README.md)所在机器上执行，简称本地执行。适用于需要安装依赖，比如vmware创建虚拟机。
 
* runner->target执行，在[neatlogic-runner](../../../neatlogic-runner/blob/develop3.0.0/README.md)所在机器上基于协议或[neatlogic-tagent-client](../../../neatlogic-tagent-client/blob/master/README.md)连远端目标执行。适用于需要安装依赖同时需要连远端目标执行，比如snmp采集。

* target执行，远端目标执行。适用于不需要环境依赖的脚本下发，比如应用启停。

* Sql文件执行。适用于数据库类DDL、DML等操作，比如应用部署过程中SQL执行。

### 目录概要说明

### bin目录
程序主入口和常用小工具

### lib 
程序主程序lib目录

### logs 
主程序的日志目录

### meaia 
python3 依赖安装和升级

###  plib 
python3 依赖安装目录

### plugins 
内置插件目录
### local 
neatlogic-runner runner执行和runner->target执行插件

### remote 
目标机器执行的插件目录

### test
测试目录

### tools 
第三方依赖目录，如数据库依赖、存储依赖、代码编译、代码扫描等第三方工具库目录

## 更多
参见：[环境搭建和调试](README_env.md)