#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 提供读取节点文件，遍历节点，更新节点运行状态功能
"""
import sys
import os
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

        self.output = {}
        self.statusPath = '{}/status/{}-{}.txt'.format(self.runPath, node['host'], node['nodeId'])

        self.outputPathPrefix = '{}/output/{}-{}'.format(self.runPath, node['host'], node['nodeId'])
        self.outputPath = self.outputPathPrefix + '.json'
        self.logPath = '{}/log/{}-{}.txt'.format(self.runPath, node['host'], node['nodeId'])
        self.logHandle = open(self.logPath, 'a')

        self.status = NodeStatus.pending
        self._loadOutput()

    def __del__(self):
        if self.logHandle is not None:
            self.logHandle.close()

    def updateNodeStatus(self, status, op=None):

        statuses = {}

        statusFile = None
        try:
            statusFile = open(self.statusPath, 'a+')
            statusFile.seek(0, 0)
            statuses = json.loads(statusFile.read())
        except Exception as ex:
            logging.error('Load status file:{}, failed {}'.format(self.statusPath, ex))

        if statusFile:
            if op is None:
                statuses['status'] = status
            else:
                statuses[op.opId] = status
            try:
                statusFile.truncate(0)
                statusFile.write(json.dumps(statuses))
                statusFile.close()
            except Exception as ex:
                logging.error('Save status file:{}, failed {}'.format(self.statusPath, ex))

        if op is None:
            try:
                serverAdapter = self.context.serverAdapter
                serverAdapter.pushNodeStatus(self, status)
            except Exception as ex:
                logging.error('Push status:{} to Server, failed {}'.format(self.statusPath, ex))

    def getNodeStatus(self, op=None):
        status = NodeStatus.pending
        statuses = {}
        try:
            statusFile = open(self.statusPath, 'r')
            statuses = json.loads(statusFile.read())
            statusFile.close()
        except Exception as ex:
            logging.error('Load status file:{}, failed {}'.format(self.statusPath, ex))

        if op is None:
            if 'status' in statuses:
                status = statuses['status']
        elif op.opId in statuses:
            status = statuses[op.opId]

        return status

    def _getOpOutputPath(self, op):
        return '{}-{}.json'.format(self.outputPathPrefix, op.opId)

    def _loadOutput(self):
        # 加载操作输出并进行合并
        if os.path.exists(self.outputPath):
            outputFile = None
            try:
                outputFile = open(self.outputPath, 'r')
                output = json.loads(outputFile.read())
                self.output = output
            except Exception as ex:
                logging.error('Load output file:{}, failed {}'.format(self.outputPath, ex))

            if outputFile:
                outputFile.close()

    def _saveOutput(self):
        if self.output:
            try:
                outputFile = open(self.outputPath, 'w')
                outputFile.write(json.dumps(self.output))
                outputFile.close()
            except Exception as ex:
                logging.error('Save output file:{}, failed {}'.format(self.outputPath, ex))

    def _loadOpOutput(self, op):
        # 加载操作输出并进行合并
        opOutputFile = None
        opOutPutPath = self._getOpOutputPath(op)
        if os.path.exists(opOutPutPath):
            try:
                opOutputFile = open(opOutPutPath, 'r')
                opOutput = json.loads(opOutputFile.read())
                self.output[op.opId] = opOutput

                if opOutputFile:
                    opOutputFile.close()
            except Exception as ex:
                logging.error('Load operation {} output file:{}, failed {}'.format(op.opId, opOutPutPath, ex))

    def getNodeLogHandle(self):
        return self.logHandle

    def execute(self, ops):
        isFail = 0
        for op in ops:
            if not self.context.isForce and self.getNodeStatus(op) == NodeStatus.succeed:
                continue

            self.updateNodeStatus(NodeStatus.running, op)
            if op.isLocal:
                # 本地执行，逐个node循环本地调用插件
                self.logHandle.write("======Local execute:{} {} {}\n".format(self.host, self.type, op.opName))
                ret = self._localExecute(op)
                if ret == 0:
                    self.logHandle.write("------Local execute succeed.\n\n")
                else:
                    isFail = 1
                    self.logHandle.write("------Local execute failed.\n\n")
            else:
                # 远程执行，则推送插件到远端并执行插件运行命令
                self.logHandle.write("======Remote execute:{} {} {}\n".format(self.host, self.type, op.opName))
                ret = self._remoteExecute(op)

                if ret == 0:
                    self.logHandle.write("------Remote execute succeed.\n\n")
                else:
                    isFail = 1
                    self.logHandle.write("------Remote execute failed.\n\n")

            if isFail > 0:
                self.updateNodeStatus(NodeStatus.failed, op)
                break
            else:
                self._loadOpOutput(op)
                self._saveOutput()
                self.updateNodeStatus(NodeStatus.succeed, op)

        if isFail == 0:
            self.updateNodeStatus(NodeStatus.succeed)
        else:
            self.updateNodeStatus(NodeStatus.failed)

        return isFail

    def _localExecute(self, op):
        os.chdir(self.runPath)
        ret = -1
        # 本地执行，则使用管道启动运行插件
        orgCmdLine = op.getCmdLine(self.output)
        cmdline = 'exec {}/{} --node \'{}\''.format(op.pluginPath, orgCmdLine, json.dumps(self.node))
        self.logHandle.flush()
        environment = {'OUTPUT_PATH': self._getOpOutputPath(op)}
        child = subprocess.Popen(cmdline, env=environment, shell=True, stdout=self.logHandle, stderr=self.logHandle)
        #child = subprocess.Popen(cmdline, shell=True, stdout=sys.stdout, stderr=sys.stderr)
        # 管道启动成功后，更新状态为running

        # 等待插件执行完成并获取进程返回值，0代表成功
        child.wait()
        ret = child.returncode

        if ret == 0:
            logging.debug('Execute command succeed:{} on node[{}]{}:{}'.format(orgCmdLine, self.id, self.host, self.port))
        else:
            logging.debug('Execute command faled:{} on node[{}]{}:{}'.format(orgCmdLine, self.id, self.host, self.port))

        return ret

    def _remoteExecute(self, op):
        remoteCmd = ''
        ret = -1
        if self.type == 'tagent':
            try:
                remotePath = '$TMPDIR/autoexec-{}-{}'.format(self.context.stepId, self.context.taskId)
                remoteCmd = 'cd {}/{} && ./{}'.format(remotePath, op.opId, op.getCmdLine(self.output))

                tagent = TagentClient.TagentClient(self.host, self.port, self.password, readTimeout=360, writeTimeout=10)
                uploadRet = 0
                uploadRet = tagent.upload(self.username, op.pluginPath, remotePath)
                if uploadRet == 0:
                    ret = tagent.execCmd(self.username, 'cd {}/{} && ./{}'.format(remotePath, op.opId, op.getCmdLine(self.output)), isVerbose=0, callback=self.logHandle.write)
                    if ret == 0 and op.hasOutput:
                        outputFilePath = self._getOpOutputPath(op)
                        outputStatus = tagent.download(self.username, '{}/{}/output.json'.format(remotePath, op.opId), outputFilePath)
                        if outputStatus != 0:
                            self.logHandle.write("ERROR: Download output failed.\n")
                            ret = 2
                    try:
                        if tagent.agentOsType == 'windows':
                            tagent.execCmd(self.username, "rd /s /q {}".format(remotePath))
                        else:
                            tagent.execCmd(self.username, "rm -rf {}".format(remotePath))
                    except Exception as ex:
                        self.logHandle.write('Remote remoe directory {} failed {}'.format(remotePath, ex))
            except Exception as ex:
                self.logHandle.write('Execute command {} failed, {}'.format(op.opId, ex))

        elif self.type == 'ssh':
            logging.getLogger("paramiko").setLevel(logging.FATAL)
            remoteRoot = '/tmp/autoexec-{}-{}'.format(self.context.stepId, self.context.taskId)
            remotePath = '{}/{}'.format(remoteRoot, op.opId)
            remoteCmd = 'cd {} && ./{}'.format(remotePath, op.getCmdLine(self.output))

            uploaded = False
            scp = None
            sftp = None
            try:
                # 建立连接
                scp = paramiko.Transport((self.host, self.port))
                scp.connect(username=self.username, password=self.password)

                # 建立一个sftp客户端对象，通过ssh transport操作远程文件
                sftp = paramiko.SFTPClient.from_transport(scp)
                # Copy a local file (localpath) to the SFTP server as remotepath
                try:
                    try:
                        sftp.stat(remoteRoot)
                    except IOError:
                        sftp.mkdir(remoteRoot)
                except SFTPError as err:
                    self.logHandle.write("mkdir {} error: {}".format(remoteRoot, err))

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
                self.logHandle.write('Upload plugin:{} to remoteRoot:{} error: {}'.format(op.opId, remoteRoot, err))

            if uploaded:
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
                            self.logHandle.write(channel.recv(1024).decode())

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
                        self.logHandle.write("Remove remote directory {} failed {}\n".format(remotePath, ex))

                except Exception as err:
                    self.logHandle.write("Execute command:{} failed, {}".format(op.opId, err))
                finally:
                    if ssh:
                        ssh.close()

                if scp:
                    scp.close()

        if ret == 0:
            logging.debug('Execute command succeed:{} on node[{}]{}:{}'.format(remoteCmd, self.id, self.host, self.port))
        else:
            logging.debug('Execute command failed:{} on node[{}]{}:{}'.format(remoteCmd, self.id, self.host, self.port))

        return ret
