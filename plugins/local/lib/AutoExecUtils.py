#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import sys
import socket
import json
import time
import binascii

PYTHON_VER = sys.version_info.major


def setEnv():
    pass


def saveOutput(outputData):
    if 'OUTPUT_PATH' in os.environ:
        outputPath = os.environ['OUTPUT_PATH']
        outputFile = open(outputPath, 'w')

        outputFile.write(json.dumps(outputData))
        outputFile.close()


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


def getMyNode(self):
    nodeJson = os.environ['AUTOEXEC_NODE']
    node = None

    if nodeJson is not None and nodeJson != '':
        node = json.load(nodeJson)

    return node


def getNode(nodeId):
    matchNode = None

    if 'AUTOEXEC_NODES_PATH' in os.environ:
        nodesJsonPath = os.environ['AUTOEXEC_NODES_PATH']
        fh = open(nodesJsonPath, 'r')

        while True:
            line = fh.readline()
            if not line:
                break
            node = json.loads(line)
            if node['nodeId'] == nodeId:
                matchNode = node

    return matchNode


def informNodeWaitInput(nodeId):
    sockPath = os.environ['AUTOEXEC_WORK_PATH'] + '/job.sock'
    if os.path.exists(sockPath):
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            client.connect(sockPath)
            request = {}
            request['action'] = 'informNodeWaitInput'
            request['nodeId'] = nodeId
            client.send(json.dumps(request))
            client.close()
            print("INFO: Inform node:{} udpate status to waitInput success.\n".format(nodeId))
        except Exception as ex:
            print("WARN: Inform node:{} udpate status to waitInput failed, {}\n".format(nodeId, ex))
    else:
        print("WARN: Inform node:{} update status to waitInput failed:socket file {} not exist.\n".format(nodeId, sockPath))
    return


def getNodes(self):
    nodesMap = {}

    if 'AUTOEXEC_NODES_PATH' in os.environ:
        nodesJsonPath = os.environ['AUTOEXEC_NODES_PATH']
        fh = open(nodesJsonPath, 'r')

        while True:
            line = fh.readline()
            if not line:
                break
            node = json.loads(line)
            nodesMap[node['nodeId']] = node

    return nodesMap


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

# 获取当前时间


def getCurrentTime():
    #return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
    return time.localtime()
