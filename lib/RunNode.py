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


class LogFile:
    def __init__(self, fileHandle):
        self.foreLine = b''
        self.fileHandle = fileHandle

    def write(self, text):
        if not text:
            return

        if not isinstance(text, bytes):
            text = text.encode()

        timeBytes = Utils.getTimeStr().encode()
        text = self.foreLine + text
        self.foreLine = b''

        start = 0
        try:
            while True:
                end = text.index(b"\n", start)
                self.fileHandle.write(timeBytes + text[start:end+1])
                start = end + 1
        except ValueError:
            if start >= 0:
                self.foreLine = text[start:]

    def close(self):
        if self.foreLine != b'':
            timeBytes = Utils.getTimeStr().encode()
            self.fileHandle.write(timeBytes + self.foreLine)

        self.fileHandle.close()


class RunNode:

    def __init__(self, context, phaseName, node):
        self.context = context
        # 如果节点运行时所有operation运行完，但是存在failIgnore则此属性会被设置为1
        self.hasIgnoreFail = 0
        self.statuses = {}
        self.statusFile = None
        self.logger = logging.getLogger('')
        self.phaseName = phaseName
        self.runPath = context.runPath
        self.node = node
        self.warnCount = 0

        self.tagent = None
        self.childPid = None
        self.isKilled = False
        self.killCmd = None
        self.logHandle = None

        self.nodeWithoutPassword = copy.copy(node)
        self.nodeWithoutPassword['password'] = ''

        if 'nodeName' in node:
            self.name = node['nodeName']
        else:
            self.name = ''

        self.type = node['nodeType']
        self.host = node['host']
        if 'port' in node:
            self.port = node['port']
        else:
            self.port = ''
        if 'protocolPort' in node:
            self.protocolPort = node['protocolPort']
        else:
            self.protocolPort = ''
        self.id = node['nodeId']
        self.username = node['username']
        self.password = node['password']

        self.phaseLogDir = '{}/log/{}'.format(self.runPath, phaseName)
        if not os.path.exists(self.phaseLogDir):
            os.mkdir(self.phaseLogDir)

        self.logPathWithTime = None
        self.logPath = '{}/{}-{}.txt'.format(self.phaseLogDir, self.host, self.port)
        self.hisLogDir = '{}/{}-{}.hislog'.format(self.phaseLogDir, self.host, self.port)

        try:
            if not os.path.exists(self.hisLogDir):
                os.mkdir(self.hisLogDir)

        except Exception as ex:
            self.logger.log(logging.FATAL, "ERROR: Create log failed, {}\n".format(ex))
            self.updateNodeStatus(NodeStatus.failed)

        self.output = self.context.output
        self.statusPhaseDir = '{}/status/{}'.format(self.runPath, phaseName)
        if not os.path.exists(self.statusPhaseDir):
            os.mkdir(self.statusPhaseDir)

        self.statusPath = '{}/{}-{}.json'.format(self.statusPhaseDir, node['host'], self.port)

        self.outputRoot = self.runPath + '/output'
        self.outputPathPrefix = '{}/output/{}-{}'.format(self.runPath, node['host'], self.port)
        self.opOutputPathPrefix = '{}/output-op/{}-{}'.format(self.runPath, node['host'], self.port)
        self.outputPath = self.outputPathPrefix + '.json'

        self.status = NodeStatus.pending
        self.outputStore = OutputStore.OutputStore(context, self.phaseName, node)
        self._loadNodeStatus()
        self._loadOutput()

    def __del__(self):
        if self.logHandle is not None:
            self.logHandle.close()

    def writeNodeLog(self, msg):
        logHandle = self.logHandle

        if logHandle is None:
            # 如果文件存在，则删除重建
            if os.path.exists(self.logPath):
                os.unlink(self.logPath)

            logHandle = LogFile(open(self.logPath, 'wb').detach())
            self.logHandle = logHandle
        if isinstance(msg, bytes):
            if msg.startswith(b'ERROR:') or msg.startswith(b'WARN:'):
                self.warnCount = self.warnCount + 1
        else:
            if msg.startswith('ERROR:') or msg.startswith('WARN:'):
                self.warnCount = self.warnCount + 1

        logHandle.write(msg)

    def updateNodeStatus(self, status, op=None, failIgnore=0, consumeTime=0):
        if status == NodeStatus.aborted or status == NodeStatus.failed:
            self.context.hasFailNodeInGlobal = True

        self.statuses['pid'] = self.context.pid

        if op is None:
            self.statuses['status'] = status
            self.statuses['warnCount'] = self.warnCount
        else:
            self.statuses[op.opId] = status
            self.statuses['currenOp'] = op.opId
            self.statuses['opPid'] = self.childPid

        try:
            if self.statusFile is None:
                self.statusFile = open(self.statusPath, 'a+')
            self.statusFile.truncate(0)
            self.statusFile.write(json.dumps(self.statuses))
            self.statusFile.flush()
            self.outputStore.saveStatus(self.statuses)
        except Exception as ex:
            self.writeNodeLog('ERROR: Save status file:{}, failed {}\n'.format(self.statusPath, ex))
            raise

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
                self.writeNodeLog('ERROR: Push status:{} to Server, failed {}\n'.format(self.statusPath, ex))

    def _loadNodeStatus(self):
        status = NodeStatus.pending
        statuses = {}
        try:
            if os.path.exists(self.statusPath):
                statusFile = open(self.statusPath, 'a+')
                statusFile.seek(0, 0)
                self.statusFile = statusFile
                content = statusFile.read()
                if content is not None and content != '':
                    statuses = json.loads(content)
            else:
                statuses = self.outputStore.loadStatus()

            self.statuses = statuses
        except Exception as ex:
            self.writeNodeLog('ERROR: Load status file:{}, failed {}\n'.format(self.statusPath, ex))
            raise

    def getNodeStatus(self, op=None):
        status = NodeStatus.pending
        if op is None:
            if 'status' in self.statuses:
                status = self.statuses['status']
        elif op.opId in self.statuses:
            status = self.statuses[op.opId]

        return status

    def ensureNodeIsRunning(self):
        isExists = False
        if 'pid' in self.statuses:
            isExists = Utils.checkPidExists(self.statuses['pid'])

        return isExists

    def _getOpOutputPath(self, op):
        opOutPutPath = '{}-{}.json'.format(self.opOutputPathPrefix, op.opId)
        opOutPutDir = os.path.dirname(opOutPutPath)
        if len(opOutPutPath) > len(opOutPutDir) and not os.path.exists(opOutPutDir):
            os.mkdir(opOutPutDir)
        return opOutPutPath

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
                content = outputFile.read()
                if content:
                    output = json.loads(content)
            except Exception as ex:
                self.writeNodeLog('ERROR: Load operation output file:{}, failed {}\n'.format(self.outputPath, ex))
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
                content = outputFile.read()
                if content:
                    output = json.loads(content)
                    self.output = output
            except Exception as ex:
                self.writeNodeLog('ERROR: Load output file:{}, failed {}\n'.format(self.outputPath, ex))
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
                self.writeNodeLog('ERROR: Save output file:{}, failed {}\n'.format(self.outputPath, ex))
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
                content = opOutputFile.read()
                if content:
                    opOutput = json.loads(content)
                    self.output[op.opId] = opOutput
            except Exception as ex:
                self.writeNodeLog('ERROR: Load operation {} output file:{}, failed {}\n'.format(op.opId, opOutPutPath, ex))
            finally:
                if opOutputFile:
                    opOutputFile.close()

    def getNodeLogHandle(self):
        return self.logHandle

    def execute(self, ops):
        if self.context.goToStop:
            return 2

        try:
            # 更新节点状态为running
            self.updateNodeStatus(NodeStatus.running)
        except Exception as ex:
            self.writeNodeLog("ERROR: Update node status failed, {}\n".format(ex))
            self.updateNodeStatus(NodeStatus.failed)

        # TODO：restore status and output from share object storage
        nodeBeginDateTimeFN = time.strftime('%Y%m%d-%H%M%S')
        nodeBeginDateTime = time.strftime('%Y-%m-%d %H:%M:%S')

        nodeStartTime = time.time()
        self.writeNodeLog("======<{}> [{}]{}:{} Launched======\n".format(nodeBeginDateTime, self.id, self.host, self.port))

        # 创建历史日志，文件名中的状态标记置为running，在一开始创建，是为了避免中间kill掉后导致历史日志丢失
        logPathWithTime = '{}/{}.{}.{}.txt'.format(self.hisLogDir, nodeBeginDateTimeFN, NodeStatus.running, self.context.execUser)
        if not os.path.exists(logPathWithTime):
            os.link(self.logPath, logPathWithTime)
        self.logPathWithTime = logPathWithTime

        hasIgnoreFail = 0
        isFail = 0
        for op in ops:
            if self.context.goToStop:
                self.updateNodeStatus(NodeStatus.paused)
                self.writeNodeLog("INFO: Node running paused.\n")
                break

            ret = 0

            try:
                # 如果当前节点某个操作已经成功执行过则略过这个操作，除非设置了isForce
                opStatus = self.getNodeStatus(op)
                if not self.context.isForce and opStatus == NodeStatus.succeed:
                    op.parseParam(self.output)
                    self._loadOpOutput(op)
                    self.writeNodeLog("INFO: Operation {} has been executed in status:{}, skip.\n".format(op.opId, opStatus))
                    continue

                op.parseParam(self.output)
            except AutoExecError.AutoExecError as err:
                try:
                    self.writeNodeLog("ERROR: {}[{}] parse param failed, {}\n".format(op.opId, op.opName, err.value))
                    self.updateNodeStatus(NodeStatus.failed, op=op)
                    if op.failIgnore:
                        hasIgnoreFail = 1
                    else:
                        isFail = 1
                        break
                except:
                    isFail = 1
                    break

            try:
                if op.opBunddleName == 'setenv':
                    envName = op.options['name']
                    envValue = op.options['value']
                    self.context.setEnv(envName, envValue)
                    continue

                if not os.path.exists(op.pluginPath):
                    self.writeNodeLog("ERROR: Plugin not exists {}\n".format(op.pluginPath))

                beginDateTime = time.strftime('%Y-%m-%d %H:%M:%S')
                startTime = time.time()

                self.writeNodeLog("------<{}> START-- {} operation {}[{}] to be start...\n".format(beginDateTime, op.opType, op.opName, op.opId))
                ret = 0
                if self.host == 'local':
                    if op.opType == 'local' or op.opType == 'sqlfile':
                        # 本地执行
                        # 输出保存到环境变量 $OUTPUT_PATH指向的文件里
                        ret = self._localExecute(op)
                    else:
                        continue
                else:
                    if op.opType == 'localremote':
                        # 本地执行，逐个node循环本地调用插件，通过-node参数把node的json传送给插件，插件自行处理node相关的信息和操作
                        # 输出保存到环境变量 $OUTPUT_PATH指向的文件里
                        ret = self._localRemoteExecute(op)
                    elif op.opType == 'remote':
                        # 远程执行，则推送插件到远端并执行插件运行命令，输出保存到执行目录的output.json中
                        ret = self._remoteExecute(op)
                    else:
                        self.writeNodeLog("WARN: Operation type:{} not supported, only support(local|remote|local-remote), ignore.\n".format(op.opType))
                        continue

                timeConsume = time.time() - startTime
                if ret != 0:
                    self.updateNodeStatus(NodeStatus.failed, op=op, consumeTime=timeConsume)
                    pass
                else:
                    self._loadOpOutput(op)
                    self._saveOutput()
                    self.updateNodeStatus(NodeStatus.succeed, op=op, consumeTime=timeConsume)

                endDateTime = time.strftime('%Y-%m-%d %H:%M:%S')

                opFinalStatus = 'success'
                if ret != 0:
                    opFinalStatus = 'failed'
                    if op.failIgnore:
                        hasIgnoreFail = 1
                    else:
                        isFail = 1
                        break

                self.writeNodeLog("------<{}> END-- {} operation {}[{}] -- duration: {:.2f} second Execute {} {}.\n\n".format(endDateTime, op.opType, op.opName, op.opId, timeConsume, op.opTypeDesc[op.opType], opFinalStatus))
                if isFail == 1:
                    break

            except:
                isFail = 1
                self.writeNodeLog("ERROR: Unknow error ocurred.\n{}\n".format(traceback.format_exc()))
                break

        nodeEndDateTime = time.strftime('%Y-%m-%d %H:%M:%S')
        nodeConsumeTime = time.time() - nodeStartTime

        finalStatus = NodeStatus.succeed
        if isFail == 0:
            if hasIgnoreFail == 1:
                # 虽然全部操作执行完，但是中间存在fail但是ignore的operation，则设置节点状态为已忽略，主动忽略节点
                self.hasIgnoreFail = 1
                finalStatus = NodeStatus.ingore
            else:
                finalStatus = NodeStatus.succeed
        else:
            if self.isKilled:
                finalStatus = NodeStatus.aborted
            else:
                finalStatus = NodeStatus.failed

        self.writeNodeLog("======<{}> [{}]{}:{} Ended, duration:{:.2f} second status:{}======\n".format(nodeEndDateTime, self.id, self.host, self.port, nodeConsumeTime, finalStatus))
        self.updateNodeStatus(finalStatus, failIgnore=hasIgnoreFail, consumeTime=nodeConsumeTime)

        # 创建带时间戳的日志文件名
        finalLogPathWithTime = logPathWithTime
        finalLogPathWithTime = finalLogPathWithTime.replace('.{}.'.format(NodeStatus.running), '.{}.'.format(finalStatus))
        if finalLogPathWithTime != logPathWithTime:
            try:
                os.rename(self.logPathWithTime, finalLogPathWithTime)
            except:
                pass
        # os.link(self.logPath, logPathWithTime)

        self.killCmd = None
        self.childPid = None
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
        environment['AUTOEXEC_WORK_PATH'] = self.context.runPath
        environment['AUTOEXEC_PHASE_NAME'] = self.phaseName
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
            self.writeNodeLog(line)

        # 等待插件执行完成并获取进程返回值，0代表成功
        child.wait()
        ret = child.returncode

        lastContent = child.stdout.read()
        if lastContent is not None:
            self.writeNodeLog(lastContent)

        if ret == 0:
            self.writeNodeLog("INFO: Execute local command succeed:{}\n".format(orgCmdLineHidePassword))
        else:
            self.writeNodeLog("ERROR: Execute local command faled:{}\n".format(orgCmdLineHidePassword))

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
        environment['AUTOEXEC_WORK_PATH'] = self.context.runPath
        environment['AUTOEXEC_PHASE_NAME'] = self.phaseName
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
            self.writeNodeLog(line)

        # 等待插件执行完成并获取进程返回值，0代表成功
        child.wait()
        ret = child.returncode

        lastContent = child.stdout.read()
        if lastContent is not None:
            self.writeNodeLog(lastContent)

        if ret == 0:
            self.writeNodeLog("INFO: Execute local-remote command succeed: {}\n".format(orgCmdLineHidePassword))
        else:
            self.writeNodeLog("ERROR: Execute local-remote command faled: {}\n".format(orgCmdLineHidePassword))

        return ret

    def _remoteExecute(self, op):
        self.childPid = None
        remoteCmd = ''

        ret = -1
        if self.type == 'tagent':
            scriptFile = None
            try:
                remoteRoot = '$TMPDIR/autoexec-{}'.format(self.context.jobId)
                remotePath = remoteRoot + '/' + op.opBunddleName
                runEnv = {'AUTOEXEC_JOBID': self.context.jobId, 'AUTOEXEC_NODE': json.dumps(self.nodeWithoutPassword)}
                self.killCmd = "kill -9 `ps aux |grep '" + remoteRoot + "'|grep -v grep|awk '{print $2}'`"

                tagent = TagentClient.TagentClient(self.host, self.port, self.password, readTimeout=360, writeTimeout=10)
                self.tagent = tagent

                # 更新节点状态为running
                self.updateNodeStatus(NodeStatus.running, op=op)

                remoteCmd = None
                uploadRet = 0
                if op.isScript == 1:
                    scriptFile = open(op.pluginPath, 'r')
                    fcntl.flock(scriptFile, fcntl.LOCK_SH)
                    uploadRet = tagent.upload(self.username, op.pluginParentPath, remoteRoot)
                    if op.hasOutput:
                        tagent.writeFile(self.username, b'', remotePath + '/output.json')

                    remoteCmd = 'cd {} && {}'.format(remotePath, op.getCmdLine(remotePath=remotePath, osType=tagent.agentOsType))
                    fcntl.flock(scriptFile, fcntl.LOCK_UN)
                    scriptFile.close()
                    scriptFile = None
                else:
                    for srcPath in [op.remoteLibPath, op.pluginParentPath]:
                        uploadRet = tagent.upload(self.username, srcPath, remoteRoot)
                        if uploadRet != 0:
                            break
                    if op.hasOutput:
                        tagent.writeFile(self.username, b'', remotePath + '/output.json')

                    remoteCmd = 'cd {} && {}'.format(remotePath, op.getCmdLine(remotePath=remotePath, osType=tagent.agentOsType))

                if tagent.agentOsType == 'windows':
                    self.killCmd = ""
                if uploadRet == 0 and not self.context.goToStop:
                    ret = tagent.execCmd(self.username, remoteCmd, env=runEnv, isVerbose=0, callback=self.writeNodeLog)
                    if ret == 0 and op.hasOutput:
                        outputFilePath = self._getOpOutputPath(op)
                        outputStatus = tagent.download(self.username, '{}/output.json'.format(remotePath), outputFilePath)
                        if outputStatus != 0:
                            self.writeNodeLog("ERROR: Download output failed.\n")
                            ret = 2
                    try:
                        if ret != 0 and self.context.devMode:
                            if tagent.agentOsType == 'windows':
                                tagent.execCmd(self.username, "rd /s /q {}".format(remoteRoot), env=runEnv)
                            else:
                                tagent.execCmd(self.username, "rm -rf {}".format(remoteRoot), env=runEnv)
                    except Exception as ex:
                        self.writeNodeLog('ERROR: Remote remove directory {} failed {}\n'.format(remoteRoot, ex))
            except Exception as ex:
                self.writeNodeLog("ERROR: Execute operation {} failed, {}\n".format(op.opName, ex))
                raise ex
            finally:
                if scriptFile is not None:
                    fcntl.flock(scriptFile, fcntl.LOCK_SH)
                    scriptFile.close()

            if ret == 0:
                self.writeNodeLog("INFO: Execute remote command by agent succeed: {}\n".format(remoteCmd))
            else:
                self.writeNodeLog("ERROR: Execute remote command by agent failed: {}\n".format(remoteCmd))

        elif self.type == 'ssh':
            logging.getLogger("paramiko").setLevel(logging.FATAL)
            remoteRoot = '/tmp/autoexec-{}'.format(self.context.jobId)
            remotePath = '{}/{}'.format(remoteRoot, op.opBunddleName)
            remoteCmd = 'AUTOEXEC_JOBID={} AUTOEXEC_NODE=\'{}\' cd {} && {}'.format(self.context.jobId, json.dumps(self.nodeWithoutPassword), remotePath, op.getCmdLine(remotePath=remotePath))
            self.killCmd = "kill -9 `ps aux |grep '" + remoteRoot + "'|grep -v grep|awk '{print $2}'`"
            scriptFile = None
            uploaded = False
            scp = None
            sftp = None
            try:
                # 建立连接
                scp = paramiko.Transport((self.host, self.protocolPort))
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
                    self.writeNodeLog("ERROR: mkdir {} failed: {}\n".format(remoteRoot, err))

                if op.isScript == 1:
                    try:
                        sftp.stat(remotePath)
                    except IOError:
                        sftp.mkdir(remotePath)
                    except SFTPError as err:
                        self.writeNodeLog("ERROR: mkdir {} failed: {}\n".format(remotePath, err))

                    scriptFile = open(op.pluginPath, 'r')
                    fcntl.flock(scriptFile, fcntl.LOCK_SH)
                    sftp.put(op.pluginPath, os.path.join(remotePath, op.scriptFileName))
                    fcntl.flock(scriptFile, fcntl.LOCK_UN)
                    scriptFile.close()
                    scriptFile = None
                    sftp.chmod(os.path.join(remotePath, op.scriptFileName), stat.S_IXUSR)

                    # remotePath = remoteRoot
                    if op.hasOutput:
                        ofh = sftp.file(os.path.join(remotePath, 'output.json'), 'w')
                        ofh.close()

                    remoteCmd = 'AUTOEXEC_JOBID={} AUTOEXEC_NODE=\'{}\' cd {} && {}'.format(self.context.jobId, json.dumps(self.nodeWithoutPassword), remotePath, op.getCmdLine(remotePath=remotePath))
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
                    for root, dirs, files in os.walk(op.opBunddleName, topdown=True, followlinks=True):
                        try:
                            # 创建当前目录
                            sftp.mkdir(os.path.join(remoteRoot, root))
                        except:
                            pass
                        for name in files:
                            # 遍历文件并scp到目标上
                            filePath = os.path.join(root, name)
                            sftp.put(filePath, os.path.join(remoteRoot, filePath))

                    sftp.chmod('{}/{}'.format(remotePath, op.opSubName), stat.S_IXUSR)

                    if op.hasOutput:
                        ofh = sftp.file(os.path.join(remotePath, 'output.json'), 'w')
                        ofh.close()

                uploaded = True

            except Exception as err:
                self.writeNodeLog('ERROR: Upload plugin:{} to remoteRoot:{} failed: {}\n'.format(op.opName, remoteRoot, err))
            finally:
                if scriptFile is not None:
                    fcntl.flock(scriptFile, fcntl.LOCK_SH)
                    scriptFile.close()

            if uploaded and not self.context.goToStop:
                ssh = None
                try:
                    ssh = paramiko.SSHClient()
                    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                    ssh.connect(self.host, self.protocolPort, self.username, self.password)
                    channel = ssh.get_transport().open_session()
                    channel.set_combine_stderr(True)
                    channel.exec_command(remoteCmd)
                    while True:
                        r, w, x = select.select([channel], [], [], 10)
                        if len(r) > 0:
                            self.writeNodeLog(channel.recv(4096))
                        if channel.exit_status_ready():
                            ret = channel.recv_exit_status()
                            break

                    if ret == 0 and op.hasOutput:
                        try:
                            outputFilePath = self._getOpOutputPath(op)
                            sftp.get('{}/output.json'.format(remotePath), outputFilePath)
                        except:
                            self.writeNodeLog("ERROR: Download output failed.\n")
                            ret = 2
                    try:
                        if ret != 0 and self.context.devMode:
                            ssh.exec_command("rm -rf {}".format(remoteRoot, remoteRoot))
                    except Exception as ex:
                        self.writeNodeLog("ERROR: Remove remote directory {} failed {}\n".format(remoteRoot, ex))

                except Exception as err:
                    self.writeNodeLog("ERROR: Execute remote operation {} failed, {}\n".format(op.opName, err))
                finally:
                    if ssh:
                        ssh.close()

                if scp:
                    scp.close()

            if ret == 0:
                self.writeNodeLog("INFO: Execute remote command by ssh succeed:{}\n".format(remoteCmd))
            else:
                self.writeNodeLog("ERROR: Execute remote command by ssh failed:{}\n".format(remoteCmd))

        return ret

    def pause(self):
        self.writeNodeLog("INFO: Try to puase node.\n")

    def kill(self):
        if self.childPid is not None:
            pid = self.childPid

            try:
                os.kill(pid, signal.SIGTERM)
                # 如果子进程没有结束，等待3秒
                loopCount = 3
                while True:
                    if loopCount <= 0:
                        break

                    time.sleep(1)
                    os.kill(pid, signal.SIGTERM)
                    loopCount = loopCount - 1

                # 如果进程仍然存在，则直接kill -9
                time.sleep(1)
                os.kill(pid, signal.SIGKILL)
            except OSError:
                # 子进程不存在，已经退出了
                self.isKilled = True
                self.updateNodeStatus(NodeStatus.aborted)
                self.writeNodeLog("INFO: Worker killed, pid:{}.\n".format(pid))

        killCmd = self.killCmd
        if self.type == 'tagent':
            if killCmd is not None:
                tagent = TagentClient.TagentClient(self.host, self.port, self.password, readTimeout=360, writeTimeout=10)
                if tagent.execCmd(self.username, killCmd, isVerbose=0, callback=self.writeNodeLog) == 0:
                    self.updateNodeStatus(NodeStatus.aborted)
                    self.writeNodeLog("INFO: Execute kill command:{} success.\n".format(killCmd))
                    self.isKilled = True
                else:
                    self.writeNodeLog("ERROR: Execute kill command:{} failed\n".format(killCmd))
            if self.tagent:
                self.tagent.close()
                self.writeNodeLog("INFO: Stop agent execution success.\n")
        elif self.type == 'ssh' and killCmd is not None:
            ssh = None
            try:
                ssh = paramiko.SSHClient()
                ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                ssh.connect(self.host, self.protocolPort, self.username, self.password)
                channel = ssh.get_transport().open_session()
                channel.set_combine_stderr(True)
                channel.exec_command(killCmd)

                while True:
                    if channel.exit_status_ready():
                        ret = channel.recv_exit_status()
                        break

                    r, w, x = select.select([channel], [], [])
                    if len(r) > 0:
                        self.writeNodeLog(channel.recv(1024).decode() + "\n")

                self.updateNodeStatus(NodeStatus.aborted)
                self.writeNodeLog("INFO: Execute kill command:{} success.\n".format(killCmd))
                self.isKilled = True
            except Exception as err:
                self.writeNodeLog("ERROR: Execute kill command:{} failed, {}\n".format(killCmd, err))
            finally:
                if ssh:
                    ssh.close()
        else:
            self.updateNodeStatus(NodeStatus.aborted)
