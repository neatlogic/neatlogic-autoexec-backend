#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 对操作插件参数进行处理，依据插件的参数描述信息进行相关处理：
 文件参数转换为对当前file子目录下文件路径名
 密码参数进行解密
"""
from email.errors import HeaderMissingRequiredValue
import os
import fcntl
import re
import json

import Utils
import AutoExecError


class Operation:

    def __init__(self, context, opsParam, param):
        self.context = context
        self.node = None
        self.jobId = context.jobId
        self.opsParam = opsParam
        self.isScript = 0
        self.hasFileOpt = False
        self.scriptContent = None
        self.interpreter = ''
        self.lockedFDs = []

        self.JSON_TYPES = {"node": 1, "json": 1, "file": 1, "multiselect": 1, "checkbox": 1, "textarea": 1}
        self.FILE_TYPES = {"file": 1}
        self.PWD_TYPES = {"password": 1, "account": 1}

        self.opId = param['opId']

        opFullName = param['opName']
        self.opName = opFullName
        self.opSubName = os.path.basename(opFullName)

        opBunddleName = os.path.dirname(opFullName)
        self.opBunddleName = opBunddleName

        # opType有三种
        # remote：推送到远程主机上运行，每个目标节点调用一次
        # localremote：在本地连接远程节点运行（插件通过-node参数接受单个当前运行node的参数），每个目标节点调用一次
        # local：在本地运行，与运行节点无关，只会运行一次
        self.opType = param['opType']
        self.opTypeDesc = {
            "local": "on runner",
            "remote": "on remote OS",
            "localremote": "on runner to target"
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
            'javascript': '.js'
        }

        # 把runner、target、runner_target、sqlfile转换为local、remote、localremote
        if self.opType == 'runner':
            self.opType = 'local'
        elif self.opType == 'target':
            self.opType = 'remote'
        elif self.opType == 'runner_target':
            self.opType = 'localremote'
        elif self.opType == 'sqlfile':
            self.opType = 'local'
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
        self.passKey = context.config['server']['password.key']
        self.param = param

        # 加载操作的output描述，并计算抽取出文件output属性
        self.outputFiles = []
        if 'output' in param:
            self.outputDesc = param['output']
            for outOptName, outOpt in self.outputDesc.items():
                if outOpt['type'] == 'filepath':
                    self.outputFiles.append(outOptName)
        else:
            self.outputDesc = {}

        if self.outputDesc:
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

            scriptFileName = scriptName
            extName = self.extNameMap[self.interpreter]
            if not scriptFileName.endswith(extName):
                scriptFileName = scriptFileName + extName

            self.scriptFileName = scriptFileName
            self.pluginParentPath = '{}/script'.format(self.context.runPath)
            if self.opBunddleName != '':
                self.pluginParentPath = self.pluginParentPath + '/' + self.opBunddleName
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
    def parseParam(self, refMap=None, resourceId=None, host=None, port=None, nodeEnv={}):
        opDesc = {}
        if 'desc' in self.param:
            opDesc = self.param['desc']

        opOpts = self.param['opt']

        for optName, optValue in opOpts.items():
            optType = opDesc.get(optName)
            if optType is None:
                self.writeLog("WARN: Can not determine option {} type by params desc, it will cause none normal parameters can not be resolved.\n".format(optName))

            if optType == 'password':
                try:
                    if optValue[0:11] == '{ENCRYPTED}':
                        optValue = Utils._rc4_decrypt_hex(self.context.passKey, optValue[11:])
                    elif optValue[0:5] == '{RC4}':
                        optValue = Utils._rc4_decrypt_hex(self.context.passKey, optValue[5:])
                    elif optValue[0:4] == 'RC4:':
                        optValue = Utils._rc4_decrypt_hex(self.context.passKey, optValue[4:])
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
                        if password[0:11] == '{ENCRYPTED}':
                            password = Utils._rc4_decrypt_hex(self.context.passKey, password[11:])
                        elif password[0:5] == '{RC4}':
                            password = Utils._rc4_decrypt_hex(self.context.passKey, password[5:])
                        elif password[0:4] == 'RC4:':
                            password = Utils._rc4_decrypt_hex(self.context.passKey, password[4:])
                        optValue = username + '/' + password
                    except Exception as err:
                        self.writeLog("WARN: {}\n".format(err.value))

            elif optType == 'file':
                matchObj = re.match(r'^\s*\$\{', str(optValue))
                if matchObj:
                    optValueStr = self.resolveOptValue(optValue, refMap=refMap, nodeEnv=nodeEnv)
                    try:
                        optValue = json.loads(optValueStr)
                    except Exception as err:
                        self.writeLog("WARN: Resolve file param {}->{} failed.\n".format(optName, optValueStr))
                        optValue = '[]'

                if optValue:
                    fileNames = self.fetchFile(optName, optValue)
                    fileNamesJson = []
                    for fileName in fileNames:
                        fileNamesJson.append('file/' + fileName)
                    optValue = json.dumps(fileNamesJson, ensure_ascii=False)
            else:
                optValue = self.resolveOptValue(optValue, refMap=refMap, nodeEnv=nodeEnv)
                if optType == 'textarea':
                    optValue = optValue.replace('\n', '\\n')

            self.options[optName] = optValue

        opArgs = self.param.get('arg')
        if opArgs is not None:
            args = []
            for opArg in opArgs:
                argType = opArg.get('type')
                argValue = opArg.get('value')
                if argType == 'password':
                    try:
                        if argValue[0:11] == '{ENCRYPTED}':
                            argValue = Utils._rc4_decrypt_hex(self.context.passKey, argValue[11:])
                        elif argValue[0:5] == '{RC4}':
                            argValue = Utils._rc4_decrypt_hex(self.context.passKey, argValue[5:])
                        elif argValue[0:4] == 'RC4:':
                            argValue = Utils._rc4_decrypt_hex(self.context.passKey, argValue[4:])
                    except:
                        self.writeLog("WARN: Decrypt password argument:{} failed.\n".format(self.opName))
                elif(argType == 'file'):
                    matchObj = re.match(r'^\s*\$\{', str(argValue))
                    if matchObj:
                        argValueStr = self.resolveOptValue(optValue, refMap=refMap, nodeEnv=nodeEnv)
                    try:
                        argValue = json.loads(optValueStr)
                    except Exception as err:
                        self.writeLog("WARN: Resolve file param {} failed.\n".format(argValueStr))
                        argValue = '[]'

                    if optValue:
                        fileNames = self.fetchFile(optName, argValue)
                        fileNamesJson = []
                        for fileName in fileNames:
                            fileNamesJson.append('file/' + fileName)
                        argValue = json.dumps(fileNamesJson, ensure_ascii=False)
                else:
                    argValue = self.resolveOptValue(argValue, refMap=refMap, nodeEnv=nodeEnv)
                args.append({'type': argType, 'value': argValue})
            self.arguments = args

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
                self.hasFileOpt = True

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

    def resolveOptValue(self, optValue, refMap=None, nodeEnv={}):
        if optValue is None or optValue == '':
            return optValue

        if not isinstance(optValue, str):
            optValue = json.dumps(optValue, ensure_ascii=False)

        if not refMap:
            refMap = self.node.output

        matchObjs = re.findall(r'(\$\{\s*([^\{\}]+)\s*\})', optValue)
        for matchObj in matchObjs:
            # 如果参数引用的是当前作业的参数（变量格式不是${opId.varName}），则从全局参数表中获取参数值
            # matchObj = re.match(r'^\s*\$\{\s*([^\{\}]+)\s*\}\s*$', optValue)
            exp = matchObj[0]
            paramName = matchObj[1]
            val = None

            nativeRefMap = self.context.opt
            globalOptMap = self.context.globalOpt
            if paramName in nativeRefMap:
                val = nativeRefMap[paramName]
            elif paramName in globalOptMap:
                val = globalOptMap[paramName]
            elif paramName in nodeEnv:
                val = nodeEnv[paramName]
            elif paramName in os.environ:
                val = os.environ[paramName]
            else:
                newVal = None
                opId = None
                # 变量格式是：${phaseName.opBunndle/opId.varName}，则是在运行过程中产生的内部引用参数
                varNames = paramName.split('.')
                if len(varNames) == 3:
                    opId = varNames[1]
                    paramName = varNames[2]

                    if opId in refMap:
                        paramMap = refMap[opId]
                        if paramName in paramMap:
                            newVal = paramMap[paramName]

                    if newVal is not None:
                        val = newVal
                    else:
                        raise AutoExecError.AutoExecError("Can not resolve param " + optValue)

            if val is not None:
                if not isinstance(val, str):
                    val = json.dumps(val, ensure_ascii=False)
                optValue = optValue.replace(exp, val)

        return optValue

    def getOneArgDef(self, val, desc=None, hideValue=False, quota='"'):
        argDef = ''
        if hideValue:
            val = '******'

        if desc is not None and desc in self.FILE_TYPES:
            files = json.loads(val)
            val = ','.join(files)

        if self.interpreter != 'cmd':
            if quota == '"':
                val = re.sub(r'(?<=\\\\)*(?<!\\)"', '\\"', val)
                val = re.sub(r'(?<=\\\\)+"', '\\"', val)
            elif quota == "'":
                val = val.replace("'", "'\\''")

        if self.interpreter == 'cmd':
            if re.search('\s', val):
                argDef = ' "%s" ' % (val)
            else:
                argDef = ' %s ' % (val)
        else:
            argDef = ' %s%s%s ' % (quota, val, quota)

        return argDef

    def appendCmdArgs(self, cmd, noPassword=False, osType='linux'):
        for arg in self.arguments:
            argDesc = arg.get('type')
            isObject = False
            if argDesc in self.JSON_TYPES:
                isObject = True

            isPassword = False
            if argDesc in self.PWD_TYPES:
                isPassword = True

            hideValue = False
            if noPassword and isPassword:
                hideValue = True

            argValue = arg.get('value')
            if (isObject or isPassword) and osType != 'windows':
                cmd = cmd + self.getOneArgDef(argValue, desc=argDesc, hideValue=hideValue, quota="'")
            else:
                cmd = cmd + self.getOneArgDef(argValue, desc=argDesc, hideValue=hideValue, quota='"')
        return cmd

    def getOneOptDef(self, key, val, desc=None, hideValue=False, quota='"'):
        optDef = ''
        if hideValue:
            val = '******'

        if desc is not None and desc in self.FILE_TYPES:
            files = json.loads(val)
            val = ','.join(files)

        if desc != 'switch' and self.interpreter != 'cmd':
            if quota == '"':
                val = re.sub(r'(?<=\\\\)*(?<!\\)"', '\\"', val)
                val = re.sub(r'(?<=\\\\)+"', '\\"', val)
            elif quota == "'":
                val = val.replace("'", "'\\''")

        if self.interpreter == 'cmd':
            if desc == 'swtich':
                if val == 'true':
                    optDef = ' /%s ' % (key)
            elif re.search('\s', val):
                optDef = ' /%s:"%s" ' % (key, val)
            else:
                optDef = ' /%s:%s ' % (key, val)
        elif self.interpreter == 'vbscript':
            if desc == 'swtich':
                if val == 'true':
                    optDef = ' /%s ' % (key)
            else:
                optDef = ' /%s:%s%s%s ' % (key, quota, val, quota)
        elif self.interpreter == 'powershell':
            if desc == 'swtich':
                if val == 'true':
                    optDef = ' -%s ' % (key)
            else:
                optDef = ' -%s %s%s%s ' % (key, quota, val, quota)
        else:
            keyLen = len(key)
            if keyLen == 1:
                if desc == 'swtich':
                    if val == 'true':
                        optDef = ' -%s ' % (key)
                else:
                    optDef = ' -%s %s%s%s ' % (key, quota, val, quota)
            else:
                if desc == 'swtich':
                    if val == 'true':
                        optDef = ' --%s ' % (key)
                else:
                    optDef = ' --%s %s%s%s ' % (key, quota, val, quota)

        return optDef

    def appendCmdOpts(self, cmd, noPassword=False, osType='Linux'):
        for k, v in self.options.items():
            if v == "" or v is None:
                continue

            kDesc = None
            if 'desc' in self.param and k in self.param['desc']:
                kDesc = self.param['desc'][k].lower()

            isObject = False
            if kDesc in self.JSON_TYPES:
                isObject = True

            isPassword = False
            if kDesc in self.PWD_TYPES or k.endswith('account'):
                isPassword = True

            hideValue = False
            if noPassword and isPassword:
                hideValue = True

            if (isObject or isPassword) and osType != 'windows':
                cmd = cmd + self.getOneOptDef(k, v, desc=kDesc, hideValue=hideValue, quota="'")
            else:
                cmd = cmd + self.getOneOptDef(k, v, desc=kDesc, hideValue=hideValue, quota='"')
        return cmd

    def getOpNameWithExt(self, osType='linux'):
        nameWithExt = None
        if self.isScript:
            if self.opType == 'remote':
                nameWithExt = self.scriptFileName
            else:
                nameWithExt = self.opName
        else:
            if self.opType == 'remote':
                extName = self.extNameMap[self.interpreter]
                if self.opSubName.endswith(extName):
                    nameWithExt = self.opSubName
                else:
                    nameWithExt = self.opSubName + extName
            else:
                nameWithExt = self.opName

        return nameWithExt

    def getCmd(self, fullPath=False, remotePath='.', osType='linux'):
        cmd = None
        if remotePath is None or fullPath == False:
            remotePath = '.'

        if self.isScript:
            if self.opType == 'remote':
                # 如果自定义脚本远程执行，为了避免中文名称带来的问题，使用opId来作为脚本文件的名称
                if osType == 'windows':
                    # 如果是windows，windows的脚本执行必须要脚本具备扩展名,自定义脚本下载时会自动加上扩展名
                    if self.interpreter == 'cmd':
                        # cmd = 'cmd /c {}/{}'.format(remotePath, self.scriptFileName)
                        cmd = 'cd {} & cmd /c {}'.format(remotePath, self.scriptFileName)
                    elif self.interpreter == 'vbscript' or self.interpreter == 'javascript':
                        # cmd = 'cscript {}/{}'.format(remotePath, self.scriptFileName)
                        cmd = 'cd {} & cscript {}'.format(remotePath, self.scriptFileName)
                    elif self.interpreter == 'powershell':
                        # cmd = 'powershell -Command "Set-ExecutionPolicy -Force RemoteSigned" & powershell {}/{}'.format(remotePath, self.scriptFileName)
                        cmd = 'cd {} & powershell -Command "Set-ExecutionPolicy -Force RemoteSigned" & powershell -f {}'.format(remotePath, self.scriptFileName)
                    else:
                        # cmd = '{} {}/{}'.format(self.interpreter, remotePath, self.scriptFileName):
                        cmd = 'cd {} & {} {}'.format(remotePath, self.interpreter, self.scriptFileName)
                else:
                    if self.interpreter in ('sh', 'bash', 'csh'):
                        # cmd = '{} -l {}/{}'.format(self.interpreter,  remotePath, self.scriptFileName)
                        cmd = 'cd {} && {} -l {}'.format(remotePath, self.interpreter,  self.scriptFileName)
                    else:
                        # cmd = '{} {}/{}'.format(self.interpreter, remotePath, self.scriptFileName)
                        cmd = 'cd {} && {} {}'.format(remotePath, self.interpreter, self.scriptFileName)
            else:
                if fullPath:
                    cmd = self.pluginPath
                else:
                    cmd = self.opName
        else:
            # 如果是内置的插件，则不会使用中文命名，同时如果是windows使用的工具会默认加上扩展名
            if self.opType == 'remote':
                if osType == 'windows':
                    # 如果是windows，windows的脚本执行必须要脚本具备扩展名
                    extName = self.extNameMap[self.interpreter]
                    nameWithExt = self.opSubName
                    if self.opSubName.endswith(extName):
                        if self.interpreter == 'cmd':
                            # cmd = 'cmd /c {}/{}'.format(remotePath, self.opSubName)
                            cmd = 'cd {} & cmd /c {}'.format(remotePath, self.opSubName)
                        elif self.interpreter == 'vbscript' or self.interpreter == 'javascript':
                            # cmd = 'cscript {}/{}'.format(remotePath, self.opSubName)
                            cmd = 'cd {} & cscript {}'.format(remotePath, self.opSubName)
                        elif self.interpreter == 'powershell':
                            cmd = 'cd {} & powershell -Command "Set-ExecutionPolicy -Force RemoteSigned" & powershell -f {}'.format(remotePath, self.opSubName)
                        else:
                            # cmd = '{} {}/{}'.format(self.interpreter, remotePath,  self.opSubName)
                            cmd = 'cd {} & {} {}'.format(remotePath, self.interpreter, self.opSubName)
                    else:
                        nameWithExt = self.opSubName + extName
                        if self.interpreter == 'cmd':
                            # cmd = 'cd {} & copy {} {} & cd \\ & cmd /c {}/{}'.format(remotePath, self.opSubName, nameWithExt, remotePath, nameWithExt)
                            cmd = 'cd {} & copy {} {} & cmd /c {}'.format(remotePath, self.opSubName, nameWithExt, nameWithExt)
                        elif self.interpreter == 'vbscript' or self.interpreter == 'javascript':
                            # cmd = 'cd {} & copy {} {} & cd \\ & cscript {}/{}'.format(remotePath, self.opSubName, nameWithExt, remotePath, nameWithExt)
                            cmd = 'cd {} & copy {} {} & cscript {}'.format(remotePath, self.opSubName, nameWithExt, nameWithExt)
                        else:
                            # cmd = 'cd {} & copy {} {} & cd \\ & {} {}/{}'.format(remotePath, self.opSubName, nameWithExt, self.interpreter, remotePath, nameWithExt)
                            cmd = 'cd {} & copy {} {} & {} {}'.format(remotePath, self.opSubName, nameWithExt, self.interpreter, nameWithExt)
                else:
                    if self.interpreter in ('sh', 'bash', 'csh'):
                        # cmd = '{} -l {}/{}'.format(self.interpreter, remotePath, self.opSubName)
                        cmd = 'cd {} && {} -l {}'.format(remotePath, self.interpreter,  self.opSubName)
                    else:
                        # cmd = '{} {}/{}'.format(self.interpreter, remotePath, self.opSubName)
                        cmd = 'cd {} && {} {}'.format(remotePath, self.interpreter,  self.opSubName)
            else:
                if fullPath:
                    cmd = self.pluginPath
                else:
                    cmd = self.opName

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

    def getCmdOptsHidePassword(self, osType='linux'):
        cmd = self.getOpNameWithExt(osType=osType)
        cmd = self.appendCmdOpts(cmd, noPassword=True, osType=osType)
        cmd = self.appendCmdArgs(cmd, noPassword=True, osType=osType)
        return cmd
