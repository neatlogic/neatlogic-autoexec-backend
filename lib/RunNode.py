#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 运行节点类
"""
import sys
import os
import traceback
import fcntl
import io
import signal
import time
import stat
import copy
import subprocess
import select
import json
import logging
import traceback
import paramiko
from paramiko.sftp import SFTPError
from paramiko.ssh_exception import SSHException
import AutoExecError
import NodeStatus
import TagentClient
import Utils
import OutputStore


class LogFile(io.TextIOWrapper):
    def write(self, d, encoding=sys.getdefaultencoding()):
        if isinstance(d, bytes):
            d = d.decode(encoding)

        for line in d.splitlines(True):
            super().write(Utils.getTimeStr())
            super().write(line)
            super().flush()
            # TODO: write log to share object storage

    def close(self):
        super().flush()
        super().close()


class RunNode:

    def __init__(self, context, phaseName, node):
        self.context = context
        # 如果节点运行时所有operation运行完，但是存在failIgnore则此属性会被设置为1
        self.hasIgnoreFail = 0

        self.logger = logging.getLogger('')
        self.phaseName = phaseName
        self.runPath = context.runPath
        self.node = node
        self.nodeWithoutPassword = copy.copy(node)
        self.nodeWithoutPassword['password'] = ''
        self.type = node['nodeType']
        self.host = node['host']
        self.port = node['port']
        self.id = node['nodeId']
        self.username = node['username']
        self.password = node['password']

        self.childPid = None
        self.killCmd = None
        self.logHandle = None

        self.output = self.context.output
        self.statusPhaseDir = '{}/status/{}'.format(self.runPath, phaseName)
        if not os.path.exists(self.statusPhaseDir):
            os.mkdir(self.statusPhaseDir)

        self.statusPath = '{}/{}-{}.json'.format(self.statusPhaseDir, node['host'], node['port'])

        self.outputRoot = self.runPath + '/output'
        self.outputPathPrefix = '{}/output/{}-{}'.format(self.runPath, node['host'], node['port'])
        self.opOutputPathPrefix = '{}/output-op/{}-{}'.format(self.runPath, node['host'], node['port'])
        self.outputPath = self.outputPathPrefix + '.json'

        self.logPhaseDir = '{}/log/{}'.format(self.runPath, phaseName)
        if not os.path.exists(self.logPhaseDir):
            os.mkdir(self.logPhaseDir)

        self.status = NodeStatus.pending
        self.outputStore = OutputStore.OutputStore(context, self.phaseName, node)
        self._loadOutput()

    def __del__(self):
        if self.logHandle is not None:
            self.logHandle.close()

    def updateNodeStatus(self, status, op=None, failIgnore=0, consumeTime=0):
        statuses = {}

        if status == NodeStatus.aborted or status == NodeStatus.failed:
            self.context.hasFailNodeInGlobal = True

        outputStore = OutputStore.OutputStore(self.context, self.phaseName, self.node)
        statusFile = None
        try:
            if not os.path.exists(self.statusPath):
                statuses = outputStore.loadStatus()
                statusFile = open(self.statusPath, 'a+')
            else:
                statusFile = open(self.statusPath, 'a+')
                statusFile.seek(0, 0)
                content = statusFile.read()
                if content is not None and content != '':
                    statuses = json.loads(content)
            if statuses is None:
                statuses = {}
        except Exception as ex:
            self.logHandle.write('ERROR: Load and update status file:{}, failed {}\n'.format(self.statusPath, ex))

        if statusFile:
            try:
                if op is None:
                    statuses['status'] = status
                else:
                    statuses[op.opId] = status
                statusFile.truncate(0)
                statusFile.write(json.dumps(statuses))
                outputStore.saveStatus(statuses)
                # TODO: write status file to share object store
                statusFile.close()
            except Exception as ex:
                self.logHandle.write('ERROR: Save status file:{}, failed {}\n'.format(self.statusPath, ex))

        if op is None:
            try:
                serverAdapter = self.context.serverAdapter
                # 当status为failed，但是failIgnore为1，不影响继续执行
                retObj = serverAdapter.pushNodeStatus(self.phaseName, self, status, failIgnore)

                # 如果update 节点状态返回当前phase是失败的状态，代表全局有节点是失败的，这个时候需要标记全局存在失败的节点
                if 'Status' in retObj and retObj['Status'] == 'OK':
                    if 'Return' in retObj and 'hasFailNode' in retObj['Return']:
                        if retObj['Return']['hasFailNode'] == 1:
                            self.context.hasFailNodeInGlobal = True

            except Exception as ex:
                raise
                #self.logHandle.write('ERROR: Push status:{} to Server, failed {}\n'.format(self.statusPath, ex))

    def getNodeStatus(self, op=None):
        status = NodeStatus.pending
        statuses = {}
        try:
            if os.path.exists(self.statusPath):
                statusFile = open(self.statusPath, 'r')
                content = statusFile.read()
                if content is not None and content != '':
                    statuses = json.loads(content)
                statusFile.close()
        except Exception as ex:
            self.logHandle.write('ERROR: Load status file:{}, failed {}\n'.format(self.statusPath, ex))

        if op is None:
            if 'status' in statuses:
                status = statuses['status']
        elif op.opId in statuses:
            status = statuses[op.opId]

        return status

    def _getOpOutputPath(self, op):
        return '{}-{}.json'.format(self.opOutputPathPrefix, op.opId)

    def _getLocalOutput(self):
        output = {}
        localOutputPath = '{}/output/local-0.json'.format(self.runPath)
        if os.path.exists(localOutputPath):
            # 如果runner本地存在local的output文件，则从本地加载
            # TODO：如果local的运行runner是随机选择的，那就要必须强制从mongodb中加载output
            outputFile = None
            try:
                outputFile = open(localOutputPath, 'r')
                fcntl.lockf(outputFile, fcntl.LOCK_SH)
                output = json.loads(outputFile.read())
            except Exception as ex:
                self.logHandle.write('ERROR: Load output file:{}, failed {}\n'.format(self.outputPath, ex))
            finally:
                if outputFile is not None:
                    fcntl.lockf(outputFile, fcntl.LOCK_UN)
                    outputFile.close()
        else:
            # 因为local的phase和remote|localremote的phase很可能不在同一个runner中执行，所以需要远程从mongodb中加载output数据
            localNode = {'host': 'local', 'port': 0}
            loalOutStore = OutputStore.OutputStore(self.context, self.phaseName, localNode)
            output = loalOutStore.loadOutput()

        return output

    def _loadOutput(self):
        # 加载操作输出并进行合并
        if os.path.exists(self.outputPath):
            # 如果runner本地存在output文件，则从本地加载
            # TODO：如果运行runner是随机选择的，那就要必须强制从mongodb中加载output
            outputFile = None
            try:
                outputFile = open(self.outputPath, 'r')
                fcntl.lockf(outputFile, fcntl.LOCK_SH)
                output = json.loads(outputFile.read())
                self.output = output
            except Exception as ex:
                self.logHandle.write('ERROR: Load output file:{}, failed {}\n'.format(self.outputPath, ex))
            finally:
                if outputFile is not None:
                    fcntl.lockf(outputFile, fcntl.LOCK_UN)
                    outputFile.close()
        else:
            # 如果本地output文件不存在则从mongodb加载
            output = self.outputStore.loadOutput()

        # 加载local节点的output
        localOutput = self._getLocalOutput()
        if localOutput is not None:
            self.output.update(localOutput)

    def _saveOutput(self):
        if self.output:
            outputFile = None
            try:
                outputFile = open(self.outputPath, 'w')
                fcntl.lockf(outputFile, fcntl.LOCK_EX)
                outputFile.write(json.dumps(self.output))
                self.outputStore.saveOutput(self.output)
            except Exception as ex:
                self.logHandle.write('ERROR: Save output file:{}, failed {}\n'.format(self.outputPath, ex))
            finally:
                if outputFile is not None:
                    fcntl.lockf(outputFile, fcntl.LOCK_UN)
                    outputFile.close()

    def _loadOpOutput(self, op):
        # 加载操作输出并进行合并
        opOutputFile = None
        opOutPutPath = self._getOpOutputPath(op)
        if os.path.exists(opOutPutPath):
            try:
                opOutputFile = open(opOutPutPath, 'r')
                opOutput = json.loads(opOutputFile.read())
                # if self.host == 'local-pre' or self.host == 'local-post':
                #    for key in opOutput:
                #        self.context.output['local'][key] = opOutput[key]
                # else:
                self.output[op.opId] = opOutput

                if opOutputFile:
                    opOutputFile.close()
            except Exception as ex:
                self.logHandle.write('ERROR: Load operation {} output file:{}, failed {}\n'.format(op.opId, opOutPutPath, ex))

    def getNodeLogHandle(self):
        return self.logHandle

    def execute(self, ops):
        if self.context.goToStop:
            return 2

        try:
            self.logPath = '{}/{}-{}.txt'.format(self.logPhaseDir, self.host, self.port)
            # 如果文件存在，则删除重建
            if os.path.exists(self.logPath):
                os.unlink(self.logPath)
            self.logHandle = LogFile(open(self.logPath, 'w').detach())

            # 更新节点状态为running
            self.updateNodeStatus(NodeStatus.running)

            hisLogDir = '{}/{}-{}.hislog'.format(self.logPhaseDir, self.host, self.port)
            if not os.path.exists(hisLogDir):
                os.mkdir(hisLogDir)

        except Exception as ex:
            self.logger.log(logging.FATAL, "ERROR: Create log failed, {}\n".format(ex))
            self.updateNodeStatus(NodeStatus.failed)

        # TODO：restore status and output from share object storage
        nodeBeginDateTimeFN = time.strftime('%Y%m%d-%H%M%S')
        nodeBeginDateTime = time.strftime('%Y-%m-%d %H:%M:%S')
        nodeStartTime = time.time()
        self.logHandle.write("======[{}]{}:{} <{}>======\n\n".format(self.id, self.host, self.port, nodeBeginDateTime))

        hasIgnoreFail = 0
        isFail = 0
        for op in ops:
            ret = 0

            try:
                if not self.context.isForce and self.getNodeStatus(op) == NodeStatus.succeed:
                    op.parseParam(self.output)
                    self._loadOpOutput(op)
                    continue

                op.parseParam(self.output)
            except AutoExecError.AutoExecError as err:
                try:
                    self.logHandle.write("ERROR: {}[{}] parse param failed, {}\n".format(op.opId, op.opName, err.value))
                    self.updateNodeStatus(NodeStatus.failed, op=op)
                    if op.failIgnore:
                        hasIgnoreFail = 1
                    else:
                        isFail = 1
                        break
                except:
                    isFail = 1

            try:
                if op.opName == 'setenv' or op.opName == 'setglobalenv':
                    envName = op.options['name']
                    envValue = op.options['value']
                    self.context.setEnv(envName, envValue)
                    continue

                if not os.path.exists(op.pluginPath):
                    self.logHandle.write("ERROR: Plugin not exists {}\n".format(op.pluginPath))

                beginDateTime = time.strftime('%Y-%m-%d %H:%M:%S')
                startTime = time.time()

                ret = 0
                if self.host == 'local':
                    if op.opType == 'local':
                        # 本地执行
                        # 输出保存到环境变量 $OUTPUT_PATH指向的文件里
                        self.logHandle.write("------{}[{}] BEGIN-- <{}> local execute...\n".format(op.opId, op.opName, beginDateTime))
                        ret = self._localExecute(op)
                    else:
                        continue
                else:
                    if op.opType == 'localremote':
                        # 本地执行，逐个node循环本地调用插件，通过-node参数把node的json传送给插件，插件自行处理node相关的信息和操作
                        # 输出保存到环境变量 $OUTPUT_PATH指向的文件里
                        self.logHandle.write("------{}[{}] BEGIN-- <{}> local-remote execute...\n".format(op.opId, op.opName, beginDateTime))
                        ret = self._localRemoteExecute(op)
                    elif op.opType == 'remote':
                        # 远程执行，则推送插件到远端并执行插件运行命令，输出保存到执行目录的output.json中
                        self.logHandle.write("------{}[{}] BEGIN-- <{}> remote execute...\n".format(op.opId, op.opName, beginDateTime))
                        ret = self._remoteExecute(op)
                    else:
                        continue

                timeConsume = time.time() - startTime
                if ret != 0:
                    self.updateNodeStatus(NodeStatus.failed, op=op, consumeTime=timeConsume)
                else:
                    self._loadOpOutput(op)
                    self._saveOutput()
                    self.updateNodeStatus(NodeStatus.succeed, op=op, consumeTime=timeConsume)

                endDateTime = time.strftime('%Y-%m-%d %H:%M:%S')
                if ret == 0:
                    self.logHandle.write("-++---{}[{}] END-- <{}> {:.2f}second Execute {} succeed.\n\n".format(op.opId, op.opName, endDateTime, timeConsume, op.opTypeDesc[op.opType]))
                else:
                    self.logHandle.write("-++---{}[{}] END-- <{}> {:.2f}second Execute {} failed.\n\n".format(op.opId, op.opName, endDateTime, timeConsume, op.opTypeDesc[op.opType]))

                    if op.failIgnore:
                        hasIgnoreFail = 1
                    else:
                        isFail = 1
                        break
            except:
                isFail = 1
                traceback.print_exc()
                break

        nodeEndDateTime = time.strftime('%Y-%m-%d %H:%M:%S')
        nodeConsumeTime = time.time() - nodeStartTime

        finalStatus = NodeStatus.succeed
        if isFail == 0:
            if hasIgnoreFail == 1:
                # 虽然全部操作执行完，但是中间存在fail但是ignore的operation，则设置节点状态为已忽略，主动忽略节点
                self.hasIgnoreFail = 1
                finalStatus = NodeStatus.ingore
                self.updateNodeStatus(finalStatus, failIgnore=hasIgnoreFail, consumeTime=nodeConsumeTime)
                self.logHandle.write("======[{}]{}:{} <{}> {:.2f}second failed, ignore======\n".format(self.id, self.host, self.port, nodeEndDateTime, nodeConsumeTime))
            else:
                finalStatus = NodeStatus.succeed
                self.updateNodeStatus(finalStatus, consumeTime=nodeConsumeTime)
                self.logHandle.write("======[{}]{}:{} <{}> {:.2f}second succeed======\n".format(self.id, self.host, self.port, nodeEndDateTime, nodeConsumeTime))
        else:
            finalStatus = NodeStatus.failed
            self.updateNodeStatus(finalStatus, consumeTime=nodeConsumeTime)
            self.logHandle.write("======[{}]{}:{} <{}> {:.2f}second failed======\n".format(self.id, self.host, self.port, nodeEndDateTime, nodeConsumeTime))

        # 创建带时间戳的日志文件名
        logPathWithTime = '{}/{}.{}.{}.txt'.format(hisLogDir, nodeBeginDateTimeFN, finalStatus, self.context.execUser)
        os.link(self.logPath, logPathWithTime)

        self.killCmd = None
        return isFail

    def _localExecute(self, op):
        self.childPid = None
        self.killCmd = None
        os.chdir(self.runPath)
        ret = -1
        # 本地执行，则使用管道启动运行插件
        orgCmdLine = op.getCmdLine(fullPath=True)
        orgCmdLineHidePassword = op.getCmdLineHidePassword(fullPath=True)

        cmdline = 'exec {}'.format(orgCmdLine)
        environment = {}
        environment['OUTPUT_ROOT_PATH'] = self.outputRoot
        environment['OUTPUT_PATH'] = self._getOpOutputPath(op)
        environment['PATH'] = '{}:{}'.format(op.pluginParentPath, os.environ['PATH'])
        environment['PERLLIB'] = '{}/lib:{}'.format(op.pluginParentPath, os.environ['PERLLIB'])
        environment['AUTOEXEC_JOBID'] = self.context.jobId
        environment['AUTOEXEC_NODE'] = json.dumps(self.node)
        environment['AUTOEXEC_NODES_PATH'] = self.context.phases[self.phaseName].nodesFilePath

        scriptFile = None
        if op.isScript == 1:
            scriptFile = open(op.pluginPath, 'r')
            fcntl.flock(scriptFile, fcntl.LOCK_SH)

        child = subprocess.Popen(cmdline, env=environment, shell=True, close_fds=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.childPid = child.pid

        if scriptFile is not None:
            fcntl.flock(scriptFile, fcntl.LOCK_UN)
            scriptFile.close()
            scriptFile = None

        # 管道启动成功后，更新状态为running
        self.updateNodeStatus(NodeStatus.running, op=op)

        while True:
            # readline 增加maxSize参数是为了防止行过长，pipe buffer满了，行没结束，导致pipe写入阻塞
            line = child.stdout.readline(4096)
            if not line:
                break
            self.logHandle.write(line)

        # 等待插件执行完成并获取进程返回值，0代表成功
        child.wait()
        ret = child.returncode

        lastContent = child.stdout.read()
        if lastContent is not None:
            self.logHandle.write(lastContent)

        if ret == 0:
            self.logHandle.write("INFO: Execute local command succeed:{}\n".format(orgCmdLineHidePassword))
        else:
            self.logHandle.write("ERROR: Execute local command faled:{}\n".format(orgCmdLineHidePassword))

        return ret

    def _localRemoteExecute(self, op):
        self.childPid = None
        self.killCmd = None
        os.chdir(self.runPath)
        ret = -1
        # 本地执行，则使用管道启动运行插件
        orgCmdLine = op.getCmdLine(fullPath=True)
        orgCmdLineHidePassword = op.getCmdLineHidePassword(fullPath=True)

        cmdline = 'exec {} --node \'{}\''.format(orgCmdLine, json.dumps(self.node))
        environment = {}
        environment['OUTPUT_ROOT_PATH'] = self.outputRoot
        environment['OUTPUT_PATH'] = self._getOpOutputPath(op)
        environment['PATH'] = '{}:{}'.format(op.pluginParentPath, os.environ['PATH'])
        environment['PERLLIB'] = '{}/lib:{}'.format(op.pluginParentPath, os.environ['PERLLIB'])
        environment['AUTOEXEC_JOBID'] = self.context.jobId
        environment['AUTOEXEC_NODE'] = json.dumps(self.node)
        environment['AUTOEXEC_NODES_PATH'] = self.context.phases[self.phaseName].nodesFilePath

        scriptFile = None
        if op.isScript == 1:
            scriptFile = open(op.pluginPath, 'r')
            fcntl.flock(scriptFile, fcntl.LOCK_SH)

        child = subprocess.Popen(cmdline, env=environment, shell=True, close_fds=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.childPid = child.pid

        if scriptFile is not None:
            fcntl.flock(scriptFile, fcntl.LOCK_UN)
            scriptFile.close()
            scriptFile = None

        # 管道启动成功后，更新状态为running
        self.updateNodeStatus(NodeStatus.running, op=op)

        while True:
            # readline 增加maxSize参数是为了防止行过长，pipe buffer满了，行没结束，导致pipe写入阻塞
            line = child.stdout.readline(4096)
            if not line:
                break
            self.logHandle.write(line)

        # 等待插件执行完成并获取进程返回值，0代表成功
        child.wait()
        ret = child.returncode

        if ret == 0:
            self.logHandle.write("INFO: Execute local-remote command succeed: {}\n".format(orgCmdLineHidePassword))
        else:
            self.logHandle.write("ERROR: Execute local-remote command faled: {}\n".format(orgCmdLineHidePassword))

        return ret

    def _remoteExecute(self, op):
        self.childPid = None

        remoteCmd = ''
        ret = -1
        if self.type == 'tagent':
            scriptFile = None
            try:
                remotePath = '$TMPDIR/autoexec-{}'.format(self.context.jobId)
                runEnv = {'AUTOEXEC_JOBID': self.context.jobId, 'AUTOEXEC_NODE': json.dumps(self.nodeWithoutPassword)}

                tagent = TagentClient.TagentClient(self.host, self.port, self.password, readTimeout=360, writeTimeout=10)

                # 更新节点状态为running
                self.updateNodeStatus(NodeStatus.running, op=op)

                remoteCmd = None
                uploadRet = 0
                if op.isScript == 1:
                    scriptFile = open(op.pluginPath, 'r')
                    fcntl.flock(scriptFile, fcntl.LOCK_SH)
                    uploadRet = tagent.upload(self.username, op.pluginPath, remotePath)
                    remoteCmd = 'cd {} && {}'.format(remotePath, op.getCmdLine(fullPath=False, osType=tagent.agentOsType))
                    fcntl.flock(scriptFile, fcntl.LOCK_UN)
                    scriptFile.close()
                    scriptFile = None
                else:
                    for srcPath in [op.remoteLibPath, op.pluginParentPath]:
                        uploadRet = tagent.upload(self.username, srcPath, remotePath)
                        if uploadRet != 0:
                            break
                    remoteCmd = 'cd {}/{} && {}'.format(remotePath, op.opName, op.getCmdLine(fullPath=False, osType=tagent.agentOsType))

                if uploadRet == 0 and not self.context.goToStop:
                    ret = tagent.execCmd(self.username, remoteCmd, env=runEnv, isVerbose=0, callback=self.logHandle.write)
                    if ret == 0 and op.hasOutput:
                        outputFilePath = self._getOpOutputPath(op)
                        outputStatus = tagent.download(self.username, '{}/{}/output.json'.format(remotePath, op.opName), outputFilePath)
                        if outputStatus != 0:
                            self.logHandle.write("ERROR: Download output failed.\n")
                            ret = 2
                    try:
                        if ret != 0 and self.context.devMode:
                            if tagent.agentOsType == 'windows':
                                tagent.execCmd(self.username, "rd /s /q {}".format(remotePath), env=runEnv)
                            else:
                                tagent.execCmd(self.username, "rm -rf {}".format(remotePath), env=runEnv)
                    except Exception as ex:
                        self.logHandle.write('ERROR: Remote remove directory {} failed {}\n'.format(remotePath, ex))
            except Exception as ex:
                self.logHandle.write("ERROR: Execute operation {} failed, {}\n".format(op.opName, ex))
                raise ex
            finally:
                if scriptFile is not None:
                    fcntl.flock(scriptFile, fcntl.LOCK_SH)
                    scriptFile.close()

            if ret == 0:
                self.logHandle.write("INFO: Execute remote command by agent succeed: {}\n".format(remoteCmd))
            else:
                self.logHandle.write("ERROR: Execute remote command by agent failed: {}\n".format(remoteCmd))

        elif self.type == 'ssh':
            logging.getLogger("paramiko").setLevel(logging.FATAL)
            remoteRoot = '/tmp/autoexec-{}'.format(self.context.jobId)
            remotePath = '{}/{}'.format(remoteRoot, op.opName)
            remoteCmd = 'AUTOEXEC_JOBID={} AUTOEXEC_NODE=\'{}\' cd {} && {}'.format(self.context.jobId, json.dumps(self.nodeWithoutPassword), remotePath, op.getCmdLine())
            self.killCmd = "kill -9 `ps aux |grep '" + remotePath + "'|grep -v grep|awk '{print $1}'`"

            scriptFile = None
            uploaded = False
            scp = None
            sftp = None
            try:
                # 建立连接
                scp = paramiko.Transport((self.host, self.port))
                scp.connect(username=self.username, password=self.password)

                # 更新节点状态为running
                self.updateNodeStatus(NodeStatus.running, op=op)

                # 建立一个sftp客户端对象，通过ssh transport操作远程文件
                sftp = paramiko.SFTPClient.from_transport(scp)
                # Copy a local file (localpath) to the SFTP server as remotepath
                try:
                    try:
                        sftp.stat(remoteRoot)
                    except IOError:
                        sftp.mkdir(remoteRoot)
                except SFTPError as err:
                    self.logHandle.write("ERROR: mkdir {} failed: {}\n".format(remoteRoot, err))

                if op.isScript == 1:
                    scriptFile = open(op.pluginPath, 'r')
                    fcntl.flock(scriptFile, fcntl.LOCK_SH)
                    sftp.put(op.pluginPath, os.path.join(remoteRoot, op.opName))
                    fcntl.flock(scriptFile, fcntl.LOCK_UN)
                    scriptFile.close()
                    scriptFile = None
                else:
                    os.chdir(op.remotePluginRootPath)
                    for root, dirs, files in os.walk('lib', topdown=True, followlinks=True):
                        try:
                            # 创建当前目录
                            sftp.mkdir(os.path.join(remoteRoot, root))
                        except:
                            pass
                        for name in files:
                            # 遍历文件并scp到目标上
                            filePath = os.path.join(root, name)
                            sftp.put(filePath, os.path.join(remoteRoot, filePath))

                    # 切换到插件根目录，便于遍历时的文件目录时，文件名为此目录相对路径
                    os.chdir(op.remotePluginRootPath)
                    # 为了从顶向下创建目录，遍历方式为从顶向下的遍历，并follow link
                    for root, dirs, files in os.walk(op.opName, topdown=True, followlinks=True):
                        try:
                            # 创建当前目录
                            sftp.mkdir(os.path.join(remoteRoot, root))
                        except:
                            pass
                        for name in files:
                            # 遍历文件并scp到目标上
                            filePath = os.path.join(root, name)
                            sftp.put(filePath, os.path.join(remoteRoot, filePath))

                    sftp.chmod('{}/{}'.format(remotePath, op.opName), stat.S_IXUSR)

                uploaded = True

            except Exception as err:
                self.logHandle.write('ERROR: Upload plugin:{} to remoteRoot:{} failed: {}\n'.format(op.opName, remoteRoot, err))
            finally:
                if scriptFile is not None:
                    fcntl.flock(scriptFile, fcntl.LOCK_SH)
                    scriptFile.close()

            if uploaded and not self.context.goToStop:
                ssh = None
                try:
                    ssh = paramiko.SSHClient()
                    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                    ssh.connect(self.host, self.port, self.username, self.password)
                    channel = ssh.get_transport().open_session()
                    channel.set_combine_stderr(True)
                    channel.exec_command(remoteCmd)

                    while True:
                        if channel.exit_status_ready():
                            ret = channel.recv_exit_status()
                            break

                        r, w, x = select.select([channel], [], [])
                        if len(r) > 0:
                            self.logHandle.write(channel.recv(1024).decode() + '\n')

                    if ret == 0 and op.hasOutput:
                        try:
                            outputFilePath = self._getOpOutputPath(op)
                            sftp.get('{}/output.json'.format(remotePath), outputFilePath)
                        except:
                            self.logHandle.write("ERROR: Download output failed.\n")
                            ret = 2

                    try:
                        if ret != 0 and self.context.devMode:
                            ssh.exec_command("rm -rf {} || rd /s /q {}".format(remotePath, remotePath))
                    except Exception as ex:
                        self.logHandle.write("ERROR: Remove remote directory {} failed {}\n".format(remotePath, ex))

                except Exception as err:
                    self.logHandle.write("ERROR: Execute remote operation {} failed, {}\n".format(op.opName, err))
                finally:
                    if ssh:
                        ssh.close()

                if scp:
                    scp.close()

            if ret == 0:
                self.logHandle.write("INFO: Execute remote command by ssh succeed:{}\n".format(remoteCmd))
            else:
                self.logHandle.write("ERROR: Execute remote command by ssh failed:{}\n".format(remoteCmd))

        return ret

    def kill(self):
        if self.childPid is not None:
            pid = self.childPid

            try:
                (exitPid, exitStatus) = os.waitpid(pid, os.WNOHANG)
                if pid is not None:
                    os.kill(pid, signal.SIGTERM)

                (exitPid, exitStatus) = os.waitpid(pid, os.WNOHANG)
                # 如果子进程没有结束，等待3秒
                loopCount = 3
                while exitPid != 0 and exitPid != pid:
                    if loopCount <= 0:
                        break

                    time.sleep(1)
                    (exitPid, exitStatus) = os.waitpid(pid, os.WNOHANG)
                    loopCount = loopCount - 1

                (exitPid, exitStatus) = os.waitpid(pid, os.WNOHANG)
                os.kill(pid, signal.SIGKILL)
            except OSError:
                # 子进程不存在，已经退出了
                pass
            finally:
                self.updateNodeStatus(NodeStatus.aborted)

        killCmd = self.killCmd
        if self.type == 'ssh' and killCmd is not None:
            ssh = None
            try:
                ssh = paramiko.SSHClient()
                ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                ssh.connect(self.host, self.port, self.username, self.password)
                channel = ssh.get_transport().open_session()
                channel.set_combine_stderr(True)
                channel.exec_command(killCmd)

                while True:
                    if channel.exit_status_ready():
                        ret = channel.recv_exit_status()
                        break

                    r, w, x = select.select([channel], [], [])
                    if len(r) > 0:
                        self.logHandle.write(channel.recv(1024).decode() + '\n')

            except Exception as err:
                self.logHandle.write("ERROR: Execute kill command:{} failed, {}\n".format(killCmd, err))
            finally:
                self.updateNodeStatus(NodeStatus.aborted)
                if ssh:
                    ssh.close()
        else:
            self.updateNodeStatus(NodeStatus.aborted)
