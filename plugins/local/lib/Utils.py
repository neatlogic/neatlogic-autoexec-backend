#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import sys
import json

class Utils :

    def __init__(self):
        pass 


    def setEnv():
        pass

    def saveOutput(self,outputData):
        if 'OUTPUT_PATH' in os.environ:
            outputPath = os.environ['OUTPUT_PATH']
            outputFile = open(outputPath, 'w')

            outputFile.write(json.dumps(outputData))
            outputFile.close()

    def getOutput(self,output_path):
        outputFile = open(output_path, "r", encoding="utf-8")
        data = json.load(outputFile)
        outputFile.close()
        return data

    def getNode(self):
        pass


    def getNodes(self):
        if 'TASK_NODES_PATH' in os.environ:
            nodesJsonPath = os.environ['TASK_NODES_PATH']
            fh = open(nodesJsonPath, 'r')
            line = fh.readline()
    
    def isJson(self,data): 
        valid = False
        print(type(data))
        try:
            json.load(data, encoding='utf-8')
            valid = True
        except ValueError:
            pass
        return valid