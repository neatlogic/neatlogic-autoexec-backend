#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import logging
import threading
import subprocess
import queue
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

    def run(self):
        while True:
            # 获取节点，如果节点是NoneType，则所有节点已经完成运行
            node = self._queue.get()
            if node is None:
                break

            # 运行完所有操作
            ret = node.execute(self.operations)
            if ret != 0:
                self.context.failNodeCount = self.context.failNodeCount + 1
                print("INFO: Node({}) {}:{} execute failed.".format(node.id, node.host, node.port))
            else:
                self.context.sucNodeCount = self.context.sucNodeCount + 1
                print("INFO: Node({}) {}:{} execute succeed.".format(node.id, node.host, node.port))


class TaskExecutor:
    def __init__(self, context, operations, parallelCount=25):
        self.context = context
        self.operations = operations
        self.parallelCount = parallelCount

    def _buildWorkerPool(self, queue):
        workers = []
        for _ in range(self.parallelCount):
            worker = TaskWorker(self.context, self.operations, queue)
            worker.start()
            workers.append(worker)
        return workers

    def execute(self):
        worker_threads = []
        try:
            nodesFactory = RunNodeFactory.RunNodeFactory(self.context)
            if nodesFactory.nodesCount > 0 and nodesFactory.nodesCount < self.parallelCount:
                self.parallelCount = nodesFactory.nodesCount

            # 初始化队列，设置最大容量为节点运行并行度的两倍，避免太多节点数据占用内存
            execQueue = queue.Queue(self.parallelCount*2)
            # 创建线程池
            worker_threads = self._buildWorkerPool(execQueue)

            # 把执行节点放到线程池的待处理队列中
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

            print("INFO: Execute complete, success nodes count:{}, skip nodes count:{}, failed nodes count:{}".format(self.context.sucNodeCount, self.context.skipNodeCount, self.context.failNodeCount))
        return self.context.failNodeCount
