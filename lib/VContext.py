#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 virtual context for serveradapter
"""
import os
from filelock import FileLock
import configparser
import pymongo

import Utils


class VContext:
    def __init__(self, jobId=0, execUser=None, isForce=False, devMode=False, dataPath=None, noFireNext=False, passThroughEnv={}):
        self.MY_KEY = 'E!YO@JyjD^RIwe*OE739#Sdk%'
        self.jobId = jobId
        self.pid = os.getpid()

        self.dbclient = None
        self.db = None

        if execUser is not None:
            self.execUser = execUser

        self.params = {}
        self.parallelCount = 25
        self.tenant = ''
        self.phases = {}
        self.opt = {}
        #self.arg = []
        #self.output = {}
        self.isForce = isForce
        self.devMode = devMode
        self.dataPath = dataPath
        self.noFireNext = noFireNext
        self.passThroughEnv = passThroughEnv

        self.goToStop = False
        # 用于标记全局是否有失败的节点
        self.hasFailNodeInGlobal = False

        homePath = os.path.split(os.path.realpath(__file__))[0]
        homePath = os.path.realpath(homePath + '/..')
        self.homePath = homePath

        self.tenant = os.getenv('tenant')
        if not self.tenant or self.tenant == '':
            self.tenant = os.getenv('TENANT')

        # 存放执行数据以及日志的根目录
        if (dataPath == None):
            self.dataPath = homePath + "/data"
        else:
            self.dataPath = dataPath

        # 读取配置
        cfgPath = homePath + '/conf/config.ini'
        cfg = configparser.ConfigParser()
        cfg.read(cfgPath)

        hasNoEncrypted = False
        serverPass = cfg.get('server', 'server.password')
        passKey = cfg.get('server', 'password.key')
        autoexecDBPass = cfg.get('autoexec', 'db.password')

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
            cfg.set('autoexec', 'db.password', autoexecDBPass)
        else:
            hasNoEncrypted = True

        self.config = cfg

        if hasNoEncrypted:
            mcfg = configparser.ConfigParser()
            mcfg.read(cfgPath)

            serverPass = mcfg.get('server', 'server.password')
            passKey = mcfg.get('server', 'password.key')
            autoexecDBPass = mcfg.get('autoexec', 'db.password')

            if not serverPass.startswith('{ENCRYPTED}'):
                mcfg.set('server', 'server.password', '{ENCRYPTED}' + Utils._rc4_encrypt_hex(self.MY_KEY, serverPass))

            if not passKey.startswith('{ENCRYPTED}'):
                mcfg.set('server', 'password.key', '{ENCRYPTED}' + Utils._rc4_encrypt_hex(self.MY_KEY, passKey))

            if not autoexecDBPass.startswith('{ENCRYPTED}'):
                mcfg.set('autoexec', 'db.password', '{ENCRYPTED}' + Utils._rc4_encrypt_hex(self.MY_KEY, autoexecDBPass))

            with FileLock(cfgPath):
                fp = open(cfgPath, 'w')
                mcfg.write(fp)
                fp.close()

        # 存放任务参数，输入输出信息，日志的目录，为了避免单目录子目录数量太多，对ID进行每3个字母分段处理
        self.runPath = self.dataPath + '/job/' + self._getSubPath(jobId)
        os.environ['JOB_PATH'] = self.runPath
        self.paramsFilePath = self.runPath + '/params.json'
        os.environ['JOB_PARAMS_PATH'] = self.paramsFilePath

    def _getSubPath(self, jobId):
        jobIdStr = str(jobId)
        jobIdLen = len(jobIdStr)
        subPath = [jobIdStr[i:i+3] for i in range(0, jobIdLen, 3)]
        return '/'.join(subPath)

    def initDB(self):
        # 初始化创建mongodb connect
        dbUrl = self.config.get('autoexec', 'db.url')
        maxPoolSize = self.config.get('autoexec', 'db.maxPoolSize')
        dbName = self.config.get('autoexec', 'db.name')
        dbUsername = self.config.get('autoexec', 'db.username')
        dbPassword = self.config.get('autoexec', 'db.password')
        if dbUrl is not None:
            mongoClient = pymongo.MongoClient(dbUrl, username=dbUsername, password=dbPassword, maxPoolSize=maxPoolSize)
            autoexecDB = mongoClient[dbName]

            self.dbclient = mongoClient
            self.db = autoexecDB
