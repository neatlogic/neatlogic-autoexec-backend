#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 对操作插件参数进行处理，依据插件的参数描述信息进行相关处理：
 文件参数转换为对当前file子目录下文件路径名
 密码参数进行解密
"""
import sys
import os
import subprocess
import re
import json

import Utils
import ServerAdapter


class Operation:

    def __init__(self, context, opsParam, param):
        self.context = context
        self.stepId = context.stepId
        self.taskId = context.taskId
        self.opsParam = opsParam
        self.opId = param['opId']
        self.opName = param['opName']

        # opType有三种
        # remote：推送到远程主机上运行，每个目标节点调用一次
        # localremote：在本地连接远程节点运行（插件通过-node参数接受单个当前运行node的参数），每个目标节点调用一次
        # local：在本地运行，与运行节点无关，只会运行一次
        self.opType = param['opType']
        ##############

        self.runPath = context.runPath
        self.dataPath = context.dataPath
        self.passKey = context.config.get('server', 'password.key')
        self.param = param

        if 'output' in param:
            self.hasOutput = True
        else:
            self.hasOutput = False

        self.options = {}

        os.chdir(self.runPath)

        # 拼装执行的命令行
        self.pluginRootPath = '{}/plugins'.format(self.context.homePath)
        self.pluginPath = '{}/plugins/{}'.format(self.context.homePath, self.opId)

        self.parseParam()

        cmd = self.opId
        for k, v in self.options.items():
            cmd = cmd + ' --{} "{}" '.format(k, v)
        self.cmdline = cmd

        if not os.path.exists('file'):
            os.mkdir('file')

        if not os.path.exists('status'):
            os.mkdir('status')

        if not os.path.exists('log'):
            os.mkdir('log')

        if not os.path.exists('output'):
            os.mkdir('output')

    # 分析操作参数进行相应处理
    def parseParam(self):
        opDesc = self.param['desc']
        opArgs = self.param['arg']

        for argName, argValue in opArgs.items():
            argValue = self.resolveArgValue(argValue)
            argType = opDesc[argName]
            if(argType == 'password' and argValue[0:5] == '{RC4}'):
                argValue = Utils.rc4(self.passKey, argValue[5:])
            elif(argType == 'file'):
                matchObj = re.match(r'^\s*\$\{\s*(.+?)\.(.+)\s*\}\s*$', argValue)
                if not matchObj:
                    fileName = self.fetchFile(argName, argValue)
                    argValue = 'file/' + fileName
            self.options[argName] = argValue

        # print("DEBUG:{}".format(str(self.options)))

    # 如果参数是文件需要下载文件到本地cache目录并symlink到任务执行路径下的file目录下
    def fetchFile(self, argName, fileId):
        cachePath = self.dataPath + '/cache'
        serverAdapter = self.context.serverAdapter
        fileName = serverAdapter.fetchFile(cachePath, fileId)

        if fileName is None:
            fileName = argName

        cacheFilePath = cachePath + '/' + fileId
        linkPath = self.runPath + '/file/' + fileName
        if os.path.islink(linkPath) and os.path.realpath(linkPath) != cacheFilePath:
            os.unlink(linkPath)

        if not os.path.exists(linkPath):
            os.symlink(cacheFilePath, linkPath)

        return fileName

    def resolveArgValue(self, argValue, refMap=None):
        if not refMap:
            refMap = self.opsParam

        matchObj = re.match(r'^\s*\$\{\s*(.+?)\.(.+)\s*\}\s*$', argValue)
        while matchObj:
            newArgValue = None
            opId = matchObj.group(1)
            paramName = matchObj.group(2)
            if opId in refMap:
                paramMap = refMap[opId]
                if paramName in paramMap:
                    newArgValue = refMap[paramName]
            if newArgValue is not None:
                argValue = newArgValue
                matchObj = re.match(r'^\s*\$\{\s*(.+?)\.(.+)\s*\}\s*$', argValue)
            else:
                break
        return argValue

    def getCmdLine(self, refMap):
        cmd = self.opId
        for k, v in self.options.items():
            matchObj = re.match(r'^\s*\$\{\s*(.+?)\.(.+)\s*\}\s*$', v)
            if matchObj:
                opId = matchObj.group(1)
                paramName = matchObj.group(2)
                if opId in refMap:
                    paramMap = refMap[opId]
                    if paramName in paramMap:
                        v = refMap[paramName]

            cmd = cmd + ' --{} "{}" '.format(k, v)
        return cmd

    def getCmdLineHidePassword(self, refMap):
        cmd = self.opId
        for k, v in self.options.items():
            matchObj = re.match(r'^\s*\$\{\s*(.+?)\.(.+)\s*\}\s*$', v)
            if matchObj:
                opId = matchObj.group(1)
                paramName = matchObj.group(2)
                if opId in refMap:
                    paramMap = refMap[opId]
                    if paramName in paramMap:
                        v = refMap[paramName]

            if k == 'password' or k == 'pass':
                cmd = cmd + ' --{} "{}" '.format(k, '******')
            else:
                cmd = cmd + ' --{} "{}" '.format(k, v)
        return cmd
