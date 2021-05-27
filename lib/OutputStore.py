#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 提供读取节点运行的输出和在某个阶段各个节点的运行状态的共享存放处理，存放到公共的mogondb
"""
import sys
import os
import pymongo
import datetime

import AutoExecError


class OutputStore:
    def __init__(self, context, phaseName, node):
        self.jobId = context.jobId
        self.phaseName = phaseName
        self.db = context.db
        self.node = node
        self.outputFile = '{}/output/{}-{}.json'.format(context.runPath, node['host'], node['port'])

    def saveOutput(self, output):
        db = self.db
        collection = db['node_output']
        pk = {'jobId': self.jobId, 'host': self.node['host'],  'port': self.node['port']}
        outData = {}
        outData['data'] = output
        outData['createDate'] = datetime.datetime.utcnow()
        outData.update(pk)

        try:
            collection.update(
                pk,
                {'$set':     outData},
                upsert=True
            )
        except Exception as ex:
            raise AutoExecError.AutoExecError('Can not save output for node({}:{}) {}'.format(self.node['host'],  self.node['port'], ex))

    def loadOutput(self):
        db = self.db
        collection = db['node_output']

        output = None
        try:
            pk = {'jobId': self.jobId, 'host': self.node['host'],  'port': self.node['port']}
            outData = collection.find_one(pk, {'data': True})
            if outData is not None:
                output = outData['data']
        except Exception as ex:
            raise AutoExecError.AutoExecError('Can not load output for node({}:{}), {}'.format(self.node['host'],  self.node['port'], ex))

        return output

    def saveStatus(self, status):
        # 状态本地有保存，不需要共享，存放到共享数据库，是为了多节点的高可用，如果有性能的问题，可以把此方法的处理逻辑直接pass掉，直接return
        # return
        db = self.db
        collection = db['node_status']
        pk = {'jobId': self.jobId, 'phase': self.phaseName, 'host': self.node['host'],  'port': self.node['port']}
        outData = {}
        outData['data'] = status
        outData['createDate'] = datetime.datetime.utcnow()
        outData.update(pk)

        try:
            collection.update(
                pk,
                {'$set':     outData},
                upsert=True
            )
        except Exception as ex:
            raise AutoExecError.AutoExecError('Can not save status for node({}:{}) {}'.format(self.node['host'],  self.node['port'], ex))

    def loadStatus(self):
        # 状态本地有保存，不需要共享，存放到共享数据库，是为了多节点的高可用，如果有性能的问题，可以把此方法的处理逻辑直接pass掉，直接return
        # return
        db = self.db
        collection = db['node_status']

        status = None
        try:
            pk = {'jobId': self.jobId, 'phase': self.phaseName, 'host': self.node['host'],  'port': self.node['port']}
            outData = collection.find_one(pk, {'data': True})
            if outData is not None:
                status = outData['data']
        except Exception as ex:
            raise AutoExecError.AutoExecError('Can not load status for node({}:{}), {}'.format(self.node['host'],  self.node['port'], ex))

        return status
