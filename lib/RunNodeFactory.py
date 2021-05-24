#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 提供读取节点文件，遍历节点，更新节点运行状态功能
"""
import sys
import os
import json
import RunNode


class RunNodeFactory:

    def __init__(self, context, phaseName):
        self.context = context
        self.phaseName = phaseName
        self.nodesFile = None

        nodesFilePath = context.getNodesFilePath(phaseName)
        if os.path.isfile(nodesFilePath):
            self.nodesFile = open(nodesFilePath)
        else:
            nodesFilePath = context.getNodesFilePath()
            self.nodesFile = open(nodesFilePath)

        line = self.nodesFile.readline()
        self.nodesFile.seek(0)
        self.nodesCount = 0
        try:
            nodesDescObj = json.loads(line)
            if 'totalCount' in nodesDescObj:
                self.nodesCount = int(nodesDescObj['totalCount'])
        except:
            pass

    def __del__(self):
        if self.nodesFile is not None:
            self.nodesFile.close()

    def nextNode(self):
        line = self.nodesFile.readline()

        while line is not None and line.strip() == '':
            line = self.nodesFile.readline()
            if not line:
                break

        runNode = None

        if line:
            nodeObj = json.loads(line)
            runNode = RunNode.RunNode(self.context, self.phaseName, nodeObj)
        else:
            self.nodesFile.close()

        return runNode
