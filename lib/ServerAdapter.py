#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import sys
import os
import json
import base64
import urllib.request
import urllib.parse
from urllib.error import URLError
from urllib.error import HTTPError

from AutoExecError import AutoExecError


class ServerAdapter:

    def __init__(self, context):
        # api路径的映射
        self.apiMap = {
            'getparams': 'params.json',
            'getnodes': 'nodes.json',
            'fetchfile': 'fetchfile'
        }

        self.context = context
        self.serverBaseUrl = context.config.get('server', 'server.baseurl')
        if(self.serverBaseUrl[-1] != '/'):
            self.serverBaseUrl = self.serverBaseUrl + '/'

        self.serverUserName = context.config.get('server', 'server.username')
        self.serverPassword = context.config.get('server', 'server.password')
        self.authToken = 'Basic ' + str(base64.b64encode(bytes(self.serverUserName + ':' + self.serverPassword, 'utf-8')))

    def addHeaders(self, request, headers):
        for k, v in headers.items():
            request.add_header(k, v)

    def httpPOST(self, apiUri, authToken, params):
        url = self.serverBaseUrl + apiUri
        userAgent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'

        headers = {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
                   'User-Agent': userAgent,
                   'Authorization': authToken}

        data = urllib.parse.urlencode(params)
        req = urllib.request.Request(url, bytes(data, 'utf-8'))
        self.addHeaders(req, headers)
        try:
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            raise AutoExecError('Request url:{} failed, {}'.format(url, ex.code, ex))
        except URLError as ex:
            raise AutoExecError('Request url:{} failed, {}'.format(url, ex.reason))
        return response

    def httpGET(self, apiUri, authToken, params):
        url = self.serverBaseUrl + apiUri
        userAgent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'
        headers = {'User-Agent': userAgent,
                   'Authorization': authToken}

        data = urllib.parse.urlencode(params)
        req = urllib.request.Request(url + '?' + data)
        self.addHeaders(req, headers)

        try:
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            raise AutoExecError('Request url:{} failed, {}'.format(url, ex.code, ex))
        except URLError as ex:
            raise AutoExecError('Request url:{} failed, {}'.format(url, ex.reason))

        return response

    def httpJSON(self, apiUri, authToken, params):
        url = self.serverBaseUrl + apiUri
        userAgent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'
        headers = {'Content-Type': 'application/json; charset=utf-8',
                   'User-Agent': userAgent,
                   'Authorization': authToken}

        req = urllib.request.Request(url, bytes(json.dumps(params), 'utf-8'))
        self.addHeaders(req, headers)

        try:
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            raise AutoExecError('Request url:{} failed, {}'.format(url, ex.code, ex))
        except URLError as ex:
            raise AutoExecError('Request url:{} failed, {}'.format(url, ex.reason))

        return response

    def getParams(self):
        params = {
            'jobId': self.context.jobId
        }

        # response = self.httpPOST(self.apiMap['getparams'], self.authToken, params)
        response = self.httpGET(self.apiMap['getparams'], self.authToken, params)

        paramsFilePath = self.context.paramsFilePath
        paramsFile = open(paramsFilePath, 'w')

        for line in response:
            paramsFile.write(str(line, encoding='utf-8'))
            paramsFile.write("\n")

        paramsFile.close()

    def getNodes(self, phase=None):
        params = {
            'jobId': self.context.jobId
        }

        if phase is not None:
            params['phase'] = phase

        # response = self.httpPOST(self.apiMap['getnodes'], self.authToken, params)
        response = self.httpGET(self.apiMap['getnodes'], self.authToken, params)

        if response.status == 200:
            nodesFilePath = self.context.nodesFilePath
            nodesFile = open(nodesFilePath, 'w')

            for line in response:
                nodesFile.write(str(line, encoding='utf-8'))
                nodesFile.write("\n")

            nodesFile.close()
        elif response.status == 304:
            # 如果阶段playbook的运行节点跟pipeline一致，则服务端api给出304反馈，代表没有更改，不需要处理
            pass

    def pushNodeStatus(self, runNode, status, consumeTime):
        if self.context.devMode:
            return

        params = {
            'jobId': self.context.jobId,
            'nodeId': runNode.node,
            'output': runNode.output,
            'status': status,
            'time': consumeTime,
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON('nodeStatusNotify', self.authToken, params)

    def pushPhaseStatus(self, phaseName, status, consumeTime, fireNext):
        if self.context.devMode:
            return

        params = {
            'jobId': self.context.jobId,
            'phaseName': phaseName,
            'status': status,
            'time': consumeTime,
            'fireNext': fireNext,
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON('phaseStatusNotify', self.authToken, params)

    def fetchFile(self, savePath, fileId):
        params = {
            'fileId': fileId
        }

        cachedFilePath = savePath + '/' + fileId
        lastModifiedTime = 0
        if os.path.exists(cachedFilePath):
            lastModifiedTime = os.path.getmtime(cachedFilePath)

        params['lastModifed'] = lastModifiedTime

        url = self.serverBaseUrl + self.apiMap['fetchfile']

        fileName = None
        response = None
        try:
            response = self.httpGET(self.apiMap['fetchfile'], self.authToken, params)
            # 获取下载文件的文件名，服务端通过header传送文件名, 例如：'Content-Disposition: attachment; filename="myfile.tar.gz"'
            resHeaders = response.info()
            contentDisposition = resHeaders['Content-Disposition']
            if contentDisposition is not None:
                fileNameIdx = contentDisposition.index('filename="')
                if fileNameIdx > 0:
                    fileName = contentDisposition[fileNameIdx+10:-1]

            if response.status == 200:
                CHUNK = 16 * 1024
                with open(cachedFilePath, 'wb') as f:
                    while True:
                        chunk = response.read(CHUNK)
                        if not chunk:
                            break
                        f.write(chunk)
                    f.close()
        except:
            if response is None or response.status != 304:
                raise

        return fileName
