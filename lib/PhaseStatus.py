#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 NeatLogic
"""

import threading


class PhaseStatus:
    def __init__(self, phaseName):
        # super().__init__()
        self.phaseName = phaseName
        self.localOutput = None
        # 用于标记当前phase是否有local或remote的工具
        self.execLocal = True
        self.hasLocal = False
        self.hasRemote = False
        # 某个节点执行完毕的Event
        self.roundFinEvent = threading.Event()
        self.globalRoundFinEvent = threading.Event()
        # 用于标记当前phase是否在pause或者abort状态中
        self.isAborting = 0
        self.isPausing = 0
        self.isComplete = 0
        # 用于标记当前runner的node的失败数量
        self.couterLock = threading.Lock()
        self.warnCountLock = threading.Lock()
        self.roundNo = 0
        self.execNodeCount = 0
        self.leftNodeCount = 0
        self.failNodeCount = 0
        self.ignoreFailNodeCount = 0
        self.sucNodeCount = 0
        self.pauseNodeCount = 0
        self.skipNodeCount = 0
        self.warnCount = 0

        # 用于记录phase的Executor
        self.executor = None
        self.nodesFilePath = None

    def incRoundCounter(self, taskCount):
        with self.couterLock:
            self.leftNodeCount += taskCount

    def setRoundFinEvent(self):
        self.roundFinEvent.set()

    def clearRoundFinEvent(self):
        self.roundFinEvent.clear()

    def waitRoundFin(self, timeOut=86400):
        execNodeCount = 0
        with self.couterLock:
            execNodeCount = self.leftNodeCount
        if execNodeCount == 0:
            return True
        else:
            return self.roundFinEvent.wait(timeout=timeOut)

    def setGlobalRoundFinEvent(self, roundNo=0):
        if roundNo == 0 or self.roundNo == roundNo:
            self.globalRoundFinEvent.set()

    def clearGlobalRoundFinEvent(self):
        self.globalRoundFinEvent.clear()

    def waitGlobalRoundFin(self, timeOut=86400):
        return self.globalRoundFinEvent.wait(timeout=timeOut)

    def produceEvent(self):
        self.execNodeCount += 1
        self.leftNodeCount -= 1
        if self.leftNodeCount <= 0:
            self.roundFinEvent.set()

    def incFailNodeCount(self):
        with self.couterLock:
            self.failNodeCount += 1
            self.produceEvent()
            return self.failNodeCount

    def incIgnoreFailNodeCount(self):
        with self.couterLock:
            self.ignoreFailNodeCount += 1
            self.produceEvent()
            return self.ignoreFailNodeCount

    def incPauseNodeCount(self):
        with self.couterLock:
            self.pauseNodeCount += 1
            self.produceEvent()
            return self.pauseNodeCount

    def incSucNodeCount(self):
        with self.couterLock:
            self.sucNodeCount += 1
            self.produceEvent()
            return self.sucNodeCount

    def incSkipNodeCount(self):
        with self.couterLock:
            self.skipNodeCount += 1
            self.produceEvent()
            return self.skipNodeCount

    def incWarnCount(self, warCount):
        with self.warnCountLock:
            self.warnCount += warCount
            return self.warnCount
