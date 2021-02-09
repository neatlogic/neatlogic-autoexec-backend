#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 提供读取节点文件，遍历节点，更新节点运行状态功能
"""
import sys
import os
import io
import signal
import time
import stat
import subprocess
import select
import json
import logging
import traceback
import paramiko
from paramiko.sftp import SFTPError
from paramiko.ssh_exception import SSHException
import NodeStatus
import TagentClient
import Utils


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

    def __init__(self, context, node):
        self.context = context
        self.runPath = context.runPath
        self.node = node
        self.type = node['nodeType']
        self.host = node['host']
        self.port = node['port']
        self.id = node['nodeId']
        self.username = node['username']
        self.password = node['password']

        self.childPid = None
        self.killCmd = None

        self.output = self.context.output
        self.statusPath = '{}/status/{}-{}.txt'.format(self.runPath, node['host'], node['nodeId'])

        self.outputPathPrefix = '{}/output/{}-{}'.format(self.runPath, node['host'], node['nodeId'])
        self.opOutputPathPrefix = '{}/output-op/{}-{}'.format(self.runPath, node['host'], node['nodeId'])
        self.outputPath = self.outputPathPrefix + '.json'
        self.logPath = '{}/log/{}-{}.txt'.format(self.runPath, node['host'], node['nodeId'])
        # self.logHandle = open(self.logPath, 'a', buffering=1)
        self.logHandle = LogFile(open(self.logPath, 'a').detach())

        self.status = NodeStatus.pending
        self._loadOutput()

    def __del__(self):
        if self.logHandle is not None:
            self.logHandle.close()

    def updateNodeStatus(self, status, op=None, consumeTime=0):
        statuses = {}

        statusFile = None
        try:
            statusFile = open(self.statusPath, 'a+')
            statusFile.seek(0, 0)
            content = statusFile.read()
            if content is not None and content != '':
                statuses = json.loads(content)
        except Exception as ex:
            self.logHandle.write('ERROR: Load and update status file:{}, failed {}\n'.format(self.statusPath, ex))

        if statusFile:
            if op is None:
                statuses['status'] = status
            else:
                statuses[op.opId] = status
            try:
                statusFile.truncate(0)
                statusFile.write(json.dumps(statuses))
                # TODO: write status file to share object store
                statusFile.close()
            except Exception as ex:
                self.logHandle.write('ERROR: Save status file:{}, failed {}\n'.format(self.statusPath, ex))

        if op is None:
            try:
                serverAdapter = self.context.serverAdapter
                serverAdapter.pushNodeStatus(self, status, time.time())
            except Exception as ex:
                self.logHandle.write('ERROR: Push status:{} to Server, failed {}\n'.format(self.statusPath, ex))

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

    def _loadOutput(self):
        # 加载操作输出并进行合并
        if os.path.exists(self.outputPath):
            outputFile = None
            try:
                outputFile = open(self.outputPath, 'r')
                output = json.loads(outputFile.read())
                self.output = output
            except Exception as ex:
                self.logHandle.write('ERROR: Load output file:{}, failed {}\n'.format(self.outputPath, ex))

            if outputFile:
                outputFile.close()

    def _saveOutput(self):
        if self.output:
            try:
                outputFile = open(self.outputPath, 'w')
                outputFile.write(json.dumps(self.output))
                # TODO: write output file to share object store
                outputFile.close()
            except Exception as ex:
                self.logHandle.write('ERROR: Save output file:{}, failed {}\n'.format(self.outputPath, ex))

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

        # TODO：restore status and output from share object storage
        nodeBeginDateTime = time.strftime('%Y-%m-%d %H:%M:%S')
        nodeStartTime = time.time()
        self.logHandle.write("------<{}> [{}]{}:{}------\n\n".format(nodeBeginDateTime, self.id, self.host, self.port))

        isFail = 0
        for op in ops:
            ret = 0

            if not self.context.isForce and self.getNodeStatus(op) == NodeStatus.succeed:
                self._loadOpOutput(op)
                continue

            op.parseParam(self.output)

            beginDateTime = time.strftime('%Y-%m-%d %H:%M:%S')
            startTime = time.time()
            # 如果节点是虚构的本地节点，则只执行类型是local的操作
            if self.host == 'local' or self.host == 'local-pre' or self.host == 'local-post':
                ret = 0
                if op.opType == 'local':
                    # 本地执行，逐个node循环本地调用插件
                    self.logHandle.write("------BEGIN-- {}[{}] local execute...\n".format(op.opId, op.opName))
                    ret = self._localExecute(op)
                else:
                    continue
            # 否则则按照以节点的方式来运行操作
            else:
                ret = 0
                if op.opType == 'localremote':
                    # 本地执行，逐个node循环本地调用插件，通过-node参数把node的json传送给插件，插件自行处理node相关的信息和操作
                    # 输出保存到环境变量 $OUTPUT_PATH指向的文件里
                    self.logHandle.write("------BEGIN--<{}> {}[{}] local-remote execute...\n".format(beginDateTime, op.opId, op.opName))
                    ret = self._localRemoteExecute(op)

                elif op.opType == 'remote':
                    # 远程执行，则推送插件到远端并执行插件运行命令，输出保存到执行目录的output.json中
                    self.logHandle.write("------BEGIN--<{}> {}[{}] remote execute...\n".format(beginDateTime, op.opId, op.opName))
                    ret = self._remoteExecute(op)

            timeConsume = time.time() - startTime
            if ret != 0:
                self.updateNodeStatus(NodeStatus.failed, op, consumeTime=timeConsume)
            else:
                self._loadOpOutput(op)
                self._saveOutput()
                self.updateNodeStatus(NodeStatus.succeed, op, consumeTime=timeConsume)

            endDateTime = time.strftime('%Y-%m-%d %H:%M:%S')
            if ret == 0:
                self.logHandle.write("------END--<{}> {}[{}] {:.2f}second Execute {} succeed.\n\n".format(endDateTime, op.opId, op.opName, timeConsume, op.opType))
            else:
                isFail = 1
                self.logHandle.write("------END--<{}> {}[{}] {:.2f}second Execute {} failed.\n\n".format(endDateTime, op.opId, op.opName, timeConsume, op.opType))
                break

        nodeEndDateTime = time.strftime('%Y-%m-%d %H:%M:%S')
        nodeConsumeTime = time.time() - nodeStartTime

        if isFail == 0:
            self.updateNodeStatus(NodeStatus.succeed, consumeTime=timeConsume)
        else:
            self.updateNodeStatus(NodeStatus.failed, consumeTime=timeConsume)

        if isFail == 0:
            self.logHandle.write("------<{}> {:.2f}second [{}]{}:{} succeed------\n".format(nodeEndDateTime, nodeConsumeTime, self.id, self.host, self.port))
        else:
            self.logHandle.write("------<{}> {:.2f}second [{}]{}:{} failed------\n".format(nodeEndDateTime, nodeConsumeTime, self.id, self.host, self.port))

        self.killCmd = None
        return isFail

    def _localExecute(self, op):
        self.childPid = None
        self.killCmd = None
        os.chdir(self.runPath)
        ret = -1
        # 本地执行，则使用管道启动运行插件
        orgCmdLine = op.getCmdLine()
        orgCmdLineHidePassword = op.getCmdLineHidePassword()

        cmdline = 'exec {}/{}'.format(op.pluginPath, orgCmdLine)
        environment = {'OUTPUT_PATH': self._getOpOutputPath(op)}
        child = subprocess.Popen(cmdline, env=environment, shell=True, close_fds=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.childPid = child.pid
        # 管道启动成功后，更新状态为running
        self.updateNodeStatus(NodeStatus.running, op)

        while True:
            line = child.stdout.readline()
            if not line:
                break
            self.logHandle.write(line)

        # 等待插件执行完成并获取进程返回值，0代表成功
        child.wait()
        ret = child.returncode

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
        orgCmdLine = op.getCmdLine()
        orgCmdLineHidePassword = op.getCmdLineHidePassword()

        cmdline = 'exec {}/{} --node \'{}\''.format(op.pluginPath, orgCmdLine, json.dumps(self.node))
        environment = {'OUTPUT_PATH': self._getOpOutputPath(op)}
        child = subprocess.Popen(cmdline, env=environment, shell=True, close_fds=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.childPid = child.pid
        # 管道启动成功后，更新状态为running
        self.updateNodeStatus(NodeStatus.running, op)

        while True:
            line = child.stdout.readline()
            if not line:
                break
            self.logHandle.write(line)

        # 等待插件执行完成并获取进程返回值，0代表成功
        child.wait()
        ret = child.returncode

        if ret == 0:
            self.logHandle.write("INFO: Execute local-remote command succeed:{}\n".format(orgCmdLineHidePassword))
        else:
            self.logHandle.write("ERROR: Execute local-remote command faled:{}\n".format(orgCmdLineHidePassword))

        return ret

    def _remoteExecute(self, op):
        self.childPid = None

        remoteCmd = ''
        ret = -1
        if self.type == 'tagent':
            try:
                remotePath = '$TMPDIR/autoexec-{}-{}'.format(self.context.stepId, self.context.taskId)
                remoteCmd = 'cd {}/{} && ./{}'.format(remotePath, op.opId, op.getCmdLine())
                remoteCmdHidePassword = 'cd {}/{} && ./{}'.format(remotePath, op.opId, op.getCmdLineHidePassword())

                runEnv = {'AUTOEXEC_TASKID': self.context.taskId, 'AUTOEXEC_STEPID': self.context.stepId}

                tagent = TagentClient.TagentClient(self.host, self.port, self.password, readTimeout=360, writeTimeout=10)

                # 更新节点状态为running
                self.updateNodeStatus(NodeStatus.running, op)

                uploadRet = 0
                uploadRet = tagent.upload(self.username, op.pluginPath, remotePath)
                if uploadRet == 0 and not self.context.goToStop:
                    ret = tagent.execCmd(self.username, 'cd {}/{} && ./{}'.format(remotePath, op.opId, op.getCmdLine()), env=runEnv, isVerbose=0, callback=self.logHandle.write)
                    if ret == 0 and op.hasOutput:
                        outputFilePath = self._getOpOutputPath(op)
                        outputStatus = tagent.download(self.username, '{}/{}/output.json'.format(remotePath, op.opId), outputFilePath)
                        if outputStatus != 0:
                            self.logHandle.write("ERROR: Download output failed.\n")
                            ret = 2
                    try:
                        if tagent.agentOsType == 'windows':
                            tagent.execCmd(self.username, "rd /s /q {}".format(remotePath), env=runEnv)
                        else:
                            tagent.execCmd(self.username, "rm -rf {}".format(remotePath), env=runEnv)
                    except Exception as ex:
                        self.logHandle.write('ERROR: Remote remove directory {} failed {}\n'.format(remotePath, ex))
            except Exception as ex:
                self.logHandle.write("ERROR: Execute operation {} failed, {}\n".format(op.opId, ex))

            if ret == 0:
                self.logHandle.write("INFO: Execute remote command by agent succeed:{}\n".format(remoteCmdHidePassword))
            else:
                self.logHandle.write("ERROR: Execute remote command by agent failed:{}\n".format(remoteCmdHidePassword))

        elif self.type == 'ssh':
            logging.getLogger("paramiko").setLevel(logging.FATAL)
            remoteRoot = '/tmp/autoexec-{}-{}'.format(self.context.stepId, self.context.taskId)
            remotePath = '{}/{}'.format(remoteRoot, op.opId)
            remoteCmd = 'AUTOEXEC_TASKID={} AUTOEXEC_STEPID={} cd {} && {}/{}'.format(self.context.taskId, self.context.stepId, remotePath, remotePath, op.getCmdLine())
            remoteCmdHidePassword = 'AUTOEXEC_TASKID={} AUTOEXEC_STEPID={} cd {} && {}/{}'.format(self.context.taskId, self.context.stepId, remotePath, remotePath, op.getCmdLineHidePassword())
            self.killCmd = "kill -9 `ps aux |grep '" + remotePath + "'|grep -v grep|awk '{print $1}'`"

            uploaded = False
            scp = None
            sftp = None
            try:
                # 建立连接
                scp = paramiko.Transport((self.host, self.port))
                scp.connect(username=self.username, password=self.password)

                # 更新节点状态为running
                self.updateNodeStatus(NodeStatus.running, op)

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

                # 切换到插件根目录，便于遍历时的文件目录时，文件名为此目录相对路径
                os.chdir(op.pluginRootPath)

                # 为了从顶向下创建目录，遍历方式为从顶向下的遍历，并follow link
                for root, dirs, files in os.walk(op.opId, topdown=True, followlinks=True):
                    try:
                        # 创建当前目录
                        sftp.mkdir(os.path.join(remoteRoot, root))
                    except:
                        pass
                    for name in files:
                        # 遍历文件并scp到目标上
                        filePath = os.path.join(root, name)
                        sftp.put(filePath, os.path.join(remoteRoot, filePath))
                    uploaded = True

                sftp.chmod('{}/{}'.format(remotePath, op.opId), stat.S_IXUSR)
            except Exception as err:
                self.logHandle.write('ERROR: Upload plugin:{} to remoteRoot:{} failed: {}\n'.format(op.opId, remoteRoot, err))

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
                        ssh.exec_command("rm -rf {} || rd /s /q {}".format(remotePath, remotePath))
                    except Exception as ex:
                        self.logHandle.write("ERROR: Remove remote directory {} failed {}\n".format(remotePath, ex))

                except Exception as err:
                    self.logHandle.write("ERROR: Execute remote operation {} failed, {}\n".format(op.opId, err))
                finally:
                    if ssh:
                        ssh.close()

                if scp:
                    scp.close()

            if ret == 0:
                self.logHandle.write("INFO: Execute remote command by ssh succeed:{}\n".format(remoteCmdHidePassword))
            else:
                self.logHandle.write("ERROR: Execute remote command by ssh failed:{}\n".format(remoteCmdHidePassword))

        return ret

    def kill(self):
        if self.childPid is not None:
            pid = self.childPid

            try:
                if pid is not None:
                    os.kill(pid, signal.SIGTERM)

                (exitPid, exitStatus) = os.waitpid(pid, os.WNOHANG)
                # 如果子进程没有结束，等待3秒
                loopCount = 3
                while exitPid != pid:
                    if loopCount <= 0:
                        break

                    time.sleep(1)
                    (exitPid, exitStatus) = os.waitpid(pid, os.WNOHANG)
                    loopCount = loopCount - 1
            except OSError:
                # 子进程不存在，已经退出了
                pass

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
                if ssh:
                    ssh.close()
