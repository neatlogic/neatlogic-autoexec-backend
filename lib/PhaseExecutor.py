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
import RunNodeFactory
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
            node = self._queue.get()
            if node is None:
                break
            self.currentNode = node

            try:
                # 运行完所有操作
                phaseStatus = self.context.phases[self.phaseName]
                localOps = copy.copy(self.operations)  # 为了让每个节点都有独立的插件参数记录，复制operation
                try:
                    ret = node.execute(localOps)
                except Exception as ex:
                    node.updateNodeStatus(NodeStatus.failed)
                    node.writeNodeLog("ERROR: Unknow error occurred.\n")
                    node.writeNodeLog(str(ex))
                    node.writeNodeLog(traceback.format_exc())
                    node.writeNodeLog("\n")
                    ret = 3

                if ret != 0:
                    phaseStatus.incFailNodeCount()
                    print("ERROR: Node({}) {}:{} execute failed.\n".format(node.id, node.host, node.port))
                else:
                    if node.hasIgnoreFail == 1:
                        phaseStatus.incIgnoreFailNodeCount()
                        print("INFO: Node({}) {}:{} execute failed, ignore.\n".format(node.id, node.host, node.port))
                    else:
                        phaseStatus.incSucNodeCount()
                        print("INFO: Node({}) {}:{} execute succeed.\n".format(node.id, node.host, node.port))
            finally:
                self.currentNode = None

    def kill(self):
        self._queue.put(None)
        if self.currentNode is not None:
            self.currentNode.kill()


class PhaseExecutor:
    def __init__(self, context, phaseName, operations, parallelCount=25):
        self.phaseName = phaseName
        self.phaseStatus = context.phases[self.phaseName]
        self.context = context
        self.operations = operations
        self.workers = []
        self.parallelCount = parallelCount
        self.execQueue = None

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
            nodesFactory = RunNodeFactory.RunNodeFactory(self.context, self.phaseName)
            if nodesFactory.nodesCount > 0 and nodesFactory.nodesCount < self.parallelCount:
                self.parallelCount = nodesFactory.nodesCount

            if not phaseStatus.hasRemote:
                self.parallelCount = 1

            # 初始化队列，设置最大容量为节点运行并行度的两倍，避免太多节点数据占用内存
            execQueue = queue.Queue(self.parallelCount*2)
            self.execQueue = execQueue
            # 创建线程池
            worker_threads = self._buildWorkerPool(execQueue)

            # 如果有本地执行的插件（不是每个节点调用一次的插件）则虚构一个local的节点，直接执行
            if phaseStatus.hasLocal:
                localRunNode = None
                try:
                    # 如果有local的操作，则往队列中压入local node，构造一个特殊的node
                    localNode = {"nodeId": 0, "nodeType": "local", "host": "local", "port": 0, "username": "", "password": ""}
                    localRunNode = RunNode.RunNode(self.context, self.phaseName, localNode)

                    if self.context.isForce and self.context.goToStop == False:
                        # 需要执行的节点实例加入等待执行队列
                        execQueue.put(localRunNode)
                    else:
                        nodeStatus = localRunNode.getNodeStatus()
                        if nodeStatus == NodeStatus.succeed:
                            print("INFO: Node({}) status:{} {}:{} had been execute succeed, skip.\n".format(localRunNode.id, nodeStatus, localRunNode.host, localRunNode.port))
                            phaseStatus.incSkipNodeCount()
                        elif nodeStatus == NodeStatus.running:
                            if localRunNode.ensureNodeIsRunning():
                                print("ERROR: Node({}) status:{} {}:{} is running, please check the status.\n".format(localRunNode.id, nodeStatus, localRunNode.host, localRunNode.port))
                                phaseStatus.incFailNodeCount()
                            else:
                                print("INFO: Node({}) status:{} {}:{} try to execute again...\n".format(localRunNode.id, nodeStatus, localRunNode.host, localRunNode.port))
                                execQueue.put(localRunNode)
                        elif self.context.goToStop == False:
                            # 需要执行的节点实例加入等待执行队列
                            print("INFO: Node({}) status:{} {}:{} execute begin...\n".format(localRunNode.id, nodeStatus, localRunNode.host, localRunNode.port))
                            execQueue.put(localRunNode)
                except Exception as ex:
                    phaseStatus.incFailNodeCount()
                    if localRunNode is not None:
                        localRunNode.writeNodeLog("ERROR: Unknown error occurred\n{}\n" + traceback.format_exc())
                    else:
                        print("ERROR: Unknown error occurred\n{}\n".format(traceback.format_exc()))

            if phaseStatus.failNodeCount > 0 or self.context.hasFailNodeInGlobal == True:
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

                        if self.context.isForce:
                            # 需要执行的节点实例加入等待执行队列
                            execQueue.put(node)
                        else:
                            nodeStatus = node.getNodeStatus()
                            if nodeStatus == NodeStatus.succeed:
                                # 如果是成功状态，回写服务端，防止状态不一致
                                phaseStatus.incSkipNodeCount()
                                print("INFO: Node({}) status:{} {}:{} had been execute succeed, skip.\n".format(node.id, nodeStatus, node.host, node.port))
                                try:
                                    self.context.serverAdapter.pushNodeStatus(self.phaseName, node, nodeStatus)
                                except Exception as ex:
                                    logging.error("RePush node status to server failed, {}\n".format(ex))
                            elif nodeStatus == NodeStatus.running:
                                if node.ensureNodeIsRunning():
                                    print("ERROR: Node({}) status:{} {}:{} is running, please check the status.\n".format(node.id, nodeStatus, node.host, node.port))
                                    phaseStatus.incFailNodeCount()
                                else:
                                    print("INFO: Node({}) status:{} {}:{} try to execute again...\n".format(node.id, nodeStatus, node.host, node.port))
                                    execQueue.put(node)
                            else:
                                # 需要执行的节点实例加入等待执行队列
                                print("INFO: Node({}) status:{} {}:{} execute begin...\n".format(node.id, nodeStatus, node.host, node.port))
                                execQueue.put(node)

                        if phaseStatus.failNodeCount > 0 or self.context.hasFailNodeInGlobal == True:
                            try:
                                while True:
                                    execQueue.get_nowait()
                            except Exception as ex:
                                pass

                            break
                    except Exception as ex:
                        phaseStatus.incFailNodeCount()
                        if node is not None:
                            node.writeNodeLog("ERROR: Unknown error occurred\n{}\n".format(traceback.format_exc()))
                        else:
                            print("ERROR: Unknown error occurred\n{}\n".format(traceback.format_exc()))
        finally:
            # 入队对应线程数量的退出信号对象
            for worker in worker_threads:
                execQueue.put(None)

            # 等待所有worker线程退出
            for worker in worker_threads:
                worker.join()

            # if phaseStatus.hasRemote:
            #    print("INFO: Execute complete, successCount:{}, skipCount:{}, failCount:{}, ignoreCount:{}\n".format(phaseStatus.sucNodeCount, phaseStatus.skipNodeCount, phaseStatus.failNodeCount, phaseStatus.ignoreFailNodeCount))

        return phaseStatus.failNodeCount

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

        print("INFO: kill complete.\n")
