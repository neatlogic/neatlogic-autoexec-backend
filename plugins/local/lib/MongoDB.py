#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import configparser
import pymongo
import json

class MongoDB:

    def __init__(self):
        homePath = os.path.split(os.path.realpath(__file__))[0]
        homePath = os.path.realpath(homePath + '/../../../')
        self.homePath = homePath
        # 读取配置
        cfgPath = homePath + '/conf/config.ini'
        cfg = configparser.ConfigParser()
        cfg.read(cfgPath)
        self.config = cfg
        dburl = cfg.get('mongoDB', 'db.url')
        dbname = cfg.get('mongoDB', 'db.name')
        dbuser = cfg.get('mongoDB', 'db.username')
        dbpwd = cfg.get('mongoDB', 'db.password')
        self.dburl = dburl
        self.dbname = dbname
        self.dbuser = dbuser 
        self.dbpwd = dbpwd 

        #初始化创建connect
        myclient = pymongo.MongoClient(dburl)
        mydb = myclient[dbname]
        self.dbclient = myclient
        self.db = mydb
        mydb.authenticate(self.dbuser, self.dbpwd)

    #table 表名 ， querystr 查询条件 ，displayStr 查询结果展示列 ，limit 限制条数
    def find(self , table , querystr=None , displayStr=None , limit=None):
        mydb = self.db
        collection = mydb[table]
        content = None
        try:
            if limit == None :
                content = collection.find(querystr , displayStr)
            else :
                content = collection.find(querystr , displayStr).limit(limit)
        except Exception as ex:
            print('MongoDb table: {} ,condition {},query failed , reason : {} '.format( table, querystr ,ex))
        return content

    #table 表名 ， data 插入数据
    def insert(self , table , data):
        mydb = self.db
        collection = mydb[table]
        try:
           collection.insert_one(data)
        except Exception as ex:
            print('MongoDb table: {} ,insert data : {} failed , reason :{} '.format(table , data ,ex))
    
    #table 表名 ,where 匹配条件， data 插入数据
    def update(self ,table , where , data):
        mydb = self.db
        collection = mydb[table]
        try:
            up_data = {"$set" : data}
            #upsert = {"upsert" : "true" }
            #print(type(upsert))
            #print(upsert)
            collection.update(where , up_data )
        except Exception as ex:
            print('MongoDb table: {} , condition : {}, update data : {} failed , reason : {} '.format(table , where, data ,ex))

    #table 表名 where 匹配条件
    def delete(self , table , where):
        mydb = self.db
        collection = mydb[table]
        try:
           collection.delete_many(where)
        except Exception as ex:
            print('MongoDb table : {} ,condition : {} ,delete data failed , reason :{} '.format(table ,where , ex))

    #清空表
    def remove(self , table):
        mydb = self.db
        collection = mydb[table]
        try:
           collection.remove()
        except Exception as ex:
            print('MongoDb table : {} , remove table data failed , reason :{} '.format(table , ex))

    def count(self , table , uniqueName):
        mydb = self.db
        collection = mydb[table]
        count = 0 
        try:
            count = collection.find(uniqueName).count()
        except Exception as ex:
            count = 0
            print('MongoDb table: {} ,condition {}, query count failed , reason : {} '.format( table, uniqueName ,ex))
        return count

    #关闭连接
    def close(self) :
        dbclient = self.dbclient
        try:
            dbclient.close()
        except Exception as ex:
            print('MongoDb close failed , reason : {} '.format(ex))
    