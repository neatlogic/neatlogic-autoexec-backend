#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import logging
import threading
from threading import Thread
import subprocess
import queue
import copy
import json
import RunNodeFactory
import RunNode
import NodeStatus


class TaskWorker(threading.Thread):
    def __init__(self, context, operations, queue):
        threading.Thread.__init__(self)
        self.context = context
        self._queue = queue
        self.operations = operations
        self.currentNode = None

    def run(self):
        while True:
            # 获取节点，如果节点是NoneType，则所有节点已经完成运行
            node = self._queue.get()
            if node is None:
                break
            self.currentNode = node

            try:
                # 运行完所有操作
                localOps = copy.copy(self.operations)  # 为了让每个节点都有独立的插件参数记录，复制operation
                ret = node.execute(localOps)
                if ret != 0:
                    self.context.failNodeCount = self.context.failNodeCount + 1
                    print("ERROR: Node({}) {}:{} execute failed.".format(node.id, node.host, node.port))
                else:
                    self.context.sucNodeCount = self.context.sucNodeCount + 1
                    print("INFO: Node({}) {}:{} execute succeed.".format(node.id, node.host, node.port))
            finally:
                self.currentNode = None

    def kill(self):
        if self.currentNode is not None:
            self.currentNode.kill()


class TaskExecutor:
    def __init__(self, context, operations, parallelCount=25):
        self.context = context
        self.operations = operations
        self.workers = []
        self.parallelCount = parallelCount

    def _buildWorkerPool(self, queue):
        workers = []
        for _ in range(self.parallelCount):
            worker = TaskWorker(self.context, self.operations, queue)
            worker.start()
            workers.append(worker)

        self.workers = workers
        return workers

    def execute(self):
        worker_threads = []
        try:
            nodesFactory = RunNodeFactory.RunNodeFactory(self.context)
            if nodesFactory.nodesCount > 0 and nodesFactory.nodesCount < self.parallelCount:
                self.parallelCount = nodesFactory.nodesCount

            if not self.context.hasRemote:
                self.parallelCount = 1

            # 初始化队列，设置最大容量为节点运行并行度的两倍，避免太多节点数据占用内存
            execQueue = queue.Queue(self.parallelCount*2)
            # 创建线程池
            worker_threads = self._buildWorkerPool(execQueue)

            # 如果有本地执行的插件（不是每个节点调用一次的插件）则虚构一个local的节点，直接执行
            if self.context.hasLocal:
                # 如果有local的操作，则往队列中压入local node，构造一个特殊的node
                localNode = {"nodeId": 0, "nodeType": "local", "host": "local-" + self.context.phase, "port": 0, "username": "", "password": ""}
                loalRunNode = RunNode.RunNode(self.context, localNode)

                if self.context.isForce:
                    # 需要执行的节点实例加入等待执行队列
                    execQueue.put(loalRunNode)
                else:
                    nodeStatus = loalRunNode.getNodeStatus()
                    if nodeStatus != NodeStatus.succeed:
                        # 需要执行的节点实例加入等待执行队列
                        print("INFO: Node({}) status:{} {}:{} execute begin...".format(loalRunNode.id, nodeStatus, loalRunNode.host, loalRunNode.port))
                        execQueue.put(loalRunNode)

            if self.context.hasRemote:
                # 然后逐个节点node调用remote或者localremote插件执行把执行节点放到线程池的待处理队列中
                while True:
                    node = nodesFactory.nextNode()
                    if node is None:
                        break

                    if self.context.isForce:
                        # 需要执行的节点实例加入等待执行队列
                        execQueue.put(node)
                    else:
                        nodeStatus = node.getNodeStatus()
                        if nodeStatus != NodeStatus.succeed:
                            # 需要执行的节点实例加入等待执行队列
                            print("INFO: Node({}) status:{} {}:{} execute begin...".format(node.id, nodeStatus, node.host, node.port))
                            execQueue.put(node)
                        else:
                            # 如果是成功状态，回写服务端，防止状态不一致
                            self.context.skipNodeCount = self.context.skipNodeCount + 1
                            print("INFO: Node({}) status:{} {}:{} had been execute succeed, skip.".format(node.id, nodeStatus, node.host, node.port))
                            try:
                                self.context.serverAdapter.pushNodeStatus(node, nodeStatus)
                            except Exception as ex:
                                logging.error('RePush node status to server failed, {}'.format(ex))
        finally:
            # 入队对应线程数量的退出信号对象
            for worker in worker_threads:
                execQueue.put(None)

            # 等待所有worker线程退出
            for worker in worker_threads:
                worker.join()

            if self.context.hasRemote:
                print("INFO: Execute complete, success nodes count:{}, skip nodes count:{}, failed nodes count:{}".format(self.context.sucNodeCount, self.context.skipNodeCount, self.context.failNodeCount))

        return self.context.failNodeCount

    def kill(self):
        self.context.goToStop = True
        killWorkers = []
        for worker in self.workers:
            try:
                t = Thread(target=worker.kill, args=())
                t.start()
                killWorkers.append(t)
            except:
                print("ERROR: unable to start thread to kill woker\n")

        for t in killWorkers:
            t.join()

        print("INFO: kill complete.")
