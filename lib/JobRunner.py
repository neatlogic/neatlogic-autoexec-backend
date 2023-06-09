#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import os
import socket
import threading
import queue
from tokenize import group
import traceback
import json
import shutil

import RunNode
import RunNodeFactory
import PhaseNodeFactory
import Operation
import PhaseExecutor
import NodeStatus
import GlobalLock


class ListenWorkThread(threading.Thread):
    def __init__(self, name, runnerListener=None, jobRunner=None):
        threading.Thread.__init__(self, name=name, daemon=True)
        server = runnerListener.server
        queue = runnerListener.workQueue
        context = jobRunner.context

        self.runnerListener = runnerListener
        self.jobRunner = jobRunner
        self.goToStop = False
        self.globalLock = GlobalLock.GlobalLock(context)
        self.context = context
        self.server = server
        self.queue = queue

    def run(self):
        while not self.goToStop:
            reqObj = self.queue.get()
            if reqObj is None:
                break

            datagram = reqObj[0]
            addr = reqObj[1]

            actionData = None
            try:
                datagram = datagram.decode('utf-8', 'ignore')
                actionData = json.loads(datagram)
                if actionData:
                    if actionData['action'] == 'informNodeWaitInput':
                        resourceId = int(actionData.get('resourceId'))
                        phaseName = actionData['phaseName']
                        clean = actionData.get('clean')
                        phaseStatus = self.context.phases.get(phaseName)
                        if phaseStatus is not None and phaseStatus.executor is not None:
                            phaseStatus.executor.informNodeWaitInput(resourceId, interact=actionData.get('interact'), clean=clean)
                            print("INFO: Node interact event recieved, processed.\n", end='')
                    elif actionData['action'] == 'informRoundContinue':
                        phaseName = actionData['phaseName']
                        roundNo = actionData['roundNo']
                        phaseStatus = self.context.phases.get(phaseName)
                        if phaseStatus is not None:
                            phaseStatus.setGlobalRoundFinEvent(roundNo)
                        print("INFO: Group execute round continue event recieved({}:{}), processed.\n".format(phaseName, roundNo), end='')
                    elif actionData['action'] == 'setEnv':
                        onlyInProcess = actionData.get('onlyInProcess')
                        for name, value in actionData('items').items():
                            if onlyInProcess:
                                os.environ[name] = value
                            else:
                                self.context.setEnv(name, value)
                            print("INFO: Set ENV variable({}) event recieved, processed.\n".format(name), end='')
                    elif actionData['action'] == 'globalLock':
                        lockThread = threading.Thread(target=self.doLock, args=(actionData['lockParams'], addr))
                        lockThread.setName('GlobalLock')
                        lockThread.start()
                        lockParams = actionData['lockParams']
                        lockMode = lockParams.get('lockMode')
                        if lockMode is None:
                            lockMode = ''
                        print("INFO: Lock event recieved, PID({}) {} {} for {}:{}.\n".format(lockParams.get('pid'), lockMode, lockParams.get('action'), lockParams.get('lockOwnerName'), lockParams.get('lockTarget', '-')), end='')
                    elif actionData['action'] == 'globalLockNotify':
                        self.globalLock.notifyWaiter(actionData['lockId'])
                        print("INFO: Lock notify event recieved, lockId:{}.\n".format(actionData['lockId']), end='')
                    elif actionData['action'] == 'queryCollectDB':
                        queryThread = threading.Thread(target=self.queryCollectDB, args=(actionData['queryParams'], addr))
                        queryThread.setName('CollectDBQuery')
                        queryThread.start()
                        print("INFO: Query collectDB event recived:{}\n".format(datagram), end='')
                    elif actionData['action'] == 'exit':
                        self.globalLock.stop()
                        self.runnerListener.stop()
                        break
            except Exception as ex:
                print('ERROR: Process event:{} failed,{}\n'.format(actionData, ex), end='')

    def doLock(self, lockParams, addr):
        if self.context.devMode:
            return {'lockId': 0}
        else:
            lockMode = lockParams.get('lockMode')
            if lockMode is None:
                lockMode = ''
            try:
                lockInfo = self.globalLock.doLock(lockParams)
                print("INFO: PID({}) {} {} lockId({}) for {}:{} success.\n".format(lockParams.get('pid'), lockMode, lockParams.get('action'), lockInfo.get('lockId'), lockParams.get('lockOwnerName'), lockParams.get('lockTarget', '-')), end='')
                self.server.sendto(json.dumps(lockInfo, ensure_ascii=False).encode('utf-8', 'ingore'), addr)
            except Exception as ex:
                lockInfo = {
                    'lockId': None,
                    'message': str(ex)
                }
                print("INFO: PID({}) {} {} for {}:{} failed, {}.\n".format(lockParams.get('pid'), lockMode, lockParams.get('action'), lockParams.get('lockOwnerName'), lockParams.get('lockTarget'), str(ex)), end='')
                self.server.sendto(json.dumps(lockInfo, ensure_ascii=False).encode('utf-8', 'ingore'), addr)

    def queryCollectDB(self, actionData, addr):
        collection = actionData['collection']
        condition = actionData['condition']
        projection = actionData['projection']
        db = self.context.db
        collection = db[collection]
        try:
            result = []
            projection['_id'] = 0
            for item in collection.find(condition, projection).limit(10):
                result.append(item)
            self.server.sendto(json.dumps({'result': result, 'error': None}, ensure_ascii=False).encode('utf-8', 'ingore'), addr)
        except Exception as ex:
            self.server.sendto(json.dumps({'result': None, 'error': str(ex)}, ensure_ascii=False).encode('utf-8', 'ingore'), addr)


class ListenThread (threading.Thread):  # 继承父类threading.Thread
    def __init__(self, name, jobRunner=None):
        threading.Thread.__init__(self, name=name, daemon=True)
        self.goToStop = False
        self.server = None
        context = jobRunner.context
        self.context = context

        self.socketPath = os.getenv('AUTOEXEC_JOB_SOCK')
        context.serverAdapter.getMongoDBConf()
        context.initDB()
        self.workQueue = queue.Queue(2048)
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self.globalLock = GlobalLock.GlobalLock(context)

        workers = []
        self.workers = workers
        for i in range(8):
            worker = ListenWorkThread('Listen-Worker-{}'.format(i), self, jobRunner)
            worker.setDaemon(True)
            worker.start()
            workers.append(worker)

    def __del__(self):
        self.stop()

    def run(self):
        socketPath = self.socketPath
        if os.path.exists(socketPath):
            os.remove(socketPath)

        self.server.bind(socketPath)

        while not self.goToStop:
            try:
                datagram, addr = self.server.recvfrom(8192)
                self.workQueue.put([datagram, addr])

                if not datagram:
                    continue
            except Exception as ex:
                pass

    def stop(self):
        self.goToStop = True
        try:
            if self.server is not None:
                self.server.close()
                self.server = None
            if os.path.exists(self.socketPath):
                os.remove(self.socketPath)

            workerCount = len(self.workers)
            # 入队对应线程数量的退出信号对象
            for idx in range(1, workerCount*2):
                self.workQueue.put(None)

            self.globalLock.stop()

            # 线程是daemon，不需要等待线程退出了
            # while len(self.workers) > 0:
            #     worker = self.workers[-1]
            #     worker.join(3)
            #     if not worker.is_alive():
            #         self.workers.pop(-1)
        except:
            print("ERROR: Unknown error occurred\n{}\n".format(traceback.format_exc()))
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
                nodesFile.write(json.dumps(node, ensure_ascii=False))
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
                    print("ERROR: Nodes file directory:{} not exists.\n".format(nodesFile), end='')

    def getParallelCount(self, totalNodeCount, roundCount):
        if roundCount <= 0:
            roundCount = totalNodeCount

        parallelCount = int(totalNodeCount / roundCount)
        remainder = totalNodeCount % roundCount
        if remainder > 0:
            parallelCount = parallelCount + 1
        return parallelCount

    def getRoundParallelCount(self, roundNo, totalNodeCount, roundCount):
        if totalNodeCount <= 0:
            totalNodeCount = 1
        if roundCount <= 0:
            roundCount = totalNodeCount

        parallelCount = int(totalNodeCount / roundCount)
        remainder = totalNodeCount % roundCount
        if remainder > 0 and roundNo <= remainder:
            parallelCount = parallelCount + 1
        return parallelCount

    def execOperations(self, groupNo, phaseName, phaseConfig, opArgsRefMap, nodesFactory, parallelCount):
        phaseStatus = self.context.phases[phaseName]

        self.context.loadEnv()

        operations = []
        # 遍历参数文件中定义的操作，逐个初始化，包括参数处理和准备，以及文件参数相关的文件下载

        for operation in phaseConfig['operations']:
            if 'opt' in operation:
                opArgsRefMap[operation['opId']] = operation['opt']
            else:
                opArgsRefMap[operation['opId']] = {}

            if operation.get('opType') == 'native' and operation.get('opName') == 'native/IF-Block':
                for ifOp in operation.get('if', []):
                    if ifOp.get('opType') in ('local', 'runner', 'sqlfie'):
                        phaseStatus.hasLocal = True
                    else:
                        phaseStatus.hasRemote = True
                for ifOp in operation.get('else', []):
                    if ifOp.get('opType') in ('local', 'runner', 'sqlfile'):
                        phaseStatus.hasLocal = True
                    else:
                        phaseStatus.hasRemote = True

            op = Operation.Operation(self.context, opArgsRefMap, operation)

            # 如果有本地操作，则在context中进行标记
            if op.opType in ('local', 'runner', 'sqlfile'):
                phaseStatus.hasLocal = True
            else:
                phaseStatus.hasRemote = True

            operations.append(op)

        phaseType = phaseConfig.get('phaseType')
        executor = PhaseExecutor.PhaseExecutor(self.context, groupNo, phaseName, phaseType, operations, nodesFactory, parallelCount)
        phaseStatus.executor = executor
        return executor.execute()

    def execPhase(self, groupNo, phaseName, phaseConfig, nodesFactory, parallelCount, opArgsRefMap):
        serverAdapter = self.context.serverAdapter
        endStatus = NodeStatus.aborted
        phaseStatus = self.context.phases[phaseName]
        try:
            # serverAdapter.pushPhaseStatus(groupNo, phaseName, phaseStatus, NodeStatus.running)
            failCount = self.execOperations(groupNo, phaseName, phaseConfig, opArgsRefMap, nodesFactory, parallelCount)
            if failCount == 0:
                endStatus = NodeStatus.succeed
                if phaseStatus.isAborting:
                    endStatus = NodeStatus.aborted
                elif self.context.goToStop or self.context.hasFailNodeInGlobal:
                    endStatus = NodeStatus.paused
                elif phaseStatus.ignoreFailNodeCount > 0:
                    endStatus = NodeStatus.completed
            else:
                self.context.hasFailNodeInGlobal = True
                endStatus = NodeStatus.failed
                if phaseStatus.isAborting:
                    endStatus = NodeStatus.aborted
        except:
            endStatus = NodeStatus.aborted
            print("ERROR: Execute phase:{} with unexpected exception.\n".format(phaseName), end='')
            traceback.print_exc()
            print("\n", end='')
        finally:
            phaseStatus.isComplete = 1
            print("INFO: Execute phase:{} complete, status:{}.\n".format(phaseName, endStatus), end='')
            serverAdapter.pushPhaseStatus(groupNo, phaseName, phaseStatus, endStatus)

    def execOneShotGroup(self, phaseGroup, groupRoundCount, opArgsRefMap):
        groupNo = phaseGroup['groupNo']
        lastPhase = None
        # runFlow是一个数组，每个元素是一个phaseGroup
        threads = []
        # 每个group有多个phase，使用线程并发执行
        phaseIndex = 0
        for phaseConfig in phaseGroup['phases']:
            phaseType = phaseConfig.get('phaseType')
            phaseName = phaseConfig['phaseName']
            phaseIndex = phaseIndex + 1

            phaseRoundCount = phaseConfig.get('roundCount', None)
            if phaseRoundCount is None:
                phaseRoundCount = groupRoundCount

            if self.context.goToStop == True:
                break

            if self.context.phasesToRun is not None and phaseName not in self.context.phasesToRun:
                continue

            if not self.context.hasFailNodeInGlobal:
                # 初始化phase的节点信息
                self.context.addPhase(phaseName)
                phaseStatus = self.context.phases[phaseName]

                if phaseType in ('local', 'runner', 'sqlfile'):
                    phaseStatus.hasLocal = True
                else:
                    phaseStatus.hasRemote = True

                serverAdapter = self.context.serverAdapter
                if not self.localDefinedNodes:
                    serverAdapter.getNodes(phase=phaseName)

                # Inner Loop 模式基于节点文件的nodesFactory，每个phase都一口气完成对所有RunNode的执行
                nodesFactory = RunNodeFactory.RunNodeFactory(self.context, phaseIndex=phaseIndex, phaseName=phaseName, phaseType=phaseType, groupNo=groupNo)
                if nodesFactory.totalNodesCount > 0:
                    parallelCount = self.getParallelCount(nodesFactory.nodesCount, phaseRoundCount)

                    lastPhase = phaseName
                    serverAdapter.pushPhaseStatus(groupNo, phaseName, phaseStatus, NodeStatus.running)
                    thread = threading.Thread(target=self.execPhase, args=(groupNo, phaseName, phaseConfig, nodesFactory, parallelCount, opArgsRefMap))
                    thread.name = 'PhaseExecutor-' + phaseName
                    threads.append(thread)
                    thread.start()

        for thread in threads:
            thread.join()

        for phaseConfig in phaseGroup['phases']:
            phaseName = phaseConfig['phaseName']
            if self.context.phasesToRun is not None and phaseName not in self.context.phasesToRun:
                continue

            phaseStatus = self.context.phases.get(phaseName)
            if phaseStatus is not None:
                print("INFO: Execute phase:{} finish, suceessCount:{}, failCount:{}, ignoreCount:{}, pauseCount:{}, skipCount:{}\n".format(phaseName, phaseStatus.sucNodeCount, phaseStatus.failNodeCount, phaseStatus.ignoreFailNodeCount, phaseStatus.pauseNodeCount, phaseStatus.skipNodeCount), end='')
                print("--------------------------------------------------------------\n\n", end='')

        return lastPhase

    def execGrayscaleGroup(self, phaseGroup, groupRoundCount, opArgsRefMap):
        # runFlow是一个数组，每个元素是一个phaseGroup
        # 启动所有的phase运行的线程，然后分批进行灰度
        groupNo = phaseGroup['groupNo']
        phaseNodeFactorys = {}
        # 下载group的节点s
        serverAdapter = self.context.serverAdapter
        if not self.localDefinedNodes:
            serverAdapter.getNodes(groupNo=groupNo)
        nodesFactory = RunNodeFactory.RunNodeFactory(self.context, groupNo=groupNo)

        realGroupRoundCount = groupRoundCount
        if realGroupRoundCount <= 0:
            realGroupRoundCount = nodesFactory.nodesCount

        if realGroupRoundCount == 0:
            realGroupRoundCount = 1

        # 获取分组运行的最大的并行线程数
        parallelCount = self.getRoundParallelCount(1, nodesFactory.nodesCount, realGroupRoundCount)

        threads = []
        for phaseConfig in phaseGroup['phases']:
            phaseName = phaseConfig['phaseName']
            if self.context.phasesToRun is not None and phaseName not in self.context.phasesToRun:
                continue

            # 初始化phase的节点信息
            self.context.addPhase(phaseName)

            phaseStatus = self.context.phases[phaseName]
            if 'phaseType' in phaseConfig:
                if phaseConfig['phaseType'] in ('local', 'runner', 'sqlfile'):
                    phaseStatus.hasLocal = True
                else:
                    phaseStatus.hasRemote = True
            else:
                for operation in phaseConfig['operations']:
                    # 如果有本地操作，则在context中进行标记
                    opType = operation['opType']
                    if opType in ('local', 'runner', 'sqlfile'):
                        phaseStatus.hasLocal = True
                    else:
                        phaseStatus.hasRemote = True

            phaseNodeFactory = PhaseNodeFactory.PhaseNodeFactory(self.context, parallelCount)
            phaseNodeFactorys[phaseName] = phaseNodeFactory
            thread = threading.Thread(target=self.execPhase, args=(groupNo, phaseName, phaseConfig, phaseNodeFactory, parallelCount, opArgsRefMap))
            thread.start()
            thread.name = 'PhaseExecutor-' + phaseName
            threads.append(thread)

        maxRoundNo = realGroupRoundCount
        if nodesFactory.nodesCount < maxRoundNo:
            maxRoundNo = nodesFactory.nodesCount
        if maxRoundNo <= 0:
            maxRoundNo = 1

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
            curRoundNodes = self.getRoundParallelCount(roundNo, nodesFactory.nodesCount, maxRoundNo)
            for k in range(1, curRoundNodes + 1):
                node = nodesFactory.nextNode()
                if node is None:
                    break
                if node['runnerId'] == self.context.runnerId:
                    oneRoundNodes.append(node)

            lastPhase = None
            phaseIndex = 0
            for phaseConfig in phaseGroup['phases']:
                if self.context.goToStop:
                    break

                phaseType = phaseConfig.get('phaseType')
                phaseName = phaseConfig['phaseName']
                if self.context.phasesToRun is not None and phaseName not in self.context.phasesToRun:
                    continue

                phaseIndex = phaseIndex + 1
                phaseStatus = self.context.phases[phaseName]
                phaseStatus.clearRoundFinEvent()
                phaseStatus.clearGlobalRoundFinEvent()
                phaseStatus.roundNo = roundNo
                execRound = 'first'
                if 'execRound' in phaseConfig:
                    execRound = phaseConfig['execRound']

                if phaseStatus.hasLocal and self.context.runnerId == nodesFactory.localRunnerId:
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
                            localRunNode = RunNode.RunNode(self.context, groupNo, phaseIndex, phaseName, phaseType, localNode)
                            phaseNodeFactory.putLocalRunNode(localRunNode)
                        phaseNodeFactory.putLocalRunNode(None)

                elif phaseStatus.hasRemote:
                    phaseNodeFactory = phaseNodeFactorys[phaseName]
                    for node in oneRoundNodes:
                        if self.context.goToStop == True:
                            phaseNodeFactory.putRunNode(None)
                            break
                        if self.context.runnerId == node['runnerId']:
                            runNode = RunNode.RunNode(self.context, groupNo, phaseIndex, phaseName, phaseType, node, nodesFactory.totalNodesCount)
                            phaseStatus.incRoundCounter(1)
                            phaseNodeFactory.putRunNode(runNode)
                    if lastRound:
                        phaseNodeFactory.putRunNode(None)

                loopCount = self.context.maxExecSecs / 3
                while not self.context.goToStop:
                    loopCount = loopCount - 1
                    if phaseStatus.waitRoundFin(3):
                        break

                if loopCount <= 0:
                    self.context.hasFailNodeInGlobal = True
                    print("ERROR: Job last more than max execute seconds:{}, exit.\n".format(self.context.maxExecSecs), end='')
                    break
                elif lastRound:
                    print("INFO: Execute phase:{} in current runner finished, wait other runner...\n".format(phaseName), end='')

                if self.context.hasFailNodeInGlobal:
                    nodeStatus = NodeStatus.failed
                    if phaseStatus.isAborting:
                        nodeStatus = NodeStatus.aborted
                    self.context.serverAdapter.pushPhaseStatus(groupNo, phaseName, phaseStatus, nodeStatus)
                    break

                if not nodesFactory.jobRunnerCount == 1:
                    loopCount = self.context.maxExecSecs / 10
                    while loopCount > 0 and not self.context.goToStop:
                        loopCount = loopCount - 1
                        print("INFO: Inform server group:%d round:%d ended.\n" % (groupNo, roundNo), end='')
                        self.context.serverAdapter.informRoundEnded(groupNo, phaseName, roundNo)
                        if phaseStatus.waitGlobalRoundFin(10):
                            break

                    if loopCount <= 0:
                        self.context.hasFailNodeInGlobal = True
                        print("ERROR: Job last more than max execute seconds:{}, exit.\n".format(self.context.maxExecSecs), end='')
                        break

                if lastRound:
                    print("INFO: Execute phase:{} finish, suceessCount:{}, failCount:{}, ignoreCount:{}, pauseCount:{}, skipCount:{}\n".format(phaseName, phaseStatus.sucNodeCount, phaseStatus.failNodeCount, phaseStatus.ignoreFailNodeCount, phaseStatus.pauseNodeCount, phaseStatus.skipNodeCount), end='')
                    print("--------------------------------------------------------------\n\n")

            if lastRound or self.context.hasFailNodeInGlobal:
                break
            firstRound = False
            midRound = False

        # 给各个phase的node factory发送None节点，通知线程任务完成
        for phaseConfig in phaseGroup['phases']:
            phaseName = phaseConfig['phaseName']
            if self.context.phasesToRun is not None and phaseName not in self.context.phasesToRun:
                continue
            phaseNodeFactory = phaseNodeFactorys[phaseName]
            phaseNodeFactory.putRunNode(None)
            phaseNodeFactory.putLocalRunNode(None)

        for thread in threads:
            thread.join()

        if not self.context.hasFailNodeInGlobal:
            lastPhase = phaseGroup['phases'][-1]

        return lastPhase

    def execute(self):
        listenThread = ListenThread('Listen-Thread', self)
        listenThread.start()

        params = self.context.params
        if 'enviroment' in params:
            for k, v in params.items():
                os.environ[k] = str(v)

        jobRoundCount = params.get('roundCount', 0)

        opArgsRefMap = {}
        lastGroupNo = None
        lastPhase = None
        groupLastPhase = None
        if 'runFlow' in params:
            for phaseGroup in params['runFlow']:
                groupNo = phaseGroup['groupNo']
                groupRoundCount = phaseGroup.get('roundCount', None)
                if groupRoundCount is None:
                    groupRoundCount = jobRoundCount

                if self.context.hasFailNodeInGlobal:
                    break

                if self.context.goToStop == True:
                    break

                if self.context.phaseGroupsToRun is not None and groupNo not in self.context.phaseGroupsToRun:
                    continue

                groupLastPhase = None
                if self.context.phasesToRun is not None and len(self.context.phasesToRun) == 1:
                    groupLastPhase = self.execOneShotGroup(phaseGroup, groupRoundCount, opArgsRefMap)
                elif 'execStrategy' in phaseGroup and phaseGroup['execStrategy'] == 'grayScale':
                    groupLastPhase = self.execGrayscaleGroup(phaseGroup, groupRoundCount, opArgsRefMap)
                else:
                    groupLastPhase = self.execOneShotGroup(phaseGroup, groupRoundCount, opArgsRefMap)

                lastGroupNo = groupNo
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
                self.context.serverAdapter.fireNextGroup(lastGroupNo)

        self.context.goToStop = True
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
        print("INFO: Try to kill job...\n", end='')
        self.stopListen()
        # 找出所有的正在之心的phase关联的PhaseExecutor执行kill
        for phaseStatus in self.context.phases.values():
            phaseStatus.isAborting = 1
            phaseStatus.setGlobalRoundFinEvent()
            phaseStatus.setRoundFinEvent()
            if phaseStatus.isComplete == 0 and phaseStatus.executor is not None:
                print("INFO: Try to kill phase:{}...\n".format(phaseStatus.phaseName), end='')
                phaseStatus.executor.kill()
        self.context.serverAdapter.jobKilled()
        print("INFO: Job killed.\n", end='')

    def pause(self):
        self.context.goToStop = True
        print("INFO: Try to pause job...\n", end='')
        # 找出所有的正在之心的phase关联的PhaseExecutor执行pause
        for phaseStatus in self.context.phases.values():
            phaseStatus.isPausing = 1
            phaseStatus.setGlobalRoundFinEvent()
            phaseStatus.setRoundFinEvent()
            if phaseStatus.isComplete == 0 and phaseStatus.executor is not None:
                print("INFO: Try to pause phase:{}...\n".format(phaseStatus.phaseName), end='')
                phaseStatus.executor.pause()
        self.context.serverAdapter.jobPaused()
        print("INFO: Job paused.\n", end='')
