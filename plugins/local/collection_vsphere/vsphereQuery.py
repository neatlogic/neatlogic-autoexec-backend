#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import ssl
ssl._create_default_https_context = ssl._create_unverified_context
import atexit
from pyVim import connect


class vsphereQuery:
    
    def __init__(self , ip , user , passwd , port):
        try:
            if port == None :
                port = 443 
            service_instance = connect.SmartConnect(host=ip,  user=user, pwd=passwd,  port=port)
        except IOError as e:
            pass

        if not service_instance:
            raise SystemExit("Unable to connect to host with supplied info.")
        #content = service_instance.RetrieveContent()
        vcontent = service_instance.content
        self.vcontent = vcontent
        self.ip = ip
        self.user = user
        self.port = port
    
    def get_datastore(self,cluster): 
        data_list = []
        datastore = cluster.datastore
        if datastore != None :
            for dst in datastore:
                ins = {}
                name = dst.name 
                moid = dst._moId
                ins['名称'] = name
                ins['moid'] = moid
                data_list.append(ins)
        return data_list

    def get_network(self,cluster): 
        data_list = []
        network = cluster.network
        if network != None :
            for nt in network:
                ins = {}
                name = nt.name 
                moid = nt._moId
                ins['名称'] = name
                ins['moid'] = moid
                data_list.append(ins)
        return data_list

    def get_hardware(self,host):
        hardware = {} 
        ins = {}
        name = host.name 
        moid = host._moId
        ins['名称'] = name
        ins['moid'] = moid
        hardware = host.hardware
        systemInfo = hardware.systemInfo
        vendor =  systemInfo.vendor
        model =  systemInfo.model
        uuid =  systemInfo.uuid
        serialNumber =  systemInfo.serialNumber
        ins['厂商'] = vendor
        ins['型号'] = model
        ins['uuid'] = uuid
        ins['serialNumber'] = serialNumber
        cpuInfo = hardware.cpuInfo
        numCpuCores = cpuInfo.numCpuCores
        numCpuThreads = cpuInfo.numCpuThreads
        numCpuPackages = cpuInfo.numCpuPackages
        hz = cpuInfo.hz
        cpuPkg = hardware.cpuPkg
        if cpuPkg != None :
            CpuPackage = cpuPkg[0]
            cpuVendor = CpuPackage.vendor
            cpuDescription = CpuPackage.description
            ins['CPU厂商'] = cpuVendor
            ins['CPU型号'] = cpuDescription
        ins['CPU内核数量'] = numCpuCores
        ins['CPU线程数量'] = numCpuThreads
        ins['CPU软件包数量'] = numCpuPackages
        ins['每个内核的CPU速度'] = str(round(hz/1000000000,0)) +'GHZ'

        memorySize = hardware.memorySize
        ins['内存大小'] = str(round(memorySize/1024/1024/1024,0))+ 'GB'

        biosInfo = hardware.biosInfo
        biosVersion = biosInfo.biosVersion
        biosVendor = biosInfo.vendor
        ins['bios版本'] = biosVersion
        ins['bios厂商'] = biosVendor

        summary = host.summary
        managementServerIp = summary.managementServerIp
        ins['受管IP'] = managementServerIp
        product = summary.config.product
        os_fullName = product.fullName
        os_name = product.name
        os_type = product.osType
        os_vendor = product.vendor
        os_version = product.version
        os_ins = {}
        os_ins['名称']=os_name
        os_ins['全名']=os_fullName
        os_ins['类型']=os_type
        os_ins['厂商']=os_vendor
        os_ins['版本']=os_version
        ins['esxi'] = os_ins

        data_list = []
        net_list = host.config.network.pnic 
        if net_list != None : 
            for net in net_list :
                net_ins = {}
                net_ins['device'] = net.device
                net_ins['driver'] = net.driver
                net_ins['mac'] = net.mac
                net_ins['speed'] = net.linkSpeed.speedMb
                net_ins['ip'] = self.str_format(net.spec.ip.ipAddress)
                data_list.append(net_ins)
        ins['网卡'] = data_list

        return ins

    def get_hostlist(self,cluster):
        data_list = []
        host_list = cluster.host
        if host_list != None :
            for host in host_list:
                data_list.append(self.get_hardware(host))
        return data_list

    def str_format(self,str):
        if str == None :
            return ''
        else :
            return str

    def get_vm(self,host , vm) :
        ins = {}
        os_name = vm.name
        guest = vm.guest
        os_ip = self.str_format(guest.ipAddress)
        os_type = self.str_format(guest.guestFullName)
        powerState = vm.summary.runtime.powerState
        hardware = vm.config.hardware
        memoryMB = str(self.str_format(hardware.memoryMB)/1024) + 'GB'
        numCPU = self.str_format(hardware.numCPU)
        numCoresPerSocket = self.str_format(hardware.numCoresPerSocket)

        #disk_list = vm.guest.disk 
        #data_list = []
        #if disk_list != None : 
        #    for disk in disk_list : 
        #        disk_ins = {}
        #        disk_ins['名称']=disk.diskPath
        #        disk_ins['容量']=str(round(disk.capacity/1024/1024/1024,0)) + 'GB'
        #        data_list.append(disk_ins)
        #ins['磁盘']=data_list

        ins['名称']=os_name
        ins['IP']=os_ip
        ins['类型']=os_type
        ins['内存']=memoryMB
        ins['主机状态']=powerState
        ins['CPU个数']=numCPU
        ins['单个CPU核数']=numCoresPerSocket
        
        ins['所在物理机']=host.hardware.systemInfo.uuid

        return ins

    def get_vmlist(self,cluster):
        data_list = []
        host_list = cluster.host
        if host_list != None :
            for host in host_list:
                vm_list = host.vm
                if vm_list != None : 
                    for vm in vm_list :
                        data_list.append(self.get_vm(host , vm ))
        return data_list

    def collect (self) :
        collectData = []
        vsphere = {}
        about = self.vcontent.about
        vsphere['version'] = about.version
        vsphere['vendor'] = about.vendor
        vsphere['name'] = about.name
        vsphere['osType'] = about.osType
        vsphere['fullName'] = about.fullName
        vsphere['instanceUuid'] = about.instanceUuid
        vsphere['IP'] = self.ip
        vsphere['port'] = self.port

        datacenter_list = []
        for datacenter in self.vcontent.rootFolder.childEntity:
            datacenter_ins = {}
            datacenter_name = datacenter.name
            datacenter_moid = datacenter._moId
            datacenter_ins['名称']=datacenter_name
            datacenter_ins['moId']=datacenter_moid
            cluster_list = [] 
            for cluster in datacenter.hostFolder.childEntity:
                cluster_ins = {}
                cluster_name = cluster.name
                cluster_moid = cluster._moId
                cluster_ins['名称']=cluster_name
                cluster_ins['moId']=cluster_moid
                #datastore
                cluster_ins['datastore'] = self.get_datastore(cluster)
                #network
                cluster_ins['network'] = self.get_network(cluster)
                #host 
                cluster_ins['host'] = self.get_hostlist(cluster)
                #vm 
                cluster_ins['vm'] = self.get_vmlist(cluster)

                cluster_list.append(cluster_ins)
            datacenter_ins['集群']=cluster_list
            datacenter_list.append(datacenter_ins)

        vsphere['datacenter'] = datacenter_list
        collectData.append(vsphere)
        return collectData