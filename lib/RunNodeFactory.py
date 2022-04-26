#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 提供读取节点文件，遍历节点，更新节点运行状态功能
"""
import os
import json
import Utils
import RunNode


class RunNodeFactory:

    def __init__(self, context, phaseName=None, groupNo=None):
        self.context = context
        self.phaseName = phaseName
        self.nodesFile = None

        nodesFilePath = context.getNodesFilePath(phaseName=phaseName, groupNo=groupNo)
        if not os.path.isfile(nodesFilePath):
            nodesFilePath = context.getNodesFilePath()
        self.nodesFile = open(nodesFilePath)

        # 第一行是节点运行描述信息，包括节点总数，local运行节点ID等信息
        line = self.nodesFile.readline()
        # self.nodesFile.seek(0)
        self.nodesCount = 0
        self.localRunnerId = 1
        self.jobRunnerIds = []
        self.jobRunnerCount = 0
        try:
            nodesDescObj = json.loads(line)
            self.nodesCount = int(nodesDescObj['totalCount'])
            self.localRunnerId = nodesDescObj['localRunnerId']
            self.jobRunnerIds = nodesDescObj['jobRunnerIds']
            self.jobRunnerCount = len(self.jobRunnerIds)
        except:
            pass

        if self.context.nodesToRun is not None:
            self.nodesCount = self.context.nodesToRunCount

    def __del__(self):
        if self.nodesFile is not None:
            self.nodesFile.close()

    def localRunNode(self):
        localRunNode = None
        localNode = self.localNode()
        if localNode is not None:
            localRunNode = RunNode.RunNode(self.context, self.phaseName, localNode)
        return localRunNode

    def nextRunNode(self):
        runNode = None
        nodeObj = self.nextNode(self.context.runnerId)
        if nodeObj is not None:
            runNode = RunNode.RunNode(self.context, self.phaseName, nodeObj)
        return runNode

    def localNode(self):
        localNode = None
        if self.context.runnerId == self.localRunnerId:
            # 如果当前runner是指定运行local阶段的runner
            localNode = {"nodeId": 0, "resourceId": 0, "protocol": "local", "host": "local", "port": 0, "username": "", "password": ""}
        return localNode

    def nextNode(self, runnerId=None):
        nodeObj = None
        line = None
        # 略掉空行
        while self.nodesFile is not None:
            line = self.nodesFile.readline()
            if not line:
                break
            if line.strip() != '':
                if runnerId is None:
                    nodeObj = json.loads(line)
                    if self.context.nodesToRun is not None:
                        if nodeObj['nodeId'] in self.context.nodesToRun:
                            break
                    else:
                        break
                else:
                    nodeObj = json.loads(line)
                    if nodeObj['runnerId'] == runnerId:
                        if self.context.nodesToRun is not None:
                            if nodeObj['nodeId'] in self.context.nodesToRun:
                                break
                        else:
                            break

        if line:
            if 'password' in nodeObj:
                password = nodeObj['password']
                if password.startswith('{ENCRYPTED}'):
                    password = Utils._rc4_decrypt_hex(self.context.passKey, password[11:])
                    nodeObj['password'] = password
            else:
                nodeObj['password'] = ''

            if 'username' not in nodeObj:
                nodeObj['username'] = 'anonymous'

            if 'protocolPort' not in nodeObj or nodeObj['protocolPort'] == '':
                if 'port' in nodeObj:
                    nodeObj['protocolPort'] = nodeObj['port']
        else:
            nodeObj = None
            if self.nodesFile is not None:
                self.nodesFile.close()
            self.nodesFile = None

        return nodeObj
