#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import threading
import configparser
import ServerAdapter


class Context:
    def __init__(self, jobId, isForce=False, failBreak=False, devMode=False, dataPath=None):
        self.jobId = jobId
        self.tenant = ''
        self.arg = {}
        self.output = {}
        #self.output['local'] = {}
        self.phase = 'pre'
        self.isForce = isForce
        self.failBreak = failBreak
        self.devMode = devMode
        self.dataPath = dataPath
        self.passThroughEnv = {}

        self.goToStop = False

        self.hasLocal = False
        self.hasRemote = False

        self.failNodeCount = 0
        self.failNodeCountLock = threading.Lock()
        self.sucNodeCount = 0
        self.sucNodeCountLock = threading.Lock()
        self.skipNodeCount = 0
        self.skipNodeCountLock = threading.Lock()

        homePath = os.path.split(os.path.realpath(__file__))[0]
        homePath = os.path.realpath(homePath + '/..')
        self.homePath = homePath

        # 存放执行数据以及日志的根目录
        if (dataPath == None):
            self.dataPath = homePath + "/data"
        else:
            self.dataPath = dataPath

        # 存放任务参数，输入输出信息，日志的目录，为了避免单目录子目录数量太多，对ID进行每3个字母分段处理
        self.runPath = self.dataPath + '/job/' + self._getSubPath(jobId)
        os.environ['JOB_PATH'] = self.runPath
        self.paramsFilePath = self.runPath + '/params.json'
        os.environ['JOB_PARAMS_PATH'] = self.paramsFilePath
        self.nodesFilePath = self.runPath + '/nodes.json'
        os.environ['JOB_NODES_PATH'] = self.nodesFilePath

        # 如果任务数据目录不存在，则创建目录
        if not os.path.exists(self.runPath):
            os.makedirs(self.runPath)

        # 读取配置
        cfgPath = homePath + '/conf/config.ini'
        cfg = configparser.ConfigParser()
        cfg.read(cfgPath)
        self.config = cfg

        serverAdapter = ServerAdapter.ServerAdapter(self)
        self.serverAdapter = serverAdapter

    def _getSubPath(self, jobId):
        jobIdStr = str(jobId)
        jobIdLen = len(jobIdStr)
        subPath = [jobIdStr[i:i+3] for i in range(0, jobIdLen, 3)]
        return '/'.join(subPath)

    def incFailNodeCount(self):
        with self.failNodeCountLock:
            self.failNodeCount += 1
            return self.failNodeCount

    def incSucNodeCount(self):
        with self.sucNodeCountLock:
            self.sucNodeCount += 1
            return self.sucNodeCount

    def incSkipNodeCount(self):
        with self.skipNodeCountLock:
            self.skipNodeCount += 1
            return self.skipNodeCount

    def setPhase(self, phaseName):
        self.phase = phaseName
        self.nodesFilePath = '{}/nodes-{}.json'.format(self.runPath, phaseName)
        os.environ['JOB_NODES_PATH'] = self.nodesFilePath

    def resetCounter(self):
        self.skipNodeCount = 0
        self.failNodeCount = 0
        self.sucNodeCount = 0
