#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 提供读取节点文件，遍历节点，更新节点运行状态功能
"""
import sys
import os
import json
import Utils
import RunNode


class RunNodeFactory:

    def __init__(self, context, phaseName=None, phaseGroup=None):
        self.context = context
        self.phaseName = phaseName
        self.nodesFile = None

        nodesFilePath = context.getNodesFilePath(phaseName=phaseName)
        if not os.path.isfile(nodesFilePath):
            nodesFilePath = context.getNodesFilePath(phaseGroup=phaseGroup)
            if not os.path.isfile(nodesFilePath):
                nodesFilePath = context.getNodesFilePath()
        self.nodesFile = open(nodesFilePath)

        # 第一行是节点运行描述信息，包括节点总数，local运行节点ID等信息
        line = self.nodesFile.readline()
        # self.nodesFile.seek(0)
        self.nodesCount = 0
        self.localRunnerId = 1
        try:
            nodesDescObj = json.loads(line)
            if 'totalCount' in nodesDescObj:
                self.nodesCount = int(nodesDescObj['totalCount'])
                self.localRunnerId = nodesDescObj['localRunnerId']
        except:
            pass

    def __del__(self):
        if self.nodesFile is not None:
            self.nodesFile.close()

    def localRunNode(self):
        localRunNode = None
        if self.context.runnerId == self.localRunnerId:
            # 如果当前runner是指定运行local阶段的runner
            localNode = self.localNode()
            localRunNode = RunNode.RunNode(self.context, self.phaseName, localNode)
        return localRunNode

    def nextRunNode(self):
        runNode = None
        nodeObj = self.nextNode()
        if nodeObj is not None:
            runNode = RunNode.RunNode(self.context, self.phaseName, nodeObj)
        return runNode

    def localNode(self):
        localNode = {"nodeId": 0, "resourceId": 0, "protocol": "local", "host": "local", "port": 0, "username": "", "password": ""}
        return localNode

    def nextNode(self):
        nodeObj = None
        line = None
        # 略掉空行
        while True:
            line = self.nodesFile.readline()
            if not line:
                break
            if line.strip() != '':
                # break
                if self.context.nodesToRun is not None:
                    nodeObj = json.loads(line)
                    if nodeObj['nodeId'] in self.context.nodesToRun:
                        break
                else:
                    nodeObj = json.loads(line)
                    break

        if line:
            if 'password' in nodeObj:
                password = nodeObj['password']
                if password.startswith('{ENCRYPTED}'):
                    password = Utils._rc4_decrypt_hex(self.context.MY_KEY, password[11:])
                    nodeObj['password'] = password
            else:
                nodeObj['password'] = ''

            if 'username' not in nodeObj:
                nodeObj['username'] = 'anonymous'

            if 'protocolPort' not in nodeObj or nodeObj['protocolPort'] == '':
                if 'port' in nodeObj:
                    nodeObj['protocolPort'] = nodeObj['port']
        else:
            self.nodesFile.close()

        return nodeObj
