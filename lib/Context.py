#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import threading
from filelock import FileLock
import configparser
import pymongo
import ServerAdapter
import Utils


class Context:
    def __init__(self, jobId, isForce=False, failBreak=False, devMode=False, dataPath=None):
        self.MY_KEY = 'E!YO@JyjD^RIwe*OE739#Sdk%'
        self.jobId = jobId
        self.parallelCount = 25
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

        # 用于标记全局是否有失败的节点
        self.hasFailNodeInGlobal = False

        # 用于标记当前runner的node的失败数量
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

        hasNoEncrypted = False
        serverPass = cfg.get('server', 'server.password')
        passKey = cfg.get('server', 'password.key')
        cmdbDBPass = cfg.get('cmdb-db', 'db.password')
        autoexecDBPass = cfg.get('autoexec-db', 'db.password')

        if serverPass.startswith('{ENCRYPTED}'):
            serverPass = Utils._rc4_decrypt_hex(self.MY_KEY, serverPass[11:])
            cfg.set('server', 'server.password', serverPass)
        else:
            hasNoEncrypted = True

        if passKey.startswith('{ENCRYPTED}'):
            passKey = Utils._rc4_decrypt_hex(self.MY_KEY, passKey[11:])
            cfg.set('server', 'password.key', passKey)
        else:
            hasNoEncrypted = True

        if autoexecDBPass.startswith('{ENCRYPTED}'):
            autoexecDBPass = Utils._rc4_decrypt_hex(self.MY_KEY, autoexecDBPass[11:])
            cfg.set('autoexec-db', 'db.password', autoexecDBPass)
        else:
            hasNoEncrypted = True

        if cmdbDBPass.startswith('{ENCRYPTED}'):
            cmdbDBPass = Utils._rc4_decrypt_hex(self.MY_KEY, cmdbDBPass[11:])
            cfg.set('cmdb-db', 'db.password', cmdbDBPass)
        else:
            hasNoEncrypted = True

        self.config = cfg

        if hasNoEncrypted:
            mcfg = configparser.ConfigParser()
            mcfg.read(cfgPath)

            serverPass = mcfg.get('server', 'server.password')
            passKey = mcfg.get('server', 'password.key')
            cmdbDBPass = mcfg.get('cmdb-db', 'db.password')
            autoexecDBPass = mcfg.get('autoexec-db', 'db.password')

            if not serverPass.startswith('{ENCRYPTED}'):
                mcfg.set('server', 'server.password', '{ENCRYPTED}' + Utils._rc4_encrypt_hex(self.MY_KEY, serverPass))

            if not passKey.startswith('{ENCRYPTED}'):
                mcfg.set('server', 'password.key', '{ENCRYPTED}' + Utils._rc4_encrypt_hex(self.MY_KEY, passKey))

            if not autoexecDBPass.startswith('{ENCRYPTED}'):
                mcfg.set('autoexec-db', 'db.password', '{ENCRYPTED}' + Utils._rc4_encrypt_hex(self.MY_KEY, autoexecDBPass))

            if not cmdbDBPass.startswith('{ENCRYPTED}'):
                mcfg.set('cmdb-db', 'db.password', '{ENCRYPTED}' + Utils._rc4_encrypt_hex(self.MY_KEY, cmdbDBPass))

            with FileLock(cfgPath):
                fp = open(cfgPath, 'w')
                mcfg.write(fp)
                fp.close()

        serverAdapter = ServerAdapter.ServerAdapter(self)
        self.serverAdapter = serverAdapter

        self.dbclient = None
        self.db = None

    def __del__(self):
        if self.dbclient is not None:
            self.dbclient.close()

    def initDB(self, parallelCount):
        # 初始化创建mongodb connect
        mongoClient = pymongo.MongoClient(self.config.get('autoexec-db', 'db.url'), maxPoolSize=parallelCount)
        autoexecDB = mongoClient[self.config.get('autoexec-db', 'db.name')]
        autoexecDB.authenticate(self.config.get('autoexec-db', 'db.username'), self.config.get('autoexec-db', 'db.password'))
        self.dbclient = mongoClient
        self.db = autoexecDB

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
