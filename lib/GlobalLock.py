#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
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
        self.holdLocks = {}  # 加锁成功的锁Id，用于作业停止时自动解锁
        self.lockWaits = {}  # 存放锁等待的lockId对应的wait Event

    def __del__(self):
        self.stop()

    def _putLock(self, lockId, lockParams, waitEvent=None):
        if waitEvent is None:
            lockPid = lockParams.get('pid', '-')
            lockOwner = lockParams.get('lockOwner', '-')
            lockTarget = lockParams.get('lockTarget', '-')
            lockMode = lockParams.get('lockMode', '-')
            self.lockHandles[lockPid + ':' + lockOwner + '/' + lockTarget + '/' + lockMode] = lockId
            self.holdLocks[lockId] = lockParams
        else:
            self.lockWaits[lockId] = waitEvent

    def _removeLock(self, lockId):
        lockParams = self.holdLocks.get(lockId)
        if lockParams is not None:
            lockPid = lockParams.get('pid', '-')
            lockOwner = lockParams.get('lockOwner', '-')
            lockTarget = lockParams.get('lockTarget', '-')
            lockMode = lockParams.get('lockMode', '-')
            del(self.lockHandles[lockPid + ':' + lockOwner + '/' + lockTarget + '/' + lockMode])
            del(self.holdLocks[lockId])

    def stop(self):
        self.goToStop = True
        for lockId in list(self.lockWaits.keys()):
            lockEvent = self.lockWaits[lockId]
            if lockEvent is not None:
                self.cancel(lockId)
                lockEvent.set()
        for lockId in list(self.holdLocks.keys()):
            lockParams = self.holdLocks[lockId]
            lockParams['lockId'] = lockId
            lockParams['action'] = 'unlock'
            self.unlock(lockParams)

    def doLock(self, lockParams):
        lockParams['jobId'] = self.context.jobId
        lockInfo = None
        lockAction = lockParams['action']
        if lockAction == 'lock':
            lockInfo = self.lock(lockParams)
        elif lockAction == 'unlock':
            lockInfo = self.unlock(lockParams)
        elif lockAction == 'cancel':
            lockId = lockParams['lockId']
            lockInfo = self.cancel(lockId)

        return lockInfo

    def notifyWaiter(self, lockId):
        lockEvent = self.lockWaits.get(lockId)
        if lockEvent is not None:
            lockEvent.set()
            self.lockWaits.pop(lockId)

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
        lockAction = lockParams.get('action', 'lock')
        lockPid = lockParams.get('pid', '-')
        lockOwner = lockParams.get('lockOwner', '-')
        lockTarget = lockParams.get('lockTarget', '-')
        lockMode = lockParams.get('lockMode', '-')

        preLockId = self.lockHandles.get(lockPid + ':' + lockOwner + '/' + lockTarget + '/' + lockMode)
        if preLockId is not None:
            lockInfo = {'lockId': lockId}
            return lockInfo

        serverAdapter = self.context.serverAdapter
        lockParams['action'] = lockAction
        lockInfo = serverAdapter.callGlobalLock(lockParams)
        # ServerApi return
        # lockInfo = {
        #     'lockId':23403298324,
        #     'lockOwner':"$sysId/$moduleId/",
        #     'lockTarget':'artifact/1.0.0/build/3',
        #     'status':'failed',#success
        #     'message':'Lock help by job:xxxxx'
        # }
        lockId = lockInfo.get('lockId')
        lockParams['lockId'] = lockId
        lockTarget = lockParams['lockTarget']
        namePath = lockParams['lockOwnerName']

        if lockInfo.get('wait') == 1:
            lockEvent = threading.Event()
            self._putLock(lockId, lockParams, lockEvent)
            print("INFO: Wait because of: {}\n".format(lockInfo.get('message', '')), end='')

            # retry
            timeOut = 15
            maxWaitCount = 3600/timeOut
            waitCount = 0
            if not lockEvent.wait(timeout=60):
                while not lockEvent.wait(timeout=timeOut):
                    if waitCount > maxWaitCount:
                        # timeout
                        break

                    lockParams['action'] = 'retry'
                    try:
                        lockInfo = serverAdapter.callGlobalLock(lockParams)
                    except Exception as ex:
                        print("WARN: Retry lock {}:{} server failed, {}.\n".format(namePath, lockTarget. str(ex)), end='')
                    finally:
                        lockParams['action'] = lockAction

                    waitCount = waitCount + 1

                if waitCount > maxWaitCount:
                    cancelId = lockId
                    lockInfo['lockId'] = None
                    lockInfo['message'] = "Lock {}:{} timeout.".format(namePath, lockTarget)
                    print("ERROR: {}\n".format(lockInfo['message']), end='')
                    lockParams['action'] = 'cancel'
                    self.cancel(cancelId)
                else:
                    self._putLock(lockId, lockParams)
            else:
                self._putLock(lockId, lockParams)
        else:
            self._putLock(lockId, lockParams, None)

        return lockInfo

    def unlock(self, lockParams):
        lockId = lockParams.get('lockId')
        serverAdapter = self.context.serverAdapter

        maxTryCount = 3600/5
        tryCount = 0
        lockInfo = {'lockId': lockId}
        while tryCount < maxTryCount:
            try:
                serverAdapter.callGlobalLock(lockParams)
                self._removeLock(lockId)
                break
            except Exception as ex:
                lockInfo['message'] = str(ex)
                print("WARN: Unlock lockId({}) server failed, {}.\n".format(lockId, str(ex)), end='')
            time.sleep(5)
            tryCount = tryCount + 1
        return lockInfo

    def cancel(self, lockId):
        serverAdapter = self.context.serverAdapter
        lockParams = {'lockId': lockId, 'action': 'cancel'}

        maxTryCount = 3600/5
        tryCount = 0
        lockInfo = None
        while tryCount < maxTryCount:
            try:
                lockInfo = serverAdapter.callGlobalLock(lockParams)
                self._removeLock(lockId)
                break
            except Exception as ex:
                print("WARN: Cancel lockId({}) server failed, {}.\n".format(lockId. str(ex)), end='')
            time.sleep(5)
            tryCount = tryCount + 1

        return lockInfo
