#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 NeatLogic
"""
import os
import time
import shutil
from pathlib import Path


class JobPurger:
    def __init__(self, context, reserveDays):
        self.context = context
        self.reserveDays = reserveDays
        self.reserveSeconds = reserveDays * 86400
        self.nowTime = time.time()
        self.jobDirIdx = 0

    def purgeEmptyJobDir(self, jobPath):
        startPath = Path(jobPath).parent
        while startPath.name != 'job':
            try:
                os.rmdir(startPath)
            except:
                break
            startPath = startPath.parent

    def purgeJob(self, absRoot):
        if os.path.exists(absRoot):
            for item in os.scandir(absRoot):
                if item.is_dir():
                    self.purgeJob(item)
                else:
                    if item.name == 'params.json':
                        paramFile = item.path
                        jobIdPath = paramFile[0:-12]
                        jobMtime = os.stat(paramFile).st_mtime
                        if self.nowTime - jobMtime > self.reserveSeconds:
                            shutil.rmtree(jobIdPath)
                            self.purgeEmptyJobDir(jobIdPath)
                            print("INFO: Remove job dictory:" + jobIdPath + "\n", end='')

    def delExpiredLog(self, hislogRoot):
        for item in os.scandir(hislogRoot):
            if item.is_file():
                fileMtime = os.stat(item.path).st_mtime
                if self.nowTime - fileMtime > self.reserveSeconds:
                    os.unlink(item.path)
                    print("INFO: Remove expired history log:" + item.path + "\n", end='')

    def purgeHisLog(self, absRoot):
        for item in os.scandir(absRoot):
            if item.is_dir():
                if item.name.endswith('.hislog'):
                    self.delExpiredLog(item.path)
                else:
                    self.purgeHisLog(item)

    def purge(self):
        jobPath = self.context.dataPath + '/job'
        self.jobDirIdx = len(jobPath) + 1
        self.purgeJob(jobPath)
        self.purgeHisLog(jobPath)
