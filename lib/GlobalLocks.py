#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import threading


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
        self.globalLocks = {}

    def __del__(self):
        self.stop()

    def _putLock(self, lockId, waitEvent):
        with GlobalLock._instance_lock:
            self.globalLocks[lockId] = waitEvent

    def _removeLock(self, lockId):
        with GlobalLock._instance_lock:
            del(self.globalLocks[lockId])

    def stop(self):
        self.goToStop = True
        for lockId in self.globalLocks.keys():
            lockEvent = self.globalLocks[lockId]
            if lockEvent is not None:
                self.cancel(lockId)
                lockEvent.set()
            else:
                self.unlock(lockId)

    def doLock(self, lockParams):
        lockInfo = {'lockId': None}
        lockAction = lockParams['action']
        if lockAction == 'lock':
            lockInfo = self.lock(lockParams)
        elif lockAction == 'unlock':
            lockId = lockParams['lockId']
            lockInfo['lockId'] = lockId
            self.unlock(lockId)
        elif lockAction == 'cancel':
            lockId = lockParams['lockId']
            lockInfo['lockId'] = lockId
            self.cancel(lockId)

        return lockInfo

    def lock(self, lockParams):
        # Lock reqeust
        # lockParams = {
        #     'lockId': None,  #如果是unlock则lockId有值，否则是空
        #     'jobId': 23434,  #作业ID，只有同一个作业ID的才可以进行相应锁ID的解锁
        #
        #     'lockOwner': "$sysId/$moduleId/$envId",  #可以为空，lockOwner和lockOwnerName加起来确定一个锁的handle
        #     'lockTarget': 'artifact/1.0.0/build/3',  # build mirror env/app env/sql
        #
        #     'lockOwnerName': "$sysName/$moduleName/$envName",  #这个属性仅仅是为了方便，为了报错写日志使用
        #     'action': 'lock',                        # lock|unlock|cancel
        #     'wait': 1, #0｜1，wait or not            # 如果wait是0，则不排队等待，直接锁失败
        #     'lockMode': 'read',                      # read|write
        # }
        # Unlock request
        # lockParams = {
        #     'lockId': 83205734845,
        #     'jobId':  34324
        # }
        if self.goToStop:
            return None

        serverAdapter = self.context.serverAdapter
        lockParams['action'] = 'lock'
        lockInfo = serverAdapter.callGlobalLock(lockParams)
        # lockInfo = {
        #     'lockId':23403298324,
        #     'status':'failed',#success
        #     'message':'Lock help by job:xxxxx'
        # }
        lockId = lockInfo['lockId']
        lockTarget = lockParams['lockTarget']
        namePath = lockParams['lockOwnerName']
        if lockInfo['wait'] == 1:
            lockedEvent = threading.Event()
            self._putLock(lockId, lockedEvent)
            print("INFO: Wait because of:" + lockInfo['message'])
            if not lockedEvent.wait(timeout=3600):
                cancelId = lockId
                lockId = None
                lockInfo['message'] = "Lock {} {} timeout.\n".format(namePath, lockTarget)
                print("ERROR: " + lockInfo['message'])
                lockParams['action'] = 'cancel'
                self.cancel(cancelId)
        else:
            self._putLock(lockId, None)
        return lockInfo

    def unlock(self, lockId):
        serverAdapter = self.context.serverAdapter
        lockParams = {'lockId': lockId, 'action': 'unlock'}
        lockInfo = serverAdapter.callGlobalLock(lockParams)
        lockId = lockInfo['lockId']
        self._removeLock(lockId)
        lockInfo = {'lockId': lockId, 'jobId': self.context.jobId}
        return lockInfo

    def cancel(self, lockId):
        serverAdapter = self.context.serverAdapter
        lockParams = {'lockId': lockId, 'action': 'cancel'}
        lockInfo = serverAdapter.callGlobalLock(lockParams)
        lockId = lockInfo['lockId']
        self._removeLock(lockId)
        lockInfo = {'lockId': lockId, 'jobId': self.context.jobId}
        return lockInfo
