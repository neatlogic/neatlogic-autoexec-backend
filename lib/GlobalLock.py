#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Copyright © 2017 NeatLogic
"""
import threading
import time


class GlobalLock(object):
    _instance_lock = threading.Lock()

    def __new__(cls, *args, **kwargs):
        if not hasattr(GlobalLock, "_instance"):
            with GlobalLock._instance_lock:
                if not hasattr(GlobalLock, "_instance"):
                    GlobalLock._instance = object.__new__(cls)
        return GlobalLock._instance

    def __init__(self, context):
        self.goToStop = False
        self.context = context
        self.lockHandles = {}  # 锁缓存存放lockOwner和lockTarget指向lockId
        self.phaseLockHandles = {}  # 当lockscope是phase的phase的锁缓存
        self.holdLocks = {}  # 加锁成功的锁Id，用于作业停止时自动解锁
        self.lockWaits = {}  # 存放锁等待的lockId对应的wait Event

    def __del__(self):
        self.stop()

    def _putLock(self, lockId, lockParams, waitEvent=None):
        if waitEvent is None:
            lockPid = lockParams.get("pid", "-")
            lockScope = lockParams.get("lockScope", "process")
            lockOwner = lockParams.get("lockOwner", "-")
            lockTarget = lockParams.get("lockTarget", "-")
            lockMode = lockParams.get("lockMode", "-")

            lockPrefix = lockPid
            if lockScope == "job":
                # job停止是会自动执行unlock，一般情况下不应该有scope是job的lock
                lockPrefix = "0"
            elif lockScope == "phase":
                # 只有workspace的lock是在某个执行阶段有效，其他lock一般都是进程级别的
                phaseName = lockParams.get("phaseName", "-")
                lockPrefix = phaseName

                phaseLocks = self.phaseLockHandles.get(phaseName, None)
                if phaseLocks is None:
                    phaseLocks = []
                    self.phaseLockHandles[phaseName] = phaseLocks
                phaseLocks.append(lockId)

            lockIdentify = lockPrefix + ":" + lockOwner + "/" + lockTarget + "/" + lockMode

            self.lockHandles[lockIdentify] = lockId
            self.holdLocks[lockId] = lockParams
        else:
            self.lockWaits[lockId] = waitEvent

    def _removeLock(self, lockId):
        lockParams = self.holdLocks.get(lockId)
        if lockParams is not None:
            lockPid = lockParams.get("pid", "-")
            lockScope = lockParams.get("lockScope", "process")
            lockOwner = lockParams.get("lockOwner", "-")
            lockTarget = lockParams.get("lockTarget", "-")
            lockMode = lockParams.get("lockMode", "-")

            lockPrefix = lockPid
            if lockScope == "job":
                lockPrefix = "0"
            elif lockScope == "phase":
                lockPrefix = lockParams.get("phaseName", "-")

            lockIdentify = lockPrefix + ":" + lockOwner + "/" + lockTarget + "/" + lockMode
            self.lockHandles.pop(lockIdentify, None)
            self.holdLocks.pop(lockId, None)
        else:
            self.lockWaits.pop(lockId, None)

    def stop(self):
        self.goToStop = True
        for lockId in list(self.lockWaits.keys()):
            lockEvent = self.lockWaits.get(lockId, None)
            if lockEvent is not None:
                self.cancel(lockId)
                lockEvent.set()
                print("INFO: Cancel lockId %s while stopping.\n" % (lockId), end="")
        for lockId in list(self.holdLocks.keys()):
            self.unlock(lockId, True)
            print("INFO: Unlock lockId %s while stopping.\n" % (lockId), end="")

    def doLock(self, lockParams):
        lockParams["jobId"] = self.context.jobId
        lockInfo = None
        lockAction = lockParams["action"]
        if lockAction == "lock":
            lockInfo = self.lock(lockParams)
        elif lockAction == "unlock":
            lockInfo = self.unlock(lockParams.get("lockId"))
        elif lockAction == "phaseEnd":
            lockInfo = self.cleanPhaseLocks(lockParams)
        elif lockAction == "cancel":
            lockId = lockParams["lockId"]
            lockInfo = self.cancel(lockId)

        return lockInfo

    def notifyWaiter(self, lockId):
        lockEvent = self.lockWaits.get(lockId)
        if lockEvent is not None:
            lockEvent.set()
            self.lockWaits.pop(lockId, None)

    def lock(self, lockParams):
        # Lock reqeust
        # lockParams = {
        #     'lockId': None,  #如果是unlock则lockId有值，否则是空
        #     'jobId': 23434,  #作业ID，只有同一个作业ID的才可以进行相应锁ID的解锁
        #     'pid': 9876,     #请求锁的进程ID
        #
        #     'operType': "deploy", #deploy|auto
        #     'lockOwner': "$sysId/$moduleId/",  #可以为空，lockOwner和lockOwnerName加起来确定一个锁的handle
        #     'lockTarget': 'artifact/1.0.0/build/3',  # build mirror env/app env/sql
        #
        #     'lockOwnerName': "$sysName/$moduleName/$envName",  #这个属性仅仅是为了方便，为了报错写日志使用
        #     'action': 'lock',                        # lock|unlock|cancel|retry
        #     'wait': 1, #0｜1，wait or not            # 如果wait是0，则不排队等待，直接锁失败
        #     'lockMode': 'read',                      # read|write
        #
        #      #下面是deploy的扩展属性
        #     'operType':       'deploy',
        #     'sysId':          '$sysId',
        #     'moduleId':       '$moduleId',
        #     'envId':         '$envId',
        #     'version':        '$version',
        #     'buildNo':        '$buildNo'
        # }
        # Unlock request
        # unLockParams = {
        #     'lockId': 83205734845,
        #     'jobId':  34324
        # }
        if self.goToStop:
            return None

        # 同一个作业内部，对同一个锁发起多次请求，如果前面已经锁上则返回相应的lockId
        lockAction = lockParams.get("action", "lock")
        lockPid = lockParams.get("pid", "-")
        lockScope = lockParams.get("lockScope", "process")
        lockOwner = lockParams.get("lockOwner", "-")
        lockOwnerName = lockParams.get("lockOwnerName", "-")
        lockTarget = lockParams.get("lockTarget", "-")
        lockMode = lockParams.get("lockMode", "-")

        lockPrefix = lockPid
        if lockScope == "phase":
            lockPrefix = lockParams.get("phaseName", "-")
        elif lockScope == "job":
            lockPrefix = "0"
        lockIdentify = lockPrefix + ":" + lockOwner + "/" + lockTarget + "/" + lockMode

        preLockId = self.lockHandles.get(lockIdentify, None)
        if preLockId is None:
            if lockMode == "read":
                lockIdentify = lockPrefix + ":" + lockOwner + "/" + lockTarget + "/write"
                preLockId = self.lockHandles.get(lockIdentify, None)
            elif lockMode == "write":
                lockIdentify = lockPrefix + ":" + lockOwner + "/" + lockTarget + "/read"
                if self.lockHandles.get(lockIdentify, None) is not None:
                    raise AttributeError("ERROR: Can not do write lock for %s/%s while had already get read lock, it will cause data consistency issues.\n" % (lockOwnerName, lockTarget))
        if preLockId is not None:
            lockInfo = {"lockId": preLockId}
            return lockInfo

        serverAdapter = self.context.serverAdapter
        lockParams["action"] = lockAction
        lockInfo = serverAdapter.callGlobalLock(lockParams)
        # ServerApi return
        # lockInfo = {
        #     'lockId':23403298324,
        #     'lockOwner':"$sysId/$moduleId/",
        #     'lockTarget':'artifact/1.0.0/build/3',
        #     'status':'failed',#success
        #     'message':'Lock help by job:xxxxx'
        # }
        lockId = lockInfo.get("lockId")
        lockParams["lockId"] = lockId
        lockTarget = lockParams["lockTarget"]
        namePath = lockParams["lockOwnerName"]

        if lockInfo.get("wait") == 1:
            lockEvent = threading.Event()
            self._putLock(lockId, lockParams, lockEvent)
            print("INFO: Wait because of: {}\n".format(lockInfo.get("message", "")), end="")

            # retry
            timeOut = 30
            maxWaitCount = 3600 / timeOut
            waitCount = 0
            while True:
                lockEvent.wait(timeout=timeOut)
                if waitCount > maxWaitCount:
                    # timeout
                    break
                lockParams["action"] = "retry"
                try:
                    lockInfo = serverAdapter.callGlobalLock(lockParams)
                    if lockInfo and lockInfo.get("wait") == 0:
                        self.lockWaits.pop(lockId, None)
                        break
                except Exception as ex:
                    print("WARN: Retry lock {}:{} server failed, {}.\n".format(namePath, lockTarget, str(ex)), end="")
                finally:
                    lockParams["action"] = lockAction
                waitCount = waitCount + 1

            if waitCount > maxWaitCount:
                cancelId = lockId
                lockInfo["lockId"] = None
                lockInfo["message"] = "Lock {}:{} timeout.".format(namePath, lockTarget)
                print("ERROR: {}\n".format(lockInfo["message"]), end="")
                lockParams["action"] = "cancel"
                self.cancel(cancelId)
            else:
                self._putLock(lockId, lockParams)
        else:
            self._putLock(lockId, lockParams, None)

        lockInfo["lockOwnerName"] = namePath
        lockInfo["lockTarget"] = lockTarget
        return lockInfo

    def unlock(self, lockId, force=False):
        if lockId is None:
            return None

        lockParams = self.holdLocks.get(lockId, {})
        operType = lockParams.get("operType", "auto")
        lockScope = lockParams.get("lockScope", "process")
        if not force and lockScope != "process":
            return lockParams

        serverAdapter = self.context.serverAdapter

        unlockParams = {
            "lockId": lockId,
            "operType": operType,
            "action": "unlock",
        }

        maxTryCount = 3600 / 5
        tryCount = 0
        lockInfo = lockParams
        while tryCount < maxTryCount:
            try:
                serverAdapter.callGlobalLock(unlockParams)
                self._removeLock(lockId)
                break
            except Exception as ex:
                lockInfo["message"] = str(ex)
                print("WARN: Unlock lockId({}) server failed, {}.\n".format(lockId, str(ex)), end="")
            time.sleep(5)
            tryCount = tryCount + 1
        return lockInfo

    def cleanPhaseLocks(self, lockParams):
        phaseName = lockParams.get("phaseName", "-")
        phaseLocks = self.phaseLockHandles.get(phaseName, [])
        for lockId in phaseLocks:
            self.unlock(lockId, True)
        self.phaseLockHandles.pop(phaseName, None)
        return {"lockIds": ",".join(str(lockId) for lockId in phaseLocks)}

    def cancel(self, lockId):
        serverAdapter = self.context.serverAdapter
        cancelParams = {"lockId": lockId, "action": "cancel"}

        maxTryCount = 3600 / 5
        tryCount = 0
        lockInfo = None
        while tryCount < maxTryCount:
            try:
                lockInfo = serverAdapter.callGlobalLock(cancelParams)
                self._removeLock(lockId)
                break
            except Exception as ex:
                print("WARN: Cancel lockId({}) server failed, {}.\n".format(lockId.str(ex)), end="")
            time.sleep(5)
            tryCount = tryCount + 1

        return lockInfo
