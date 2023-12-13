#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 NeatLogic
"""

import os
import json


def setEnv():
    modPaths = os.path.split(os.path.realpath(__file__))
    binPath = os.path.realpath(modPaths[0]+'/..')
    outputPath = os.path.join(binPath, 'output.json')
    os.environ['OUTPUT_PATH'] = outputPath
    hidePwdInCmdLine()


def hidePwdInCmdLine():
    pass


def saveOutput(outputData):
    modPaths = os.path.split(os.path.realpath(__file__))
    binPath = os.path.realpath(modPaths[0]+'/..')
    outputPath = os.path.join(binPath, 'output.json')
    print("INFO: Try save output to {}.\n".format(outputPath))
    if outputPath is not None and outputPath != '':
        outputFile = open(outputPath, 'w')
        outputFile.write(json.dumps(outputData, indent=4, ensure_ascii=False))
        outputFile.close()
    else:
        print("WARN: Could not save output file, because of environ OUTPUT_PATH not defined.\n")
