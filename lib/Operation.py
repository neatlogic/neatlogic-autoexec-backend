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
import fcntl
import stat
import subprocess
import re
import json

import Utils
import AutoExecError
import ServerAdapter


class Operation:

    def __init__(self, context, opsParam, param):
        self.context = context
        self.node = None
        self.jobId = context.jobId
        self.opsParam = opsParam
        self.isScript = 0
        self.scriptContent = None
        self.interpreter = ''
        self.lockedFDs = []

        self.opId = param['opId']

        opFullName = param['opName']
        self.opName = opFullName
        self.opSubName = os.path.basename(opFullName)

        opBunddleName = os.path.dirname(opFullName)
        if opBunddleName == '':
            self.opBunddleName = self.opName
        else:
            self.opBunddleName = opBunddleName

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
            'bash': '.sh',
            'ksh': '.sh',
            'csh': '.sh',
            'sh': '.sh',
            'javascript:': '.js'
        }

        # 把runner、target、runner_target、sqlfile转换为local、remote、localremote
        if self.opType == 'runner':
            self.opType = 'local'

        elif self.opType == 'target':
            self.opType = 'remote'
        elif self.opType == 'runner_target':
            self.opType = 'localremote'
        elif self.opType == 'sqlfile':
            self.opType = 'localremote'
        ##############

        if 'isScript' in param:
            self.isScript = param['isScript']
            if 'scriptContent' in param and param['scriptContent'] != '':
                self.scriptContent = param['scriptContent']

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
        self.arguments = []

        # 拼装执行的命令行
        self.pluginRootPath = '{}/plugins'.format(self.context.homePath)
        self.localLibPath = '{}/plugins/local/lib'.format(self.context.homePath)
        self.remotePluginRootPath = self.pluginRootPath + '/remote'
        self.remoteLibPath = '{}/plugins/remote/lib'.format(self.context.homePath)

        self.pluginPath = None
        self.pluginParentPath = None
        self.scriptFileName = None

        if self.isScript == 1:
            scriptName = self.opName
            if not self.opName.isascii():
                # 如果脚本名不是ascii的，则只使用其id来作为脚本名
                scriptName = self.opId.split('_')[-1]
                self.opBunddleName = scriptName

            scriptFileName = scriptName + self.extNameMap[self.interpreter]
            self.scriptFileName = scriptFileName
            self.pluginParentPath = '{}/script/{}'.format(self.context.runPath, self.opBunddleName)
            if not os.path.exists(self.pluginParentPath):
                os.mkdir(self.pluginParentPath)
            self.pluginPath = '{}/{}'.format(self.pluginParentPath, scriptFileName)
            self.fetchScript(self.pluginPath, self.opId)
        else:
            if self.opType == 'remote':
                self.pluginParentPath = '{}/plugins/remote/{}'.format(self.context.homePath, self.opBunddleName)
                self.pluginPath = '{}/{}'.format(self.pluginParentPath, self.opSubName)
            else:
                self.pluginParentPath = '{}/plugins/local/{}'.format(self.context.homePath, self.opBunddleName)
                self.pluginPath = '{}/{}'.format(self.pluginParentPath, self.opSubName)

        self.KEY = 'E!YO@JyjD^RIwe*OE739#Sdk%'

    def __del__(self):
        for fd in self.lockedFDs:
            fcntl.flock(fd, fcntl.LOCK_UN)
            fd.close()

    def setNode(self, node):
        self.node = node

    def writeLog(self, msg):
        if self.node:
            self.node.writeNodeLog(msg)
        else:
            print(msg, end='')

    # 分析操作参数进行相应处理
    def parseParam(self, refMap=None, resourceId=None, host=None, port=None):
        opDesc = {}
        if 'desc' in self.param:
            opDesc = self.param['desc']

        opOpts = self.param['opt']

        for optName, optValue in opOpts.items():
            optValue = self.resolveOptValue(optValue, refMap=refMap)
            if optName in opDesc:
                optType = opDesc[optName]
                if optType == 'password' and optValue[0:11] == '{ENCRYPTED}':
                    try:
                        optValue = Utils._rc4_decrypt_hex(self.KEY, optValue[11:])
                    except:
                        self.writeLog("WARN: Decrypt password option:{}->{} failed.\n".format(self.opName, optName))
                elif optType == 'account' and resourceId != '':
                    # format username/accountId
                    if optValue is not None and optValue != '':
                        accountDesc = optValue.split('/')
                        retObj = {}
                        try:
                            username = accountDesc[0]
                            accountId = accountDesc[1]
                            protocol = accountDesc[2]
                            password = self.context.serverAdapter.getAccount(resourceId, host, port, username, protocol, accountId)
                            optValue = username + '/' + Utils._rc4_decrypt_hex(self.KEY, password[11:])
                        except Exception as err:
                            self.writeLog("WARN: {}\n".format(err.value))

                elif optType == 'file':
                    matchObj = re.match(r'^\s*\$\{', '{}'.format(optValue))
                    if not matchObj:
                        fileNames = self.fetchFile(optName, optValue)
                        fileNamesJson = []
                        for fileName in fileNames:
                            fileNamesJson.append('file/' + fileName)
                        #optValue = json.dumps(fileNamesJson, ensure_ascii=False)
                        optValue = fileNamesJson
                self.options[optName] = optValue

        if 'arg' in self.param and 'values' in self.param['arg']:
            opArgs = self.param['arg']
            argType = self.param['arg']['type']
            argValues = []
            for argValue in opArgs['values']:
                argValue = self.resolveOptValue(argValue, refMap=refMap)
                if(argType == 'password' and argValue[0:11] == '{ENCRYPTED}'):
                    try:
                        argValue = Utils._rc4_decrypt_hex(self.KEY, argValue[11:])
                    except:
                        self.writeLog("WARN: Decrypt password argument:{} failed.\n".format(self.opName))
                elif(argType == 'file'):
                    matchObj = re.match(r'^\s*\$\{', '{}'.format(argValue))
                    if not matchObj:
                        fileNames = self.fetchFile(optName, argValue)
                        fileNamesJson = []
                        for fileName in fileNames:
                            fileNamesJson.append('file/' + fileName)
                        #argValue = json.dumps(fileNamesJson, ensure_ascii=False)
                        argValue = fileNamesJson
                argValues.append(argValue)
            self.arguments = argValues

    # 如果参数是文件需要下载文件到本地cache目录并symlink到任务执行路径下的file目录下
    def fetchFile(self, optName, fileIds):
        cachePath = self.dataPath + '/cache'
        serverAdapter = self.context.serverAdapter

        fileNamesArray = []
        for fileId in fileIds:
            if isinstance(fileId, str):
                continue

            fileName = serverAdapter.fetchFile(cachePath, fileId)

            if fileName is not None:
                cacheFilePath = '{}/{}'.format(cachePath, fileId)

                linkPath = self.runPath + '/file/' + fileName

                cacheFile = None
                try:
                    cacheFile = open(cacheFilePath, 'r')
                    fcntl.flock(cacheFile, fcntl.LOCK_EX)
                    if os.path.exists(linkPath):
                        if not os.path.samefile(linkPath, cacheFilePath):
                            os.unlink(linkPath)
                            os.link(cacheFilePath, linkPath)
                    else:
                        os.link(cacheFilePath, linkPath)
                finally:
                    if cacheFile is not None:
                        fcntl.flock(cacheFile, fcntl.LOCK_UN)
                        cacheFile.close()

                fileNamesArray.append(fileName)

        return fileNamesArray

    # 获取script
    def fetchScript(self, savePath, opId):
        if self.scriptContent:
            filePathTmp = savePath + '.tmp'
            fileTmp = open(filePathTmp, 'a+')
            fcntl.lockf(fileTmp, fcntl.LOCK_EX)
            fileTmp.truncate(0)
            fileTmp.write(self.scriptContent)

            if os.path.exists(savePath):
                os.unlink(savePath)
            os.rename(filePathTmp, savePath)
        else:
            serverAdapter = self.context.serverAdapter
            serverAdapter.fetchScript(savePath, opId)

    def resolveOptValue(self, optValue, refMap=None):
        if not isinstance(optValue, str):
            return optValue

        if not refMap:
            refMap = self.node.output

        # 如果参数引用的是当前作业的参数（变量格式不是${opId.varName}），则从全局参数表中获取参数值
        matchObj = re.match(r'^\s*\$\{\s*([^\{\}]+)\s*\}\s*$', optValue)
        if matchObj:
            paramName = matchObj.group(1)

            nativeRefMap = self.context.opt
            globalOptMap = self.globalOpt
            if paramName in nativeRefMap:
                optValue = nativeRefMap[paramName]
            elif paramName in globalOptMap:
                optValue = globalOptMap[paramName]
            elif paramName in os.environ:
                optValue = os.environ[paramName]
            else:
                newArgValue = None
                opId = None
                paramName = None
                # 变量格式是：${opBunndle/opId.varName}，则是在运行过程中产生的内部引用参数
                varNames = paramName.split('.', 1)
                if len(varNames) == 2:
                    opId = varNames[0]
                    paramName = varNames[1]

                    if opId in refMap:
                        paramMap = refMap[opId]
                        if paramName in paramMap:
                            newArgValue = paramMap[paramName]

                if newArgValue is not None:
                    optValue = newArgValue
                else:
                    raise AutoExecError.AutoExecError("Can not resolve param " + optValue)

        return optValue

    def appendCmdArgs(self, cmd, noPassword=False, osType='linux'):
        argDesc = 'input'
        if 'arg' in self.param and 'type' in self.param['arg']:
            argDesc = self.param['arg']['type'].lower()

        if noPassword and argDesc == 'password':
            for argValue in self.arguments:
                cmd = cmd + ' "******"'
        elif argDesc in ('node', 'json', 'file', 'multiselect'):
            for argValue in self.arguments:
                jsonStr = jsonStr.dumps(argValue)
                if (osType == 'windows'):
                    jsonStr = jsonStr.replace('\\', '\\\\')
                    jsonStr = jsonStr.replace('"', '\\"')
                    cmd = cmd + ' "{}"'.format(jsonStr)
                else:
                    jsonStr = jsonStr.replace("'", "'\\''")
                    cmd = cmd + " '{}'".format(jsonStr)
        elif argDesc == 'password':
            for argValue in self.arguments:
                if osType == 'windows':
                    argValue = argValue.replace('\\', '\\\\')
                    argValue = argValue.replace('"', '\\"')
                    cmd = cmd + ' "{}"'.format(argValue)
                else:
                    argValue = argValue.replace("'", "'\\''")
                    cmd = cmd + " '{}'".format(argValue)
        else:
            for argValue in self.arguments:
                argValue = argValue.replace('\\', '\\\\')
                argValue = argValue.replace('"', '\\"')
                cmd = cmd + ' "{}"'.format(argValue)

        return cmd

    def appendCmdOpts(self, cmd, noPassword=False, osType='linux'):
        for k, v in self.options.items():
            if v == "" or v is None:
                continue

            kDesc = None
            if 'desc' in self.param and k in self.param['desc']:
                kDesc = self.param['desc'][k].lower()

            if noPassword and (kDesc == 'password' or k.endswith('account')):
                cmd = cmd + ' --{} "{}" '.format(k, '******')
            else:
                if kDesc in ('node', 'json', 'file', 'multiselect'):
                    jsonStr = json.dumps(v)
                    if osType == 'windows':
                        jsonStr = jsonStr.replace('\\', '\\\\')
                        jsonStr = jsonStr.replace('"', '\\"')
                        cmd = cmd + " --{} '{}' ".format(k, jsonStr)
                    else:
                        jsonStr = jsonStr.replace("'", "'\\''")
                        cmd = cmd + " --{} '{}' ".format(k, jsonStr)
                elif kDesc == 'password' or k.endswith('account'):
                    if osType == 'windows':
                        v = v.replace('\\', '\\\\')
                        v = v.replace('"', '\\"')
                        cmd = cmd + ' --{} "{}" '.format(k, v)
                    else:
                        v = v.replace("'", "'\\''")
                        cmd = cmd + " --{} '{}' ".format(k, v)
                elif len(k) == 1:
                    v = v.replace('\\', '\\\\')
                    v = v.replace('"', '\\"')
                    cmd = cmd + ' -{} "{}" '.format(k, v)
                else:
                    v = v.replace('\\', '\\\\')
                    v = v.replace('"', '\\"')
                    cmd = cmd + ' --{} "{}" '.format(k, v)
        return cmd

    def getCmd(self, fullPath=False, remotePath='.', osType='linux'):
        cmd = None
        if remotePath is None:
            remotePath = '.'

        if self.isScript:
            if self.opType == 'remote':
                # 如果自定义脚本远程执行，为了避免中文名称带来的问题，使用opId来作为脚本文件的名称
                if osType == 'windows':
                    # 如果是windows，windows的脚本执行必须要脚本具备扩展名,自定义脚本下载时会自动加上扩展名
                    if self.interpreter == 'cmd':
                        cmd = 'cmd /c {}/{}'.format(remotePath, self.scriptFileName)
                    elif self.interpreter == 'vbscript' or self.interpreter == 'javascript':
                        cmd = 'cscript {}/{}'.format(remotePath, self.scriptFileName)
                    elif self.interpreter == 'powershell':
                        cmd = 'powershell -Command "Set-ExecutionPolicy -Force RemoteSigned" && powershell {}/{}'.format(remotePath, self.scriptFileName)
                    else:
                        cmd = '{} {}/{}'.format(self.interpreter, remotePath, self.scriptFileName)
                else:
                    if self.interpreter in ('sh', 'bash', 'csh'):
                        cmd = '{} -l {}/{}'.format(self.interpreter, remotePath, self.scriptFileName)
                    else:
                        cmd = '{} {}/{}'.format(self.interpreter, remotePath, self.scriptFileName)
            else:
                if fullPath:
                    cmd = self.pluginPath
                else:
                    cmd = self.pluginPath
        else:
            # 如果是内置的插件，则不会使用中文命名，同时如果是windows使用的工具会默认加上扩展名
            if self.opType == 'remote':
                if osType == 'windows':
                    # 如果是windows，windows的脚本执行必须要脚本具备扩展名
                    extName = self.extNameMap[self.interpreter]
                    nameWithExt = self.opSubName
                    if self.opSubName.endswith(extName):
                        if self.interpreter == 'cmd':
                            cmd = 'cmd /c {}'.format(self.opSubName)
                        elif self.interpreter == 'vbscript' or self.interpreter == 'javascript':
                            cmd = 'cscript {}'.format(self.opSubName)
                        else:
                            cmd = '{} {}'.format(self.interpreter, self.opSubName)
                    else:
                        nameWithExt = self.opSubName + extName
                        if self.interpreter == 'cmd':
                            cmd = 'rename {} {} & cmd /c {}'.format(self.opSubName, nameWithExt, nameWithExt)
                        elif self.interpreter == 'vbscript' or self.interpreter == 'javascript':
                            cmd = 'rename {} {} & cscript {}'.format(self.opSubName, nameWithExt, nameWithExt)
                        else:
                            cmd = 'rename {} {} & {} {}'.format(self.opSubName, nameWithExt, self.interpreter, nameWithExt)
                else:
                    if self.interpreter in ('sh', 'bash', 'csh'):
                        cmd = '{} -l {}/{}'.format(self.interpreter, remotePath, self.opSubName)
                    else:
                        cmd = '{} {}/{}'.format(self.interpreter, remotePath, self.opSubName)
            else:
                if fullPath:
                    cmd = self.pluginPath
                else:
                    cmd = self.opSubName

        return cmd

    def getCmdLine(self, fullPath=False, remotePath=None, osType='linux'):
        cmd = self.getCmd(fullPath=fullPath, remotePath=remotePath, osType=osType)
        cmd = self.appendCmdOpts(cmd, osType=osType)
        cmd = self.appendCmdArgs(cmd, osType=osType)
        return cmd

    def getCmdLineHidePassword(self, fullPath=False, remotePath=None, osType='linux'):
        cmd = self.getCmd(fullPath=fullPath, remotePath=remotePath, osType=osType)
        cmd = self.appendCmdOpts(cmd, noPassword=True, osType=osType)
        cmd = self.appendCmdArgs(cmd, noPassword=True, osType=osType)
        return cmd
