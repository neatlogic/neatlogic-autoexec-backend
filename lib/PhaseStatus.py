#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import threading


class PhaseStatus:
    def __init__(self, phaseName):
        super().__init__()
        self.phaseName = phaseName
        # 用于标记当前phase是否有local或remote的工具
        self.hasLocal = False
        self.hasRemote = False
        # 用于标记当前runner的node的失败数量
        self.failNodeCount = 0
        self.failNodeCountLock = threading.Lock()
        self.ignoreFailNodeCount = 0
        self.ignoreFailNodeCountLock = threading.Lock()
        self.sucNodeCount = 0
        self.sucNodeCountLock = threading.Lock()
        self.skipNodeCount = 0
        self.skipNodeCountLock = threading.Lock()
        # 用于记录phase的Executor
        self.executor = None
        self.nodesPath = None

    def incFailNodeCount(self):
        with self.failNodeCountLock:
            self.failNodeCount += 1
            return self.failNodeCount

    def incIgnoreFailNodeCount(self):
        with self.ignoreFailNodeCountLock:
            self.ignoreFailNodeCount += 1
            return self.ignoreFailNodeCount

    def incSucNodeCount(self):
        with self.sucNodeCountLock:
            self.sucNodeCount += 1
            return self.sucNodeCount

    def incSkipNodeCount(self):
        with self.skipNodeCountLock:
            self.skipNodeCount += 1
            return self.skipNodeCount
