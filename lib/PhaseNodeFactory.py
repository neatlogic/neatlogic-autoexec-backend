#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 提供读取节点文件，遍历节点，更新节点运行状态功能
"""
import queue


class PhaseNodeFactory:

    def __init__(self, context, parallelCount):
        self.context = context
        self.parallelCount = parallelCount
        self.nodeQueue = queue.Queue(parallelCount + 1)
        self.localNodeQueue = queue.Queue(5)

    def putRunNode(self, runNode):
        self.nodeQueue.put(runNode)

    def nextRunNode(self):
        node = None
        while self.context.goToStop == False:
            try:
                node = self.nodeQueue.get(timeout=5)
                return node
            except Exception as ex:
                pass
        return node

    def putLocalRunNode(self, localNode):
        self.localNodeQueue.put(localNode)

    def localRunNode(self):
        node = None
        while self.context.goToStop == False:
            try:
                node = self.localNodeQueue.get(timeout=5)
                return node
            except Exception as ex:
                pass
        return node
