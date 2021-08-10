#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import os
import socket
import threading
import json
import shutil

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
            datagram = server.recv(4096)
            if not datagram:
                continue
            actionData = json.loads(datagram.decode('utf-8'))
            try:
                if actionData['action'] == 'informNodeWaitInput':
                    nodeId = actionData['nodeId']
                    for phaseStatus in self.context.phases.values():
                        if phaseStatus.executor is not None:
                            phaseStatus.executor.informNodeWaitInput(nodeId)
            except Exception as ex:
                print('ERROR: Ileggle request from sock {}\n{}\n'.format(actionData, ex))

    def stop(self):
        self.goToStop = True
        self.server.close()
        os.remove(self.socketPath)


class JobRunner:
    def __init__(self, context, nodesFile=None):
        self.context = context
        self.localDefinedParams = False
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
            context.serverAdapter.getNodes()
        else:
            # 如果命令行参数指定了nodesfile参数，则以此文件做为运行目标节点列表
            self.localDefinedNodes = True
            # 如果指定的参数文件存在，而且目录不是params文件最终的存放目录，则拷贝到最终的存放目录
            dstPath = '{}/nodes.json'.format(self.context.runPath)
            if os.path.exists(nodesFile):
                if dstPath != os.path.realpath(nodesFile):
                    shutil.copyfile(nodesFile, dstPath)
            else:
                print("ERROR: Nodes file directory:{} not exists.\n".format(nodesFile))

    def execOperations(self, phaseName, opsParams, opArgsRefMap, parallelCount):
        phaseStatus = self.context.phases[phaseName]
        phaseStatus.hasLocal = False
        phaseStatus.hasRemote = False

        self.context.initDB(parallelCount)
        self.context.loadEnv()

        operations = []
        # 遍历参数文件中定义的操作，逐个初始化，包括参数处理和准备，以及文件参数相关的文件下载

        for operation in opsParams:
            if 'arg' in operation:
                opArgsRefMap[operation['opId']] = operation['arg']
            else:
                opArgsRefMap[operation['opId']] = {}

            op = Operation.Operation(self.context, opArgsRefMap, operation)
            # op.parseParam()

            # 如果有本地操作，则在context中进行标记
            if op.opType == 'local':
                phaseStatus.hasLocal = True
            else:
                phaseStatus.hasRemote = True

            operations.append(op)

        executor = PhaseExecutor.PhaseExecutor(self.context, phaseName, operations, parallelCount)
        phaseStatus.executor = executor
        return executor.execute()

    def execPhase(self, phaseName, phaseConfig, parallelCount, opArgsRefMap):
        self.context.addPhase(phaseName)

        serverAdapter = self.context.serverAdapter
        if not self.localDefinedNodes:
            serverAdapter.getNodes(phaseName)

        phaseStatus = self.context.phases[phaseName]
        print("INFO: Begin to execute phase:{} operations...\n".format(phaseName))
        self.context.serverAdapter.pushPhaseStatus(phaseName, phaseStatus, NodeStatus.running)
        failCount = self.execOperations(phaseName, phaseConfig, opArgsRefMap, parallelCount)
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

        print("INFO: Execute phase:{} finish, suceessCount:{}, failCount:{}, ignoreCount:{}, skipCount:{}\n".format(phaseName, phaseStatus.sucNodeCount, phaseStatus.failNodeCount, phaseStatus.ignoreFailNodeCount, phaseStatus.skipNodeCount))
        print("--------------------------------------------------------------\n\n")

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

                # runFlow是一个数组，每个元素是一个phaseGroup
                threads = []
                # 每个group有多个phase，使用线程并发执行
                for phaseName, phaseConfig in phaseGroup.items():
                    if self.context.goToStop == True:
                        break

                    lastPhase = phaseName
                    if not self.context.hasFailNodeInGlobal:
                        thread = threading.Thread(target=self.execPhase, args=(phaseName, phaseConfig, parallelCount, opArgsRefMap))
                        thread.start()
                        thread.name = 'PhaseExecutor-' + phaseName
                        threads.append(thread)

                for thread in threads:
                    thread.join()

        status = 0
        if self.context.hasFailNodeInGlobal:
            status = 1
        elif not self.context.goToStop:
            # 所有跑完了，如果全局不存在失败的节点，且nofirenext则通知后台调度器调度下一个phase,通知后台做fireNext的处理
            if not self.context.noFireNext:
                self.context.serverAdapter.fireNextPhase(lastPhase)

        self.context.goToStop = True
        listenThread.stop()
        return status

    def kill(self):
        self.context.goToStop = True
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
