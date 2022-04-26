#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 提供读取节点运行的输出和在某个阶段各个节点的运行状态的共享存放处理，存放到公共的mogondb
"""
import datetime

import AutoExecError


class OutputStore:
    def __init__(self, context, phaseName, node):
        self.jobId = context.jobId
        self.phaseName = phaseName
        self.db = context.db
        self.node = node
        self.outputFile = None
        if 'port' in self.node:
            self.port = node['port']
        else:
            self.port = ''
        if node is not None:
            self.outputFile = '{}/output/{}-{}.json'.format(context.runPath, node['host'], self.port)

    def saveOutput(self, output):
        db = self.db

        if db is None:
            return

        collection = db['_node_output']
        pk = {'jobId': self.jobId, 'resourceId': self.node['resourceId']}
        outData = {}
        outData['host'] = self.node['host']
        outData['port'] = self.port
        outData['data'] = output
        outData['createDate'] = datetime.datetime.utcnow()
        outData.update(pk)

        try:
            collection.replace_one(pk, outData, upsert=True)
        except Exception as ex:
            raise AutoExecError.AutoExecError('Can not save output for node({}:{}) {}'.format(self.node['host'],  self.port, ex))

    def loadOutput(self):
        output = {}
        db = self.db

        if db is None:
            return output

        collection = db['_node_output']

        try:
            pk = {'jobId': self.jobId, 'resourceId': self.node['resourceId']}
            outData = collection.find_one(pk, {'data': True})
            if outData is not None:
                output = outData['data']
        except Exception as ex:
            raise AutoExecError.AutoExecError('Can not load output for node({}:{}), {}'.format(self.node['host'],  self.port, ex))

        return output

    def saveStatus(self, status):
        # 状态本地有保存，不需要共享，存放到共享数据库，是为了多节点的高可用，如果有性能的问题，可以把此方法的处理逻辑直接pass掉，直接return
        # return
        db = self.db

        if db is None:
            return

        collection = db['_node_status']
        pk = {'jobId': self.jobId, 'phase': self.phaseName, 'resourceId': self.node['resourceId']}
        outData = {}
        outData['host'] = self.node['host']
        outData['port'] = self.port
        outData['data'] = status
        outData['createDate'] = datetime.datetime.utcnow()
        outData.update(pk)

        try:
            collection.replace_one(pk, outData, upsert=True)
        except Exception as ex:
            raise AutoExecError.AutoExecError('Can not save status for node({}:{}) {}'.format(self.node['host'],  self.port, ex))

    def loadStatus(self):
        status = {}

        # 状态本地有保存，不需要共享，存放到共享数据库，是为了多节点的高可用，如果有性能的问题，可以把此方法的处理逻辑直接pass掉，直接return
        # return status
        db = self.db

        if db is None:
            return status

        collection = db['_node_status']

        try:
            pk = {'jobId': self.jobId, 'phase': self.phaseName, 'resourceId': self.node['resourceId']}
            outData = collection.find_one(pk, {'data': True})
            if outData is not None:
                status = outData['data']
        except Exception as ex:
            raise AutoExecError.AutoExecError('Can not load status for node({}:{}), {}'.format(self.node['host'],  self.port, ex))

        return status

    def removeJobStatus(self):
        db = self.db

        if db is None:
            return

        collection = db['_node_status']

        status = {}
        try:
            pk = {'jobId': self.jobId}
            collection.remove(pk)
        except Exception as ex:
            raise AutoExecError.AutoExecError('Can not dele status for job:{}\n'.format(self.jobId))

        return status
