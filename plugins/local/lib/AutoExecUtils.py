#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 NeatLogic
"""

import os
import sys
import os.path
import fcntl
import socket
import json
import time
import binascii
import pymongo
import configparser
import ServerAdapter

PYTHON_VER = sys.version_info.major
AUTOEXEC_CONTEXT = None


class Context:
    def __init__(self, config, tenent=None):
        self.devMode = False
        self.tenant = tenent
        self.config = config
        self.jobId = os.getenv('AUTOEXEC_JOBID')
        self.fileFeteched = {}
        self.scriptFetched = {}
        self.opFetched = {}


def setEnv():
    pass


def getAutoexecContext():
    global AUTOEXEC_CONTEXT
    if AUTOEXEC_CONTEXT is None:
        homePath = os.path.split(os.path.realpath(__file__))[0]
        homePath = os.path.realpath(homePath + '/../../../')
        # 读取配置
        cfgPath = homePath + '/conf/config.ini'
        cfg = configparser.ConfigParser()
        cfg.read(cfgPath)

        config = {}
        for section in cfg.sections():
            config[section] = {}
            for confKey in cfg[section]:
                config[section][confKey] = cfg[section][confKey]

        serverPass = config['server']['server.password']
        passKey = config['server']['password.key']
        autoexecDBPass = config['autoexec'].get('db.password')

        MY_KEY = 'c3H002LGZRrseEPck9tsNgfXHJcl0USJ'
        if passKey.startswith('{ENCRYPTED}'):
            passKey = _rc4_decrypt_hex(MY_KEY, passKey[11:])
            config['server']['password.key'] = passKey

        if serverPass.startswith('{ENCRYPTED}'):
            serverPass = _rc4_decrypt_hex(passKey, serverPass[11:])
            config['server']['server.password'] = serverPass

        if autoexecDBPass and autoexecDBPass.startswith('{ENCRYPTED}'):
            autoexecDBPass = _rc4_decrypt_hex(passKey, autoexecDBPass[11:])
            config['autoexec']['db.password'] = autoexecDBPass

        AUTOEXEC_CONTEXT = Context(config, os.getenv('AUTOEXEC_TENANT'))
    return AUTOEXEC_CONTEXT


def saveOutput(outputData):
    outputPath = os.getenv('OUTPUT_PATH')
    print("INFO: Try save output to {}.\n".format(outputPath), end='')
    if outputPath is not None and outputPath != '':
        outputDir = os.path.dirname(outputPath)
        if not outputDir == '' and not os.path.exists(outputDir):
            os.makedirs(outputDir, exist_ok=True)
        outputFile = open(outputPath, 'w')
        outputFile.write(json.dumps(outputData, indent=4, ensure_ascii=False))
        outputFile.close()
        print("INFO: Save output success.\n", end='')
    else:
        print("WARN: Could not save output file, because of environ OUTPUT_PATH not defined.\n", end='')


def saveLiveData(outputData):
    outputPath = os.getenv('LIVEDATA_PATH')
    print("INFO: Try save output to {}.\n".format(outputPath), end='')
    if outputPath is not None and outputPath != '':
        outputDir = os.path.dirname(outputPath)
        if not outputDir == '' and not os.path.exists(outputDir):
            os.makedirs(outputDir, exist_ok=True)
        outputFile = open(outputPath, 'w')
        outputFile.write(json.dumps(outputData, indent=4, ensure_ascii=False))
        outputFile.close()
        print("INFO: Save output success.\n", end='')
    else:
        print("WARN: Could not save output file, because of environ OUTPUT_PATH not defined.\n", end='')


def getOutput(output_path):
    outputFile = open(output_path, "r", encoding="utf-8")
    data = json.load(outputFile)
    outputFile.close()
    return data


def _rc4(key, data):
    x = 0
    box = list(range(256))
    for i in range(256):
        x = (x + box[i] + ord(key[i % len(key)])) % 256
        box[i], box[x] = box[x], box[i]
    x = y = 0
    out = []
    for char in data:
        x = (x + 1) % 256
        y = (y + box[x]) % 256
        box[x], box[y] = box[y], box[x]
        out.append(chr(ord(char) ^ box[(box[x] + box[y]) % 256]))
    return ''.join(out)


def _rc4_decrypt_hex(key, data):
    if PYTHON_VER == 2:
        return _rc4(key, binascii.unhexlify(data))
    elif PYTHON_VER == 3:
        return _rc4(key, binascii.unhexlify(data.encode("latin-1")).decode("latin-1"))


def getDB():
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    serverAdapter.getMongoDBConf()

    cfg = context.config
    dburl = cfg['autoexec']['db.url']
    dbname = cfg['autoexec']['db.name']
    dbuser = cfg['autoexec']['db.username']
    dbpwd = cfg['autoexec']['db.password']

    dbclient = pymongo.MongoClient(dburl, username=dbuser, password=dbpwd)
    mydb = dbclient[dbname]

    return (dbclient, mydb)


def getMyNode():
    nodeJson = os.environ['AUTOEXEC_NODE']
    node = None

    if nodeJson is not None and nodeJson != '':
        node = json.loads(nodeJson)

    return node


def getNode(resourceId):
    matchNode = None

    if 'AUTOEXEC_NODES_PATH' in os.environ:
        nodesJsonPath = os.environ['AUTOEXEC_NODES_PATH']
        fh = open(nodesJsonPath, 'r')

        while True:
            line = fh.readline()
            if not line:
                break
            node = json.loads(line)
            if node.get('resourceId') == resourceId:
                matchNode = node

    return matchNode


def loadNodeOutput():
    output = {}
    outputPath = os.getenv('NODE_OUTPUT_PATH')
    # 加载操作输出并进行合并
    if os.path.exists(outputPath):
        outputFile = None
        try:
            outputFile = open(outputPath, 'r')
            fcntl.flock(outputFile, fcntl.LOCK_SH)
            content = outputFile.read()
            if content:
                output = json.loads(content)
        except Exception as ex:
            print('ERROR: Load output file:{}, failed {}\n'.format(outputPath, ex))
        finally:
            if outputFile is not None:
                fcntl.flock(outputFile, fcntl.LOCK_UN)
                outputFile.close()
    else:
        print('WARN: Output file:{} not found.\n'.format(outputPath))

    return output


def getOutput(varKey):
    lastDotPos = varKey.rindex('.')
    varName = varKey[lastDotPos+1:]
    pluginId = varKey[0:lastDotPos]
    output = loadNodeOutput()
    pluginOut = output.get(pluginId)

    val = None
    if pluginOut is not None:
        val = pluginOut.get(varName)
    return val


def informNodeWaitInput(resourceId, title=None, opType='button', message='Please select', options=None, role=None, pipeFile=None):
    sockPath = os.getenv('AUTOEXEC_JOB_SOCK')
    phaseName = os.getenv('AUTOEXEC_PHASE_NAME')
    if os.path.exists(sockPath):
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            client.connect(sockPath)
            request = {}
            request['action'] = 'informNodeWaitInput'
            request['phaseName'] = phaseName
            request['resourceId'] = resourceId

            if (options is not None and (isinstance(options, tuple) or isinstance(options, list))):
                request['interact'] = {
                    'title': title,  # 交互操作标题
                    'opType': opType,  # 类型：button|input|select|mselect
                    'message': message,  # 交互操作文案
                    'options': options,  # 操作列表json数组，譬如：["commit","rollback"]
                    'role': role,  # 可以操作此操作的角色，如果空代表不控制
                    'pipeFile': pipeFile  # 交互管道文件
                }
            else:
                request['interact'] = None

            client.send(json.dumps(request))
            client.close()
            print("INFO: Inform node:{} udpate status to waitInput success.\n".format(resourceId))
        except Exception as ex:
            print("WARN: Inform node:{} udpate status to waitInput failed, {}\n".format(resourceId, ex))
    else:
        print("WARN: Inform node:{} update status to waitInput failed:socket file {} not exist.\n".format(resourceId, sockPath))
    return


def setJobEnv(onlyInProcess, items):
    if not items:
        return

    sockPath = os.getenv('AUTOEXEC_JOB_SOCK')
    if os.path.exists(sockPath):
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            client.connect(sockPath)
            request = {}
            request['action'] = 'setEnv'
            request['onlyInProcess'] = onlyInProcess
            request['items'] = items

            client.send(json.dumps(request))
            client.close()
        except Exception as ex:
            raise Exception('ERROR: Set job env failed, {}.\n'.format(str(ex)))
    return


def getNodes(phaseName=None, groupNo=None):
    nodesMap = {}

    nodesJsonPath = os.getenv('AUTOEXEC_NODES_PATH')

    if nodesJsonPath is not None:
        found = False
        nodesJsonDir = os.path.dirname(nodesJsonPath)
        if phaseName is not None:
            nodesJsonPath = '{}/nodes-ph-{}.json'.format(nodesJsonDir, phaseName)
            if os.path.exists(nodesJsonPath):
                found = True

        if not found and groupNo is not None:
            nodesJsonPath = '{}/nodes-gp-{}.json'.format(nodesJsonDir, groupNo)
            if os.path.exists(nodesJsonPath):
                found = True

        if not found:
            nodesJsonPath = '{}/nodes.json'.format(nodesJsonDir)

        with open(nodesJsonPath, 'r') as fh:
            line = fh.readline()
            while True:
                line = fh.readline()
                if not line:
                    break
                node = json.loads(line)
                del node['password']
                nodesMap[node['resourceId']] = node
            fh.close()
    return nodesMap


def getNodesArray(phaseName=None, groupNo=None):
    nodesArray = []

    nodesJsonPath = os.getenv('AUTOEXEC_NODES_PATH')

    if nodesJsonPath is not None:
        found = False
        nodesJsonDir = os.path.dirname(nodesJsonPath)
        if phaseName is not None:
            nodesJsonPath = '{}/nodes-ph-{}.json'.format(nodesJsonDir, phaseName)
            if os.path.exists(nodesJsonPath):
                found = True

        if not found and groupNo is not None:
            nodesJsonPath = '{}/nodes-gp-{}.json'.format(nodesJsonDir, groupNo)
            if os.path.exists(nodesJsonPath):
                found = True

        if not found:
            nodesJsonPath = '{}/nodes.json'.format(nodesJsonDir)

        with open(nodesJsonPath, 'r') as fh:
            line = fh.readline()
            while True:
                line = fh.readline()
                if not line:
                    break
                node = json.loads(line)
                del node['password']
                nodesArray.append(node)
            fh.close()
    return nodesArray


def isJson(data):
    valid = False
    try:
        json.load(data, encoding='utf-8')
        valid = True
    except ValueError:
        pass
    return valid

# 以下几种JSON字符都会影响json字符串转换成JSON格式


def handleJsonstr(jsonstr):
    # 将字符串里的单引号替换成双引号
    jsonstr = jsonstr.replace('\'', '\"')
    # 带u'的字符串
    jsonstr = jsonstr.replace('u\'', '\'')
    # None数据
    jsonstr = jsonstr.replace('None', '""')
    return jsonstr


def getNodePwd(resourceId, host, port, username, protocol):
    context = getAutoexecContext()
    config = context.config
    passKey = config['server']['password.key']
    serverAdapter = ServerAdapter.ServerAdapter(context)
    pwdEncrypted = serverAdapter.getNodePwd(resourceId, host, port, username, protocol)
    if pwdEncrypted.startswith('{ENCRYPTED}'):
        nodePwd = _rc4_decrypt_hex(passKey, pwdEncrypted[11:])
    elif pwdEncrypted.startswith('{RC4}'):
        nodePwd = _rc4_decrypt_hex(passKey, pwdEncrypted[5:])
    return nodePwd


# def getInspectConf(ciType, resourceId):
#     context = getAutoexecContext()
#     serverAdapter = ServerAdapter.ServerAdapter(context)
#     return serverAdapter.getInspectConf(ciType, resourceId)


def updateInspectStatus(ciType, resourceId, status, alertCount):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.updateInspectStatus(ciType, resourceId, status, alertCount)


def updateMonitorStatus(ciType, resourceId, status, alertCount):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.updateMonitorStatus(ciType, resourceId, status, alertCount)


def setResourceInspectJobId(resourceId, jobId, phaseName):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.setResourceInspectJobId(resourceId, jobId, phaseName)


def getCmdbCiAttrs(resourceId, attrList):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.getCmdbCiAttrs(resourceId, attrList)


def getAccessEndpointConf(resourceId):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.getAccessEndpointConf(resourceId)


def getScript(scriptId):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.getScript(scriptId)


def getCITxtFilePathList(resoruceId):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.getCITxtFilePathList(resoruceId)


def uploadFile(filePath, fileType):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.uploadFile(filePath, fileType)


def removeUploadedFile(fileId):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.removeUploadedFile(fileId)


def txtFileInspectSave(params):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.txtFileInspectSave(params)


def notifyInspectReport(params):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.notifyInspectReport(params)


def getResourceInfoList(ip, port, name, type):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.getResourceInfoList(ip, port, name, type)

def saveVersionMetrics(data):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.saveVersionMetrics(data)

def saveVersionCveList(data):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.saveVersionCveList(data)

def getJobStatus(params):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.getJobStatus(params)
