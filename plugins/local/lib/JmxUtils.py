#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import sys
import os.path
from jmxquery import JMXConnection, JMXQuery

class JmxUtils:

    def __init__(self, jmxHost , jmxPort , jmxUsername , jmxPassword , isVerbose):
        
        self.jmxHost = jmxHost
        self.jmxPort = jmxPort 
        self.jmxUrl = "service:jmx:rmi:///jndi/rmi://{}:{}/jmxrmi".format(jmxHost , jmxPort )
        if isVerbose is None :
            isVerbose = 0 
        self.isVerbose = isVerbose

        jmxConnection = None 
        if(jmxUsername is not None and jmxUsername !=''   and  jmxPassword is not None and  jmxPassword != '' ) :
            jmxConnection = JMXConnection(self.jmxUrl)
        else :
            jmxConnection = JMXConnection(self.jmxUrl , jmxUsername , jmxPassword)
        self.connection = jmxConnection
    
    def handQueryData(self , jmxQuery , metricName):
        metricMap = {}
        try :
            metrics = self.connection.query(jmxQuery)
            for metric in metrics:
                if (self.isVerbose == 1):
                    metric_name = metric.metric_name
                    metric_name = metric_name.replace('{name}_','')
                    metric_name = metric_name.replace('_{attributeKey}','')
                    print("INFO:: Attribute {} ,Value {} .".format( metric_name , metric.value))
                
                data = {}
                if metricName is None :
                    if metric.attribute in metricMap :
                        data = metricMap[metric.attribute]
                        
                    if metric.attributeKey is not None :
                        data[metric.attributeKey] = metric.value
                    else :
                        data[metric.attribute] = metric.value
                    metricMap[metric.attribute] = data
                else :
                    if metric.metric_name in metricMap :
                        data = metricMap[metric.metric_name]

                    if metric.attributeKey is not None :
                        data[metric.attributeKey] = metric.value
                    else :
                        data[metric.attribute] = metric.value
                    metricMap[metric.metric_name] = data
                
        except Exception as ex:
            errMsg = str(ex)
            print("WARN:: Jmx get Bean {} failed , {} .".format(errMsg))
        return metricMap

    def queryCheck( self , beanName , attribute):
        ret = 0 
        errMsg = ''
        try :
            self.queryBeanByNameAndAtrribute( beanName , attribute)
            ret = 1
        except Exception as ex:
            ret = 0 
            errMsg = str(ex)
        return (ret , errMsg)


    def queryBeanByName(self , beanName):
        return self.queryBeanByNameAndAtrribute(beanName , None )

    def queryBeanByNameAndAtrribute(self , beanName , atrributeName , metricName=None):
        metricNameStr = "{name}_{attribute}_{attributeKey}"
        if metricName is not None and metricName != '' :
            metricNameStr = metricName
        
        jmxQuery = [
            JMXQuery(
                mBeanName = beanName,
                metric_name = metricNameStr
                )
            ]
        
        if atrributeName is not None and atrributeName != '':
            jmxQuery = [
                JMXQuery(
                    mBeanName = beanName ,
                    attribute = atrributeName,  
                    metric_name = metricNameStr
                )
            ]
            data = self.handQueryData(jmxQuery , metricName)
        return data
    
    def queryBeanByNameAndAtrributes(self , beanName , atrributeNames):
        data = [] 
        for atrribute in atrributeNames :
            data.append(self.queryBeanByNameAndAtrribute(beanName , atrribute))
        return data 

    def queryBeanByTypeAndNameAtrribute(self , type , beanName , atrributeName):
        beanName_str = "java.lang:type={0},name={1}".format(type, beanName)
        return self.queryBeanByNameAndAtrribute(beanName_str , atrributeName)

    def queryBeanByTypeAndNamesAtrributes(self , type , beanNames , atrributeNames):
        data = [] 
        for name in beanNames :
            for atrribute in atrributeNames :
                data.append(self.queryBeanByTypeAndNameAtrribute(type , name , atrribute))
        return data 
