#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
from filelock import FileLock
import json
from shutil import copyfile
import datetime

import VContext
import PhaseStatus
import ServerAdapter
import AutoExecError


class Context(VContext.VContext):
    def __init__(self, jobId, execUser=None, paramsFile=None, firstFire=False, phaseGroups='', phases='', nodes='', isForce=False, devMode=False, dataPath=None, noFireNext=False, passThroughEnv={}):
        super().__init__(jobId=jobId, execUser=execUser, isForce=isForce, devMode=devMode, dataPath=dataPath, noFireNext=noFireNext, passThroughEnv=passThroughEnv)

        self.firstFire = firstFire

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

        paramsLoaded = False
        # 获取运行参数和运行节点参数文件，如果命令行提供的文件路径则不到服务端进行下载
        if firstFire or not os.path.exists(self.paramsFilePath):
            if paramsFile is None or paramsFile == '':
                self.params = serverAdapter.getParams()
                paramsLoaded = True
            else:
                if not paramsFile.startswith('/'):
                    paramsFile = os.path.join(self.runPath, paramsFile)
                # 如果指定的参数文件存在，而且目录不是params文件最终的存放目录，则拷贝到最终的存放目录
                if os.path.exists(paramsFile):
                    if self.paramsFilePath != os.path.realpath(paramsFile):
                        copyfile(paramsFile, self.paramsFilePath)
                else:
                    print("ERROR: Params file:{} not exists.\n".format(paramsFile), end='')

        if paramsLoaded == False:
            # 加载运行参数文件
            fd = None
            try:
                fd = open(self.paramsFilePath, 'r')
                self.params = json.loads(fd.read())
            except Exception as ex:
                print('ERROR: Load params from file {} failed.\n{}\n'.format(self.paramsFilePath, ex), end='')
            finally:
                if fd is not None:
                    fd.close()

        params = self.params
        if 'jobId' in params:
            jobId = params['jobId']
            self.jobId = str(jobId)

        if self.execUser is None:
            if 'execUser' in params and params['execUser'] != 'system':
                self.execUser = params['execUser']
            else:
                self.execUser = 'anonymouse'

        if 'tenant' in params:
            self.tenant = params['tenant']
        if self.tenant is None:
            self.tenant = 'none'

        if 'opt' in params:
            self.opt = params['opt']
        else:
            self.opt = {}

        if 'globalOpt' in params:
            self.globalOpt = params['globalOpt']
        else:
            self.globalOpt = {}

        if 'environment' in params:
            for k, v in params['environment'].items():
                if isinstance(v, object):
                    os.environ[k] = json.dumps(v, ensure_ascii=False)
                else:
                    os.environ[k] = v

        if 'passThroughEnv' in params:
            passThroughInParams = params['passThroughEnv']
            for key in self.passThroughEnv.keys():
                passThroughInParams[key] = self.passThroughEnv[key]
            self.passThroughEnv = passThroughInParams

        self.phaseGroupsToRun = None
        if phaseGroups != '':
            self.phaseGroupsToRun = {}
            for groupNo in phaseGroups.split(','):
                self.phaseGroupsToRun[int(groupNo)] = 1

        self.phasesToRun = None
        if phases != '':
            self.phasesToRun = {}
            for execPhase in phases.split(','):
                self.phasesToRun[execPhase] = 1

        self.nodesToRunCount = 0
        self.nodesToRun = None
        if nodes != '':
            self.nodesToRun = {}
            for execNode in nodes.split(','):
                self.nodesToRun[int(execNode)] = 1
                self.nodesToRunCount = self.nodesToRunCount + 1

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
        collection = db['_autoexec_env']

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
        collection = db['_autoexec_env']
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

    def getNodesFilePath(self, phaseName=None, groupNo=None):
        nodesFilePath = None
        if phaseName is not None:
            nodesFilePath = '{}/nodes-ph-{}.json'.format(self.runPath, phaseName)
        elif groupNo is not None:
            nodesFilePath = '{}/nodes-gp-{}.json'.format(self.runPath, groupNo)
        else:
            nodesFilePath = '{}/nodes.json'.format(self.runPath)
        return nodesFilePath

    def addPhase(self, phaseName):
        if self.phasesToRun is None or phaseName in self.phasesToRun:
            phase = PhaseStatus.PhaseStatus(phaseName)
            phase.nodesFilePath = self.getNodesFilePath()
            self.phases[phaseName] = phase

    def close(self):
        if self.dbclient:
            self.dbclient.close()
