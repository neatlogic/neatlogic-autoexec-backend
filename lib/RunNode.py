#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 运行节点类
"""
from distutils.command.upload import upload
import os
import traceback
import fcntl
import signal
import time
import stat
import copy
import subprocess
import select
import json
import logging
import re
import chardet
import traceback

from setuptools import find_namespace_packages
import paramiko
from paramiko.sftp import SFTPError
from paramiko.ssh_exception import SSHException

from AutoExecError import AutoExecError
import Operation
import ConditionDSL
import NodeStatus
import TagentClient
import Utils
import OutputStore


class LogFile:
    def __init__(self, fileHandle, runNode):
        self.failIgnore = False
        self.hintKeyBytes = b'ERROR:'
        self.foreLine = b''
        self.fileHandle = fileHandle
        self.runNode = runNode
        self.srcEncoding = None
        self.failPats = []
        self.failPatsOp = 'and'
        self.failExpPat = None

    def setFailPattern(self, failIgnore, operator, patOpts, exPatOpt):
        self.failIgnore = failIgnore
        if(failIgnore):
            self.hintKeyBytes = b'WARN:'
        self.failPatsOp = operator
        for reOpt in patOpts:
            if reOpt is not None and reOpt != '':
                try:
                    self.failPats.append(re.compile(reOpt.get('value')))
                except Exception as ex:
                    self.write("WARN: Log fail pattern not a regexp:{}, {}, ignore.\n".format(reOpt.get('value'), str(ex)))
        try:
            if exPatOpt is not None and exPatOpt != '':
                self.failExpPat = re.compile(exPatOpt)
        except Exception as ex:
            self.write("WARN: Log fail except pattern not a regexp:{}, {}, ignore.\n".format(exPatOpt, str(ex)))

    def clearFailPattern(self):
        self.failPats = []
        self.failPatsOp = 'and'
        self.failExpPat = None

    def checkFailLog(self, line):
        if not self.failPats:
            return False

        if self.failExpPat is not None:
            if self.failExpPat.search(line):
                return False

        if self.failPatsOp == 'and':
            matched = True
            for pat in self.failPats:
                if not pat.search(line):
                    matched = False
                    break
            if matched:
                if not self.failIgnore:
                    self.runNode.hasFailLog = True
                pats = str(self.failPats[0])
                for pat in self.failPats[1:]:
                    pats = pats + 'and ' + pat
                timeBytes = Utils.getTimeStr().encode()
                self.fileHandle.write(timeBytes + self.hintKeyBytes + ' Fail pattern {} matched for pre line.\n'.format(pats).encode())
        else:
            matched = False
            for pat in self.failPats:
                if pat.search(line):
                    if not self.failIgnore:
                        self.runNode.hasFailLog = True
                    matched = True
                    timeBytes = Utils.getTimeStr().encode()
                    self.fileHandle.write(timeBytes + self.hintKeyBytes + ' Fail pattern {} matched for pre line.\n'.format(pat).encode())
                    break

        return matched

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
                line = text[start:end+1]
                decodeLine = None
                if self.srcEncoding is None:
                    detectInfo = chardet.detect(text)
                    detectEnc = detectInfo['encoding']
                    if detectEnc != 'ascii' and not detectEnc.startswith('ISO-8859'):
                        self.srcEncoding = detectEnc
                    else:
                        decodeLine = line.decode()
                if self.srcEncoding is not None:
                    try:
                        decodeLine = line.decode(self.srcEncoding)
                        line = decodeLine.encode('utf-8')
                    except:
                        pass

                self.fileHandle.write(timeBytes + line)
                start = end + 1

                self.checkFailLog(decodeLine)

        except ValueError:
            if start >= 0:
                self.foreLine = text[start:]

    def close(self):
        if self.foreLine != b'':
            decodeLine = None
            timeBytes = Utils.getTimeStr().encode()
            if self.srcEncoding is not None:
                try:
                    decodeLine = self.foreLine.decode(self.srcEncoding)
                    self.foreLine = decodeLine.encode('utf-8')
                except:
                    pass
            else:
                decodeLine = self.foreLine.decode()
            self.fileHandle.write(timeBytes + self.foreLine)

            self.checkFailLog(decodeLine)

        self.fileHandle.close()


class RunNode:

    def __init__(self, context, groupNo, phaseIndex, phaseName, phaseType, node, totalNodesCount=0):
        self.context = context
        # 如果节点运行时所有operation运行完，但是存在failIgnore则此属性会被设置为1
        self.hasIgnoreFail = 0
        self.statuses = {}
        self.statusFile = None
        self.logger = logging.getLogger('')
        self.groupNo = groupNo
        self.phaseIndex = phaseIndex
        self.phaseName = phaseName
        self.phaseType = phaseType
        self.runPath = context.runPath
        self.node = node
        self.totalNodesCount = totalNodesCount
        self.warnCount = 0
        self.isAborting = False
        self.hasFailLog = False

        self.tagent = None
        self.childPid = None
        self.isKilled = False
        self.killCmd = None
        self.logHandle = None

        self.nodeWithoutPassword = copy.copy(node)
        self.nodeWithoutPassword['password'] = ''

        self.resourceId = node.get('resourceId', 0)

        self.name = node.get('nodeName', '')
        self.type = node.get('protocol', '')
        self.host = node.get('host', '')
        self.port = node.get('port', '')
        self.protocolPort = node.get('protocolPort', '')

        self.id = self.resourceId
        self.username = node.get('username', 'none')
        self.password = node.get('password', '')

        self.phaseLogDir = '{}/log/{}'.format(self.runPath, phaseName)
        if not os.path.exists(self.phaseLogDir):
            os.mkdir(self.phaseLogDir)

        self.logPathWithTime = None
        self.logPath = '{}/{}-{}-{}.txt'.format(self.phaseLogDir, self.host, self.port, self.resourceId)
        self.hisLogDir = '{}/{}-{}-{}.hislog'.format(self.phaseLogDir, self.host, self.port, self.resourceId)

        try:
            if not os.path.exists(self.hisLogDir):
                os.mkdir(self.hisLogDir)
        except Exception as ex:
            self.logger.log(logging.FATAL, "ERROR: Create log dir {} failed, {}\n".format(self.hisLogDir, ex))
            self.updateNodeStatus(NodeStatus.failed)

        self.localOutput = {}
        self.output = {'nodeEnv': {}}
        self.input = {}
        self.statusPhaseDir = '{}/status/{}'.format(self.runPath, phaseName)
        if not os.path.exists(self.statusPhaseDir):
            os.mkdir(self.statusPhaseDir)

        self.statusPath = '{}/{}-{}-{}.json'.format(self.statusPhaseDir, self.host, self.port, self.resourceId)

        self.outputRoot = self.runPath + '/output'
        self.outputRelDir = 'output/{}-{}-{}'.format(self.host, self.port, self.resourceId)
        self.outputDir = '{}/{}'.format(self.runPath, self.outputRelDir)
        self.outputPath = self.outputDir + '.json'

        self.inputRoot = self.runPath + '/input'
        self.inputRelDir = 'input/{}-{}-{}'.format(self.host, self.port, self.resourceId)
        self.inputDir = '{}/{}'.format(self.runPath, self.inputRelDir)
        self.inputPath = self.inputDir + '.json'

        self.opOutputRoot = self.runPath + '/output-op'
        self.opOutputRelDir = 'output-op/{}-{}-{}'.format(self.host, self.port, self.resourceId)
        self.opOutputDir = '{}/{}'.format(self.runPath, self.opOutputRelDir)
        #self.opInputRelDir = 'input-op/{}-{}-{}'.format(self.host, self.port, self.resourceId)
        #self.opInputDir = '{}/{}'.format(self.runPath, self.opInputRelDir)
        self.opLocalOutputDir = '{}/output-op/local-0-0'.format(self.runPath)

        self.liveDataDir = '{}/livedata/{}/{}-{}-{}'.format(self.runPath, phaseName, self.host, self.port, self.resourceId)

        os.makedirs(self.outputRoot, exist_ok=True)
        os.makedirs(self.opOutputDir, exist_ok=True)
        os.makedirs(self.inputRoot, exist_ok=True)
        os.makedirs(self.liveDataDir, exist_ok=True)

        self.status = NodeStatus.pending
        self.outputStore = OutputStore.OutputStore(context, self.phaseName, node)
        self._loadNodeStatus()
        self._loadOutput()
        self._loadInput()

        self.nodeEnv = self.output.get('nodeEnv', {}).copy()
        # 下面的nodeEnv是动态生成的
        self.nodeEnv['RESOURCE_ID'] = self.resourceId
        self.nodeEnv['NODE_NAME'] = self.name
        self.nodeEnv['NODE_HOST'] = self.host
        self.nodeEnv['NODE_PORT'] = str(self.port)
        self.nodeEnv['NODE_PROTOCOL_PORT'] = self.protocolPort
        self.nodeEnv['INS_NAME'] = self.name
        self.nodeEnv['INS_HOST'] = self.host
        self.nodeEnv['INS_PORT'] = self.port
        self.nodeEnv['INS_PROTOCOL_PORT'] = self.protocolPort
        self.nodeEnv['INS_PATH'] = '%s/%s' % (os.getenv('NAME_PATH'), self.name)
        self.nodeEnv['INS_ID_PATH'] = '%s/%s' % (os.getenv('ID_PATH'), self.id)

        # if self.logHandle is None:
        #     # 如果文件存在，则删除重建
        #     if os.path.exists(self.logPath):
        #         os.unlink(self.logPath)
        #     self.logHandle = LogFile(open(self.logPath, 'wb').detach(), self)

    def __del__(self):
        if self.logHandle is not None:
            self.logHandle.close()

    def writeNodeLog(self, msg):
        if isinstance(msg, bytes):
            if msg.startswith(b'ERROR:') or msg.startswith(b'WARN:'):
                self.warnCount = self.warnCount + 1
        else:
            if msg.startswith('ERROR:') or msg.startswith('WARN:'):
                self.warnCount = self.warnCount + 1

        if self.logHandle is not None:
            self.logHandle.write(msg)
        else:
            print(msg)

    def updateNodeStatus(self, status, op=None, interact=None, failIgnore=0, consumeTime=0):
        if status == NodeStatus.aborted or status == NodeStatus.failed:
            if op is None or not op.failIgnore:
                self.context.hasFailNodeInGlobal = True
            if self.isAborting:
                status = NodeStatus.aborted
        elif status == NodeStatus.ignored:
            if self.isAborting:
                status = NodeStatus.aborted

        self.statuses['pid'] = self.context.pid
        self.statuses['interact'] = interact

        if op is None:
            if self.statuses.get('status') == status:
                # If reupdate return
                return

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
            self.statusFile.write(json.dumps(self.statuses, ensure_ascii=False))
            self.statusFile.flush()
            self.outputStore.saveStatus(self.statuses)
        except Exception as ex:
            raise AutoExecError('Save status file:{}, failed {}'.format(self.statusPath, ex))

        if op is None:
            try:
                serverAdapter = self.context.serverAdapter
                # 当status为failed，但是failIgnore为1，不影响继续执行
                retObj = serverAdapter.pushNodeStatus(self.groupNo, self.phaseName, self, status, failIgnore=failIgnore, warnCount=self.warnCount)

                # 如果update 节点状态返回当前phase是失败的状态，代表全局有节点是失败的，这个时候需要标记全局存在失败的节点
                if 'Status' in retObj and retObj['Status'] == 'OK':
                    self.writeNodeLog("INFO: Change node status to " + status + ".\n")
                    if 'Return' in retObj and 'hasFailNode' in retObj['Return']:
                        if retObj['Return']['hasFailNode'] == 1:
                            self.context.hasFailNodeInGlobal = True
                else:
                    self.writeNodeLog("INFO: Change node status to {} failed, {}\n".format(status, json.dumps(retObj, ensure_ascii=False)))
            except Exception as ex:
                raise AutoExecError('Push status:{} to server, failed {}'.format(self.statusPath, ex))

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
            raise AutoExecError('Load status file:{}, failed {}'.format(self.statusPath, ex))

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

    def _ensureOpOutputDir(self, op):
        outDir = self.opOutputDir
        if not os.path.exists(outDir):
            os.mkdir(outDir)
            # 如果操作是带目录的，则创建子目录
        opBundleDir = os.path.dirname(op.opId)
        if opBundleDir:
            outDir = outDir + '/' + opBundleDir
            if not os.path.exists(outDir):
                os.mkdir(outDir)
        return outDir

    def _ensureOpFileOutputDir(self, op):
        outDir = self.opOutputDir
        outRelDir = self.opOutputRelDir
        if not os.path.exists(outDir):
            os.mkdir(outDir)
        for subName in op.opId.split('/'):
            outRelDir = outRelDir + '/' + subName
            outDir = outDir + '/' + subName
            if not os.path.exists(outDir):
                os.mkdir(outDir)
        return outRelDir

    def _getOpOutputPath(self, op):
        opOutputPath = '{}/{}.json'.format(self.opOutputDir, op.opId)
        return opOutputPath

    def _getOpLocalOutputPath(self, op):
        opLocalOutputPath = '{}/{}.json'.format(self.opLocalOutputDir, op.opId)
        return opLocalOutputPath

    def _getOpLiveDataPath(self, op):
        opLiveDataDir = '{}/{}.json'.format(self.liveDataDir, op.opId)
        return opLiveDataDir

    def _getLocalOutput(self):
        output = {}
        # localOutputPath = '{}/output/local-0-0.json'.format(self.runPath)
        # if os.path.exists(localOutputPath):
        #     # 如果runner本地存在local的output文件，则从本地加载
        #     # TODO：如果local的运行runner是随机选择的，那就要必须强制从mongodb中加载output
        #     outputFile = None
        #     try:
        #         outputFile = open(localOutputPath, 'r')
        #         fcntl.flock(outputFile, fcntl.LOCK_SH)
        #         content = outputFile.read()
        #         if content:
        #             output = json.loads(content)
        #     except Exception as ex:
        #         raise AutoExecError('Load operation output file:{}, failed {}'.format(self.outputPath, ex))
        #     finally:
        #         if outputFile is not None:
        #             fcntl.flock(outputFile, fcntl.LOCK_UN)
        #             outputFile.close()
        # else:
        # 因为local的phase和remote|localremote的phase很可能不在同一个runner中执行，所以需要远程从mongodb中加载output数据
        phaseStatus = self.context.phases[self.phaseName]
        if phaseStatus.localOutput is None:
            localNode = {'resourceId': 0, 'host': 'local', 'port': 0}
            loalOutStore = OutputStore.OutputStore(self.context, self.phaseName, localNode)
            output = loalOutStore.loadOutput()
            phaseStatus.localOutput = output
        else:
            output = phaseStatus.localOutput

        return output

    def _loadOutput(self):
        # 加载操作输出并进行合并
        if os.path.exists(self.outputPath):
            # 如果runner本地存在output文件，则从本地加载
            # TODO：如果运行runner是随机选择的，那就要必须强制从mongodb中加载output
            outputFile = None
            try:
                outputFile = open(self.outputPath, 'r')
                fcntl.flock(outputFile, fcntl.LOCK_SH)
                content = outputFile.read()
                if content:
                    output = json.loads(content)
                    self.output = output
            except Exception as ex:
                raise AutoExecError('Load output file:{}, failed {}'.format(self.outputPath, ex))
            finally:
                if outputFile is not None:
                    fcntl.flock(outputFile, fcntl.LOCK_UN)
                    outputFile.close()
        else:
            # 如果本地output文件不存在则从mongodb加载
            self.output = self.outputStore.loadOutput()

        if 'nodeEnv' not in self.output:
            self.output['nodeEnv'] = {}

        # 为了让remote的节点能够引用到local输出的参数，需要加载local节点的output
        localOutput = self._getLocalOutput()
        if localOutput is not None:
            self.localOutput = localOutput

        if 'nodeEnv' not in self.localOutput:
            self.localOutput['nodeEnv'] = {}

    def _loadInput(self):
        # 加载操作输入参数
        if os.path.exists(self.inputPath):
            inputFile = None
            try:
                inputFile = open(self.inputPath, 'r')
                fcntl.flock(inputFile, fcntl.LOCK_SH)
                content = inputFile.read()
                if content:
                    input = json.loads(content)
                    self.input = input
            except Exception as ex:
                raise AutoExecError('Load input file:{}, failed {}'.format(self.inputPath, ex))
            finally:
                if inputFile is not None:
                    fcntl.flock(inputFile, fcntl.LOCK_UN)
                    inputFile.close()

    def _saveOutput(self):
        if self.output:
            outputFile = None
            localOutFile = None
            try:
                if self.resourceId == 0:
                    phaseStatus = self.context.phases[self.phaseName]
                    phaseStatus.localOutput = self.output

                outputFile = open(self.outputPath, 'w')
                fcntl.flock(outputFile, fcntl.LOCK_EX)
                outputFile.write(json.dumps(self.output, indent=4, ensure_ascii=False))
                self.outputStore.saveOutput(self.output)

                if self.resourceId != 0 and self.totalNodesCount == 1:
                    phaseStatus = self.context.phases[self.phaseName]
                    localOutputPath = '{}/output/local-0-0.json'.format(self.runPath)
                    localOutFile = open(localOutputPath, 'w')
                    fcntl.flock(outputFile, fcntl.LOCK_EX)
                    localOutFile.write(json.dumps(phaseStatus.localOutput, indent=4, ensure_ascii=False))
                    self.outputStore.saveOutputToLocal(phaseStatus.localOutput)
            except Exception as ex:
                raise AutoExecError('Save output file:{}, failed {}'.format(self.outputPath, ex))
            finally:
                if localOutFile is not None:
                    fcntl.flock(localOutFile, fcntl.LOCK_UN)
                    localOutFile.close()
                if outputFile is not None:
                    fcntl.flock(outputFile, fcntl.LOCK_UN)
                    outputFile.close()

    def _loadOpOutput(self, op):
        # 加载操作输出并进行合并
        opOutputFile = None
        opOutPutPath = self._getOpOutputPath(op)
        if os.path.exists(opOutPutPath):
            try:
                opOutput = {}
                opOutputFile = open(opOutPutPath, 'r')
                content = opOutputFile.read()
                if content:
                    opOutput = json.loads(content)

                # 根据output的定义填入工具没有输出的output属性
                for outOptName, outOpt in op.outputDesc.items():
                    if outOptName not in opOutput:
                        opOutput[outOptName] = outOpt.get('defaultValue')

                self.output[op.opId] = opOutput

                if self.resourceId != 0 and self.totalNodesCount == 1:
                    phaseStatus = self.context.phases[self.phaseName]
                    opLocalOutput = phaseStatus.localOutput.get(op.opId, {})
                    opLocalOutput.update(opOutput)
                    phaseStatus.localOutput[op.opId] = opLocalOutput
            except Exception as ex:
                raise AutoExecError('Load operation {} output file:{}, failed {}'.format(op.opId, opOutPutPath, ex))
            finally:
                if opOutputFile:
                    opOutputFile.close()

    def _saveOpOutput(self, op):
        # 修改操作的输出后保存到对应的文件
        opOutput = self.output[op.opId]
        if opOutput:
            opOutputFile = None
            opOutPutPath = self._getOpOutputPath(op)
            try:
                opOutputFile = open(opOutPutPath, 'w')
                fcntl.flock(opOutputFile, fcntl.LOCK_EX)
                opOutputFile.write(json.dumps(opOutput, indent=4, ensure_ascii=False))
                if self.resourceId != 0 and self.totalNodesCount == 1:
                    phaseStatus = self.context.phases[self.phaseName]
                    opLocalOutput = phaseStatus.localOutput.get(op.opId, {})
                    opLocalOutput.update(opOutput)
                    phaseStatus.localOutput[op.opId] = opLocalOutput
            except Exception as ex:
                raise AutoExecError('Save operation {} output file:{}, failed {}'.format(op.opId, opOutPutPath, ex))
            finally:
                if opOutputFile:
                    fcntl.flock(opOutputFile, fcntl.LOCK_UN)
                    opOutputFile.close()

    def _saveOpInput(self, op):
        opDesc = op.param.get('desc', {})
        saveOpts = {}
        for optName, optValue in op.options.items():
            optType = opDesc.get(optName)
            if optType in ('password', 'account'):
                saveOpts[optName] = '******'
            elif optType == 'textarea':
                optValue = optValue.replace('\\n', '\n')
                saveOpts[optName] = optValue
            else:
                saveOpts[optName] = optValue
        saveArgs = []
        for arg in op.arguments:
            argType = arg.get('type')
            if argType in ('password', 'account'):
                saveArgs.append('******')
            elif argType == 'textarea':
                argVal = arg.get('value')
                argVal = argVal.replace('\\n', '\n')
                saveArgs.append(argVal)
            else:
                saveArgs.append(arg.get('value'))

        inputFile = None
        try:
            inputFile = open(self.inputPath, 'w')
            fcntl.flock(inputFile, fcntl.LOCK_EX)
            self.input[op.opId] = {'options': saveOpts, 'arguments': saveArgs}
            inputFile.write(json.dumps(self.input, indent=4, ensure_ascii=False))
        except Exception as ex:
            raise AutoExecError('Save input file:{}, failed {}'.format(self.inputPath, ex))
        finally:
            if inputFile is not None:
                fcntl.flock(inputFile, fcntl.LOCK_UN)
                inputFile.close()

    def _getOpFileOutMap(self, op):
        fileOutMap = {}
        opOutput = self.output.get(op.opId)
        if opOutput is not None:
            for fileOpt in op.outputFiles:
                filePath = opOutput[fileOpt]
                if filePath is not None:
                    fileOutMap[fileOpt] = filePath
            return fileOutMap

    def _removeOpOutput(self, op):
        opOutPutPath = self._getOpOutputPath(op)
        if os.path.exists(opOutPutPath):
            os.remove(opOutPutPath)
        self.output.pop(op.opId, None)

    def getNodeLogHandle(self):
        return self.logHandle

    def execOneOperation(self, op):
        ret = 0
        timeConsume = None
        startTime = time.time()
        try:
            self.writeNodeLog("------START--[{}] {} execution start...\n".format(op.opId, op.opType))
            if op.opMemo is not None:
                self.writeNodeLog("------{}---\n".format(op.opMemo))

            # 如果当前节点某个操作已经成功执行过则略过这个操作，除非设置了isForce
            opStatus = self.getNodeStatus(op)
            op.parseParam(refMap=self.output, localRefMap=self.localOutput, resourceId=self.resourceId, host=self.host, port=self.port, nodeEnv=self.nodeEnv)

            startTime = time.time()
            if not self.context.isForce and opStatus == NodeStatus.succeed and self.phaseType != 'sqlfile':
                self._loadOpOutput(op)
                self.writeNodeLog("INFO: Operation {} has been executed in status:{}, skip.\n".format(op.opId, opStatus))
                timeConsume = time.time() - startTime
                self.writeNodeLog("------END--[{}] {} execution complete -- duration: {:.2f} second.\n\n".format(op.opId, op.opType, timeConsume))
                return

            self._saveOpInput(op)

            if op.opBunddleName != 'native' and not os.path.exists(op.pluginPath):
                ret = 1
                self.writeNodeLog("ERROR: Plugin not exists {}\n".format(op.pluginPath))

            if ret == 0:
                if op.opBunddleName == 'native':
                    try:
                        if op.opSubName == 'echo':
                            msgLine = ''
                            for arg in op.arguments:
                                msg = arg.get('value', '')
                                msgLine = msgLine + msg
                            self.writeNodeLog(msgLine + "\n")
                        elif op.opSubName == 'export':
                            for arg in op.arguments:
                                envName = arg.get('value', '')
                                if envName != '' and os.getenv(envName) is not None:
                                    self.writeNodeLog('INFO: Execute -> native/{} {}\n'.format(op.opSubName, envName))
                                    self.context.exportEnv(envName)
                        elif op.opSubName == 'setenv':
                            envName = op.options['name']
                            envValue = op.options['value']
                            envScope = op.options['scope']
                            self.writeNodeLog('INFO: Execute -> native/{} {}={} scope:{}\n'.format(op.opSubName, envName, envValue, envScope))
                            matchObjs = re.search(r'\$\(([^\)]+)\)', envValue)
                            if matchObjs is not None:
                                if re.search(r'\brm\b', envValue) or re.search(r'\bcp\b', envValue) or re.search(r'>', envValue):
                                    print("WARN: Shell eval string contains critical command rm|cp or redirect symbol, not permitted, evaluate aborted.\n")
                                else:
                                    result = subprocess.run('echo ' + envValue, shell=True, stdout=subprocess.PIPE)
                                    envValue = result.stdout.decode().strip()
                            if envScope == 'global':
                                self.context.setEnv(envName, envValue)
                                self.context.exportEnv(envName)
                            else:
                                op.hasNodeEnv = True
                                self.nodeEnv[envName] = envValue
                                persistenceEnv = self.output['nodeEnv']
                                persistenceEnv[envName] = envValue
                        elif op.opSubName == 'failkeys':
                            self.writeNodeLog('INFO: Execute -> native/{} --operator "{}" --exclude "{}" {}\n'.format(op.opSubName, op.options.get('operator'), op.options.get('exclude'), ' '.join(e.get('value') for e in op.arguments)))
                            self.logHandle.setFailPattern(op.failIgnore, op.options.get('operator'), op.arguments, op.options.get('exclude'))
                        elif op.opSubName == 'extractprestepstatus':
                            envName = op.options.get('envname')
                            envScope = op.options.get('scope')
                            self.writeNodeLog('INFO: Excute -> native/{} --scope {} --envname "{}"\n'.format(op.opSubName, envScope, envName))
                            if op.preOp is not None and op.preOp.status is not None:
                                if envScope == 'global':
                                    self.context.setEnv(envName, op.preOp.status)
                                    self.context.exportEnv(envName)
                                else:
                                    op.hasNodeEnv = True
                                    self.nodeEnv[envName] = op.preOp.status
                                    persistenceEnv = self.output['nodeEnv']
                                    persistenceEnv[envName] = op.preOp.status
                        else:
                            # 其他需要在local执行的native操作，native工具需要支持执行在local和local-remote模式下
                            # native工具一般用于处理数据，不需要连接remote进行操作
                            if self.host == 'local':
                                ret = self._localExecute(op)
                            elif op.opType == 'localremote':
                                ret = self._localRemoteExecute(op)
                    except Exception as ex:
                        ret = 1
                        self.writeNodeLog('ERROR: Execute native plugin native/{} failed, {}\n'.format(op.opSubName, str(ex)))
                elif self.host == 'local':
                    if op.opType == 'local':
                        # 本地执行
                        # 输出保存到环境变量 $OUTPUT_PATH指向的文件里
                        ret = self._localExecute(op)
                    else:
                        return
                else:
                    if op.opType == 'localremote':
                        if self.password == '':
                            self.writeNodeLog("WARN: Can not find password for {}@{}:{}, Please check if the node is exists in resource center or check if password is configed for the user account.\n".format(self.username, self.host, self.protocolPort))
                        # 本地执行，逐个node循环本地调用插件，通过-node参数把node的json传送给插件，插件自行处理node相关的信息和操作
                        # 输出保存到环境变量 $OUTPUT_PATH指向的文件里
                        ret = self._localRemoteExecute(op)
                    elif op.opType == 'remote':
                        if self.password == '':
                            ret = 1
                            self.writeNodeLog("ERROR: Can not find password for {}@{}:{}, Please check if the node is exists in resource center or check if password is configed for the user account.\n".format(self.username, self.host, self.protocolPort))
                        else:
                            # 远程执行，则推送插件到远端并执行插件运行命令，输出保存到执行目录的output.json中
                            ret = self._remoteExecute(op)
                    else:
                        ret = 1
                        self.writeNodeLog("WARN: Operation type:{} not supported, only support(local|remote|local-remote), ignore.\n".format(op.opType))

            timeConsume = time.time() - startTime
            if ret != 0:
                self._removeOpOutput(op)
                self.updateNodeStatus(NodeStatus.failed, op=op, consumeTime=timeConsume)
            else:
                if op.hasOutput or op.hasNodeEnv:
                    if op.opType not in ('remote', 'native'):
                        self._loadOpOutput(op)
                    self._saveOutput()
                self.updateNodeStatus(NodeStatus.succeed, op=op, consumeTime=timeConsume)
        except:
            ret = 3
            timeConsume = time.time() - startTime
            self.writeNodeLog("ERROR: Error ocurred.\n{}\n".format(traceback.format_exc()))

        hintKey = 'FINE:'
        opFinalStatus = NodeStatus.succeed
        if ret != 0 or self.hasFailLog:
            if op.failIgnore:
                opFinalStatus = NodeStatus.ignored
                hintKey = 'WARN:'
            else:
                opFinalStatus = NodeStatus.failed
                hintKey = 'ERROR:'

        op.status = opFinalStatus

        self.writeNodeLog("{} Execute operation {} {} {}.\n".format(hintKey, op.opName, op.opTypeDesc.get(op.opType, ''), opFinalStatus))
        self.writeNodeLog("------END--[{}] {} execution complete -- duration: {:.2f} second.\n\n".format(op.opId, op.opType, timeConsume))

        return opFinalStatus

    def getIfBlockOps(self, ifOp):
        result = True
        opParams = ifOp.param
        condition = opParams['condition']
        ast = ConditionDSL.Parser(condition)
        if isinstance(ast, ConditionDSL.Operation):
            interpreter = ConditionDSL.Interpreter()
            result = interpreter.resolve(self.nodeEnv, AST=ast.asList())
        else:
            raise AutoExecError("Parse error, syntax error at char 0\n")

        activeOps = None
        if result:
            activeOps = opParams['if']
        else:
            activeOps = opParams['else']

        phaseStatus = self.context.phases[self.phaseName]
        opArgsRefMap = ifOp.opsParam
        retOps = []
        for operation in activeOps:
            if 'opt' in operation:
                opArgsRefMap[operation['opId']] = operation['opt']
            else:
                opArgsRefMap[operation['opId']] = {}

            op = Operation.Operation(self.context, opArgsRefMap, operation)

            # 如果有本地操作，则在context中进行标记
            if op.opType == 'local':
                phaseStatus.hasLocal = True
            else:
                phaseStatus.hasRemote = True

            retOps.append(op)

        return retOps

    def execute(self, ops):
        if self.context.goToStop:
            return 2

        # 初始化日志
        if self.logHandle is None:
            # 如果文件存在，则删除重建
            if os.path.exists(self.logPath):
                os.unlink(self.logPath)
            self.logHandle = LogFile(open(self.logPath, 'wb').detach(), self)

        finalStatus = None
        hasIgnoreFail = 0
        isFail = 0

        try:
            nodeBeginDateTimeFN = time.strftime('%Y%m%d-%H%M%S')
            nodeStartTime = time.time()

            # 第一次写入日志才会触发日志初始化，日志初始化后才能进行历史日志的生成
            self.writeNodeLog("======[{}]{}:{} Launched by {}://{}@{}:{}======\n".format(self.id, self.host, self.port, self.type, self.username, self.host, self.protocolPort))

            # 创建历史日志，文件名中的状态标记置为running，在一开始创建，是为了避免中间kill掉后导致历史日志丢失
            logPathWithTime = '{}/{}.{}.{}.txt'.format(self.hisLogDir, nodeBeginDateTimeFN, NodeStatus.running, self.context.execUser)
            if not os.path.exists(logPathWithTime):
                os.link(self.logPath, logPathWithTime)
            self.logPathWithTime = logPathWithTime

            self.updateNodeStatus(NodeStatus.running)

            self.logHandle.clearFailPattern()

            for op in ops:
                if self.context.goToStop:
                    self.updateNodeStatus(NodeStatus.paused)
                    self.writeNodeLog("INFO: Node running paused.\n")
                    break

                # evaluate if-block
                if op.opName == 'native/IF-Block':
                    ifOps = self.getIfBlockOps(op)
                    for ifOp in ifOps:
                        ifOp.setNode(self)
                        opStatus = self.execOneOperation(ifOp)
                        if opStatus == NodeStatus.failed:
                            isFail = 1
                            hasIgnoreFail = 0
                            break
                        elif opStatus == NodeStatus.ignored:
                            hasIgnoreFail = 1
                else:
                    op.setNode(self)
                    # execute on operation
                    opStatus = self.execOneOperation(op)

                    if opStatus == NodeStatus.failed:
                        isFail = 1
                        hasIgnoreFail = 0
                        break
                    elif opStatus == NodeStatus.ignored:
                        hasIgnoreFail = 1

            # nodeEndDateTime = time.strftime('%Y-%m-%d %H:%M:%S')
            nodeConsumeTime = time.time() - nodeStartTime

            hintKey = 'FINE:'
            if isFail == 0:
                if hasIgnoreFail == 1:
                    # 虽然全部操作执行完，但是中间存在fail但是ignore的operation，则设置节点状态为已忽略，主动忽略节点
                    self.hasIgnoreFail = 1
                    finalStatus = NodeStatus.ignored
                    hintKey = 'WARN:'
                else:
                    finalStatus = NodeStatus.succeed
                    hintKey = 'FINE:'
            else:
                if self.isKilled:
                    finalStatus = NodeStatus.aborted
                    hintKey = 'ERROR:'
                else:
                    finalStatus = NodeStatus.failed
                    hintKey = 'ERROR:'

            self.updateNodeStatus(finalStatus, failIgnore=hasIgnoreFail, consumeTime=nodeConsumeTime)
            self.writeNodeLog("{} Node execute complete, status:{}.\n".format(hintKey, finalStatus))
            self.writeNodeLog("======[{}]{}:{} executed by {}://{}@{}:{} ended, duration:{:.2f} second ======\n".format(self.id, self.host, self.port, self.type, self.username, self.host, self.protocolPort, nodeConsumeTime))

            # 创建带时间戳的日志文件名
            finalLogPathWithTime = logPathWithTime
            finalLogPathWithTime = finalLogPathWithTime.replace('.{}.'.format(NodeStatus.running), '.{}.'.format(finalStatus))
            if finalLogPathWithTime != logPathWithTime:
                # if self.logHandle is not None:
                #     self.logHandle.close()
                #     self.logHandle = None
                os.rename(self.logPathWithTime, finalLogPathWithTime)

        except Exception as ex:
            if finalStatus is None:
                finalStatus = NodeStatus.failed

            try:
                self.writeNodeLog("ERROR: Unknow error occurred.\n")
                self.writeNodeLog(str(ex))
                self.writeNodeLog(traceback.format_exc())
                self.writeNodeLog("\n")
            except Exception as ex:
                print("ERROR: Can not write node log.\n{}\n{}\n".format(str(ex), traceback.format_exc()), end='')
        finally:
            phaseStatus = self.context.phases[self.phaseName]
            phaseStatus.incWarnCount(self.warnCount)
        self.killCmd = None
        self.childPid = None

        return finalStatus

    def _localExecute(self, op):
        self.childPid = None
        self.killCmd = None
        # os.chdir(self.runPath)
        ret = -1
        # 本地执行，则使用管道启动运行插件
        orgCmdLine = op.getCmdLine(fullPath=True, osType='Linux')
        orgCmdLineHidePassword = op.getCmdLineHidePassword(fullPath=False, osType='Linux')

        cmdline = 'exec {}'.format(orgCmdLine)
        environment = os.environ.copy()
        environment['TERM'] = 'dumb'
        environment['GROUP_NO'] = str(self.groupNo)
        environment['OUTPUT_DIR'] = self.opOutputDir
        environment['OUTPUT_PATH'] = self._getOpOutputPath(op)
        environment['LIVEDATA_PATH'] = self._getOpLiveDataPath(op)
        environment['NODE_OUTPUT_PATH'] = self.outputPath
        environment['PATH'] = '{}/lib:{}:{}'.format(op.pluginParentPath, op.localLibPath, os.getenv('PATH'))
        environment['PYTHONPATH'] = '{}:{}/lib:{}:{}'.format(op.pluginParentPath, op.pluginParentPath, op.localLibPath, os.getenv('PYTHONPATH'))
        environment['PERL5LIB'] = '{}:{}/lib:{}:{}'.format(op.pluginParentPath, op.pluginParentPath, op.localLibPath, os.getenv('PERL5LIB'))
        environment['AUTOEXEC_PHASE_NAME'] = self.phaseName
        environment['AUTOEXEC_NODE'] = json.dumps(self.node, ensure_ascii=False)
        environment['AUTOEXEC_NODES_PATH'] = self.context.phases[self.phaseName].nodesFilePath

        scriptFile = None
        if op.isScript == 1:
            scriptFile = open(op.pluginPath, 'r')
            fcntl.flock(scriptFile, fcntl.LOCK_SH)

        self.writeNodeLog("INFO: Execute -> {}\n".format(orgCmdLineHidePassword))
        child = subprocess.Popen(cmdline, env=environment, cwd=self.runPath, shell=True, close_fds=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
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
        ret = child.wait()

        lastContent = child.stdout.read()
        if lastContent is not None:
            self.writeNodeLog(lastContent)

        return ret

    def _localRemoteExecute(self, op):
        self.childPid = None
        self.killCmd = None
        # os.chdir(self.runPath)
        ret = -1
        # 本地执行，则使用管道启动运行插件
        orgCmdLine = op.getCmdLine(fullPath=True, osType='Linux')
        orgCmdLineHidePassword = op.getCmdLineHidePassword(fullPath=False, osType='Linux')

        # cmdline = 'exec {} --node \'{}\''.format(orgCmdLine, json.dumps(self.node, ensure_ascii=False))
        cmdline = 'exec {}'.format(orgCmdLine)
        environment = os.environ.copy()
        environment['TERM'] = 'dumb'
        environment['GROUP_NO'] = str(self.groupNo)
        environment['OUTPUT_DIR'] = self.opOutputDir
        environment['OUTPUT_PATH'] = self._getOpOutputPath(op)
        environment['LIVEDATA_PATH'] = self._getOpLiveDataPath(op)
        environment['NODE_OUTPUT_PATH'] = self.outputPath
        environment['PATH'] = '{}/lib:{}:{}'.format(op.pluginParentPath, op.localLibPath, os.getenv('PATH'))
        environment['PYTHONPATH'] = '{}:{}/lib:{}:{}'.format(op.pluginParentPath, op.pluginParentPath, op.localLibPath, os.getenv('PYTHONPATH'))
        environment['PERL5LIB'] = '{}:{}/lib:{}:{}'.format(op.pluginParentPath, op.pluginParentPath, op.localLibPath, os.getenv('PERL5LIB'))
        environment['AUTOEXEC_PHASE_NAME'] = self.phaseName
        environment['NODE_HOST'] = self.host
        environment['NODE_PORT'] = str(self.port)
        environment['NODE_NAME'] = self.name
        environment['AUTOEXEC_NODE'] = json.dumps(self.node, ensure_ascii=False)
        environment['AUTOEXEC_NODES_PATH'] = self.context.phases[self.phaseName].nodesFilePath

        scriptFile = None
        if op.isScript == 1:
            scriptFile = open(op.pluginPath, 'r')
            fcntl.flock(scriptFile, fcntl.LOCK_SH)

        self.writeNodeLog("INFO: Execute -> {}\n".format(orgCmdLineHidePassword))
        child = subprocess.Popen(cmdline, env=environment, cwd=self.runPath, shell=True, close_fds=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
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
        ret = child.wait()

        lastContent = child.stdout.read()
        if lastContent is not None:
            self.writeNodeLog(lastContent)

        return ret

    def _remoteExecute(self, op):
        self.childPid = None

        remoteCmd = None
        remoteCmdHidePass = None
        jobDir = 'autoexec-{}-{}-{}'.format(self.context.jobId, self.resourceId, self.phaseIndex)
        self.writeNodeLog("INFO: Job directory:{}\n".format(jobDir))

        ret = -1
        if self.type == 'tagent':
            scriptFile = None
            try:
                remoteRoot = '$TMPDIR/' + jobDir
                remotePath = remoteRoot + '/' + op.opBunddleName
                if op.opBunddleName == '':
                    remotePath = remoteRoot

                runEnv = {
                    'AUTOEXEC_JOBID': self.context.jobId,
                    'AUTOEXEC_NODE': json.dumps(self.nodeWithoutPassword, ensure_ascii=False),
                    'HISTSIZE': '0',
                    'NODE_HOST': self.host,
                    'NODE_PORT': str(self.port),
                    'NODE_NAME': self.name
                }
                insPath = os.getenv('INS_PATH')
                insIdPath = os.getenv('INS_ID_PATH')
                if insPath:
                    runEnv['INS_PATH'] = insPath
                    runEnv['INS_ID_PATH'] = insIdPath

                self.killCmd = "kill -9 `ps auxe |grep AUTOEXEC_JOBID=" + self.context.jobId + "|grep -v grep|awk '{print $2}'`"

                context = self.context
                tagent = TagentClient.TagentClient(self.host, self.protocolPort, self.password,  connectTimeout=context.rexecConnTimeout, readTimeout=60, writeTimeout=context.rexecWriteTimeout, execTimeout=context.maxExecSecs)
                self.tagent = tagent

                # 更新节点状态为running
                self.updateNodeStatus(NodeStatus.running, op=op)

                self.writeNodeLog("INFO: Begin to upload remote operation...\n")
                uploadRet = 0
                if op.isScript == 1:
                    scriptFile = open(op.pluginPath, 'r')
                    try:
                        uploadRet = tagent.upload(self.username, op.remoteLibPath, remoteRoot, dirCreate=True)
                        if uploadRet == 0:
                            fcntl.flock(scriptFile, fcntl.LOCK_SH)
                            uploadRet = tagent.upload(self.username, op.pluginPath, remotePath + '/' + op.scriptFileName, convertCharset=1)
                            fcntl.flock(scriptFile, fcntl.LOCK_UN)
                    finally:
                        scriptFile.close()
                        scriptFile = None
                else:
                    for srcPath in [op.remoteLibPath, op.pluginParentPath]:
                        uploadRet = tagent.upload(self.username, srcPath, remoteRoot, dirCreate=True)
                        if uploadRet != 0:
                            break
                    if uploadRet == 0 and tagent.agentCharset not in ['UTF-8', 'cp65001']:
                        # 如果脚本使用编码与服务端不一致，则执行转换
                        uploadRet = tagent.upload(self.username, op.pluginPath, remotePath + '/', convertCharset=1)

                if uploadRet == 0 and op.hasFileOpt:
                    uploadRet = tagent.upload(self.username, self.context.runPath + '/file', remotePath + '/')
                if uploadRet == 0 and op.hasFilePathOpt:
                    uploadRet = tagent.upload(self.username, self.context.runPath + '/file', remotePath + '/')
                    for filePath in op.filePaths:
                        uploadRet = tagent.upload(self.username, self.context.runPath + '/' + filePath, remotePath + '/file/')
                if uploadRet == 0 and op.hasOutput:
                    uploadRet = tagent.writeFile(self.username, b'', remotePath + '/output.json')

                if tagent.agentOsType == 'windows':
                    killCmd = '''
                        function KillProcTree {
                            Param([int]$ppid);
                            Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $ppid } | ForEach-Object { Kill-Tree $_.ProcessId };
                            Stop-Process -Id $ppid;
                        };

                        Function killProcessByEnv($env){
                            foreach($process in Get-Process){
                                $processId = $process.id;
                                $wmiObj = Get-WmiObject Win32_Process -Filter "ProcessId=$processId";
                                $cmdLine = $wmiObj.CommandLine
                                if ($cmdLine -Match $env){
                                    KillProcTree $processId;
                                }
                                else{
                                    foreach($entry in $process.StartInfo.EnvironmentVariables){
                                        $name = $entry.Name;
                                        $val = $entry.Value;
                                        if ("$name=$val" -eq $env){
                                            KillProcTree $processId;
                                        }
                                    }
                                }
                            }
                        };
                    '''
                    killCmd = killCmd.replace('"', '\\"')
                    killCmd = re.sub(r'\\s+', ' ', killCmd)
                    self.killCmd = 'powershell -command "%s killProcessByEnv AUTOEXEC_JOBID=%s"' % (killCmd, self.context.jobId)

                remoteCmd = op.getCmdLine(fullPath=True, remotePath=remotePath, osType=tagent.agentOsType)
                remoteCmdHidePass = op.getCmdOptsHidePassword(osType=tagent.agentOsType)

                if uploadRet == 0:
                    self.writeNodeLog("INFO: Remote operation upload success.\n")

                if uploadRet == 0 and not self.context.goToStop:
                    tagent = TagentClient.TagentClient(self.host, self.protocolPort, self.password,  connectTimeout=context.rexecConnTimeout, readTimeout=context.rexecReadTimeout, writeTimeout=context.rexecWriteTimeout, execTimeout=context.maxExecSecs)
                    self.writeNodeLog("INFO: Execute -> {}\n".format(remoteCmdHidePass))
                    ret = tagent.execCmd(self.username, remoteCmd, env=runEnv, isVerbose=0, callback=self.writeNodeLog)
                    if ret == 0 and op.hasOutput:
                        self._ensureOpOutputDir(op)
                        outputFilePath = self._getOpOutputPath(op)
                        outputStatus = tagent.download(self.username, '{}/output.json'.format(remotePath), outputFilePath, convertCharset=1)
                        if outputStatus != 0:
                            self.writeNodeLog("ERROR: Download output failed.\n")
                            ret = 2
                        else:
                            # 如果成功，而且工具有文件输出的output配置
                            # 则下载output文件到操作的文件输出目录，
                            # 并更新文件output对应的key的目录为相对于作业目录下的目录
                            self._loadOpOutput(op)

                            outFileMap = self._getOpFileOutMap(op)
                            opFileOutRelDir = None
                            if outFileMap:
                                opFileOutRelDir = self._ensureOpFileOutputDir(op)

                            for outFileKey, outFilePath in outFileMap.items():
                                outFileName = os.path.basename(outFilePath)
                                savePath = '{}/{}/{}'.format(self.runPath, opFileOutRelDir, outFileName)
                                outputStatus = tagent.download(self.username, '{}/{}'.format(remotePath, outFilePath), savePath)

                                opOutput = self.output.get(op.opId)
                                if opOutput is None:
                                    break

                                opOutput[outFileKey] = opFileOutRelDir + '/' + outFileName

                                if outputStatus != 0:
                                    opOutput[outFileKey] = None
                                    self.writeNodeLog("ERROR: Download output file:{} failed.\n".format(outFilePath))
                                    ret = 2

                            self._saveOpOutput(op)
                    try:
                        if ret == 0 or self.context.fialRserveDir == 0:
                            if tagent.agentOsType == 'windows':
                                tagent.execCmd(self.username, 'rd /s /q "{}"'.format(remoteRoot))
                            else:
                                tagent.execCmd(self.username, "rm -rf {}".format(remoteRoot))
                    except Exception as ex:
                        self.writeNodeLog('WARN: Remote remove directory {} failed {}\n'.format(remoteRoot, ex))
            except Exception as ex:
                self.writeNodeLog("ERROR: Execute operation {} failed, {}\n".format(op.opName, ex))
            finally:
                if scriptFile is not None:
                    fcntl.flock(scriptFile, fcntl.LOCK_UN)
                    scriptFile.close()

        elif self.type == 'ssh':
            logging.getLogger("paramiko").setLevel(logging.FATAL)
            remoteRoot = '/tmp/' + jobDir
            remotePath = '{}/{}'.format(remoteRoot, op.opBunddleName)
            if op.opBunddleName == '':
                remotePath = remoteRoot

            remoteEnv = ''
            insPath = os.getenv('INS_PATH')
            insIdPath = os.getenv('INS_ID_PATH')
            if insPath:
                remoteEnv = '&& HISTSIZE=0 NODE_HOST="{}" NODE_PORT={} NODE_NAME="{}" AUTOEXEC_JOBID={} INS_PATH=\'{}\' INS_ID_PATH={} AUTOEXEC_NODE=\'{}\' '.format(
                    self.host, str(self.port), self.name, self.context.jobId, insPath, insIdPath, json.dumps(self.nodeWithoutPassword, ensure_ascii=False))
            else:
                remoteEnv = '&& HISTSIZE=0 NODE_HOST="{}" NODE_PORT={} NODE_NAME="{}" AUTOEXEC_JOBID={} AUTOEXEC_NODE=\'{}\' '.format(
                    self.host, str(self.port), self.name, self.context.jobId, json.dumps(self.nodeWithoutPassword, ensure_ascii=False))
            remoteCmd = op.getCmdLine(fullPath=True, remotePath=remotePath, osType='Unix').replace('&&', remoteEnv)
            remoteCmdHidePass = op.getCmdOptsHidePassword(osType='Unix')
            self.killCmd = "kill -9 `ps auxe |grep AUTOEXEC_JOBID=" + self.context.jobId + "|grep -v grep|awk '{print $2}'`"
            scriptFile = None
            uploaded = False
            hasError = False
            ssh = None
            sftp = None
            try:
                self.writeNodeLog("INFO: Begin to upload remote operation...\n")
                # 建立连接
                ssh = paramiko.SSHClient()
                ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                ssh.connect(self.host, self.protocolPort, self.username, self.password, timeout=self.context.rexecConnTimeout, banner_timeout=self.context.rexecConnTimeout, auth_timeout=self.context.rexecConnTimeout)
                sftp = ssh.open_sftp()

                # 更新节点状态为running
                self.updateNodeStatus(NodeStatus.running, op=op)

                # 建立一个sftp客户端对象，通过ssh transport操作远程文件
                # Copy a local file (localpath) to the SFTP server as remotepath
                try:
                    try:
                        sftp.stat(remoteRoot)
                    except IOError:
                        sftp.mkdir(remoteRoot)
                except SFTPError as err:
                    hasError = True
                    self.writeNodeLog("ERROR: Mkdir {} failed: {}\n".format(remoteRoot, err))

                absRoot = op.remotePluginRootPath
                dirStartPos = len(absRoot) + 1
                for root, dirs, files in os.walk(op.remotePluginRootPath + '/lib', topdown=True, followlinks=True):
                    root = root[dirStartPos:]
                    try:
                        # 创建当前目录
                        sftp.mkdir(os.path.join(remoteRoot, root))
                    except:
                        pass
                    for direntry in dirs:
                        try:
                            sftp.mkdir(os.path.join(remoteRoot, root, direntry))
                        except:
                            pass
                    for name in files:
                        # 遍历文件并scp到目标上
                        filePath = os.path.join(root, name)
                        absFilePath = os.path.join(absRoot, filePath)
                        try:
                            sftp.put(absFilePath, os.path.join(remoteRoot, filePath))
                        except Exception as err:
                            hasError = True
                            self.writeNodeLog("ERROR: SFTP put file {} failed:{}\n".format(filePath, err))

                if op.isScript == 1:
                    try:
                        sftp.stat(remotePath)
                    except IOError:
                        sftp.mkdir(remotePath)
                    except SFTPError as err:
                        hasError = True
                        self.writeNodeLog("ERROR: Mkdir {} failed: {}\n".format(remotePath, err))

                    scriptFile = open(op.pluginPath, 'r')
                    fcntl.flock(scriptFile, fcntl.LOCK_SH)
                    sftp.put(op.pluginPath, os.path.join(remotePath, op.scriptFileName))
                    fcntl.flock(scriptFile, fcntl.LOCK_UN)
                    scriptFile.close()
                    scriptFile = None
                    sftp.chmod(os.path.join(remotePath, op.scriptFileName), stat.S_IRWXU)

                    # remoteCmd = op.getCmdLine(fullPath=True, remotePath=remotePath).replace('&&', remoteEnv)
                    # remoteCmdHidePass = op.getCmdOptsHidePassword().replace('&&', remoteEnv)
                else:
                    # 切换到插件根目录，便于遍历时的文件目录时，文件名为此目录相对路径
                    # 为了从顶向下创建目录，遍历方式为从顶向下的遍历，并follow link
                    for root, dirs, files in os.walk(op.remotePluginRootPath + '/' + op.opBunddleName, topdown=True, followlinks=True):
                        root = root[dirStartPos:]
                        try:
                            # 创建当前目录
                            sftp.mkdir(os.path.join(remoteRoot, root))
                        except:
                            pass
                        for direntry in dirs:
                            try:
                                sftp.mkdir(os.path.join(remoteRoot, root, direntry))
                            except:
                                pass
                        for name in files:
                            # 遍历文件并scp到目标上
                            filePath = os.path.join(root, name)
                            absFilePath = os.path.join(absRoot, filePath)
                            try:
                                sftp.put(absFilePath, os.path.join(remoteRoot, filePath))
                            except Exception as err:
                                hasError = True
                                self.writeNodeLog("ERROR: SFTP put file {} failed:{}\n".format(filePath, err))

                    sftp.chmod('{}/{}'.format(remotePath, op.opSubName), stat.S_IRWXU)

                if hasError == 0 and op.hasFileOpt:
                    try:
                        sftp.stat(os.path.join(remotePath, 'file'))
                    except Exception as err:
                        sftp.mkdir(os.path.join(remotePath, 'file'))
                    try:
                        for file in os.listdir(os.path.join(self.context.runPath, 'file')):
                            localFilePath = os.path.join(self.context.runPath, 'file', file)
                            if os.path.isfile(localFilePath):
                                sftp.put(localFilePath, os.path.join(remotePath, 'file', file))
                    except Exception as err:
                        hasError = True
                        self.writeNodeLog("ERROR: SFTP upload file params failed:{}\n".format(err))
                if hasError == 0 and op.hasFilePathOpt:
                    try:
                        sftp.stat(os.path.join(remotePath, 'file'))
                    except Exception as err:
                        sftp.mkdir(os.path.join(remotePath, 'file'))
                    try:
                        for file in op.filePaths:
                            localFilePath = os.path.join(self.context.runPath, file)
                            if os.path.isfile(localFilePath):
                                sftp.put(localFilePath, os.path.join(remotePath, 'file', file))
                    except Exception as err:
                        hasError = True
                        self.writeNodeLog("ERROR: SFTP upload file params failed:{}\n".format(err))

                if op.hasOutput:
                    ofh = sftp.file(os.path.join(remotePath, 'output.json'), 'w')
                    ofh.close()

                if hasError == False:
                    uploaded = True
                    self.writeNodeLog('INFO: Remote operation upload success.\n')

            except Exception as err:
                self.writeNodeLog('ERROR: Upload plugin:{} to remoteRoot:{} failed: {}\n'.format(op.opName, remoteRoot, err))
                if sftp is not None:
                    sftp.close()
            finally:
                if scriptFile is not None:
                    fcntl.flock(scriptFile, fcntl.LOCK_UN)
                    scriptFile.close()

            if uploaded and not self.context.goToStop:
                self.writeNodeLog("INFO: Execute -> {}\n".format(remoteCmdHidePass))
                try:
                    # ret = 0
                    channel = ssh.get_transport().open_session()
                    channel.set_combine_stderr(True)
                    channel.exec_command(remoteCmd)
                    while True:
                        r, w, x = select.select([channel], [], [], 10)
                        # if len(r) > 0:
                        while channel.recv_ready():
                            remoteOut = channel.recv(4096)
                            self.writeNodeLog(remoteOut)
                        if channel.exit_status_ready():
                            ret = channel.recv_exit_status()
                            break

                    if ret == 0 and op.hasOutput:
                        outFileKey = None
                        outFilePath = None

                        try:
                            self._ensureOpOutputDir(op)
                            outputFilePath = self._getOpOutputPath(op)
                            sftp.get('{}/output.json'.format(remotePath), outputFilePath)
                            # 如果成功，而且工具有文件输出的output配置
                            # 则下载output文件到操作的文件输出目录，
                            # 并更新文件output对应的key的目录为相对于作业目录下的目录
                            self._loadOpOutput(op)

                            outFileMap = self._getOpFileOutMap(op)
                            opFileOutRelDir = None
                            if outFileMap:
                                opFileOutRelDir = self._ensureOpFileOutputDir(op)

                            for outFileKey, outFilePath in outFileMap.items():
                                opOutput = self.output.get(op.opId)
                                if opOutput is None:
                                    break

                                try:
                                    outFileName = os.path.basename(outFilePath)
                                    savePath = '{}/{}/{}'.format(self.runPath, opFileOutRelDir, outFileName)
                                    sftp.get('{}/{}'.format(remotePath, outFilePath), savePath)

                                    opOutput[outFileKey] = opFileOutRelDir + '/' + outFileName
                                except Exception as ex:
                                    opOutput[outFileKey] = None
                                    self.writeNodeLog("ERROR: Download output file:{} failed {}\n".format(outFilePath, ex))
                                    ret = 2
                            self._saveOpOutput(op)
                        except Exception as ex:
                            self.writeNodeLog("ERROR: Download output failed {}\n".format(ex))
                            ret = 2
                    try:
                        if ret == 0 or self.context.fialRserveDir == 0:
                            ssh.exec_command("rm -rf {}".format(remoteRoot, remoteRoot))
                    except Exception as ex:
                        self.writeNodeLog("WARN: Remove remote directory {} failed {}\n".format(remoteRoot, ex))

                except Exception as err:
                    self.writeNodeLog("ERROR: Execute remote operation {} failed, {}\n".format(op.opName, err))
                finally:
                    if sftp is not None:
                        sftp.close()
                    if ssh is not None:
                        ssh.close()

            if ssh is not None:
                ssh.close()

        return ret

    def pause(self):
        self.writeNodeLog("INFO: Try to puase node.\n")

    def kill(self):
        self.isAborting = True
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
                tagent = TagentClient.TagentClient(self.host, self.port, self.password, connectTimeout=60, readTimeout=360, writeTimeout=60)
                if tagent.execCmd(self.username, killCmd, isVerbose=0, callback=self.writeNodeLog) == 0:
                    self.writeNodeLog("INFO: Execute kill command:{} success.\n".format(killCmd))
                    self.updateNodeStatus(NodeStatus.aborted)
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
                ssh.connect(self.host, self.protocolPort, self.username, self.password, timeout=self.context.rexecConnTimeout, banner_timeout=self.context.rexecConnTimeout, auth_timeout=self.context.rexecConnTimeout)
                channel = ssh.get_transport().open_session()
                channel.set_combine_stderr(True)
                channel.exec_command(killCmd)

                while True:
                    if channel.exit_status_ready():
                        ret = channel.recv_exit_status()
                        break

                    r, w, x = select.select([channel], [], [])
                    if len(r) > 0:
                        self.writeNodeLog(channel.recv(1024).decode(errors='ignore') + "\n")

                self.writeNodeLog("INFO: Execute kill command:{} success.\n".format(killCmd))
                self.updateNodeStatus(NodeStatus.aborted)
                self.isKilled = True
            except Exception as err:
                self.writeNodeLog("ERROR: Execute kill command:{} failed, {}\n".format(killCmd, err))
            finally:
                if ssh:
                    ssh.close()
        else:
            self.updateNodeStatus(NodeStatus.aborted)
