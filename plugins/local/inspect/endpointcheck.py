#!/usr/bin/python
# -*- coding:UTF-8 -*-

import re
import AutoExecUtils
import os
import tempfile
import stat
import traceback
import datetime
import argparse
import sys
import json
import socket
import re
import requests
from http import cookiejar
import urllib
from urllib import request, parse, error
from urllib.error import URLError
from urllib.error import HTTPError
import time
import logging
import TagentClient
import select
import paramiko
from paramiko.sftp import SFTPError
from paramiko.ssh_exception import SSHException

from ping3 import ping


def usage():
    pname = os.path.basename(__file__)
    exit(1)


def pingCheck(host, timeOut):
    second = ping(dest_addr=host, timeout=timeOut)
    if second:
        print('INFO: {} is reachable, took {} second'.format(host, second))
        return (True, None)
    else:
        loopCount = 2
        while not second and loopCount > 0:
            second = ping(dest_addr=host, timeout=5)
            loopCount = loopCount - 1
        if second:
            print('INFO: {} is reachable, took {} second'.format(host, second))
            return (True, None)
        else:
            errorMsg = 'ERROR: {} is unreachable, took {} second'.format(host, second)
            print(errorMsg)
            return (False, errorMsg)


def tcpCheck(endPoint, timeOut):
    colonPos = endPoint.rindex(':')
    if colonPos < 0:
        errorMsg = "ERROR: Malform end point format: {}".format(endPoint)
        print(errorMsg)
        return (False, errorMsg)

    try:
        host = endPoint[0:colonPos]
        port = int(endPoint[colonPos+1:])
        sock = socket.socket()
        sock.settimeout(timeOut)
        sock.connect((host, port))
        print('INFO: Tcp handshake ' + endPoint + ' success.')
    except Exception as ex:
        errorMsg = "ERROR: Can not connect {}.".format(endPoint)
        print(errorMsg)
        return (False, errorMsg)

    return (True, None)


def urlCheck(endPoint, timeOut):
    url = endPoint
    userAgent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'

    req = urllib.request.Request(url)
    req.add_header('User-Agent', userAgent)

    try:
        response = urllib.request.urlopen(req, timeout=timeOut)
        print('INFO: Http request ' + endPoint + ' success.')
    except HTTPError as ex:
        errMsg = ex.code
        if ex.code > 500:
            content = ex.read()
        errorMsg = "ERROR: Request failed，status code{}, {}".format(ex.code, content)
        print(errorMsg)
        return (False, errorMsg)
    except URLError as ex:
        errorMsg = "ERROR: Request url:{} failed, {}".format(url, ex.reason)
        print(errorMsg)
        return (False, errorMsg)

    return (True, None)


def execOneHttpReq(urlConf, valuesJar, timeOut):
    url = urlConf['url']
    method = urlConf['method']
    data = urlConf['data']
    proxyStr = urlConf['proxy']
    matchKey = urlConf['matchKey']
    extractContent = urlConf['extractConf']

    dataContent = json.dumps(data, ensure_ascii=False)
    hasReplaced = False
    for varName, varValue in valuesJar.items():
        dataContent = dataContent.replace('\$\{' + varName + '\}', varValue)
    data = json.loads(dataContent)

    cookie = cookiejar.CookieJar()
    cookieHandler = request.HTTPCookieProcessor(cookie)
    httpHandler = request.HTTPHandler()
    httpsHandler = request.HTTPSHandler()
    proxyHandler = None
    if proxyStr is not None and proxyStr != '':
        proxyInfo = proxyStr.split('://', 1)
        proxy = {proxyInfo[0]: proxyInfo[1]}
        proxyHandler = request.ProxyHandler(proxy)

    opener = request.build_opener(httpHandler, httpsHandler, cookieHandler, proxyHandler)

    req = None
    if method == 'POST-FORM':
        formData = parse.urlencode(data).encode()
        req = request.Request(url, data=formData)
        req.add_header('Content-Type', 'application/x-www-form-urlencoded; charset=utf-8')
    elif method == 'POST-JSON':
        jsonData = json.dumps(data)
        req = request.Request(url, data=jsonData)
        req.add_header('Content-Type', 'application/json; charset=utf-8')
    else:
        formData = parse.urlencode(data).encode()
        req = request.Request(url + formData)

    userAgent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'
    req.add_header('User-Agent', userAgent)

    res = opener.open(req, timeout=timeOut)
    content = res.read().decode()
    print('INFO: Http request ' + url + ' success.')
    ret = True
    if matchKey is not None and matchKey != '':
        matchObj = re.search(matchKey, content)
        if matchObj is None:
            ret = False
            print("ERROR: Response content not match:" + matchKey + "\n")
            print(content)

    for varName in extractContent:
        pattern = extractContent[varName]
        matchObj = re.search(pattern, content)
        if matchObj:
            valuesJar[varName] = matchObj.group(1)

    return ret


def urlSeqCheck(urlSeq, timeOut):
    # url检查序列样例
    # [
    #     {
    #         "name": "查询1",
    #         "url": "http://abc.com.cn",
    #         "method": "POST-FORM|POST_JSON|GET",
    #         "data": {"key1": "value1", "key2": "value2"},
    #         "proxy": "http://proxy.com:8080",
    #         "matchKey": ["(key1)|(key2)", "key3", "key4"],
    #         "extractConf": {"varname1": "patter1n", "varname2": "pattern2"}
    #     },
    #     {
    #         "name": "查询2",
    #         "url": "http://abc.com.cn",
    #         "method": "POST-FORM|POST_JSON|GET",
    #         "data": {"key1": "value1", "key2": "${varname1}"},
    #         "proxy": "http://proxy.com:8080",
    #         "matchKey": ["(key1)|(key2)", "key3", "key4"],
    #         "extractConf": {"varname1": "patter1n", "varname2": "pattern2"}
    #     }
    # ]

    hasError = False
    for urlConf in urlSeq:
        try:
            ret = execOneHttpReq(urlConf, timeOut)
            if not ret:
                hasError = True
                break
        except Exception as ex:
            hasError = True
            print("ERROR: " + str(ex))
            break


def _remoteExecute(nodeInfo, scriptDef):
    self.childPid = None

    jobId = os.gentenv('AUTOEXEC_JOBID')
    resourceId = nodeInfo['resoruceId']
    host = nodeInfo['host']
    protocol = nodeInfo['protocol']
    protocolPort = nodeInfo['protocolPort']
    username = nodeInfo['username']
    password = nodeInfo['password']

    scriptName = getScriptFileName(scriptDef)
    scriptContent = scriptDef['script']

    output = ''
    scriptCmd = None
    remoteCmd = None
    killCmd = None

    ret = -1
    if protocol == 'tagent':
        scriptFile = None
        try:
            jobSubDir = 'autoexec-{}-{}'.format(jobId, resourceId)
            remoteRoot = '$TMPDIR/autoexec-{}-{}'.format(jobId, resourceId)
            remotePath = remoteRoot
            runEnv = {'AUTOEXEC_JOBID': jobId, 'AUTOEXEC_NODE': json.dumps(nodeInfo), 'HISTSIZE': '0'}
            killCmd = "kill -9 `ps aux |grep '" + remoteRoot + "'|grep -v grep|awk '{print $2}'`"

            tagent = TagentClient.TagentClient(host, protocolPort, password, readTimeout=360, writeTimeout=10)
            uploadRet = tagent.execCmd(username, 'cd $TMPDIR && mkdir ' + jobSubDir, env=None, isVerbose=0)
            uploadRet = tagent.writeFile(username, scriptContent, remotePath + '/' + scriptName)

            if uploadRet == 0:
                scriptCmd = getScriptCmd(scriptDef, tagent.agentOsType, remotePath)
                remoteCmd = 'cd {} && {}'.format(remotePath, scriptCmd)

                def getOutputLine(line):
                    print(line)
                    output = output + line
                    outLen = len(output)
                    if (outLen > 1024):
                        output = output[outLen-1024:]

                ret = tagent.execCmd(username, remoteCmd, env=runEnv, isVerbose=0, callback=getOutputLine)

                try:
                    if ret == 0:
                        if tagent.agentOsType == 'windows':
                            tagent.execCmd(username, "rd /s /q {}".format(remoteRoot), env=runEnv)
                        else:
                            tagent.execCmd(username, "rm -rf {}".format(remoteRoot), env=runEnv)
                except Exception as ex:
                    print('ERROR: Remote remove directory {} failed {}\n'.format(remoteRoot, ex))
        except Exception as ex:
            print("ERROR: Execute remote script {} failed, {}\n".format(scriptName, ex))
            raise ex

        if ret == 0:
            print("INFO: Execute remote script by agent succeed: {}\n".format(scriptCmd))
        else:
            print("ERROR: Execute remote script by agent failed: {}\n".format(scriptCmd))

    elif protocol == 'ssh':
        logging.getLogger("paramiko").setLevel(logging.FATAL)
        remoteRoot = '/tmp/autoexec-{}-{}'.format(jobId, resourceId)
        remotePath = remoteRoot
        remoteCmd = 'cd {} && HISTSIZE=0 AUTOEXEC_JOBID={} {}'.format(remotePath, jobId, scriptName)
        killCmd = "kill -9 `ps aux |grep '" + remoteRoot + "'|grep -v grep|awk '{print $2}'`"
        scriptFile = None
        uploaded = False
        hasError = False
        scp = None
        sftp = None
        try:
            print("INFO: Begin to upload remote script...\n")
            # 建立连接
            scp = paramiko.Transport((host, protocolPort))
            scp.connect(username=username, password=password)

            # 建立一个sftp客户端对象，通过ssh transport操作远程文件
            sftp = paramiko.SFTPClient.from_transport(scp)
            # Copy a local file (localpath) to the SFTP server as remotepath
            try:
                try:
                    sftp.stat(remoteRoot)
                except IOError:
                    sftp.mkdir(remoteRoot)
            except SFTPError as err:
                hasError = True
                print("ERROR: mkdir {} failed: {}\n".format(remoteRoot, err))

            tmp = tempfile.NamedTemporaryFile(delete=True)
            try:
                tmp.write(scriptContent)
                sftp.put(tmp.name, os.path.join(remotePath, scriptName))
            finally:
                tmp.close()

            sftp.chmod(os.path.join(remotePath, scriptName), stat.S_IXUSR)
            remoteCmd = 'cd {} && AUTOEXEC_JOBID={} AUTOEXEC_NODE=\'{}\' {}'.format(remotePath, jobId, json.dumps(nodeInfo), scriptCmd)

            if hasError == False:
                uploaded = True
        except Exception as err:
            print('ERROR: Upload script:{} to remoteRoot:{} failed: {}\n'.format(scriptName, remoteRoot, err))

        if uploaded:
            print("INFO: Upload script success, begin to execute remote operation...\n")
            ssh = None
            try:
                ret = 0
                ssh = paramiko.SSHClient()
                ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                ssh.connect(host, protocolPort, username, password)
                channel = ssh.get_transport().open_session()
                channel.set_combine_stderr(True)
                channel.exec_command(remoteCmd)
                while True:
                    r, w, x = select.select([channel], [], [], 10)
                    if len(r) > 0:
                        out = channel.recv(4096)
                        print(out)
                        output = output + out
                        outLen = len(output)
                        if (outLen > 1024):
                            output = output[outLen-1024:]
                    if channel.exit_status_ready():
                        ret = channel.recv_exit_status()
                        break

                try:
                    if ret == 0:
                        ssh.exec_command("rm -rf {}".format(remoteRoot, remoteRoot))
                except Exception as ex:
                    print("ERROR: Remove remote directory {} failed {}\n".format(remoteRoot, ex))

            except Exception as err:
                print("ERROR: Execute remote script {} failed, {}\n".format(scriptName, err))
            finally:
                if ssh:
                    ssh.close()

            if scp:
                scp.close()

        if ret == 0:
            print("INFO: Execute remote script by ssh succeed:{}\n".format(scriptCmd))
        else:
            print("ERROR: Execute remote script by ssh failed:{}\n".format(scriptCmd))

    result = False
    errorMsg = ''
    if ret == 0:
        result = True
    else:
        errorMsg = output
    return (result, errorMsg)


def getScriptFileName(scriptDef):
    extNameMap = {
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

    scriptFileName = None
    interpreter = scriptDef['config']['parser']
    if interpreter not in extNameMap:
        print("WARN: Can not determine script file extension name.")
        scriptFileName = scriptDef['config']['scriptName']
    else:
        scriptFileName = scriptDef['config']['scriptName'] + '.' + extNameMap[interpreter]
    return scriptFileName


def getScriptCmd(scriptDef, osType, remotePath):
    scriptFileName = getScriptFileName(scriptDef)
    interpreter = scriptDef['config']['parser']

    if osType == 'windows':
        # 如果是windows，windows的脚本执行必须要脚本具备扩展名,自定义脚本下载时会自动加上扩展名
        if interpreter == 'cmd':
            cmd = 'cmd /c {}/{}'.format(remotePath, scriptFileName)
        elif interpreter == 'vbscript' or interpreter == 'javascript':
            cmd = 'cscript {}/{}'.format(remotePath, scriptFileName)
        else:
            cmd = '{} {}/{}'.format(interpreter, remotePath, scriptFileName)
    else:
        if interpreter in ('sh', 'bash', 'csh'):
            cmd = '{} -l {}/{}'.format(interpreter, remotePath, scriptFileName)
        else:
            cmd = '{} {}/{}'.format(interpreter, remotePath, scriptFileName)


def executeRemoteScript(nodeInfo, scriptName, timeOut):
    ret = False
    errorMsg = ''
    resourceId = nodeInfo['resourceId']
    endPointConf = AutoExecUtils.getAccessEndpointConf(resourceId)
    if 'config' in endPointConf:
        scriptConf = endPointConf['config']
        if scriptConf['type'] != 'script':
            errorMsg = "ERROR: Config error, not script, {}".format(json.dumps(endPointConf))
            print(errorMsg)
        else:
            scriptId = scriptConf['script']
            scriptDef = AutoExecUtils.getScript(scriptId)
            (ret, errorMsg) = _remoteExecute(nodeInfo, scriptDef)
    else:
        errorMsg = "ERROR: Script config error."
    return (ret, errorMsg)


def saveInspectData(inspectData):
    out = {'DATA': inspectData}
    AutoExecUtils.saveOutput(out)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--node', default='', help='Execution node json')
    parser.add_argument('--timeout', default=10, help='Timeout value')
    args = parser.parse_args()

    timeOut = int(args.timeout)
    if timeOut == 0:
        timeOut = 5

    node = args.node

    try:
        nodeInfo = {}
        hasOptError = False
        if node is None:
            node = os.getenv('AUTOEXEC_NODE')
        if node is None or node == '':
            print("ERROR: Can not find node definition.\n")
            hasOptError = True
        else:
            nodeInfo = json.loads(node)

        if hasOptError:
            usage()

        hasError = False

        ip = nodeInfo['host']
        port = nodeInfo['port']
        resourceId = nodeInfo['resourceId']
        ciAttrs = AutoExecUtils.getCmdbCiAttrs(resourceId, ['access_type', 'access_endpoint'])

        accessEndPoint = ''
        if 'access_endpoint' in ciAttrs:
            accessEndPoint = ciAttrs['access_endpoint']
        accessType = None
        if 'access_type' in ciAttrs:
            accessType = ciAttrs['access_type']

        if accessType is None:
            if accessEndPoint.startswith('https://'):
                accessType = 'HTTPS'
            elif accessEndPoint.startswith('http://'):
                accessType = 'HTTP'
            elif re.match(':\d+$', accessEndPoint):
                accessType = 'TCP'
            else:
                accessType = 'PING'

        if accessEndPoint == '':
            if accessType in ['HTTP', 'HTTPS']:
                if port is not None:
                    accessEndPoint = '{}://{}:{}'.format(accessType.lower(), ip, port)
                else:
                    accessEndPoint = '{}://{}'.format(accessType.lower(), ip)
            elif ip is not None:
                if port is not None:
                    accessEndPoint = '{}:{}'.format(ip, port)
                else:
                    accessEndPoint = ip

        try:
            ret = False
            errorMsg = None
            startTime = time.time()
            if accessType in ('HTTP', 'HTTPS'):
                # url check
                (ret, errorMsg) = urlCheck(accessEndPoint, timeOut)
            elif accessType == 'TCP':
                # ip:port tcp
                (ret, errorMsg) = tcpCheck(accessEndPoint, timeOut)
            elif accessType == 'URL-SEQUENCE':
                (ret, errorMsg) = urlSeqCheck(nodeInfo, timeOut)
            elif accessType == 'BATCH':
                (ret, errorMsg) = executeRemoteScript(nodeInfo, timeOut)
            else:
                # ping
                (ret, errorMsg) = pingCheck(accessEndPoint, timeOut)

            if not ret:
                hasError = True

            timeConsume = time.time() - startTime
            inspectInfo = {'_OBJ_CATEGORY': 'EMPTY',
                           '_OBJ_TYPE': 'EMPTY',
                           'ACCESS_TYPE': accessType,
                           'ACCESS_ENDPOINT': accessEndPoint}
            if hasError:
                inspectInfo['AVAILABILITY'] = 0
                inspectInfo['ERROR_MESSAGE'] = errorMsg
                inspectInfo['RESPONSE_TIME'] = timeConsume
            else:
                inspectInfo['AVAILABILITY'] = 1
                inspectInfo['ERROR_MESSAGE'] = None
                inspectInfo['RESPONSE_TIME'] = timeConsume

            saveInspectData(inspectInfo)
        except Exception as ex:
            inspectInfo['AVAILABILITY'] = 0
            inspectInfo['ERROR_MESSAGE'] = str(ex)
            saveInspectData(inspectInfo)
    except Exception as ex:
        print('ERROR: Unknow Error, {}'.format(traceback.format_exc()))
        exit(-1)
