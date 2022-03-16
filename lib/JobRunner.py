#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import os
import time
import socket
import threading
import traceback
import json
import shutil

import RunNode
import RunNodeFactory
import PhaseNodeFactory
import Operation
import PhaseExecutor
import NodeStatus


class ListenThread (threading.Thread):  # 继承父类threading.Thread
    def __init__(self, name, context=None):
        threading.Thread.__init__(self, name=name, daemon=True)
        self.context = context
        self.goToStop = False
        self.socketPath = context.runPath + '/job.sock'

    def run(self):
        socketPath = self.socketPath
        if os.path.exists(socketPath):
            os.remove(socketPath)

        server = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        server.bind(socketPath)
        self.server = server

        while not self.goToStop:
            actionData = None
            try:
                datagram = server.recv(4096)
                if not datagram:
                    continue
                actionData = json.loads(datagram.decode('utf-8'))
            except Exception as ex:
                pass

            try:
                if actionData:
                    if actionData['action'] == 'informNodeWaitInput':
                        nodeId = actionData['nodeId']
                        for phaseStatus in self.context.phases.values():
                            if phaseStatus.executor is not None:
                                phaseStatus.executor.informNodeWaitInput(nodeId, interact=actionData['interact'])
                    elif actionData['action'] == 'exit':
                        self.server.shutdown()
                        break
            except Exception as ex:
                print('ERROR: Inform node status to waitInput failed, {}\n{}\n'.format(actionData, ex))

    def stop(self):
        self.goToStop = True
        try:
            self.server.close()
            if os.path.exists(self.socketPath):
                os.remove(self.socketPath)
        except:
            pass


class JobRunner:
    def __init__(self, context, nodesFile=None):
        self.context = context
        self.localDefinedNodes = False

        # 切换到任务的执行路径
        os.chdir(context.runPath)

        if 'runNode' in context.params:
            # 如果在参数文件中声明了runNode，则以此作为运行目标，用于工具测试的执行，所以不支持phase内部定义runNode
            self.localDefinedNodes = True
            dstPath = '{}/nodes.json'.format(self.context.runPath)
            nodesFile = open(dstPath, 'w')
            for node in context.params['runNode']:
                nodesFile.write(json.dumps(node))
            nodesFile.close()
        elif nodesFile is None or nodesFile == '':
            # 如果命令行没有指定nodesfile参数，则通过作业id到服务端下载节点参数文件
            dstPath = '{}/nodes.json'.format(self.context.runPath)
            if context.firstFire:
                context.serverAdapter.getNodes()
            elif not os.path.exists(dstPath):
                context.serverAdapter.getNodes()
        else:
            # 如果命令行参数指定了nodesfile参数，则以此文件做为运行目标节点列表
            self.localDefinedNodes = True
            # 如果指定的参数文件存在，而且目录不是params文件最终的存放目录，则拷贝到最终的存放目录
            if context.firstFire:
                dstPath = '{}/nodes.json'.format(self.context.runPath)
                if os.path.exists(nodesFile):
                    if dstPath != os.path.realpath(nodesFile):
                        shutil.copyfile(nodesFile, dstPath)
                else:
                    print("ERROR: Nodes file directory:{} not exists.\n".format(nodesFile))

    def execOperations(self, phaseName, phaseConfig, opArgsRefMap, nodesFactory, parallelCount):
        phaseStatus = self.context.phases[phaseName]
        self.context.initDB(parallelCount)
        self.context.loadEnv()

        operations = []
        # 遍历参数文件中定义的操作，逐个初始化，包括参数处理和准备，以及文件参数相关的文件下载

        for operation in phaseConfig['operations']:
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

            operations.append(op)

        executor = PhaseExecutor.PhaseExecutor(self.context, phaseName, operations, nodesFactory, parallelCount)
        phaseStatus.executor = executor
        return executor.execute()

    def execPhase(self, phaseName, phaseConfig, nodesFactory, parallelCount, opArgsRefMap):
        serverAdapter = self.context.serverAdapter
        phaseStatus = self.context.phases[phaseName]
        print("INFO: Begin to execute phase:{} operations...\n".format(phaseName))

        try:
            self.context.serverAdapter.pushPhaseStatus(phaseName, phaseStatus, NodeStatus.running)
            failCount = self.execOperations(phaseName, phaseConfig, opArgsRefMap, nodesFactory, parallelCount)
            if failCount == 0:
                if phaseStatus.ignoreFailNodeCount > 0:
                    self.context.serverAdapter.pushPhaseStatus(phaseName, phaseStatus, NodeStatus.completed)
                else:
                    self.context.serverAdapter.pushPhaseStatus(phaseName, phaseStatus, NodeStatus.succeed)
            else:
                self.context.hasFailNodeInGlobal = True
                failStatus = NodeStatus.failed
                if phaseStatus.isAborting:
                    failStatus = NodeStatus.aborted
                elif phaseStatus.isPausing:
                    failStatus = NodeStatus.paused
                self.context.serverAdapter.pushPhaseStatus(phaseName, phaseStatus, failStatus)
        except:
            print("ERROR: Execute phase:{} with unexpected exception.\n".format(phaseName))
            traceback.print_exc()
            print("\n")

        print("INFO: Execute phase:{} finish, suceessCount:{}, failCount:{}, ignoreCount:{}, skipCount:{}\n".format(phaseName, phaseStatus.sucNodeCount, phaseStatus.failNodeCount, phaseStatus.ignoreFailNodeCount, phaseStatus.skipNodeCount))
        print("--------------------------------------------------------------\n\n")

    def execOneShotGroup(self, phaseGroup, parallelCount, opArgsRefMap):
        groupId = phaseGroup['groupId']
        lastPhase = None
        # runFlow是一个数组，每个元素是一个phaseGroup
        threads = []
        # 每个group有多个phase，使用线程并发执行
        for phaseConfig in phaseGroup['phases']:
            phaseName = phaseConfig['phaseName']

            if self.context.goToStop == True:
                break

            if self.context.phasesToRun is not None and phaseName not in self.context.phasesToRun:
                continue

            if not self.context.hasFailNodeInGlobal:
                # 初始化phase的节点信息
                self.context.addPhase(phaseName)
                serverAdapter = self.context.serverAdapter
                if not self.localDefinedNodes:
                    serverAdapter.getNodes(phaseName)

                # Inner Loop 模式基于节点文件的nodesFactory，每个phase都一口气完成对所有RunNode的执行
                nodesFactory = RunNodeFactory.RunNodeFactory(self.context, phaseName=phaseName, phaseGroup=groupId)
                if nodesFactory.nodesCount > 0 and nodesFactory.nodesCount < parallelCount:
                    parallelCount = nodesFactory.nodesCount

                lastPhase = phaseName
                thread = threading.Thread(target=self.execPhase, args=(phaseName, phaseConfig, nodesFactory, parallelCount, opArgsRefMap))
                thread.name = 'PhaseExecutor-' + phaseName
                threads.append(thread)
                thread.start()

        for thread in threads:
            thread.join()

        return lastPhase

    def execGrayscaleGroup(self, phaseGroup, parallelCount, opArgsRefMap):
        # runFlow是一个数组，每个元素是一个phaseGroup
        # 启动所有的phase运行的线程，然后分批进行灰度
        groupId = phaseGroup['groupId']
        phaseNodeFactorys = {}

        nodesFactory = RunNodeFactory.RunNodeFactory(self.context, phaseGroup=groupId)
        if nodesFactory.nodesCount > 0 and nodesFactory.nodesCount <= parallelCount:
            parallelCount = nodesFactory.nodesCount

        threads = []
        for phaseConfig in phaseGroup['phases']:
            phaseName = phaseConfig['phaseName']
            # 初始化phase的节点信息
            self.context.addPhase(phaseName)

            phaseStatus = self.context.phases[phaseName]
            for operation in phaseConfig['operations']:
                # 如果有本地操作，则在context中进行标记
                opType = operation['opType']
                if opType in ('local', 'runner'):
                    phaseStatus.hasLocal = True
                else:
                    phaseStatus.hasRemote = True

            serverAdapter = self.context.serverAdapter
            if not self.localDefinedNodes:
                serverAdapter.getNodes(phaseName=phaseName, phaseGroup=groupId)

            phaseNodeFactory = PhaseNodeFactory.PhaseNodeFactory(self.context, parallelCount)
            phaseNodeFactorys[phaseName] = phaseNodeFactory
            thread = threading.Thread(target=self.execPhase, args=(phaseName, phaseConfig, phaseNodeFactory, parallelCount, opArgsRefMap))
            thread.start()
            thread.name = 'PhaseExecutor-' + phaseName
            threads.append(thread)

        maxRoundNo = int(nodesFactory.nodesCount / parallelCount)
        lastRoundCount = nodesFactory.nodesCount % parallelCount
        if lastRoundCount != 0 and lastRoundCount < parallelCount:
            maxRoundNo = maxRoundNo + 1

        firstRound = True
        midRound = False
        lastRound = False

        for roundNo in range(1, maxRoundNo + 1):
            if self.context.goToStop:
                break

            if roundNo >= maxRoundNo / 2:
                midRound = True
            if roundNo == maxRoundNo:
                lastRound = True

            oneRoundNodes = []
            for k in range(1, parallelCount + 1):
                node = nodesFactory.nextNode()
                if node is None:
                    break
                oneRoundNodes.append(node)

            lastPhase = None
            for phaseConfig in phaseGroup['phases']:
                if self.context.goToStop:
                    break

                phaseName = phaseConfig['phaseName']
                phaseStatus = self.context.phases[phaseName]

                execRound = 'first'
                if 'execRound' in phaseConfig:
                    execRound = phaseConfig['execRound']

                if phaseStatus.hasLocal:
                    needExecute = False
                    if firstRound and execRound == 'first':
                        needExecute = True
                    if midRound and execRound == 'middle':
                        needExecute = True
                    if lastRound and execRound == 'last':
                        needExecute = True

                    if needExecute:
                        # Local执行的phase，直接把localNode put到队列
                        phaseStatus.incRoundCounter(1)
                        phaseNodeFactory = phaseNodeFactorys[phaseName]
                        if not self.context.goToStop == True:
                            localNode = nodesFactory.localNode()
                            localRunNode = RunNode.RunNode(self.context, phaseName, localNode)
                            phaseNodeFactory.putLocalRunNode(localRunNode)
                            phaseNodeFactory.putLocalRunNode(None)

                elif phaseStatus.hasRemote:
                    phaseStatus.incRoundCounter(len(oneRoundNodes))

                    phaseNodeFactory = phaseNodeFactorys[phaseName]
                    for node in oneRoundNodes:
                        if self.context.goToStop == True:
                            phaseNodeFactory.putRunNode(None)
                            break
                        runNode = RunNode.RunNode(self.context, phaseName, node)
                        phaseNodeFactory.putRunNode(runNode)

                while not self.context.goToStop:
                    if phaseStatus.waitRoundFin(3):
                        break

                if self.context.hasFailNodeInGlobal:
                    self.context.serverAdapter.pushPhaseStatus(phaseName, phaseStatus, NodeStatus.failed)
                    break

            if lastRound or self.context.hasFailNodeInGlobal:
                break
            firstRound = False
            midRound = False

        # 给各个phase的node factory发送None节点，通知线程任务完成
        for phaseConfig in phaseGroup['phases']:
            phaseName = phaseConfig['phaseName']
            phaseNodeFactory = phaseNodeFactorys[phaseName]
            phaseNodeFactory.putRunNode(None)

        for thread in threads:
            thread.join()

        if not self.context.hasFailNodeInGlobal:
            lastPhase = phaseGroup['phases'][-1]
        return lastPhase

    def execute(self):
        listenThread = ListenThread('Listen-Thread', self.context)
        listenThread.start()

        params = self.context.params
        parallelCount = 25
        if 'parallel' in params:
            parallelCount = int(params['parallel'])
            self.context.parallelCount = parallelCount

        opArgsRefMap = {}
        lastPhase = None
        if 'runFlow' in params:
            # groupId = 1
            for phaseGroup in params['runFlow']:
                groupId = phaseGroup['groupId']
                if self.context.goToStop == True:
                    break

                if self.context.phaseGroupsToRun is not None and groupId not in self.context.phaseGroupsToRun:
                    continue
                # groupId = groupId + 1
                if 'execStrategy' in phaseGroup and phaseGroup['execStrategy'] == 'grayScale':
                    groupLastPhase = self.execGrayscaleGroup(phaseGroup, parallelCount, opArgsRefMap)
                else:
                    groupLastPhase = self.execOneShotGroup(phaseGroup, parallelCount, opArgsRefMap)

                if groupLastPhase is not None:
                    lastPhase = groupLastPhase

        self.stopListen()
        listenThread.stop()

        status = 0
        if self.context.hasFailNodeInGlobal:
            status = 1
        elif not self.context.goToStop:
            # 所有跑完了，如果全局不存在失败的节点，且nofirenext则通知后台调度器调度下一个phase,通知后台做fireNext的处理
            if not self.context.noFireNext and lastPhase is not None:
                self.context.serverAdapter.fireNextPhase(lastPhase)

        self.context.goToStop = True
        self.context.close()
        return status

    def stopListen(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        try:
            sock.connect(self.socketPath)
            sock.sendall('{"action":"exit"}')
            sock.close()
        except:
            pass

    def kill(self):
        self.context.goToStop = True
        self.stopListen()
        self.context.close()
        # 找出所有的正在之心的phase关联的PhaseExecutor执行kill
        for phaseStatus in self.context.phases.values():
            phaseStatus.isAborting = 1
            if phaseStatus.executor is not None:
                phaseStatus.executor.kill()
        self.context.serverAdapter.jobKilled()

    def pause(self):
        self.context.goToStop = True
        # 找出所有的正在之心的phase关联的PhaseExecutor执行pause
        for phaseStatus in self.context.phases.values():
            phaseStatus.isPausing = 1
            if phaseStatus.executor is not None:
                phaseStatus.executor.pause()
        self.context.serverAdapter.jobPaused()
