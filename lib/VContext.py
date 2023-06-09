#!/usr/bin/python3
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
    def __init__(self, jobId=0, execUser=None, isForce=False, devMode=False, dataPath=None, runPath=None, noFireNext=False, passThroughEnv={}):
        self.jobId = str(jobId)
        self.pid = os.getpid()

        self.dbclient = None
        self.db = None

        if execUser is not None:
            self.execUser = execUser

        self.params = {}
        self.runnerId = 1
        self.tenant = 'none'
        self.phases = {}
        self.opt = {}
        self.maxExecSecs = 86400
        self.rexecConnTimeout = 60
        self.rexecReadTimeout = 3600
        self.rexecWriteTimeout = 60
        self.isForce = isForce
        self.devMode = devMode
        self.dataPath = dataPath
        self.runPath = runPath
        self.noFireNext = noFireNext
        self.passThroughEnv = passThroughEnv

        self.fileFeteched = {}
        self.scriptFetched = {}
        self.opFetched = {}

        self.goToStop = False
        # 用于标记全局是否有失败的节点
        self.hasFailNodeInGlobal = False

        homePath = os.path.split(os.path.realpath(__file__))[0]
        homePath = os.path.realpath(homePath + '/..')
        self.homePath = homePath

        if 'tenant' in passThroughEnv:
            self.tenant = passThroughEnv['tenant']
        else:
            self.tenant = os.getenv('tenant')
            if not self.tenant or self.tenant == '':
                self.tenant = os.getenv('TENANT')
        if self.tenant is None:
            self.tenant = 'none'

        if 'runnerId' in passThroughEnv:
            self.runnerId = int(passThroughEnv['runnerId'])
            os.environ['RUNNER_ID'] = str(self.runnerId)
        elif 'RUNNER_ID' in os.environ:
            self.runnerId = int(os.getenv('RUNNER_ID'))

        # 存放执行数据以及日志的根目录
        if (dataPath == None):
            self.dataPath = homePath + "/data"
        else:
            self.dataPath = dataPath

        # 读取配置
        cfgPath = homePath + '/conf/config.ini'
        cfg = configparser.ConfigParser()
        cfg.optionxform = str
        cfg.read(cfgPath)

        config = {}
        self.config = config
        for section in cfg.sections():
            config[section] = {}
            for confKey in cfg[section]:
                config[section][confKey] = cfg[section][confKey]

        self.failReserveDir = int(config['autoexec'].get('rexec.fail.reservedir', 0))
        self.maxExecSecs = int(config['autoexec'].get('job.maxExecSecs', 86400))
        self.rexecConnTimeout = int(config['autoexec'].get('rexec.connectTimeout', 60))
        self.rexecReadTimeout = int(config['autoexec'].get('rexec.readTimeout', 3600))
        self.rexecWriteTimeout = int(config['autoexec'].get('rexec.writeTimeout', 60))

        hasNoEncrypted = False
        # serverPass = cfg.get('server', 'server.password')
        serverPass = config['server']['server.password']
        # passKey = cfg.get('server', 'password.key')
        passKey = config['server']['password.key']
        # autoexecDBPass = cfg.get('autoexec', 'db.password')
        autoexecDBPass = config['autoexec'].get('db.password')

        MY_KEY = 'c3H002LGZRrseEPck9tsNgfXHJcl0USJ'
        if passKey.startswith('{ENCRYPTED}'):
            passKey = Utils._rc4_decrypt_hex(MY_KEY, passKey[11:])
            config['server']['password.key'] = passKey
        else:
            hasNoEncrypted = True
        self.passKey = passKey

        if serverPass.startswith('{ENCRYPTED}'):
            serverPass = Utils._rc4_decrypt_hex(self.passKey, serverPass[11:])
            config['server']['server.password'] = serverPass
        else:
            hasNoEncrypted = True

        if autoexecDBPass and autoexecDBPass.startswith('{ENCRYPTED}'):
            autoexecDBPass = Utils._rc4_decrypt_hex(self.passKey, autoexecDBPass[11:])
            config['autoexec']['db.password'] = autoexecDBPass
        else:
            hasNoEncrypted = True

        os.environ['DEPLOY_POSSIBLE_ENCS'] = config['autoexec']['deploy.possibleEncodings']

        if hasNoEncrypted:
            serverPass = config['server']['server.password']
            passKey = config['server']['password.key']
            autoexecDBPass = config['autoexec'].get('db.password')

            if not passKey.startswith('{ENCRYPTED}'):
                cfg.set('server', 'password.key', '{ENCRYPTED}' + Utils._rc4_encrypt_hex(MY_KEY, self.passKey))

            if not serverPass.startswith('{ENCRYPTED}'):
                cfg.set('server', 'server.password', '{ENCRYPTED}' + Utils._rc4_encrypt_hex(self.passKey, serverPass))

            if autoexecDBPass and not autoexecDBPass.startswith('{ENCRYPTED}'):
                cfg.set('autoexec', 'db.password', '{ENCRYPTED}' + Utils._rc4_encrypt_hex(self.passKey, autoexecDBPass))

            with FileLock(cfgPath):
                fp = open(cfgPath, 'w')
                cfg.write(fp)
                fp.close()

        # 存放任务参数，输入输出信息，日志的目录，为了避免单目录子目录数量太多，对ID进行每3个字母分段处理
        if runPath is None:
            self.runPath = self.dataPath + '/job/' + self._getSubPath(jobId)

        os.environ['JOB_PATH'] = self.runPath
        self.paramsFilePath = self.runPath + '/params.json'
        os.environ['JOB_PARAMS_PATH'] = self.paramsFilePath

    def __del__(self):
        if self.dbclient is not None:
            self.dbclient.close()

    def _getSubPath(self, jobId):
        jobIdStr = str(jobId)
        jobIdLen = len(jobIdStr)
        subPath = [jobIdStr[i:i+3] for i in range(0, jobIdLen, 3)]
        return '/'.join(subPath)

    def initDB(self):
        dbUrl = self.config['autoexec']['db.url']
        maxPoolSize = int(self.config['autoexec']['db.maxPoolSize'])
        dbName = self.config['autoexec']['db.name']
        dbUsername = self.config['autoexec']['db.username']
        dbPassword = self.config['autoexec']['db.password']

        if maxPoolSize <= 0:
            maxPoolSize = 64

        if dbUrl is not None:
            mongoClient = pymongo.MongoClient(dbUrl, username=dbUsername, password=dbPassword, maxPoolSize=maxPoolSize)
            autoexecDB = mongoClient[dbName]

            self.dbclient = mongoClient
            self.db = autoexecDB
