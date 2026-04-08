#!/usr/bin/env python3
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
        while startPath.name != "job":
            try:
                os.rmdir(startPath)
            except:
                break
            startPath = startPath.parent

    def getJobIdByPath(self, jobPath):
        jobRoot = Path(self.context.dataPath) / "job"
        try:
            relativePath = Path(jobPath).resolve().relative_to(jobRoot.resolve())
        except Exception:
            return None
        return "".join(relativePath.parts)

    def purgeJobData(self, jobId):
        db = self.context.db
        if db is None or not jobId:
            return

        pk = {"jobId": jobId}
        db["_node_output"].delete_many(pk)
        db["_node_status"].delete_many(pk)

    def purgeJob(self, absRoot):
        if os.path.exists(absRoot):
            for item in os.scandir(absRoot):
                if item.is_dir():
                    self.purgeJob(item)
                else:
                    if item.name == "firstgroup" or item.name == "params.json":
                        paramFile = item.path
                        if not os.path.exists(paramFile):
                            continue
                        jobIdPath = paramFile[0:-12]
                        try:
                            jobMtime = os.stat(paramFile).st_mtime
                        except FileNotFoundError:
                            continue
                        if self.nowTime - jobMtime > self.reserveSeconds:
                            jobId = self.getJobIdByPath(jobIdPath)
                            self.purgeJobData(jobId)
                            shutil.rmtree(jobIdPath, ignore_errors=True)
                            self.purgeEmptyJobDir(jobIdPath)
                            print("INFO: Remove job dictory:" + jobIdPath + "\n", end="")

    def delExpiredLog(self, hislogRoot):
        for item in os.scandir(hislogRoot):
            if item.is_file():
                fileMtime = os.stat(item.path).st_mtime
                if self.nowTime - fileMtime > self.reserveSeconds:
                    os.unlink(item.path)
                    print("INFO: Remove expired history log:" + item.path + "\n", end="")

    def purgeHisLog(self, absRoot):
        for item in os.scandir(absRoot):
            if item.is_dir():
                if item.name.endswith(".hislog"):
                    self.delExpiredLog(item.path)
                else:
                    self.purgeHisLog(item)

    def purge(self):
        jobPath = self.context.dataPath + "/job"
        self.jobDirIdx = len(jobPath) + 1
        self.purgeJob(jobPath)
        self.purgeHisLog(jobPath)
