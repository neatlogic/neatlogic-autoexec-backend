#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import logging
import threading
from threading import Thread
import traceback
import subprocess
import queue
import copy
import json
import RunNode
import NodeStatus


class PhaseWorker(threading.Thread):
    def __init__(self, context, phaseName, operations, queue):
        threading.Thread.__init__(self)
        self.phaseName = phaseName
        self.context = context
        self._queue = queue
        self.operations = operations
        self.currentNode = None

    def run(self):
        while self.context.goToStop == False:
            # 获取节点，如果节点是NoneType，则所有节点已经完成运行
            node = None
            try:
                node = self._queue.get(timeout=86400)
            except Exception as ex:
                print("WARN: Task last for 24 hours, it's too long, exit.\n")
                break

            if node is None:
                break
            self.currentNode = node
            phaseStatus = self.context.phases[self.phaseName]

            nodeStatus = node.getNodeStatus()
            if nodeStatus == NodeStatus.succeed:
                # 如果是成功状态，回写服务端，防止状态不一致
                phaseStatus.incSkipNodeCount()
                print("INFO: Node({}) status:{} {}:{} had been execute succeed, skip.\n".format(node.resourceId, nodeStatus, node.host, node.port))
                try:
                    self.context.serverAdapter.pushNodeStatus(self.phaseName, node, nodeStatus)
                except Exception as ex:
                    logging.error("RePush node status to server failed, {}\n".format(ex))
                continue
            elif nodeStatus == NodeStatus.running:
                if node.ensureNodeIsRunning():
                    print("ERROR: Node({}) status:{} {}:{} is running, please check the status.\n".format(node.resourceId, nodeStatus, node.host, node.port))
                    phaseStatus.incFailNodeCount()
                    continue
                elif self.context.goToStop == False:
                    print("INFO: Node({}) status:{} {}:{} try to execute again...\n".format(node.resourceId, nodeStatus, node.host, node.port))
            elif self.context.goToStop == False:
                print("INFO: Node({}) status:{} {}:{} execute begin...\n".format(node.resourceId, nodeStatus, node.host, node.port))

            # 运行完所有操作
            localOps = []
            # 为了让每个节点都有独立的插件参数记录，复制operation
            for op in self.operations:
                localOps.append(copy.copy(op))

            opsStatus = None
            try:
                opsStatus = node.execute(localOps)
            except Exception as ex:
                if opsStatus is None:
                    opsStatus = NodeStatus.failed
                print("ERROR: Unknow error occurred.{}\m{}\n".format(str(ex), traceback.format_exc))

            if opsStatus == NodeStatus.ignored:
                phaseStatus.incIgnoreFailNodeCount()
                print("WARN: Node({}) {}:{} execute failed, ignore.\n".format(node.resourceId, node.host, node.port))
            elif opsStatus == NodeStatus.succeed:
                phaseStatus.incSucNodeCount()
                print("INFO: Node({}) {}:{} execute succeed.\n".format(node.resourceId, node.host, node.port))
            else:
                phaseStatus.incFailNodeCount()
                print("ERROR: Node({}) {}:{} execute failed.\n".format(node.resourceId, node.host, node.port))

    def informNodeWaitInput(self, nodeId, interact=None):
        currentNode = self.currentNode
        if currentNode is not None and currentNode.id == nodeId:
            currentNode.updateNodeStatus('waitInput', interact=interact)
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
    def __init__(self, context, phaseName, operations, nodesFactory, parallelCount=25):
        self.phaseName = phaseName
        self.phaseStatus = context.phases[self.phaseName]
        self.context = context
        self.operations = operations
        self.nodesFactory = nodesFactory
        self.workers = []
        self.parallelCount = parallelCount
        self.execQueue = None
        self.waitInputFlagFilePath = self.context.runPath + '/log/' + self.phaseName + '.waitInput'

    def _buildWorkerPool(self, queue):
        workers = []
        for i in range(self.parallelCount):
            worker = PhaseWorker(self.context, self.phaseName, self.operations, queue)
            worker.start()
            worker.setName('Worker-{}'.format(i))
            workers.append(worker)

        self.workers = workers
        return workers

    def execute(self):
        phaseStatus = self.phaseStatus
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
            if phaseStatus.hasLocal:
                localRunNode = None
                try:
                    # 如果有local的操作，则往队列中压入local node，构造一个特殊的node
                    localNode = {"nodeId": 0, "resourceId": 0, "protocol": "local", "host": "local", "port": 0, "username": "", "password": ""}
                    localRunNode = RunNode.RunNode(self.context, self.phaseName, localNode)

                    if self.context.goToStop == False:
                        # 需要执行的节点实例加入等待执行队列
                        execQueue.put(localRunNode)
                except Exception as ex:
                    phaseStatus.incFailNodeCount()
                    if localRunNode is not None:
                        localRunNode.writeNodeLog("ERROR: Unknown error occurred\n{}\n" + traceback.format_exc())
                    else:
                        print("ERROR: Unknown error occurred\n{}\n".format(traceback.format_exc()))

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
                        node = nodesFactory.nextNode()
                        if node is None:
                            break

                        if self.context.goToStop == False:
                            # 需要执行的节点实例加入等待执行队列
                            execQueue.put(node)
                    except Exception as ex:
                        phaseStatus.incFailNodeCount()
                        if node is not None:
                            node.writeNodeLog("ERROR: Unknown error occurred\n{}\n".format(traceback.format_exc()))
                        else:
                            print("ERROR: Unknown error occurred\n{}\n".format(traceback.format_exc()))

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
            # for worker in worker_threads:
            #    worker.join()
            while len(worker_threads) > 0:
                worker = worker_threads[-1]
                worker.join(3)
                if not worker.is_alive():
                    worker_threads.pop(-1)

            # if phaseStatus.hasRemote:
            #    print("INFO: Execute complete, successCount:{}, skipCount:{}, failCount:{}, ignoreCount:{}\n".format(phaseStatus.sucNodeCount, phaseStatus.skipNodeCount, phaseStatus.failNodeCount, phaseStatus.ignoreFailNodeCount))
        return phaseStatus.failNodeCount

    def informNodeWaitInput(self, nodeId, interact=None):
        hasInformed = False
        for worker in self.workers:
            if (worker.informNodeWaitInput(nodeId, interact=interact)):
                hasInformed = True
        if hasInformed:
            self.context.serverAdapter.pushPhaseStatus(self.phaseName, self.phaseStatus, NodeStatus.waitInput)
            print("INFO: Update runner node status to waitInput succeed.\n")

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
                print("ERROR: unable to start thread to pause woker\n")

        for t in pauseWorkers:
            t.join()

        print("INFO: Try to pause job complete.\n")

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
                print("ERROR: unable to start thread to kill woker\n")

        for t in killWorkers:
            t.join()

        print("INFO: Try to kill job complete.\n")
