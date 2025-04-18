#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Copyright © 2017 NeatLogic
"""
from multiprocessing import Condition
import sys
import os
import stat
import fcntl
import ssl
import time
import json
import base64
import urllib.request
import urllib.parse
from urllib.error import URLError
from urllib.error import HTTPError
import ipaddress


class HorizonAdapter:

    LB_METHOD_DICT = {
        0: "轮询",
        1: "加权轮询",
        2: "节点最少连接",
        3: "加权节点最少连接",
        4: "服务最少连接",
        5: "加权服务最少连接",
        6: "最快相应",
        7: "最少请求",
    }
    PROTOCOL_DICT = {
        0: "tcp",
        1: "udp",
    }
    STATUS_DICT = {
        0: "stop",
        1: "start",
    }
    IPTYPE_DICT = {
        0: "IPV4",
        1: "IPV6",
    }

    def __init__(self, ip, port, apiVersion, username, password):
        ssl._create_default_https_context = ssl._create_unverified_context

        self.serverBaseUrl = "https://{}:{}/adcapi/{}/".format(ip, port, apiVersion)
        if self.serverBaseUrl[-1] != "/":
            self.serverBaseUrl = self.serverBaseUrl + "/"
        self.apiVersion = apiVersion
        self.ip = ip
        self.port = port
        self.username = username
        self.password = password

    # def getAuthKey(self, apiUri, )
    def addHeaders(self, request, headers):
        for k, v in headers.items():
            request.add_header(k, v)

    def getAuthKey(self):
        url = self.serverBaseUrl
        userAgent = "Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)"

        headers = {"Content-Type": "application/x-www-form-urlencoded; charset=utf-8", "User-Agent": userAgent}
        params = {}
        params["username"] = self.username
        params["password"] = self.password
        params["action"] = "login"

        data = urllib.parse.urlencode(params)
        req = urllib.request.Request(url, bytes(data, "utf-8"), method="POST")
        self.addHeaders(req, headers)
        response = None
        try:
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            errMsg = ex.code
            if ex.code > 500:
                content = ex.read()
                errObj = json.loads(content)
                errMsg = errObj["Message"]
            print("ERROR: :Request url:{} failed, {}".format(url, errMsg))
        except URLError as ex:
            print("ERROR: :Request url:{} failed, {}\n".format(url, ex.reason))

        authKeyResponse = json.loads(response.read())
        print(authKeyResponse)
        authKey = authKeyResponse["authkey"]
        return authKey

    def getItem(self, params=None):
        url = self.serverBaseUrl
        userAgent = "Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)"
        headers = {"User-Agent": userAgent}
        if params != None:
            data = urllib.parse.urlencode(params)
            url = url + "?" + data
        req = urllib.request.Request(url)
        self.addHeaders(req, headers)
        response = None
        try:
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            errMsg = ex.code
            if ex.code > 500:
                content = ex.read()
                errObj = json.loads(content)
                errMsg = errObj["Message"]
                print("ERROR: :Request url:{} failed, {}".format(url, errMsg))
        except URLError as ex:
            print("ERROR: :Request url:{} failed, {}".format(url, ex.reason))
        return response

    def getBasicInfo(self, authKey):
        horizon = {}
        params = {"action": "system.information.get", "authKey": authKey}
        response = self.getItem(params)

        if response is None:
            return horizon
        if response.status == 200:
            horizonResponse = json.loads(response.read())
            # horizon['_OBJ_CATEGORY'] = 'LOADBALANCER'
            # horizon['_OBJ_TYPE'] = 'HORIZON'
            horizon["DEV_NAME"] = horizonResponse["hostname"]
            horizon["MODEL"] = horizonResponse["product_model"]
            horizon["VERSION"] = horizonResponse["software_version"]
            horizon["SN"] = horizonResponse["serial_number"]
            horizon["MGMT_IP"] = self.ip
            horizon["UPTIME"] = horizonResponse["running_time"]
            return horizon

    def getVS(self, authKey):
        virtualServers = []
        params = {"action": "slb.va.list", "authKey": authKey}
        response = self.getItem(params)
        if response is None:
            return pods
        if response.status == 200:
            vaResponse = json.loads(response.read())
            for vaObj in vaResponse:
                ip = vaObj["address"]
                for vsObj in vaObj["virtual_services"]:
                    vs = {}
                    # vs['_OBJ_CATEGORY'] = 'xxxxx'
                    # vs['_OBJ_TYPE'] = 'LOADBALANCER-VS'
                    vs["NAME"] = vsObj["name"]
                    vs["IP"] = ip
                    vs["PORT"] = vsObj["port"]
                    vs["POOLNAME"] = vsObj["pool"]
                    vs["SOURCENAT"] = vsObj["source_nat"]
                    vs["PATHPERSIST"] = vsObj["path_persist"]
                    vs["AUTOSNAT"] = vsObj["auto_snat"]

                    virtualServers.append(vs)
        else:
            print("ERROR: :Request horizon vs failed . \n")
        return virtualServers

    def generate_ip_range(self, start_ip, end_ip):
        start_ip = ipaddress.IPv4Address(start_ip)
        end_ip = ipaddress.IPv4Address(end_ip)

        ip_range = list(ipaddress.summarize_address_range(start_ip, end_ip))
        return [str(ip) for network in ip_range for ip in network]

    def create_ip_dict_array(self, start_ip, end_ip):
        ip_range = self.generate_ip_range(start_ip, end_ip)
        result = [{"VALUE": ip} for ip in ip_range]
        return result

    def getNatPool(self, authKey):
        natPools = []
        params = {"action": "nat.pool.list", "authKey": authKey}
        response = self.getItem(params)
        if response is None:
            return natPools
        if response.status == 200:
            natPoolRs = json.loads(response.read())
            for natPoolObj in natPoolRs:
                natPool = {}
                natPool["_OBJ_CATEGORY"] = "LOADBALANCER"
                natPool["_OBJ_TYPE"] = "LOADBALANCER-SNATPOOL"
                natPool["NAME"] = natPoolObj["name"]
                natPool["IP_TYPE"] = HorizonAdapter.IPTYPE_DICT[natPoolObj["ip_type"]]

                ipList = []
                for member in natPoolObj["member_list"]:
                    startIp = member["start_ip_addr"]
                    stopIp = member["end_ip_addr"]
                    ipDictRange = self.create_ip_dict_array(startIp, stopIp)
                    for ip_dict in ipDictRange:
                        # print(ip_dict)

                        ipList.append(ip_dict)
                natPool["MEMBER_LIST"] = ipList
                natPools.append(natPool)
        else:
            print("Request horzion pool failed . \n")
        return natPools

    def getPools(self, authKey):
        pools = []
        params = {"action": "slb.pool.list", "authKey": authKey}
        response = self.getItem(params)
        if response is None:
            return pools
        if response.status == 200:
            poolrs = json.loads(response.read())
            # print("==================\n")
            # print(json.dumps(poolrs))
            # print("==================\n")

            for poolObj in poolrs:
                pool = {}
                pool["NAME"] = poolObj["name"]
                pool["LBMETHOD"] = HorizonAdapter.LB_METHOD_DICT[poolObj["lb_method"]]
                pool["PROTOCOL"] = HorizonAdapter.PROTOCOL_DICT[poolObj["protocol"]]

                members = []
                membersObj = poolObj["members"]
                for memberObj in membersObj:
                    member = {}
                    member["NAME"] = memberObj["nodename"]
                    member["IP"] = memberObj["server"]
                    member["PORT"] = memberObj["port"]
                    member["STATUS"] = HorizonAdapter.STATUS_DICT[memberObj["status"]]
                    members.append(member)
                pool["MEMBERS"] = members
                pools.append(pool)

        else:
            print("Request horzion pool failed . \n")

        return pools

    def getPorts(self, authKey):
        ports = []
        params = {"action": "interface.ethernet.list", "authKey": authKey}
        response = self.getItem(params)
        if response is None:
            return ports
        if response.status == 200:
            portRs = json.loads(response.read())
            for portObj in portRs:
                port = {}
                port["_OBJ_CATEGORY"] = "LOADBALANCER"
                port["_OBJ_TYPE"] = "PORT"
                port["NAME"] = str(portObj["slot"]) + ":" + str(portObj["port"])
                port["MAC"] = portObj["mac_addr"].lower()

                ports.append(port)
        else:
            print("Request horzion ports failed . \n")
        return ports

    def collect(self):
        authKey = self.getAuthKey()
        horizon = self.getBasicInfo(authKey)
        vs = self.getVS(authKey)
        pools = self.getPools(authKey)
        natPools = self.getNatPool(authKey)

        for vsObj in vs:
            vsPool = []
            vsPoolName = vsObj["POOLNAME"]
            for poolObj in pools:
                poolName = poolObj["NAME"]
                if vsPoolName == poolName:
                    vsPool.append(poolObj)
            vsObj["POOL"] = vsPool
        for vsObj in vs:
            vsNatPool = []
            vsNatPoolName = vsObj["SOURCENAT"]
            for natPoolObj in natPools:
                natPoolName = natPoolObj["NAME"]
                if vsNatPoolName == natPoolName:
                    vsNatPool.append(natPoolObj)
            vsObj["SNAT_POOL"] = vsNatPool

        ports = self.getPorts(authKey)
        horizon["PORTS"] = ports
        horizon["VIRTUAL_SERVERS"] = vs
        # horizon['SNAT_POOL'] = natPools

        return horizon
