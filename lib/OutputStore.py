#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
 提供读取节点文件，遍历节点，更新节点运行状态功能
"""
import sys
import os
import pymongo
import datetime

import AutoExecError


class OutputStore:
    def __init__(self, context, node):
        self.jobId = context.jobId
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
