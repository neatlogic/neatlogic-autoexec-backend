#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 提供读取节点文件，遍历节点，更新节点运行状态功能
"""
import sys
import os
import queue
import json
import Utils


class PhaseNodeFactory:

    def __init__(self, context, parallelCount):
        self.context = context
        self.parallelCount = parallelCount
        self.nodeQueue = queue.Queue(parallelCount + 1)

    def nextRunNode(self):
        node = None
        while self.context.goToStop == False:
            try:
                node = self.nodeQueue.get(timeout=5)
                if node is None:
                    break
            except Exception as ex:
                pass

        return node

    def putRunNode(self, runNode):
        self.nodeQueue.put(runNode)

    def localRunNode(self):
        self.nextRunNode()
