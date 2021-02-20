# /usr/bin/python
import os
import sys
import json


def setEnv():
    pass


def saveOutput(outputData):
    if 'OUTPUT_PATH' in os.environ:
        outputPath = os.environ['OUTPUT_PATH']
        outputFile = open(outputPath, 'w')

        outputFile.write(json.dumps(outputData))
        outputFile.close()


def getNode():
    pass


def getNodes():
    if 'TASK_NODES_PATH' in os.environ:
        nodesJsonPath = os.environ['TASK_NODES_PATH']
        fh = open(nodesJsonPath, 'r')
        line = fh.readline()
