#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Copyright © 2017 NeatLogic
提供读取节点文件，遍历节点，更新节点运行状态功能
"""
import os
import json
import Utils
import RunNode


class RunNodeFactory:

    def __init__(self, context, phaseIndex=0, phaseName=None, phaseType=None, groupNo=None):
        self.context = context
        self.groupNo = groupNo
        self.phaseIndex = phaseIndex
        self.phaseName = phaseName
        self.phaseType = phaseType
        self.nodesFile = None
        self.cleared = False
        self.lastRound = True

        nodesFilePath = context.getNodesFilePath(phaseName=phaseName, groupNo=groupNo)
        if not os.path.isfile(nodesFilePath):
            nodesFilePath = context.getNodesFilePath(groupNo=groupNo)
        if not os.path.isfile(nodesFilePath):
            nodesFilePath = context.getNodesFilePath()
        self.nodesFile = open(nodesFilePath)

        seqDescFilePath = nodesFilePath + ".desc"
        if os.path.isfile(seqDescFilePath):
            with open(seqDescFilePath) as seqDescFile:
                descContent = seqDescFile.read()
                if descContent is None or descContent == "":
                    descContent = '{"maxParallel": 1, "roundDef": []}'
                self.seqDesc = json.loads(descContent)
                seqDescFile.close()
        else:
            self.seqDesc = None

        # 第一行是节点运行描述信息，包括节点总数，local运行节点ID等信息
        line = self.nodesFile.readline()
        # self.nodesFile.seek(0)
        self.nodesCount = 0
        self.totalNodesCount = 1
        self.localRunnerId = 1
        self.jobRunnerIds = []
        self.jobRunnerCount = 0
        try:
            nodesDescObj = json.loads(line)
            self.nodesCount = int(nodesDescObj.get("totalCount", 0))
            self.totalNodesCount = self.nodesCount
            self.localRunnerId = nodesDescObj.get("localRunnerId", 0)
            self.jobRunnerIds = nodesDescObj.get("jobRunnerIds", [])
            self.jobRunnerCount = len(self.jobRunnerIds)
        except:
            pass

        if self.context.nodesToRun is not None:
            self.nodesCount = self.context.nodesToRunCount

    def __del__(self):
        if self.nodesFile is not None:
            self.nodesFile.close()

    def setLastRound(self):
        self.lastRound = True

    def localRunNode(self):
        localRunNode = None
        localNode = self.localNode()
        if localNode is not None:
            localRunNode = RunNode.RunNode(self.context, self.groupNo, self.phaseIndex, self.phaseName, self.phaseType, localNode)
        self.cleared = True
        return localRunNode

    def nextRunNode(self):
        runNode = None
        nodeObj = self.nextNode(self.context.runnerId)
        if nodeObj is not None:
            runNode = RunNode.RunNode(self.context, self.groupNo, self.phaseIndex, self.phaseName, self.phaseType, nodeObj, self.totalNodesCount)
        else:
            self.cleared = True
        return runNode

    def localNode(self):
        localNode = None
        if self.context.runnerId == self.localRunnerId:
            # 如果当前runner是指定运行local阶段的runner
            localNode = {"resourceId": 0, "protocol": "local", "host": "local", "port": 0, "username": "", "password": ""}
        self.cleared = True
        return localNode

    def getSeqParallelCount(self):
        if self.seqDesc is None:
            return 1
        return self.seqDesc.get("maxParallel", 1)

    def getSeqRoundCount(self):
        if self.seqDesc is None:
            return None
        roundsDef = self.seqDesc.get("roundDef", [])
        return len(roundsDef)

    def getRoundSeqNo(self, roundNo):
        if self.seqDesc is None:
            return 1
        roundsDef = self.seqDesc.get("roundDef", [])
        if roundNo <= len(roundsDef):
            return roundsDef[roundNo - 1][0]
        else:
            return 0

    def getRoundSeqCount(self, roundNo):
        if self.seqDesc is None:
            return 1
        roundsDef = self.seqDesc.get("roundDef", [])
        if roundNo <= len(roundsDef):
            return roundsDef[roundNo - 1][1]
        else:
            return 1

    def goFirstLine(self):
        self.nodesFile.seek(0, os.SEEK_SET)
        self.nodesFile.readline()

    def nextNode(self, runnerId=None, seqNo=None):
        nodeObj = None
        line = None
        # 略掉空行
        while self.nodesFile is not None:
            nodeObj = None
            line = self.nodesFile.readline()
            if not line:
                break
            if line.strip() != "":
                nodeObj = json.loads(line)
                if self.context.nodesToRun is not None:
                    if nodeObj.get("resourceId") in self.context.nodesToRun:
                        break
                    else:
                        continue

                if seqNo is not None and nodeObj.get("seqNo", 0) != seqNo:
                    continue

                if runnerId is None or nodeObj.get("runnerId", None) == runnerId:
                    break

        if line:
            if "password" in nodeObj:
                password = nodeObj["password"]
                if password[0:11] == "{ENCRYPTED}":
                    password = Utils._rc4_decrypt_hex(self.context.passKey, password[11:])
                elif password[0:5] == "{RC4}":
                    password = Utils._rc4_decrypt_hex(self.context.passKey, password[5:])
                elif password[0:4] == "RC4:":
                    password = Utils._rc4_decrypt_hex(self.context.passKey, password[4:])
                nodeObj["password"] = password
            else:
                nodeObj["password"] = ""

            if "username" not in nodeObj:
                nodeObj["username"] = "none"

            if "roundSeqno" not in nodeObj:
                nodeObj["roundSeqno"] = 1

            protocol = nodeObj.get("protocol")
            protocolPort = nodeObj.get("protocolPort")
            servicePorts = nodeObj.get("servicePorts")

            if servicePorts is not None:
                servicePort = servicePorts.get(protocol)
                if servicePort is not None and servicePort != "":
                    protocolPort = servicePort

            if protocol.startswith("tagent."):
                nodeObj["protocol"] = "tagent"
                protocolPortTxt = protocol[7:]
                if protocolPortTxt != "":
                    protocolPort = int(protocolPortTxt)

            if protocolPort is None or protocolPort == "":
                protocolPort = nodeObj.get("port", 0)

            nodeObj["protocolPort"] = protocolPort
        # else:
        #     self.cleared = True
        #     nodeObj = None
        #     if self.nodesFile is not None:
        #         self.nodesFile.close()
        #     self.nodesFile = None

        return nodeObj
