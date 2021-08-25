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
import datetime

import VContext
import PhaseStatus
import ServerAdapter
import AutoExecError
import Utils


class Context(VContext.VContext):
    def __init__(self, jobId, paramsFile=None, isForce=False, devMode=False, dataPath=None, noFireNext=False, passThroughEnv={}):
        VContext.VContext.__init__(self, jobId=jobId, isForce=isForce, devMode=devMode, dataPath=dataPath, noFireNext=noFireNext, passThroughEnv=passThroughEnv)

        self.dbclient = None
        self.db = None

        # 初始化ServerAdapter，用于调用后台的接口对接处理
        serverAdapter = ServerAdapter.ServerAdapter(self)
        self.serverAdapter = serverAdapter

        # cache目录如果不存在则创建
        cachePath = os.path.join(self.dataPath, 'cache')
        if not os.path.exists(cachePath):
            os.mkdir(cachePath)

        # 如果任务数据目录不存在，则创建目录
        if not os.path.exists(self.runPath):
            os.makedirs(self.runPath)

        # 获取运行参数和运行节点参数文件，如果命令行提供的文件路径则不到服务端进行下载
        if paramsFile is None or paramsFile == '':
            serverAdapter.getParams()
        else:
            self.localDefinedParams = True

            if not paramsFile.startswith('/'):
                paramsFile = os.path.join(self.runPath, paramsFile)
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
            self.jobId = '{}'.format(jobId)

        if 'execUser' in params:
            self.execUser = params['execUser']

        if 'tenant' in params:
            self.tenant = params['tenant']

        if 'opt' in params:
            self.opt = params['opt']

        # if 'arg' in params:
        #    self.arg = params['arg']

        if 'passThroughEnv' in params:
            self.passThroughEnv = params['passThroughEnv']

        paramFile.close()

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

    def loadEnv(self):
        db = self.db
        collection = db['autoexec_env']

        envs = {}
        try:
            pk = {'jobId': self.jobId}
            outData = collection.find_one(pk, {'data': True})

            for item in collection.find(pk, {'_id': 0, 'name': 1, 'value': 1}):
                os.environ[item['name']] = item['value']

        except Exception as ex:
            raise AutoExecError.AutoExecError('Can not load envirment, {}'.format(ex))

    def setEnv(self, name, value):
        os.environ[name] = value

        db = self.db
        collection = db['autoexec_env']
        pk = {'jobId': self.jobId, 'name': name}
        outData = {}
        outData['value'] = value
        outData['createDate'] = datetime.datetime.utcnow()
        outData.update(pk)

        try:
            collection.update(
                pk,
                {'$set':     outData},
                upsert=True
            )
        except Exception as ex:
            raise AutoExecError.AutoExecError('Can not save envirment {}={}, {}'.format(name, value, ex))

    def exportEnv(self, name):
        value = ''
        if name in os.environ:
            value = os.environ[name]
        self.serverAdapter.exportEnv(name, value)

    def getNodesFilePath(self, phaseName=None):
        nodesFilePath = None
        if phaseName is not None:
            nodesFilePath = '{}/nodes-{}.json'.format(self.runPath, phaseName)
        else:
            nodesFilePath = '{}/nodes.json'.format(self.runPath)
        return nodesFilePath

    def addPhase(self, phaseName):
        phase = PhaseStatus.PhaseStatus(phaseName)
        phase.nodesFilePath = self.getNodesFilePath()
        self.phases[phaseName] = phase
