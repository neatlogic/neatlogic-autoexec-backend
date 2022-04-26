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

    def callApi(self, lockParams):
        pass

    def doLock(self, lockParams):
        lockId = None
        lockAction = lockParams['action']
        if lockAction == 'lock':
            lockId = self.lock(lockParams)
        elif lockAction == 'unlock':
            lockId = lockParams['lockId']
            self.unlock(lockId)
        elif lockAction == 'cancel':
            lockId = lockParams['lockId']
            self.cancel(lockId)
        return lockId

    def lock(self, lockParams):
        # Lock reqeust
        # lockParams = {
        #     'lockId': None,
        #     'sysId': 343,
        #     'moduleId': 4353,
        #     'envId': 3,
        #     'sysName': 'mySys',
        #     'moduleName': 'myModule',
        #     'envName': 'SIT',
        #     'version': '2.0.0',
        #     'buildNo': '2',
        #     'action': 'lock',  # unlock
        #     'wait': 1, #0｜1，wait or not
        #     'lockTarget': 'workspace',  # build mirror env/app env/sql
        #     'lockMode': 'read',  # write
        #     'namePath': 'mySys/myModule/SIT'
        # }
        # Unlock request
        # lockParams = {
        #     'lockId': 83205734845,
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
        namePath = lockParams['namePath']
        if lockInfo['wait'] == 1:
            lockedEvent = threading.Event()
            self._putLock(lockId, lockedEvent)
            print("INFO: Wait because of:" + lockInfo['message'])
            if not lockedEvent.wait(timeout=3600):
                cancelId = lockId
                lockId = None
                print("ERROR: Lock {} {} timeout.\n".format(namePath, lockTarget))
                lockParams['action'] = 'cancel'
                self.cancel(cancelId)
        else:
            self._putLock(lockId, None)
        return lockId

    def unlock(self, lockId):
        serverAdapter = self.context.serverAdapter
        lockParams = {'lockId': lockId, 'action': 'unlock'}
        lockInfo = serverAdapter.callGlobalLock(lockParams)
        lockId = lockInfo['lockId']
        self._removeLock(lockId)
        return lockId

    def cancel(self, lockId):
        serverAdapter = self.context.serverAdapter
        lockParams = {'lockId': lockId, 'action': 'cancel'}
        lockInfo = serverAdapter.callGlobalLock(lockParams)
        lockId = lockInfo['lockId']
        self._removeLock(lockId)
        return lockId
