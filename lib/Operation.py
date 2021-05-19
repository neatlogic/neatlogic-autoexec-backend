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
import AutoExecError
import ServerAdapter


class Operation:

    def __init__(self, context, opsParam, param):
        self.context = context
        self.jobId = context.jobId
        self.opsParam = opsParam
        self.opId = param['opId']
        self.opName = param['opName']
        self.isScript = 0
        self.interpreter = ''
        self.scriptId = ''

        # opType有三种
        # remote：推送到远程主机上运行，每个目标节点调用一次
        # localremote：在本地连接远程节点运行（插件通过-node参数接受单个当前运行node的参数），每个目标节点调用一次
        # local：在本地运行，与运行节点无关，只会运行一次
        self.opType = param['opType']
        self.opTypeDesc = {
            "local": "Runner本地执行",
            "remote": "远程执行",
            "localremote": "Runner本地连接远程执行"
        }

        self.extNameMap = {
            'perl': '.pl',
            'python': '.py',
            'ruby': '.rb',
            'cmd': '.bat',
            'powershell': '.ps1',
            'vbscript': '.vbs',
            'javascript:': '.js'
        }

        # 把runner、target、runner_target转换为local、remote、localremote
        if self.opType == 'runner':
            self.opType = 'local'

        elif self.opType == 'target':
            self.opType = 'remote'
        elif self.opType == 'runner_target':
            self.opType = 'localremote'
        ##############

        if 'isScript' in param:
            self.isScript = param['isScript']
            if 'scriptId' in param:
                self.scriptId = param['scriptId']
        if 'interpreter' in param:
            self.interpreter = param['interpreter']

        # failIgnore参数，用于插件运行失败不影响后续插件运行
        self.failIgnore = False
        if 'failIgnore' in param:
            self.failIgnore = param['failIgnore']

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
        self.remotePluginRootPath = self.pluginRootPath + os.path.sep + 'remote'
        self.remoteLibPath = '{}/plugins/remote/lib'.format(self.context.homePath)

        self.pluginPath = None
        self.pluginParentPath = None

        if self.isScript == 1:
            scriptFileName = self.opName + self.extNameMap[self.interpreter]

            self.pluginParentPath = '{}/plugins/script'.format(self.context.homePath)
            self.pluginPath = '{}/{}'.format(self.pluginParentPath, scriptFileName)

        else:
            if self.opType == 'remote':
                self.pluginParentPath = '{}/plugins/remote/{}'.format(self.context.homePath, self.opName)
                self.pluginPath = '{}/{}'.format(self.pluginParentPath, self.opName)
            else:
                self.pluginParentPath = '{}/plugins/local/{}'.format(self.context.homePath, self.opName)
                self.pluginPath = '{}/{}'.format(self.pluginParentPath, self.opName)

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

    # 分析操作参数进行相应处理
    def parseParam(self, refMap=None):
        opDesc = {}
        if 'desc' in self.param:
            opDesc = self.param['desc']

        opArgs = self.param['arg']

        for argName, argValue in opArgs.items():
            argValue = self.resolveArgValue(argValue, refMap=refMap)
            if argName in opDesc:
                argType = opDesc[argName]
                if(argType == 'password' and argValue[0:5] == '{RC4}'):
                    try:
                        argValue = Utils._rc4_decrypt_hex(self.passKey, argValue[5:])
                    except:
                        print("WARN: Decrypt password arg:{}->{} failed.\n".format(self.opName, argName))
                elif(argType == 'file'):
                    matchObj = re.match(r'^\s*\$\{', argValue)
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
            os.link(cacheFilePath, linkPath)

        return fileName

    # 获取script
    def fetchScript(self, scriptId, savePath):
        savePath = '{}/script/{}.{}'.format(self.pluginRootPath, scriptId, self.extNameMap[self.interpreter])
        serverAdapter = self.context.serverAdapter
        serverAdapter.fetchFile(savePath, scriptId)

    def resolveArgValue(self, argValue, refMap=None):
        if not refMap:
            refMap = self.context.output

        # 如果参数引用的是当前作业的参数（变量格式不是${opId.varName}），则从全局参数表中获取参数值
        matchObj = re.match(r'^\s*\$\{\s*([^\.]+)\s*\}\s*$', argValue)
        if matchObj:
            paramName = matchObj.group(1)
            nativeRefMap = self.context.arg
            if paramName in nativeRefMap:
                argValue = nativeRefMap[paramName]
            else:
                raise AutoExecError.AutoExecError("Can not resolve param " + argValue)
        else:
            # 变量格式是：${opId.varName}，则是在运行过程中产生的内部引用参数
            matchObj = re.match(r'^\s*\$\{\s*(.+)\s*\}\s*$', argValue)
            if matchObj:
                varName = matchObj.group(1)
                varNames = varName.split('.', 3)
                newArgValue = None
                opId = None
                paramName = None
                if len(varNames) == 3:
                    opId = varNames[1]
                    paramName = varNames[2]
                else:
                    opId = varNames[0]
                    paramName = varNames[1]

                if opId in refMap:
                    paramMap = refMap[opId]
                    if paramName in paramMap:
                        newArgValue = paramMap[paramName]

                if newArgValue is not None:
                    argValue = newArgValue
                else:
                    raise AutoExecError.AutoExecError("Can not resolve param " + argValue)

        return argValue

    def getCmdLine(self, fullPath=False, osType='linux'):
        cmd = None
        if self.isScript:
            if self.opType == 'remote':
                # 如果自定义脚本远程执行，为了避免中文名称带来的问题，使用opId来作为脚本文件的名称
                if osType == 'windows':
                    # 如果是windows，windows的脚本执行必须要脚本具备扩展名,自定义脚本下载时会自动加上扩展名
                    if self.interpreter == 'cmd':
                        cmd = 'cmd /c {}'.format(self.opId)
                    elif self.interpreter == 'vbscript' or self.interpreter == 'javascript':
                        cmd = 'cscript {}'.format(self.opId)
                    else:
                        cmd = '{} {}'.format(self.interpreter, self.opId)
                else:
                    cmd = '{} {}'.format(self.interpreter, self.opId)
            else:
                if fullPath:
                    cmd = '{} {}'.format(self.interpreter, self.pluginPath)
                else:
                    cmd = '{} {}'.format(self.interpreter, self.opName)
        else:
            # 如果是内置的插件，则不会使用中文命名，同时如果是windows使用的工具会默认加上扩展名
            if self.opType == 'remote':
                if osType == 'windows':
                    # 如果是windows，windows的脚本执行必须要脚本具备扩展名
                    extName = self.extNameMap[self.interpreter]
                    nameWithExt = self.opName
                    if self.opName.endswith(extName):
                        nameWithExt = self.opName + extName
                        if self.interpreter == 'cmd':
                            cmd = 'cmd /c {}'.format(self.opName)
                        elif self.interpreter == 'vbscript' or self.interpreter == 'javascript':
                            cmd = 'cscript {}'.format(self.opName)
                        else:
                            cmd = '{} {}'.format(self.interpreter, self.opName)
                    else:
                        if self.interpreter == 'cmd':
                            cmd = 'rename {} {} && cmd /c {}'.format(self.opName, nameWithExt, nameWithExt)
                        elif self.interpreter == 'vbscript' or self.interpreter == 'javascript':
                            cmd = 'rename {} {} && cscript {}'.format(self.opName, nameWithExt, nameWithExt)
                        else:
                            cmd = 'rename {} {} && {} {}'.format(self.opName, nameWithExt, self.interpreter, self.opName)
                else:
                    cmd = '{} {}'.format(self.interpreter, self.opName)
            else:
                if fullPath:
                    cmd = self.pluginPath
                else:
                    cmd = self.opName

        for k, v in self.options.items():
            isNodeParam = False
            if 'desc' in self.param and k in self.param['desc']:
                kDesc = self.param['desc'][k]
                if kDesc.lower() == 'node':
                    isNodeParam = True

            if isNodeParam:
                cmd = cmd + ' --{} \'{}\' '.format(k, v)
            elif len(k) == 1:
                cmd = cmd + ' -{} "{}" '.format(k, v)
            else:
                cmd = cmd + ' --{} "{}" '.format(k, v)

        return cmd

    def getCmdLineHidePassword(self):
        cmd = None
        if self.isScript:
            cmd = self.interpreter + ' ' + self.opName
        else:
            cmd = self.opName

        for k, v in self.options.items():
            isNodeParam = False
            if 'desc' in self.param and k in self.param['desc']:
                kDesc = self.param['desc'][k]
                if kDesc.lower() == 'node':
                    isNodeParam = True

            if k == 'password' or k == 'pass':
                cmd = cmd + ' --{} "{}" '.format(k, '******')
            else:
                if isNodeParam:
                    cmd = cmd + ' --{} \'{}\' '.format(k, v)
                elif len(k) == 1:
                    cmd = cmd + ' -{} "{}" '.format(k, v)
                else:
                    cmd = cmd + ' --{} "{}" '.format(k, v)
        return cmd
