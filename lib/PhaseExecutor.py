#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import logging
import threading
from threading import Thread
import traceback
import queue
import NodeStatus
import OutputStore


class PhaseWorker(threading.Thread):
    def __init__(self, context, groupNo, phaseName, phaseType, operations, execQueue):
        threading.Thread.__init__(self)
        self.groupNo = groupNo
        self.phaseName = phaseName
        self.phaseType = phaseType
        self.context = context
        self._queue = execQueue
        self.operations = operations
        self.currentNode = None

    def run(self):
        while self.context.goToStop == False:
            # 获取节点，如果节点是NoneType，则所有节点已经完成运行
            node = None
            try:
                node = self._queue.get(timeout=self.context.maxExecSecs)
            except Exception as ex:
                print("WARN: Task last for 24 hours, it's too long, exit.\n", end='')
                break

            phaseStatus = self.context.phases[self.phaseName]
            if node is None:
                phaseStatus.setRoundFinEvent()
                break
            self.currentNode = node

            nodeStatus = node.getNodeStatus()

            if self.context.goToStop == False and self.phaseType == 'sqlfile':
                print("INFO: SQL file execute begin...\n", end='')
            elif (nodeStatus == NodeStatus.succeed or nodeStatus == NodeStatus.ignored) and not self.context.isForce:
                # 如果是成功状态，回写服务端，防止状态不一致
                phaseStatus.incSkipNodeCount()
                print("INFO: Node({}) status:{} {}:{} had been executed, skip.\n".format(node.resourceId, nodeStatus, node.host, node.port), end='')
                try:
                    self.context.serverAdapter.pushNodeStatus(self.groupNo, self.phaseName, node, nodeStatus)
                except Exception as ex:
                    logging.error("RePush node status to server failed, {}\n".format(ex))
                continue
            elif nodeStatus == NodeStatus.running and not self.context.isForce:
                if node.ensureNodeIsRunning():
                    print("ERROR: Node({}) status:{} {}:{} is running, please check the status.\n".format(node.resourceId, nodeStatus, node.host, node.port), end='')
                    phaseStatus.incFailNodeCount()
                    continue
                elif self.context.goToStop == False:
                    print("INFO: Node({}) status:{} {}:{} try to execute again...\n".format(node.resourceId, nodeStatus, node.host, node.port), end='')
            elif self.context.goToStop == False:
                print("INFO: Node({}) status:{} {}:{} execute begin...\n".format(node.resourceId, nodeStatus, node.host, node.port), end='')

            # 运行完所有操作
            preOp = None
            localOps = []
            # 为了让每个节点都有独立的插件参数记录，复制operation
            for op in self.operations:
                localOp = op.copy()
                localOp.preOp = preOp
                localOps.append(localOp)
                preOp = localOp

            opsStatus = None
            try:
                opsStatus = node.execute(localOps)
            except Exception as ex:
                if opsStatus is None:
                    opsStatus = NodeStatus.failed
                print("ERROR: Unknow error occurred.{}\n{}\n".format(str(ex), traceback.format_exc), end='')
            finally:
                self.currentNode = None

            if opsStatus == NodeStatus.ignored:
                phaseStatus.incIgnoreFailNodeCount()
                print("WARN: Node({}) {}:{} execute failed, ignore.\n".format(node.resourceId, node.host, node.port), end='')
            elif opsStatus == NodeStatus.succeed:
                phaseStatus.incSucNodeCount()
                print("INFO: Node({}) {}:{} execute succeed.\n".format(node.resourceId, node.host, node.port), end='')
            elif opsStatus == NodeStatus.paused:
                phaseStatus.incPauseNodeCount()
                print("WARN: Node({}) {}:{} execute paused.\n".format(node.resourceId, node.host, node.port), end='')
            else:
                phaseStatus.incFailNodeCount()
                print("ERROR: Node({}) {}:{} execute failed.\n".format(node.resourceId, node.host, node.port), end='')

    def informNodeWaitInput(self, resourceId, interact=None, clean=None):
        currentNode = self.currentNode
        if currentNode is not None and currentNode.resourceId == resourceId:
            if clean is None or clean == 0:
                currentNode.updateNodeStatus('waitInput', interact=interact)
            elif clean == 1:
                currentNode.updateNodeStatus('running', interact=None)
            return True
        else:
            return False

    def pause(self):
        self._queue.put(None)
        if self.currentNode is not None:
            self.currentNode.pause()

    def kill(self):
        self._queue.put(None)
        if self.currentNode is not None:
            self.currentNode.kill()


class PhaseExecutor:
    def __init__(self, context, groupNo, phaseName, phaseType, operations, nodesFactory, parallelCount=25):
        self.groupNo = groupNo
        self.phaseName = phaseName
        self.phaseType = phaseType
        self.phaseStatus = context.phases[self.phaseName]
        self.context = context
        self.operations = operations
        self.nodesFactory = nodesFactory
        self.workers = []
        self.parallelCount = parallelCount
        self.execQueue = None
        self.isRunning = False
        self.waitInputFlagFilePath = self.context.runPath + '/log/' + self.phaseName + '.waitInput'

    def _buildWorkerPool(self, execQueue):
        workers = []
        for i in range(self.parallelCount):
            worker = PhaseWorker(self.context, self.groupNo, self.phaseName, self.phaseType, self.operations, execQueue)
            worker.start()
            worker.setName('Worker-{}'.format(i))
            workers.append(worker)

        self.workers = workers
        return workers

    def _loadLocalOutput(self):
        phaseStatus = self.context.phases[self.phaseName]
        if phaseStatus.localOutput is None:
            localNode = {'resourceId': 0, 'host': 'local', 'port': 0}
            loalOutStore = OutputStore.OutputStore(self.context, self.phaseName, localNode)
            output = loalOutStore.loadOutput()
            phaseStatus.localOutput = output

    def execute(self):
        phaseStatus = self.phaseStatus
        self._loadLocalOutput()

        worker_threads = []
        try:
            # 删除当前阶段的waitInput标记文件
            if os.path.exists(self.waitInputFlagFilePath):
                os.unlink(self.waitInputFlagFilePath)

            nodesFactory = self.nodesFactory

            if not phaseStatus.hasRemote:
                self.parallelCount = 1

            # 初始化队列，设置最大容量为节点运行并行度的两倍，避免太多节点数据占用内存
            execQueue = queue.Queue(self.parallelCount * 2)
            self.execQueue = execQueue
            # 创建线程池
            worker_threads = self._buildWorkerPool(execQueue)

            # 如果有本地执行的插件（不是每个节点调用一次的插件）则虚构一个local的节点，直接执行
            if phaseStatus.hasLocal and phaseStatus.execLocal:
                node = None
                try:
                    # 如果有local的操作，则往队列中压入local node，构造一个特殊的node
                    node = nodesFactory.localRunNode()

                    # 如果node是None，代表local的操作不是在当前runner执行
                    if self.context.goToStop == False:
                        if node is None:
                            print("INFO: Local phase:{} is no need to execute in current runner.\n".format(self.phaseName), end='')
                        elif not self.isRunning:
                            self.isRunning = True
                            self.context.serverAdapter.pushPhaseStatus(self.groupNo, self.phaseName, phaseStatus, NodeStatus.running)
                            print("INFO: Begin to execute phase:{} operations...\n".format(self.phaseName), end='')

                        # 需要执行的节点实例加入等待执行队列
                        execQueue.put(node)
                except Exception as ex:
                    phaseStatus.incFailNodeCount()
                    if node is not None:
                        node.writeNodeLog("ERROR: Unknown error occurred\n{}\n" + traceback.format_exc())
                    else:
                        print("ERROR: Unknown error occurred\n{}\n".format(traceback.format_exc()), end='')

                if self.context.goToStop or phaseStatus.failNodeCount > 0 or self.context.hasFailNodeInGlobal == True:
                    try:
                        while True:
                            execQueue.get_nowait()
                    except Exception as ex:
                        pass

            elif phaseStatus.hasRemote:
                # 然后逐个节点node调用remote或者localremote插件执行把执行节点放到线程池的待处理队列中
                while self.context.goToStop == False:
                    node = None
                    try:
                        node = nodesFactory.nextRunNode()
                        if node is None:
                            break

                        if self.context.goToStop == False:
                            if not self.isRunning:
                                self.isRunning = True
                                self.context.serverAdapter.pushPhaseStatus(self.groupNo, self.phaseName, phaseStatus, NodeStatus.running)
                                print("INFO: Begin to execute phase:{} operations...\n".format(self.phaseName), end='')

                            # 需要执行的节点实例加入等待执行队列
                            execQueue.put(node)
                    except Exception as ex:
                        phaseStatus.incFailNodeCount()
                        if node is not None:
                            node.writeNodeLog("ERROR: Unknown error occurred\n{}\n".format(traceback.format_exc()))
                        else:
                            print("ERROR: Unknown error occurred\n{}\n".format(traceback.format_exc()), end='')

                    if self.context.goToStop or phaseStatus.failNodeCount > 0 or self.context.hasFailNodeInGlobal == True:
                        try:
                            while True:
                                execQueue.get_nowait()
                        except Exception as ex:
                            pass
                        break
        finally:
            workerCount = len(worker_threads)
            # 入队对应线程数量的退出信号对象
            for idx in range(1, workerCount*2):
                execQueue.put(None)

            # 等待所有worker线程退出
            while len(worker_threads) > 0:
                worker = worker_threads[-1]
                worker.join(3)
                if not worker.is_alive():
                    worker_threads.pop(-1)

        return phaseStatus.failNodeCount

    def informNodeWaitInput(self, resourceId, interact=None, clean=None):
        hasInformed = False
        for worker in self.workers:
            if (worker.informNodeWaitInput(resourceId, interact=interact, clean=clean)):
                hasInformed = True
        if hasInformed:
            self.context.serverAdapter.pushPhaseStatus(self.groupNo, self.phaseName, self.phaseStatus, NodeStatus.waitInput)
            if clean == 1:
                print("INFO: Update runner node status to running succeed.\n", end='')
            else:
                print("INFO: Update runner node status to waitInput succeed.\n", end='')

    def pause(self):
        self.context.goToStop = True
        try:
            while True:
                self.execQueue.get_nowait()
            self.execQueue.put(None)
        except Exception as ex:
            pass

        i = 1
        pauseWorkers = []
        for worker in self.workers:
            try:
                t = Thread(target=worker.pause, args=())
                t.setName('Pauser-{}'.format(i))
                t.start()
                pauseWorkers.append(t)
                i = i+1
            except:
                print("ERROR: Unable to start thread to pause woker.\n", end='')

        for t in pauseWorkers:
            t.join()

        #self.context.serverAdapter.pushPhaseStatus(self.groupNo, self.phaseName, self.phaseStatus, NodeStatus.paused)
        print("INFO: Try to pause job complete.\n", end='')

    def kill(self):
        self.context.goToStop = True
        try:
            while True:
                self.execQueue.get_nowait()
            self.execQueue.put(None)
        except Exception as ex:
            pass

        i = 1
        killWorkers = []
        for worker in self.workers:
            try:
                t = Thread(target=worker.kill, args=())
                t.setName('Killer-{}'.format(i))
                t.start()
                killWorkers.append(t)
                i = i+1
            except:
                print("ERROR: Unable to start thread to kill woker.\n", end='')

        for t in killWorkers:
            t.join()

        #self.context.serverAdapter.pushPhaseStatus(self.groupNo, self.phaseName, self.phaseStatus, NodeStatus.aborted)
        print("INFO: Try to kill phase:{} complete.\n".format(self.phaseName), end='')
