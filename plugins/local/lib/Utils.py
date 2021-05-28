#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import sys
import json
import time


class Utils:

    def __init__(self):
        pass

    def setEnv():
        pass

    def saveOutput(self, outputData):
        if 'OUTPUT_PATH' in os.environ:
            outputPath = os.environ['OUTPUT_PATH']
            outputFile = open(outputPath, 'w')

            outputFile.write(json.dumps(outputData))
            outputFile.close()

    def getOutput(self, output_path):
        outputFile = open(output_path, "r", encoding="utf-8")
        data = json.load(outputFile)
        outputFile.close()
        return data

    def getMyNode(self):
        nodeJson = os.environ['AUTOEXEC_NODE']
        node = None

        if nodeJson is not None and nodeJson != '':
            node = json.load(nodeJson)

        return node

    def getNode(self, nodeId):
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

    def isJson(self, data):
        valid = False
        try:
            json.load(data, encoding='utf-8')
            valid = True
        except ValueError:
            pass
        return valid

    # 以下几种JSON字符都会影响json字符串转换成JSON格式
    def handleJsonstr(self, jsonstr):
        # 将字符串里的单引号替换成双引号
        jsonstr = jsonstr.replace('\'', '\"')
        # 带u'的字符串
        jsonstr = jsonstr.replace('u\'', '\'')
        # None数据
        jsonstr = jsonstr.replace('None', '""')
        return jsonstr

    # 获取当前时间
    def getCurrentTime(self):
        return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
