#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import threading
from filelock import FileLock
import configparser
import json
from shutil import copyfile
import pymongo

import PhaseStatus
import ServerAdapter
import Utils


class Context:
    def __init__(self, jobId, paramsFile=None, isForce=False, devMode=False, dataPath=None):
        self.MY_KEY = 'E!YO@JyjD^RIwe*OE739#Sdk%'
        self.jobId = jobId
        self.execUser = 'anonymous'
        self.params = {}
        self.parallelCount = 25
        self.tenant = ''
        self.phases = {}
        self.arg = {}
        self.output = {}
        #self.output['local'] = {}
        self.isForce = isForce
        self.devMode = devMode
        self.dataPath = dataPath
        self.passThroughEnv = {}
        self.dbclient = None

        self.goToStop = False
        # 用于标记全局是否有失败的节点
        self.hasFailNodeInGlobal = False

        homePath = os.path.split(os.path.realpath(__file__))[0]
        homePath = os.path.realpath(homePath + '/..')
        self.homePath = homePath

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

        # 初始化ServerAdapter，用于调用后台的接口对接处理
        serverAdapter = ServerAdapter.ServerAdapter(self)
        self.serverAdapter = serverAdapter

        # 存放任务参数，输入输出信息，日志的目录，为了避免单目录子目录数量太多，对ID进行每3个字母分段处理
        self.runPath = self.dataPath + '/job/' + self._getSubPath(jobId)
        os.environ['JOB_PATH'] = self.runPath
        self.paramsFilePath = self.runPath + '/params.json'
        os.environ['JOB_PARAMS_PATH'] = self.paramsFilePath

        # 如果任务数据目录不存在，则创建目录
        if not os.path.exists(self.runPath):
            os.makedirs(self.runPath)

        # 获取运行参数和运行节点参数文件，如果命令行提供的文件路径则不到服务端进行下载
        if paramsFile is None or paramsFile == '':
            serverAdapter.getParams()
        else:
            self.localDefinedParams = True
            # 如果指定的参数文件存在，而且目录不是params文件最终的存放目录，则拷贝到最终的存放目录
            dstPath = '{}/params.json'.format(self.runPath)
            if os.path.exists(paramsFile):
                if dstPath != os.path.realpath(paramsFile):
                    copyfile(paramsFile, dstPath)
            else:
                print("ERROR: Params file:{} not exists.\n".format(paramsFile))

        # 加载运行参数文件
        paramFile = open(self.paramsFilePath, 'r')
        params = json.loads(paramFile.read())
        self.params = params

        if 'jobId' in params:
            jobId = params['jobId']
            self.jobId = jobId

        if 'execUser' in params:
            self.execUser = params['execUser']

        if 'tenant' in params:
            self.tenant = params['tenant']

        if 'arg' in params:
            self.arg = params['arg']

        if 'passThroughEnv' in params:
            self.passThroughENv = params['passThroughEnv']

        paramFile.close()

        self.dbclient = None
        self.db = None

        os.chdir(self.runPath)

        if not os.path.exists('script'):
            os.mkdir('script')

        if not os.path.exists('file'):
            os.mkdir('file')

        if not os.path.exists('status'):
            os.mkdir('status')

        if not os.path.exists('log'):
            os.mkdir('log')

        if not os.path.exists('output'):
            os.mkdir('output')

        if not os.path.exists('output-op'):
            os.mkdir('output-op')

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

    def getNodesFilePath(self, phaseName=None):
        nodesFilePath = None
        if phaseName is not None:
            nodesFilePath = '{}/nodes-{}.json'.format(self.runPath, phaseName)
        else:
            nodesFilePath = '{}/nodes.json'.format(self.runPath)
        return nodesFilePath

    def addPhase(self, phaseName):
        phase = PhaseStatus.PhaseStatus(phaseName)
        self.phases[phaseName] = phase
