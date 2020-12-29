#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import configparser
import ServerAdapter


class Context:
    def __init__(self, stepId, taskId, isForce=False, dataPath=None):
        self.stepId = stepId
        self.taskId = taskId
        self.phase = 'pre'
        self.isForce = isForce
        self.dataPath = dataPath

        self.goToStop = False

        self.hasLocal = False
        self.hasRemote = False
        self.failNodeCount = 0
        self.sucNodeCount = 0
        self.skipNodeCount = 0

        homePath = os.path.split(os.path.realpath(__file__))[0]
        homePath = os.path.realpath(homePath + '/..')
        self.homePath = homePath

        # 存放执行数据以及日志的根目录
        if (dataPath == None):
            self.dataPath = homePath + "/data"
        else:
            self.dataPath = dataPath

        # 存放任务参数，输入输出信息，日志的目录，为了避免单目录子目录数量太多，对ID进行每3个字母分段处理
        self.runPath = self.dataPath + '/task/' + self._getSubPath(stepId, taskId)
        self.paramsFilePath = self.runPath + '/params.json'
        self.nodesFilePath = self.runPath + '/nodes.json'

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

    def _getSubPath(self, stepId, taskId):
        stepIdStr = str(stepId)
        stepIdLen = len(stepIdStr)
        subPath = [stepIdStr[i:i+3] for i in range(0, stepIdLen, 3)]

        taskIdStr = str(taskId)
        taskIdLen = len(taskIdStr)
        subPath = subPath + [taskIdStr[i:i+3] for i in range(0, taskIdLen, 3)]
        return '/'.join(subPath)
