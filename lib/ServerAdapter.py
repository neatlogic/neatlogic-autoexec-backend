#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 NeatLogic
"""
from ast import Return
import os
import traceback
import stat
import fcntl
from filelock import FileLock
import ssl
import time
import json
import base64
import requests
import urllib.request
import urllib.parse
from urllib.error import URLError
from urllib.error import HTTPError
from hashlib import sha256
import hmac
import base64
import tarfile

from AutoExecError import AutoExecError


class ServerAdapter:

    def __init__(self, context):
        ssl._create_default_https_context = ssl._create_unverified_context

        # api路径的映射
        self.apiMap = {
            'getMongoDBConf': '/neatlogic/api/rest/mongodb/datasource/get',
            'register': '/neatlogic/api/rest/autoexec/tool/register',
            'cleanNativeTools': '/neatlogic/api/rest/autoexec/tool/batch/delete',
            'getParams': '/neatlogic/api/rest/autoexec/job/create/param/get',
            'getNodes': '/neatlogic/api/binary/autoexec/job/phase/nodes/download',
            'fetchFile': '/neatlogic/api/binary/file/download',
            'fetchScript': 'neatlogic/api/binary/autoexec/job/phase/operation/script/get/forautoexec',
            'getScript': '/neatlogic/api/rest/autoexec/script/active/version/get',
            'getAccount': '/neatlogic/api/rest/resourcecenter/resource/account/get',
            'getNodePwd': '/neatlogic/api/rest/resourcecenter/resource/account/get',
            'getInspectConf': '/neatlogic/api/rest/autoexec/inspect/nodeconf/get',
            'updateInspectStatus': '/neatlogic/api/rest/cmdb/cientity/updateinspectstatus',
            'updateMonitorStatus': '/neatlogic/api/rest/cmdb/cientity/updatemonitorstatus',
            'updateNodeStatus': '/neatlogic/api/rest/autoexec/job/phase/node/status/update',
            'updatePhaseStatus': '/neatlogic/api/rest/autoexec/job/phase/status/update',
            'fireNextGroup': '/neatlogic/api/rest/autoexec/job/next/group/fire',
            'fireNextPhase': '/neatlogic/api/rest/autoexec/job/next/phase/fire',
            'informRoundEnded': '/neatlogic/api/rest/autoexec/job/phase/inform/round/end',
            'updateJobStatus': '/neatlogic/api/rest/autoexec/job/status/update',
            'exportJobEnv': '/neatlogic/api/rest/autoexec/job/env/update',
            'updateGlobalParam': '/neatlogic/api/rest/autoexec/global/param/update/forautoexec',
            'setResourceInspectJobId': '/neatlogic/api/rest/autoexec/job/resource/inspect/update',
            'getCmdbCiAttrs': '/neatlogic/api/rest/cmdb/cientity/attrentity/get',
            'getAccessEndpoint': '/neatlogic/api/rest/resourcecenter/resource/accessendpoint/get',
            'globalLock': '/neatlogic/api/rest/global/lock',
            'getDeployIdPath': '/neatlogic/api/rest/resourcecenter/resource/appidmoduleidenvid/get',
            'getDeployRunnerGroup': '/neatlogic/api/rest/deploy/runner/group/get/forautoexec',
            'getCITxtFilePathList': '/neatlogic/api/rest/inspect/configfile/resource/path/list',
            'uploadFile': '/neatlogic/api/binary/file/upload',
            'removeUploadedFile': '/neatlogic/api/rest/file/delete',
            'txtFileInspectSave': '/neatlogic/api/rest/inspect/configfile/audit/save',
            'inspectReport': '/neatlogic/api/rest/inspect/autoexec/job/report/notify',
            'getResourceInfo': '/neatlogic/api/rest/resourcecenter/resource/custom/list',
            'saveVersionMetrics': '/neatlogic/api/rest/deploy/version/commit/analyze/save',
            'saveVersionCveList': '/neatlogic/api/rest/deploy/version/cvelist/save'
            'getJobStatus': '/neatlogic/api/rest/autoexec/job/status/get',
        }

        self.context = context
        self.fileFeteched = context.fileFeteched
        self.scriptFetched = context.scriptFetched
        self.opFetched = context.opFetched
        serverBaseUrl = context.config['server']['server.baseurl']
        if (serverBaseUrl[-1] == '/'):
            serverBaseUrl = serverBaseUrl[0:-1]
        self.serverBaseUrl = serverBaseUrl

        self.serverUserName = context.config['server']['server.username']
        self.serverPassword = context.config['server']['server.password']
        # self.authToken = 'Basic ' + str(base64.b64encode(bytes(self.serverUserName + ':' + self.serverPassword, 'utf-8')).decode('ascii', errors='ignore'))

    def addHeaders(self, request, headers):
        for k, v in headers.items():
            if isinstance(v, str):
                request.add_header(k, v)
            else:
                request.add_header(k, str(v))

    def getSignHeaders(self, apiUri, postBody=None):
        signContent = self.serverUserName + '#' + apiUri + '#'
        if postBody is not None and postBody != '':
            signContent = signContent + base64.b64encode(postBody.encode('utf-8')).decode('utf-8')

        digest = 'Hmac ' + hmac.new(self.serverPassword.encode('utf-8'), signContent.encode('utf-8'), digestmod=sha256).hexdigest()
        headers = {
            'Tenant': self.context.tenant,
            'AuthType': 'hmac',
            'x-access-key': self.serverUserName,
            'Authorization': digest
        }
        return headers

    def signRequest(self, request, apiUri, postBody=None):
        headers = self.getSignHeaders(apiUri, postBody)
        for k, v in headers.items():
            request.add_header(k, v)

    def httpPOST(self, apiUri, params):
        if apiUri[0] != "/":
            apiUri = '/' + apiUri

        url = self.serverBaseUrl + apiUri
        headers = {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'}

        postBody = json.dumps(params, ensure_ascii=False)
        req = urllib.request.Request(url, postBody.encode('utf-8'))
        self.addHeaders(req, headers)
        try:
            self.signRequest(req, apiUri, postBody)
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            errMsg = ex.code
            if ex.code > 500:
                content = ex.read()
                errObj = json.loads(content)
                errMsg = errObj.get('Message', '')
            raise AutoExecError("Request failed, {}\n".format(errMsg))
        except URLError as ex:
            raise AutoExecError("Request url:{} failed, {}\n".format(url, ex.reason))
        return response

    def httpGET(self, apiUri, params=None):
        if apiUri[0] != "/":
            apiUri = '/' + apiUri

        if params:
            data = urllib.parse.urlencode(params)
            apiUri = apiUri + '?' + data

        url = self.serverBaseUrl + apiUri
        req = urllib.request.Request(url)

        try:
            self.signRequest(req, apiUri)
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            errMsg = ex.code
            if ex.code > 500:
                content = ex.read()
                errObj = json.loads(content)
                errMsg = errObj['Message']
            raise AutoExecError("Request failed, {}".format(errMsg))
        except URLError as ex:
            raise AutoExecError("Request url:{} failed, {}".format(url, ex.reason))

        return response

    def httpJSON(self, apiUri, params):
        if apiUri[0] != "/":
            apiUri = '/' + apiUri

        url = self.serverBaseUrl + apiUri
        headers = {'Content-Type': 'application/json; charset=utf-8'}

        postBody = json.dumps(params, ensure_ascii=False)
        req = urllib.request.Request(url, postBody.encode('utf-8'))
        self.addHeaders(req, headers)
        try:
            self.signRequest(req, apiUri, postBody)
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            errMsg = ex.code
            if ex.code > 500:
                content = ex.read()
                errObj = json.loads(content)
                errMsg = errObj.get('Message', '')
            raise AutoExecError("Request failed, {}".format(errMsg))
        except URLError as ex:
            raise AutoExecError("Request url:{} failed, {}".format(url, ex.reason))

        return response

    # 获取租户mongoDB的配置
    def getMongoDBConf(self):
        if self.context.devMode:
            return

        contextCfg = self.context.config
        dbUrl = contextCfg['autoexec'].get('db.url')

        if not dbUrl:
            response = self.httpGET(self.apiMap['getMongoDBConf'])

            try:
                charset = response.info().get_content_charset()
                content = response.read().decode(charset, errors='ignore')
                contentObj = json.loads(content)
                if contentObj.get('Status') != 'OK':
                    raise AutoExecError("Request failed, {}".format(contentObj.get('Message')))

                mongoDBConf = contentObj.get('Return')
                optionStr = mongoDBConf.get('option')
                if optionStr:
                    contextCfg['autoexec']['db.url'] = 'mongodb://%s/?%s' % (mongoDBConf['host'], optionStr)
                else:
                    contextCfg['autoexec']['db.url'] = 'mongodb://%s/' % (mongoDBConf['host'])
                contextCfg['autoexec']['db.name'] = mongoDBConf['database']
                contextCfg['autoexec']['db.username'] = mongoDBConf['username']
                contextCfg['autoexec']['db.password'] = mongoDBConf['passwordPlain']
            except:
                raise

    # 获取作业的运行参数文件params.json
    def getParams(self):
        params = {
            'jobId': self.context.jobId
        }

        lastModifiedTime = 0
        paramsFilePath = self.context.paramsFilePath
        if os.path.exists(paramsFilePath):
            lastModifiedTime = os.path.getmtime(paramsFilePath)
        params['lastModified'] = lastModifiedTime

        paramsFile = None
        try:
            paramsFile = open(paramsFilePath, 'a+')
            fcntl.flock(paramsFile, fcntl.LOCK_EX)

            response = self.httpJSON(self.apiMap['getParams'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    params = retObj['Return']
                    paramsFile.truncate(0)
                    paramsFile.write(json.dumps(params, indent=4, ensure_ascii=False))
                    return params
                else:
                    raise "Get parameters for job {} failed, {}".format(self.context.jobId, retObj['Message'])
            else:
                raise "Get parameters for job {} failed, status code:{} {}".format(self.context.jobId, response.status, content)
        except:
            raise
        finally:
            if paramsFile:
                fcntl.flock(paramsFile, fcntl.LOCK_UN)
                paramsFile.close()

    # 下载运行作业或作业某个阶段的运行目标节点
    def getNodes(self, phase=None, groupNo=None):
        params = {
            'jobId': self.context.jobId,
            'runnerId': self.context.runnerId,
            'passThroughEnv': self.context.passThroughEnv,
            'phase': '',
            'nodeFrom': 'job'
        }

        if phase is not None:
            params['phase'] = phase
            params['nodeFrom'] = 'phase'

        if groupNo is not None:
            params['groupNo'] = groupNo
            params['nodeFrom'] = 'group'

        lastModifiedTime = 0
        nodesFilePath = self.context.getNodesFilePath(phaseName=phase, groupNo=groupNo)
        if os.path.exists(nodesFilePath):
            lastModifiedTime = os.path.getmtime(nodesFilePath)
        params['lastModified'] = lastModifiedTime

        nodesFile = None
        try:
            response = self.httpGET(self.apiMap['getNodes'],  params)

            if response.status == 200:
                nodesFile = open(nodesFilePath, 'a+')
                fcntl.flock(nodesFile, fcntl.LOCK_EX)
                nodesFile.truncate(0)
                for line in response:
                    nodesFile.write(str(line, encoding='utf-8'))

                if phase is not None:
                    self.context.phases[phase].nodesFilePath = nodesFilePath

            # elif response.status == 205:
                # 如果阶段playbook的运行节点跟pipeline一致，阶段节点使用作业节点
            #    pass
            elif response.status == 204:
                # 如果当前已经存在阶段节点文件，而且修改时间大于服务端，则服务端api给出204反馈，代表没有更改，不需要处理
                if phase is not None:
                    self.context.phases[phase].nodesFilePath = nodesFilePath
        finally:
            if nodesFile:
                fcntl.flock(nodesFile, fcntl.LOCK_UN)
                nodesFile.close()

    # 更新运行阶段某个节点的状态到服务端
    def pushNodeStatus(self, groupNo, phaseName, runNode, status, failIgnore=0, warnCount=0):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'groupNo': groupNo,
            'phase': phaseName,
            'resourceId': runNode.resourceId,
            'host': runNode.host,
            'port': runNode.port,
            'status': status,
            'failIgnore': failIgnore,
            'warnCount': warnCount,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }

        response = self.httpJSON(self.apiMap['updateNodeStatus'],  params)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    # 更新运行端阶段的状态
    def pushPhaseStatus(self, groupNo, phaseName, phaseStatus, status):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'groupNo': groupNo,
            'phase': phaseName,
            'status': status,
            'failNodeCount': phaseStatus.failNodeCount,
            'sucNodeCount': phaseStatus.sucNodeCount,
            'skipNodeCount': phaseStatus.skipNodeCount,
            'ignoreFailNodeCount': phaseStatus.ignoreFailNodeCount,
            'warnCount': phaseStatus.warnCount,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }

        try:
            response = self.httpJSON(self.apiMap['updatePhaseStatus'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            # 如果更新阶段状态失败，很可能是因为节点和阶段对应关系存在问题，更新节点文件的时间到1970-1-1
            # 促使下次运行主动更新节点文件
            found = False

            phaseNodesFilePath = self.context.getNodesFilePath(phaseName=phaseName)
            if (os.path.exists(phaseNodesFilePath)):
                found = True
                os.utime(phaseNodesFilePath, (0, 0))

            if not found:
                groupNodesFilePath = self.context.getNodesFilePath(groupNo=groupNo)
                if (os.path.exists(groupNodesFilePath)):
                    found = True
                    os.utime(groupNodesFilePath, (0, 0))

            if not found:
                nodesFilePath = self.context.getNodesFilePath()
                if (os.path.exists(nodesFilePath)):
                    os.utime(nodesFilePath, (0, 0))

            raise

    # 通知后端进行下一个组的调度，后端根据当前phase的全局节点运行状态判断是否调度下一个阶段
    def fireNextGroup(self, groupNo):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'runnerId': self.context.runnerId,
            'groupNo': groupNo,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON(self.apiMap['fireNextGroup'],  params)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    # 通知后端进行下一个阶段的调度，后端根据当前phase的全局节点运行状态判断是否调度下一个阶段
    def fireNextPhase(self, lastPhase):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'runnerId': self.context.runnerId,
            'lastPhase': lastPhase,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON(self.apiMap['fireNextPhase'],  params)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    # 通知后端进行下一个阶段的调度，后端根据当前phase的全局节点运行状态判断是否调度下一个阶段
    def informRoundEnded(self, groupNo, phaseName, roundNo):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'runnerId': self.context.runnerId,
            'groupNo': groupNo,
            'phase': phaseName,
            'roundNo': roundNo,
            'time': time.time(),
            'pid': os.getpid(),
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON(self.apiMap['informRoundEnded'],  params)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    # 通知后端当前job已经暂停完成
    def jobPaused(self):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'time': time.time(),
            'status': 'paused',
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON(self.apiMap['updateJobStatus'],  params)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    # 通知后端当前job已经Kill完成
    def jobKilled(self):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'time': time.time(),
            'status': 'aborted',
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON(self.apiMap['updateJobStatus'],  params)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    # 下载操作运行参数的文件参数对应的文件，下载到cache目录
    def fetchFile(self, savePath, fileId):
        params = {
            'id': fileId
        }

        cachedFilePath = '{}/{}'.format(savePath, fileId)

        lockFilePath = cachedFilePath + '.lock'
        lockFile = None

        cachedFileTmp = None
        fileName = None
        response = None
        try:
            lockFile = open(lockFilePath, 'w+')
            fcntl.flock(lockFile, fcntl.LOCK_EX)

            fileName = self.fileFeteched.get(fileId)
            if fileName is not None:
                return fileName

            lastModifiedTime = 0
            if os.path.exists(cachedFilePath):
                lastModifiedTime = os.path.getmtime(cachedFilePath)
            params['lastModified'] = lastModifiedTime

            response = self.httpGET(self.apiMap['fetchFile'],  params)
            # 获取下载文件的文件名，服务端通过header传送文件名, 例如：'Content-Disposition: attachment; filename="myfile.tar.gz"'
            resHeaders = response.info()
            contentDisposition = resHeaders['Content-Disposition']
            if contentDisposition is not None:
                fileNameIdx = contentDisposition.index('filename="')
                if fileNameIdx > 0:
                    fileName = contentDisposition[fileNameIdx+10:-1]

            if response.status == 200:
                cachedFilePathTmp = cachedFilePath + '.tmp'
                cachedFileTmp = open(cachedFilePathTmp, 'wb')
                CHUNK = 16 * 1024
                while True:
                    chunk = response.read(CHUNK)
                    if not chunk:
                        break
                    cachedFileTmp.write(chunk)
                cachedFileTmp.close()
                cachedFileTmp = None

                if os.path.exists(cachedFilePath):
                    os.unlink(cachedFilePath)
                os.rename(cachedFilePathTmp, cachedFilePath)

            self.fileFeteched[fileId] = fileName

            return fileName
        except:
            raise AutoExecError("ERROR: Fetch file:{} to {} failed.\n".format(fileId, savePath))
        finally:
            if cachedFileTmp is not None:
                cachedFileTmp.close()
            if lockFile is not None:
                fcntl.flock(lockFile, fcntl.LOCK_UN)
                lockFile.close()

    # 从自定义脚本库下载脚本到脚本目录
    def fetchScriptLib(self, operation, scriptId, opId=None):
        pluginParentPath = operation.pluginParentPath
        scriptFilePath = None
        useLibs = []

        params = {
            'jobId': self.context.jobId,
            'operationId': opId,
            'scriptId': scriptId
        }

        scriptFileName = None
        scriptFile = None
        lockFile = None
        scriptIdFilePath = '%s/%s' % (pluginParentPath, scriptId)
        scriptIdLockFilePath = '%s.lock' % (scriptIdFilePath)
        lastModifiedTime = 0

        response = None
        try:
            newScriptFilePath = self.scriptFetched.get(scriptId)
            if newScriptFilePath is not None:
                return (newScriptFilePath, [])

            lockFile = open(scriptIdLockFilePath, 'w+')
            fcntl.flock(lockFile, fcntl.LOCK_EX)

            newScriptFilePath = self.scriptFetched.get(scriptId)
            if newScriptFilePath is not None:
                return (newScriptFilePath, [])

            usedScriptVerId = None
            if os.path.exists(scriptIdFilePath):
                try:
                    scriptFilePath = os.readlink(scriptIdFilePath)
                    lastModifiedTime = os.path.getmtime(scriptIdFilePath)
                    scriptFilename = os.path.basename(scriptFilePath)
                    usedScriptVerId = scriptFilename[0:scriptFilename.index('.')]
                    params['scriptVersionId'] = int(usedScriptVerId)
                except:
                    # link has been removed
                    pass

            params['acceptStream'] = "True"
            params['lastModified'] = lastModifiedTime

            response = self.httpGET(self.apiMap['fetchScript'],  params)

            resHeaders = response.headers
            if response.status == 200:
                scriptId = resHeaders.get('ScriptId')
                scriptName = resHeaders.get('ScriptName', 'none')
                scriptVerId = resHeaders.get('ScriptVersionId')
                isLib = int(resHeaders.get('ScriptIsLib', 0))
                useLibs = json.loads(resHeaders.get('ScriptUseLibs', '[]'))
                interpreter = resHeaders.get('ScriptInterpreter')

                scriptFileName = operation.getScriptFileName(scriptName, interpreter, isLib)
                scriptFilePath = '%s/%s.%s' % (pluginParentPath, scriptVerId, scriptFileName)
                scriptLibFilePath = '%s/%s.%s.lib' % (pluginParentPath, scriptVerId, scriptFileName)

                contentType = resHeaders.get('Content-Type')
                if contentType.startswith('application/json'):
                    charset = resHeaders.get_content_charset()
                    content = response.read().decode(charset, errors='ignore')
                    retObj = json.loads(content).get('Return')
                    scriptContent = retObj['script']

                    if not os.path.exists(scriptFilePath):
                        if scriptContent is not None:
                            scriptFile = open(scriptFilePath, 'w')
                            scriptFile.write(scriptContent)
                            scriptFile.close()
                            scriptFile = None
                else:
                    if not os.path.exists(scriptFilePath):
                        scriptFile = open(scriptFilePath, 'wb')
                        CHUNK = 16 * 1024
                        while True:
                            chunk = response.read(CHUNK)
                            if not chunk:
                                break
                            scriptFile.write(chunk)
                        scriptFile.close()
                        scriptFile = None

                os.chmod(scriptFilePath, stat.S_IRWXU)
                scriptLibFile = open(scriptLibFilePath, 'w')
                scriptLibFile.write(','.join(map(str, useLibs)))
                scriptLibFile.close()

                if scriptVerId != None and usedScriptVerId != scriptVerId:
                    if os.path.exists(scriptIdFilePath):
                        os.unlink(scriptIdFilePath)
                    os.symlink(scriptFilePath, scriptIdFilePath)

                    scriptNamePath = '%s/%s' % (pluginParentPath, scriptFileName)
                    if os.path.exists(scriptNamePath):
                        os.unlink(scriptNamePath)
                    os.symlink(scriptFilePath, scriptNamePath)

                    if scriptFilePath is not None:
                        self.scriptFetched[scriptId] = scriptFilePath

                if scriptFileName.endswith('.tar'):
                    try:
                        with tarfile.open(scriptFilePath, "r") as tf:
                            tf.extractall(path=pluginParentPath)
                    except Exception as ex:
                        raise AutoExecError("ERROR: Extract package from file {} failed, {}.".format(scriptFileName, str(ex)))

            return (scriptFilePath, useLibs)

        except Exception as ex:
            raise AutoExecError("ERROR: Fetch {} custom lib to {}/{} failed, {}.\n".format(scriptId, pluginParentPath, scriptFileName, str(ex)))
        finally:
            if lockFile is not None:
                fcntl.flock(lockFile, fcntl.LOCK_UN)
                lockFile.close()
            if scriptFile is not None:
                scriptFile.close()

    def fetchOperation(self, operation):
        opId = operation.opId

        opFileLockFile = None
        opFilePath = '%s/%s' % (operation.pluginParentPath, opId)
        opLockFilePath = '%s.lock' % (opFilePath)

        try:
            newScriptFilePath = self.opFetched.get(opId)
            if newScriptFilePath is not None:
                return newScriptFilePath

            opFileLockFile = open(opLockFilePath, 'w+')
            fcntl.flock(opFileLockFile, fcntl.LOCK_EX)

            newScriptFilePath = self.opFetched.get(opId)
            if newScriptFilePath is not None:
                return newScriptFilePath

            oldScriptFilePath = None
            if os.path.exists(opFilePath):
                try:
                    oldScriptFilePath = os.readlink(opFilePath)
                except:
                    pass

            useLibs = []
            opScriptFilePath = None
            (opScriptFilePath, useLibs) = self.fetchScriptLib(operation, operation.scriptId, opId)

            # 避免使用递归，如果使用递归，会因为循环递归导致死锁
            while (useLibs):
                libScriptId = useLibs.pop()
                (scriptFilePath, myUseLibs) = self.fetchScriptLib(operation, libScriptId)
                useLibs.extend(myUseLibs)

            if oldScriptFilePath != opScriptFilePath:
                if os.path.exists(opFilePath):
                    os.unlink(opFilePath)
                os.symlink(opScriptFilePath, opFilePath)

            self.opFetched[opId] = opScriptFilePath

            return opScriptFilePath

        except Exception as ex:
            raise AutoExecError("ERROR: Fetch {} custom script to {}/{} failed, {}.\n".format(opId, operation.pluginParentPath, operation.scriptFileName, str(ex)))
        finally:
            if opFileLockFile is not None:
                fcntl.flock(opFileLockFile, fcntl.LOCK_UN)
                opFileLockFile.close()

    def getScript(self, scriptId):
        params = {
            'operationId': scriptId
        }

        url = self.serverBaseUrl + self.apiMap['getScript']
        try:
            response = self.httpGET(self.apiMap['getScript'],  params)

            if response.status == 200:
                charset = response.info().get_content_charset()
                content = response.read().decode(charset, errors='ignore')
                retObj = json.loads(content)
                return retObj['Return']
        except:
            raise

    # 注册native工具到服务端工具库
    def registerTool(self, toolObj):
        response = self.httpJSON(self.apiMap['register'],  toolObj)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    # 清除不存在的native工具
    def cleanNativeTools(self, importTime):
        response = self.httpJSON(self.apiMap['cleanNativeTools'],  {'importTime': importTime})

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    def callGlobalLock(self, lockParams):
        # Lock reqeust
        # lockParams = {
        #     'lockId': None,
        #     'sysId': 343,
        #     'moduleId': 4353,
        #     'envId': 3,
        #     'sysName': 'mySys',
        #     'moduleName': 'myModule',
        #     'envName': 'SIT',
        #     'version': '2.0.0',
        #     'buildNo': '2',
        #     'action': 'lock',  # unlock
        #     'wait': 1, #0｜1，wait or not
        #     'lockTarget': 'workspace',  # build mirror env/app env/sql
        #     'lockMode': 'read',  # write
        #     'namePath': 'mySys/myModule/SIT'
        # }
        # Unlock request
        # lockParams = {
        #     'lockId': 83205734845,
        # }
        try:
            response = self.httpJSON(self.apiMap['globalLock'],  lockParams)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if retObj.get('Status') == 'OK':
                lockInfo = retObj.get('Return')
                return lockInfo
            else:
                raise AutoExecError("Lock failed, {}".format(retObj.get('Message')))
        except:
            raise

    def exportEnv(self, name, value, isHidden=0):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'envName': name,
            'envValue': value,
            'isHidden': isHidden,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }

        self.httpJSON(self.apiMap['exportJobEnv'],  params)

        return

    def updateGlobalParam(self, name, value):
        if self.context.devMode:
            return {}
        params = {
            'jobId': self.context.jobId,
            'key': name,
            'defaultValue': value,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }

        self.httpJSON(self.apiMap['updateGlobalParam'],  params)

        return

    def getAccount(self, resourceId, host, port, username, protocol, accountId):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'resourceId': resourceId,
            'host': host,
            'port': port,
            'username': username,
            'accountId': accountId,
            'protocol': protocol
        }

        if username is None:
            username = 'none'

        try:
            response = self.httpJSON(self.apiMap['getAccount'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return']
                else:
                    raise AutoExecError("Get Account for {} user:{} failed, {}".format(protocol, username, retObj['Message']))
            else:
                raise AutoExecError("Get Account for {} user:{} failed, status code:{} {}".format(protocol, username, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get Account for {} user:{} failed, {}".format(protocol, username, ex))

    def getNodePwd(self, resourceId, host, port, username, protocol):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'resourceId': resourceId,
            'host': host,
            'port': port,
            'username': username,
            'protocol': protocol
        }

        if username is None:
            username = 'none'
        try:
            response = self.httpJSON(self.apiMap['getNodePwd'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return']
                else:
                    raise AutoExecError("Get password for {}://{}@{}:{} failed, {}".format(protocol, username, host, port, retObj['Message']))
            else:
                raise AutoExecError("Get password for {}://{}@{}:{} failed, status code:{} {}".format(protocol, username, host, port, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get password for {}://{}@{}:{} failed, {}".format(protocol, username, host, port, ex))

    def getInspectConf(self, ciType, resourceId):
        if self.context.devMode:
            return {}

        params = {
            'tenent': self.context.tenent,
            'jobId': self.context.jobId,
            'ciType': ciType,
            'resourceId': resourceId,
            'time': time.time()
        }

        try:
            response = self.httpJSON(self.apiMap['getInspectConf'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return']
                else:
                    raise AutoExecError("Get Inspect Config for {}/{} failed, {}".format(ciType, resourceId, retObj['Message']))
            else:
                raise AutoExecError("Get Inspect Config for {}/{} failed, status code:{} {}".format(ciType, resourceId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get Inspect Config for {}/{} failed, {}".format(ciType, resourceId, ex))

    def updateInspectStatus(self, ciType, resourceId, status, alertCount):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'ciType': ciType,
            'ciEntityId': resourceId,
            'inspectStatus': status,
            'alertCount': alertCount,
            'inspectTime': int(time.time() * 1000)
        }

        try:
            response = self.httpJSON(self.apiMap['updateInspectStatus'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return True
                else:
                    raise AutoExecError("Update inspect status for {}/{} failed, {}".format(ciType, resourceId, retObj['Message']))
            else:
                raise AutoExecError("Update inspect status for {}/{} failed, status code:{} {}".format(ciType, resourceId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Update inspect status for {}/{} failed, {}".format(ciType, resourceId, ex))

    def updateMonitorStatus(self, ciType, resourceId, status, alertCount):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'ciType': ciType,
            'ciEntityId': resourceId,
            'monitorStatus': status,
            'alertCount': alertCount,
            'monitorTime': int(time.time() * 1000)
        }

        try:
            response = self.httpJSON(self.apiMap['updateMonitorStatus'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return True
                else:
                    raise AutoExecError("Update monitor status for {}/{} failed, {}".format(ciType, resourceId, retObj['Message']))
            else:
                raise AutoExecError("Update monitor status for {}/{} failed, status code:{} {}".format(ciType, resourceId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Update monitor status for {}/{} failed, {}".format(ciType, resourceId, ex))

    def setResourceInspectJobId(self, resourceId, jobId, phaseName):
        if self.context.devMode:
            return {}

        params = {
            'resourceId': resourceId,
            'jobId': jobId,
            'phaseName': phaseName,
            'inspectTime': int(time.time() * 1000)
        }

        try:
            response = self.httpJSON(self.apiMap['setResourceInspectJobId'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return True
                else:
                    raise AutoExecError("Set resrouce({}) inspect job Id({}) faield, {}".format(resourceId, jobId, retObj['Message']))
            else:
                raise AutoExecError("Set resrouce({}) inspect job Id({}) faield, status code:{} {}".format(resourceId, jobId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Set resrouce({}) inspect job Id({}) failed, {}".format(resourceId, jobId, ex))

    def getCmdbCiAttrs(self, resourceId, attrList):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'ciEntityId': resourceId,
            'attrList': attrList
        }

        try:
            response = self.httpJSON(self.apiMap['getCmdbCiAttrs'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    attrData = retObj['Return']['attrEntityData']
                    attrsMap = {}
                    for attrInfo in attrData.values():
                        name = attrInfo['name']
                        values = attrInfo['actualValueList']
                        if len(values) == 0:
                            attrsMap[name] = None
                        elif len(values) == 1:
                            attrsMap[name] = values[0]
                        else:
                            attrsMap = values

                    return attrsMap
                else:
                    raise AutoExecError("Get attributes for resourceId:{} failed, {}".format(resourceId, retObj['Message']))
            else:
                raise AutoExecError("Get attributes for resourceId:{} failed, status code:{} {}".format(resourceId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get attributes for resourceId:{} failed, {}".format(resourceId, ex))

    def getAccessEndpointConf(self, resourceId):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'tenant': self.context.tenant,
            'resourceId': resourceId
        }

        try:
            response = self.httpJSON(self.apiMap['getAccessEndpoint'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return']
                else:
                    raise AutoExecError("Get AccessEndpoint Config for {} failed, {}".format(resourceId, retObj['Message']))
            else:
                raise AutoExecError("Get AccessEndpoint Config for {} failed, status code:{} {}".format(resourceId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get AccessEndpoint Config for {} failed, {}".format(resourceId, ex))

    def getDeployIdPath(self, namePath):
        namePath = namePath.strip()
        dpNames = namePath.split('/')
        partsName = ('sysName', 'moduleName', 'envName')
        params = {}
        for idx in range(0, len(dpNames)):
            params[partsName[idx]] = dpNames[idx]
        params['tenant'] = self.context.tenant

        try:
            response = self.httpJSON(self.apiMap['getDeployIdPath'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return']
                else:
                    raise AutoExecError("Get deploy id path for {} failed, {}".format(namePath, retObj['Message']))
            else:
                raise AutoExecError("Get deploy id path for {} failed, status code:{} {}".format(namePath, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get deploy id path for {} failed, {}".format(namePath, ex))

    def getDeployRunnerGroup(self, sysId, moduleId, envId):
        idPath = '%s/%s/%s' % (sysId, moduleId, envId)
        params = {'sysId': sysId, 'moduleId': moduleId, 'envId': envId}
        params['tenant'] = self.context.tenant
        try:
            response = self.httpJSON(self.apiMap['getDeployRunnerGroup'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return']
                else:
                    raise AutoExecError("Get deploy runner group config for {} failed, {}".format(idPath, retObj['Message']))
            else:
                raise AutoExecError("Get deploy runner group config for {} failed, status code:{} {}".format(idPath, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get deploy runner group config for {} failed, {}".format(idPath, ex))

    def getCITxtFilePathList(self, resourceId):
        try:
            response = self.httpJSON(self.apiMap['getCITxtFilePathList'],  {'resourceId': resourceId})
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return'].get('tbodyList')
                else:
                    raise AutoExecError("Get config file list for ci:{} failed, {}".format(resourceId, retObj.get('Message')))
            else:
                raise AutoExecError("Get config file list for ci:{} failed, status code:{} {}".format(resourceId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get config file list for ci:{} failed, {}".format(resourceId, ex))

    def uploadFile(self, filePath, fileType='inspectconfigfile'):
        try:
            apiUri = self.apiMap['uploadFile']
            if apiUri[0] != "/":
                apiUri = '/' + apiUri + '?param=file&type=%s' % (fileType)

            url = self.serverBaseUrl + apiUri
            headers = self.getSignHeaders(apiUri)
            myFile = {'param': (None, 'file'),
                      'type': (None, fileType),
                      'file': (filePath, open(filePath, 'rb'), 'text/plain')}

            response = requests.post(url, files=myFile, headers=headers)

            retObj = response.json()
            if response.status_code == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return']
                else:
                    raise AutoExecError("Upload file:{} failed, {}".format(filePath, retObj.get('Message')))
            else:
                raise AutoExecError("Upload file:{} failed, status code:{} {}".format(filePath, response.status_code, json.dumps(retObj)))
        except Exception as ex:
            raise AutoExecError("Upload file:{} failed, {}".format(filePath, ex))

    def removeUploadedFile(self, fileId):
        try:
            response = self.httpJSON(self.apiMap['removeUploadedFile'],  {'fileId': fileId})
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') != 'OK':
                    raise AutoExecError("Remove uploaded file(fileId={}) failed, {}".format(fileId, retObj.get('Message')))
            else:
                raise AutoExecError("Remove uploaded file(fileId={}) failed, status code:{} {}".format(fileId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Remove uploaded file(fileId={}) failed, {}".format(fileId, ex))

    def txtFileInspectSave(self, params):
        try:
            objHint = 'CI(%s) file(%s):%s' % (params.get('resourceId'), params.get('pathId'), params.get('path'))
            response = self.httpJSON(self.apiMap['txtFileInspectSave'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') != 'OK':
                    raise AutoExecError("Save Inspect for {} failed, {}".format(objHint, retObj.get('Message')))
            else:
                raise AutoExecError("Save Inspect for {} failed, status code:{} {}".format(objHint, response.status, content))
        except Exception as ex:
            raise AutoExecError("Save Inspect for {} failed, {}".format(objHint, ex))

    def notifyInspectReport(self, params):
        try:
            jobId = params['jobId']
            response = self.httpJSON(self.apiMap['inspectReport'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') != 'OK':
                    raise AutoExecError("Notify inspect Report {} failed, {}".format(jobId, retObj['Message']))
            else:
                raise AutoExecError("Notify inspect Report {} failed, status code:{} {}".format(jobId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Notify inspect Report {} failed, {}".format(jobId, ex))

    def getResourceInfoList(self, ip, port, name, type):
        param = {"keyword": "", "searchMode": "text", "currentPage": 1, "pageSize": 10}
        conditionList = []
        conditionRelList = []
        uuid = {
            "ip": "c9cc49f2fbab454ca678361c5a3794cc",
            "port": "a04cff8b501c44f7a66b9c0b15e2f3d4",
            "name": "a72d187fde1b4114b5dbb35b633c5b62",
            "typeIdList": "bf12f6806aa6477086c7e1d7c7c9a52a"
        }
        valueList = []
        if ip is not None and ip != '':
            conditionList.append({"uuid": uuid['ip'], "name": "ip", "valueList": [ip], "expression": "equal"})
            valueList.append(uuid['ip'])

        if port is not None and port != '':
            conditionList.append({"uuid": uuid['port'], "name": "port", "valueList": [port], "expression": "equal"})
            valueList.append(uuid['port'])

        if name is not None and name != '':
            conditionList.append({"uuid": uuid['name'], "name": "name", "valueList": [name], "expression": "equal"})
            valueList.append(uuid['name'])

        if type is not None and type != '':
            conditionList.append({"uuid": uuid['typeIdList'], "name": "typeIdList", "valueList": [type], "expression": "like"})
            valueList.append(uuid['typeIdList'])

        conditionLen = len(valueList)
        if conditionLen > 1:
            count = 0
            for i in valueList:
                if (count + 1 > conditionLen - 1):
                    break
                form = valueList[count]
                to = valueList[count+1]
                conditionRelList.append({"joinType": "and", "from": form, "to": to})
                count = count + 1
            conditionGroupins = {"uuid": "6f81871c303b458b8be100ee64aa9506", "conditionList": conditionList, "conditionRelList": conditionRelList}
            conditionGroupList = []
            conditionGroupList.append(conditionGroupins)
            param["conditionGroupList"] = conditionGroupList

            try:
                response = self.httpJSON(self.apiMap['getResourceInfo'], param)
                charset = response.info().get_content_charset()
                content = response.read().decode(charset, errors='ignore')
                retObj = json.loads(content)
                if response.status == 200:
                    if retObj.get('Status') == 'OK':
                        return retObj['Return'].get('tbodyList')
                    else:
                        raise AutoExecError("Get Resource info ip:{}/name:{}/port:{}/type:{} failed, {}".format(ip, name, port, type, retObj.get('Message')))
                else:
                    raise AutoExecError("Get Resource info ip:{}/name:{}/port:{}/type:{} failed, status code:{} {}".format(ip, name, port, type, response.status, content))
            except Exception as ex:
                raise AutoExecError("Get Resource info ip:{}/name:{}/port:{}/type:{} failed, {}".format(ip, name, port, type, ex))
        else:
            raise AutoExecError("Get Resource info  ip:{}/name:{}/port:{}/type:{} failed, parameter empty or not value.".format(ip, name, port, type))

    def saveVersionMetrics(self, data):
        try:
            response = self.httpJSON(self.apiMap['saveVersionMetrics'], data)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj
                else:
                    raise AutoExecError("saveVersionMetrics {} {}".format(data, content))
            else:
                raise AutoExecError("saveVersionMetrics: ".format(content))
        except AutoExecError:
            raise
        except Exception as ex:
            raise AutoExecError("saveVersionMetrics {} failed, {}".format(data, ex))

    def saveVersionCveList(self, data):
        try:
            response = self.httpJSON(self.apiMap['saveVersionCveList'], data)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj
                else:
                    raise AutoExecError("saveVersionCveList {} {}".format(data, content))
            else:
                raise AutoExecError("saveVersionCveList: ".format(content))
        except AutoExecError:
            raise
        except Exception as ex:
            raise AutoExecError("saveVersionCveList {} failed, {}".format(data, ex))

    def getJobStatus(self, params):
        try:
            jobId = params['jobId']
            response = self.httpJSON(self.apiMap['getJobStatus'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') != 'OK':
                    raise AutoExecError("getJobStatus {} failed, {}".format(jobId, retObj['Message']))
                
                return retObj.get('Return').get('status')
            else:
                raise AutoExecError("getJobStatus {} failed, status code:{} {}".format(jobId, response.status, content))
        except Exception as ex:
            raise AutoExecError("getJobStatus {} failed, {}".format(jobId, ex))

