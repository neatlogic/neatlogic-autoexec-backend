#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import os
import time
import socket
import threading
import queue
import traceback
import json
import shutil

import RunNodeFactory
import Operation
import PhaseExecutor
import NodeStatus


class ListenWorkThread(threading.Thread):
    def __init__(self, name, server, queue, context=None):
        threading.Thread.__init__(self, name=name, daemon=True)
        self.goToStop = False
        self.context = context
        server.server = server
        self.queue = queue

    def run(self):
        serverAdapter = self.context.serverAdapter
        while not self.goToStop:
            reqObj = self.queue.get()
            if reqObj is None:
                break

            datagram = reqObj[0]
            addr = reqObj[1]

            actionData = None
            try:
                actionData = json.loads(datagram.decode('utf-8'))
                if actionData:
                    if actionData['action'] == 'informNodeWaitInput':
                        nodeId = actionData['nodeId']
                        for phaseStatus in self.context.phases.values():
                            if phaseStatus.executor is not None:
                                phaseStatus.executor.informNodeWaitInput(nodeId, interact=actionData['interact'])
                    elif actionData['action'] == 'deployLock':
                        lockId = serverAdapter.deployLock(actionData['lockParams'])
                        self.server.sendto({'lockId': lockId}, addr)
                    elif actionData['action'] == 'exit':
                        self.server.shutdown()
                        break
            except Exception as ex:
                print('ERROR: Inform node status to waitInput failed, {}\n{}\n'.format(actionData, ex))

    def stop(self):
        self.goToStop = True


class ListenThread (threading.Thread):  # 继承父类threading.Thread
    def __init__(self, name, context=None):
        threading.Thread.__init__(self, name=name, daemon=True)
        self.goToStop = False
        self.socketPath = context.runPath + '/job.sock'
        context.initDB()
        self.context = context
        self.workQueue = queue.Queue(2048)
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        workers = []
        self.workers = workers
        for i in range(8):
            worker = ListenWorkThread('Listen-Worker-{}'.format(i), self.server, self.workQueue, self.context)
            worker.start()
            workers.append(worker)

    def run(self):
        socketPath = self.socketPath
        if os.path.exists(socketPath):
            os.remove(socketPath)

        self.server.bind(socketPath)

        while not self.goToStop:
            actionData = None
            try:
                datagram, addr = self.server.recv(8192)
                self.workQueue.put([datagram, addr])

                if not datagram:
                    continue
            except Exception as ex:
                pass

    def stop(self):
        self.goToStop = True
        try:
            self.server.close()
            if os.path.exists(self.socketPath):
                os.remove(self.socketPath)

            workerCount = len(self.workers)
            # 入队对应线程数量的退出信号对象
            for idx in range(1, workerCount*2):
                self.workQueue.put(None)

            while len(self.workers) > 0:
                worker = self.workers[-1]
                worker.join(3)
                if not worker.is_alive():
                    self.workers.pop(-1)
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

    def execOperations(self, phaseName, opsParams, opArgsRefMap, nodesFactory, parallelCount):
        phaseStatus = self.context.phases[phaseName]
        phaseStatus.hasLocal = False
        phaseStatus.hasRemote = False

        self.context.loadEnv()

        operations = []
        # 遍历参数文件中定义的操作，逐个初始化，包括参数处理和准备，以及文件参数相关的文件下载

        for operation in opsParams:
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
        try:
            serverAdapter = self.context.serverAdapter

            phaseStatus = self.context.phases[phaseName]
            print("INFO: Begin to execute phase:{} operations...\n".format(phaseName))

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

        print("INFO: Execute phase:{} finish, suceessCount:{}, failCount:{}, ignoreCount:{}, skipCount:{}\n".format(phaseName, phaseStatus.sucNodeCount, phaseStatus.failNodeCount, phaseStatus.ignoreFailNodeCount, phaseStatus.skipNodeCount))
        print("--------------------------------------------------------------\n\n")

    def execOneShotGroup(self, phaseGroup, parallelCount, opArgsRefMap):
        lastPhase = None
        # runFlow是一个数组，每个元素是一个phaseGroup
        threads = []
        # 每个group有多个phase，使用线程并发执行
        for phaseName, phaseConfig in phaseGroup.items():
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
                nodesFactory = RunNodeFactory.RunNodeFactory(self.context, phaseName)
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
        pass

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
            for phaseGroup in params['runFlow']:
                if self.context.goToStop == True:
                    break

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
