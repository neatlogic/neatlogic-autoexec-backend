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

    def __init__(self, context, param):
        self.context = context
        self.stepId = context.stepId
        self.taskId = context.taskId
        self.opId = param['opId']
        self.opName = param['opName']
        self.runPath = context.runPath
        self.dataPath = context.dataPath
        self.passKey = context.config.get('server', 'password.key')
        self.param = param
        if not 'isLocal' in param:
            self.isLocal = False
        elif param['isLocal'].lower() == 'true':
            self.isLocal = True
        else:
            self.isLocal = False

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
            argType = opDesc[argName]
            if(argType == 'password' and argValue[0:5] == '{RC4}'):
                argValue = Utils.Utils.rc4(self.passKey, argValue[5:])
            elif(argType == 'file'):
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

        linkPath = self.runPath + '/file/' + fileName
        if not os.path.exists(linkPath):
            os.symlink(cachePath + '/' + fileId, linkPath)

        return fileName

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
