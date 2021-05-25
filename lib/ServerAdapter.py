#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import sys
import os
import stat
import fcntl
import ssl
import time
import json
import base64
import urllib.request
import urllib.parse
from urllib.error import URLError
from urllib.error import HTTPError

from AutoExecError import AutoExecError


class ServerAdapter:

    def __init__(self, context):
        ssl._create_default_https_context = ssl._create_unverified_context

        # api路径的映射
        self.apiMap = {
            'register': '/codedriver/public/api/rest/autoexec/tool/register',
            'getParams': '/codedriver/public/api/rest/autoexec/job/create/param/get',
            'getNodes': '/codedriver/public/api/binary/autoexec/job/phase/nodes/download',
            'fetchFile': '/codedriver/public/api/binary/autoexec/job/phase/nodes/download',
            'fetchScript': '/codedriver/public/api/rest/autoexec/script/active/version/get',
            'updateNodeStatus': '/codedriver/public/api/rest/autoexec/job/phase/node/status/update',
            'updatePhaseStatus': '/codedriver/public/api/rest/autoexec/job/phase/status/update',
            'fireNextPhase': '/codedriver/public/api/rest/autoexec/job/status/update',
        }

        self.context = context
        self.serverBaseUrl = context.config.get('server', 'server.baseurl')
        if(self.serverBaseUrl[-1] != '/'):
            self.serverBaseUrl = self.serverBaseUrl + '/'

        self.serverUserName = context.config.get('server', 'server.username')
        self.serverPassword = context.config.get('server', 'server.password')
        self.authToken = 'Basic ' + str(base64.b64encode(bytes(self.serverUserName + ':' + self.serverPassword, 'utf-8')).decode('ascii'))

    def addHeaders(self, request, headers):
        for k, v in headers.items():
            request.add_header(k, v)

    def httpPOST(self, apiUri, authToken, params):
        url = self.serverBaseUrl + apiUri
        userAgent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'

        headers = {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
                   'User-Agent': userAgent,
                   'Tenant': self.context.tenant,
                   'Authorization': authToken}

        data = urllib.parse.urlencode(params)
        req = urllib.request.Request(url, bytes(data, 'utf-8'))
        self.addHeaders(req, headers)
        try:
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            errMsg = ex.code
            if ex.code > 500:
                content = ex.read()
                errObj = json.loads(content)
                errMsg = errObj['Message']
            raise AutoExecError('Request url:{} failed, {}'.format(url, errMsg, ex))
        except URLError as ex:
            raise AutoExecError('Request url:{} failed, {}'.format(url, ex.reason))
        return response

    def httpGET(self, apiUri, authToken, params):
        url = self.serverBaseUrl + apiUri
        userAgent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'
        headers = {'User-Agent': userAgent,
                   'Tenant': self.context.tenant,
                   'Authorization': authToken}

        data = urllib.parse.urlencode(params)
        url = url + '?' + data
        req = urllib.request.Request(url)
        self.addHeaders(req, headers)

        try:
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            errMsg = ex.code
            if ex.code > 500:
                content = ex.read()
                errObj = json.loads(content)
                errMsg = errObj['Message']
            raise AutoExecError('Request url:{} failed, {}'.format(url, errMsg, ex))
        except URLError as ex:
            raise AutoExecError('Request url:{} failed, {}'.format(url, ex.reason))

        return response

    def httpJSON(self, apiUri, authToken, params):
        url = self.serverBaseUrl + apiUri
        userAgent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'
        headers = {'Content-Type': 'application/json; charset=utf-8',
                   'User-Agent': userAgent,
                   'Tenant': self.context.tenant,
                   'Authorization': authToken, }

        req = urllib.request.Request(url, bytes(json.dumps(params), 'utf-8'))
        self.addHeaders(req, headers)

        try:
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            errMsg = ex.code
            if ex.code > 500:
                content = ex.read()
                errObj = json.loads(content)
                errMsg = errObj['Message']
            raise AutoExecError('Request url:{} failed, {}'.format(url, errMsg, ex))
        except URLError as ex:
            raise AutoExecError('Request url:{} failed, {}'.format(url, ex.reason))

        return response

    # 获取作业的运行参数文件params.json
    def getParams(self):
        params = {
            'jobId': self.context.jobId
        }

        # response = self.httpPOST(self.apiMap['getParams'], self.authToken, params)
        response = self.httpGET(self.apiMap['getParams'], self.authToken, params)

        paramsFilePath = self.context.paramsFilePath
        paramsFile = open(paramsFilePath, 'w')

        for line in response:
            paramsFile.write(str(line, encoding='utf-8'))
            paramsFile.write("\n")

        paramsFile.close()

    # 下载运行作业或作业某个阶段的运行目标节点
    def getNodes(self, phase=None):
        params = {
            'jobId': self.context.jobId,
            'phase': ''
        }

        if phase is not None:
            params['phase'] = phase

        lastModifiedTime = 0
        nodesFilePath = self.context.getNodesFilePath(phase)
        if os.path.exists(nodesFilePath):
            lastModifiedTime = os.path.getmtime(nodesFilePath)

        params['lastModified'] = lastModifiedTime

        # response = self.httpPOST(self.apiMap['getNodes'], self.authToken, params)
        response = self.httpGET(self.apiMap['getNodes'], self.authToken, params)

        if response.status == 200:
            nodesFile = open(nodesFilePath, 'w')

            for line in response:
                nodesFile.write(str(line, encoding='utf-8'))
                nodesFile.write("\n")

            nodesFile.close()

            if response.status == 205:
                # 如果阶段playbook的运行节点跟pipeline一致，阶段节点使用作业节点
                pass
            elif response.status == 204:
                # 如果当前已经存在阶段节点文件，而且修改时间大于服务端，则服务端api给出204反馈，代表没有更改，不需要处理
                pass

    # 更新运行阶段某个节点的状态到服务端
    def pushNodeStatus(self, phaseName, runNode, status, failIgnore):
        if self.context.devMode:
            return

        params = {
            'jobId': self.context.jobId,
            'phase': phaseName,
            'nodeId': runNode.node,
            'output': runNode.output,
            'status': status,
            'failIgnore': failIgnore,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON(self.apiMap['updateNodeStatus'], self.authToken, params)

        try:
            content = response.read()
            return json.loads(content)
        except:
            return None

    # 更新运行端阶段的状态
    def pushPhaseStatus(self, phaseName, status, fireNext=0):
        if self.context.devMode:
            return

        params = {
            'jobId': self.context.jobId,
            'phase': phaseName,
            'status': status,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON(self.apiMap['updatePhaseStatus'], self.authToken, params)

        try:
            content = response.read()
            return json.loads(content)
        except:
            return None

    # 通知后端进行下一个阶段的调度，后端根据当前phase的全局节点运行状态判断是否调度下一个阶段
    def fireNextPhase(self, phaseName):
        if self.context.devMode:
            return

        params = {
            'jobId': self.context.jobId,
            'phase': phaseName,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON(self.apiMap['fireNextPhase'], self.authToken, params)

        try:
            content = response.read()
            return json.loads(content)
        except:
            return None

    # 下载操作运行参数的文件参数对应的文件，下载到cache目录
    def fetchFile(self, savePath, fileId):
        params = {
            'id': fileId
        }

        cachedFilePath = savePath + '/' + fileId
        lastModifiedTime = 0
        if os.path.exists(cachedFilePath):
            lastModifiedTime = os.path.getmtime(cachedFilePath)

        params['lastModified'] = lastModifiedTime

        url = self.serverBaseUrl + self.apiMap['fetchFile']

        cachedFile = None
        fileName = None
        response = None
        try:
            cachedFile = open(cachedFilePath, 'wb+')
            response = self.httpGET(self.apiMap['fetchFile'], self.authToken, params)
            # 获取下载文件的文件名，服务端通过header传送文件名, 例如：'Content-Disposition: attachment; filename="myfile.tar.gz"'
            resHeaders = response.info()
            contentDisposition = resHeaders['Content-Disposition']
            if contentDisposition is not None:
                fileNameIdx = contentDisposition.index('filename="')
                if fileNameIdx > 0:
                    fileName = contentDisposition[fileNameIdx+10:-1]

            if response.status == 200:
                fcntl.lockf(cachedFile, fcntl.LOCK_EX)
                cachedFile.truncate(0)
                CHUNK = 16 * 1024
                while True:
                    chunk = response.read(CHUNK)
                    if not chunk:
                        break
                    cachedFile.write(chunk)
            return fileName
        except:
            if response is None or response.status != 204:
                raise
        finally:
            if cachedFile is not None:
                fcntl.lockf(cachedFile, fcntl.LOCK_UN)
                cachedFile.close()

    # 从自定义脚本库下载脚本到脚本目录
    def fetchScript(self, savePath, scriptId):
        params = {
            'operationId': scriptId
        }

        cachedFilePath = savePath
        lastModifiedTime = 0
        if os.path.exists(cachedFilePath):
            lastModifiedTime = os.path.getmtime(cachedFilePath)

        params['lastModified'] = lastModifiedTime

        url = self.serverBaseUrl + self.apiMap['fetchScript']

        cachedFile = None
        response = None
        try:
            cachedFile = open(cachedFilePath, 'w+')
            response = self.httpGET(self.apiMap['fetchScript'], self.authToken, params)

            if response.status == 200:
                retObj = json.loads(response.read())
                scriptContent = retObj['Return']['script']

                fcntl.lockf(cachedFile, fcntl.LOCK_EX)
                cachedFile.truncate(0)
                cachedFile.write(scriptContent)
        except:
            if response is None or response.status != 204:
                raise
        finally:
            if cachedFile is not None:
                fcntl.lockf(cachedFile, fcntl.LOCK_UN)
                cachedFile.close()
                os.chmod(savePath, stat.S_IRWXU)

        return savePath

    # 注册native工具到服务端工具库
    def registerTool(self, toolObj):
        response = self.httpJSON(self.apiMap['register'], self.authToken, toolObj)

        try:
            content = response.read()
            return json.loads(content)
        except:
            return None
