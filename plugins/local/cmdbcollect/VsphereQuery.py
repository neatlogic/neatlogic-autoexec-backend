#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
from pyVim import connect
from pyVim.connect import SmartConnect, Disconnect, SmartConnection
from ipaddress import ip_address, IPv4Address
import traceback
import atexit
import ssl
ssl._create_default_https_context = ssl._create_unverified_context


class VsphereQuery:

    def __init__(self, ip, user, passwd, port):
        try:
            if port == None:
                port = 443
            service_instance = connect.SmartConnect(host=ip,  user=user, pwd=passwd,  port=port)
        except IOError as e:
            print("ERROR: Connection failed ,operat is  ocurred.\n{}\n".format(traceback.format_exc()))

        if not service_instance:
            raise SystemExit("Unable to connect to host with supplied info.")
        #content = service_instance.RetrieveContent()
        vcontent = service_instance.content
        self.service_instance = service_instance
        self.vcontent = vcontent
        self.ip = ip
        self.user = user
        self.port = port

    def get_datastore(self, cluster):
        data_list = []
        if not hasattr(cluster, 'datastore'):
            return data_list
        datastore = cluster.datastore
        if datastore != None:
            for dst in datastore:
                ins = {}
                name = dst.name
                moid = dst._moId
                summary = dst.summary
                ins['NAME'] = name
                ins['MOID'] = moid
                available = round(summary.freeSpace/1024/1204/1024, 2)
                capacity = round(summary.capacity/1024/1024/1024, 2)
                used = capacity - available
                used_pct = round((used/capacity)*100)
                ins['AVAILABLE'] = available
                ins['CAPACITY'] = capacity
                ins['USED'] = used
                ins['USED_PCT'] = used_pct
                ins['STATUS'] = dst.overallStatus
                ins['TYPE'] = summary.type
                ins['UNIT'] = 'GB'
                ins['PATH'] = summary.url
                data_list.append(ins)
        return data_list

    def get_network(self, cluster):
        data_list = []
        if not hasattr(cluster, 'network'):
            return data_list
        network = cluster.network
        if network != None:
            for nt in network:
                ins = {}
                name = nt.name
                moid = nt._moId
                ins['NAME'] = name
                ins['MOID'] = moid
                ins['STATUS'] = nt.overallStatus
                data_list.append(ins)
        return data_list

    def get_hardware(self, host):
        hardware = {}
        ins = {}
        name = host.name
        moid = host._moId
        ins['NAME'] = name
        ins['MOID'] = moid
        hardware = host.hardware
        systemInfo = hardware.systemInfo
        vendor = systemInfo.vendor
        model = systemInfo.model
        uuid = systemInfo.uuid
        serialNumber = systemInfo.serialNumber
        ins['MANUFACTURER'] = vendor
        ins['MODEL'] = model
        ins['UUID'] = uuid
        ins['BOARD_SERIAL'] = serialNumber
        cpuInfo = hardware.cpuInfo
        numCpuCores = cpuInfo.numCpuCores
        numCpuThreads = cpuInfo.numCpuThreads
        numCpuPackages = cpuInfo.numCpuPackages
        hz = cpuInfo.hz
        cpuPkg = hardware.cpuPkg
        if cpuPkg != None:
            CpuPackage = cpuPkg[0]
            cpuVendor = CpuPackage.vendor
            cpuDescription = CpuPackage.description
            ins['CPU_VENDOR'] = cpuVendor
            ins['CPU_MODEL'] = cpuDescription
        ins['CPU_CORES'] = numCpuCores
        ins['CPU_THREADS'] = numCpuThreads
        ins['CPU_PACKAGES'] = numCpuPackages
        ins['CPU_SPEED'] = round(hz/1000000000, 0)
        #ins['CPU_UNIT'] = 'GHZ'

        memorySize = hardware.memorySize
        ins['MEM_MAXIMUM_CAPACITY'] = round(memorySize/1024/1024/1024, 0)
        #ins['MEMORY_UNIT'] = 'GB'

        biosInfo = hardware.biosInfo
        biosVersion = biosInfo.biosVersion
        biosVendor = biosInfo.vendor
        ins['BIOS_VERSION'] = biosVersion
        ins['BIOS_VENDOR'] = biosVendor

        summary = host.summary
        managementServerIp = summary.managementServerIp
        ins['MANAGEMENT_SERVERIP'] = managementServerIp
        product = summary.config.product
        os_version = product.version
        ins['ESXI_VERSION'] = os_version
        ins['ESXI_IP'] = name

        data_list = []
        net_list = host.config.network.pnic
        if net_list != None:
            for net in net_list:
                net_ins = {}
                net_ins['NAME'] = net.device
                #net_ins['DRIVER'] = net.driver
                net_ins['MAC'] = net.mac
                #net_ins['SPEED'] = net.linkSpeed.speedMb
                net_ins['IP_ADDRESS'] = self.str_format(net.spec.ip.ipAddress)
                data_list.append(net_ins)
        ins['ETH_INTERFACES'] = data_list
        return ins

    def get_hostlist(self, cluster):
        data_list = []
        if not hasattr(cluster, 'host'):
            return data_list

        host_list = cluster.host
        for host in host_list:
            data_list.append(self.get_hardware(host))
        return data_list

    def str_format(self, str):
        if str == None:
            return ''
        else:
            return str

    def validIPAddress(self, ipAddress):
        try:
            return "IPv4" if type(ip_address(ipAddress)) is IPv4Address else "IPv6"
        except ValueError:
            return "Invalid"

    # 查vm网卡获取所有IP
    def get_nic_ipv4(self, vm):
        net = vm.guest.net
        if net is None or len(net) == 0:
            return None
        ipAddress_arry = net[0].ipAddress
        ipv4 = None
        for ip in ipAddress_arry:
            if(self.validIPAddress(ip) == 'IPv4'):
                ipv4 = ip
                break
        return ipv4

    def get_vm(self, host, vm, cluster):
        ins = {}
        os_id = vm._moId
        os_name = vm.name
        guest = vm.guest
        config = vm.config
        os_type = config.guestFullName.lower()
        if("windows" in os_type or "win" in os_type):
            os_type = 'Windows'
        elif("aix" in os_type):
            os_type = 'AIX'
        else:
            os_type = 'Linux'

        # 先看vmtools拿到的ip是不是ipv6
        os_ip = self.str_format(guest.ipAddress)
        if self.validIPAddress(os_ip) != "IPv4":
            os_ip = self.get_nic_ipv4(vm)
            if os_ip is None:
                return None
        powerState = vm.summary.runtime.powerState
        hardware = vm.config.hardware
        memory = hardware.memoryMB
        numCPU = self.str_format(hardware.numCPU)
        numCoresPerSocket = self.str_format(hardware.numCoresPerSocket)

        disk_list = vm.guest.disk
        data_list = []
        if disk_list != None:
            for disk in disk_list:
                disk_ins = {}
                disk_ins['NAME'] = disk.diskPath
                disk_ins['CAPACITY'] = round(disk.capacity/1024/1024/1024, 0)
                disk_ins['UNIT'] = 'GB'
                data_list.append(disk_ins)
        ins['DISKS'] = data_list

        ins['NAME'] = os_name
        ins['IP'] = os_ip
        ins['VM_ID'] = os_id
        ins['OS_TYPE'] = os_type
        ins['MEM_TOTAL'] = memory
        ins['MEM_UNIT'] = 'MB'
        ins['STATE'] = powerState
        ins['CPU_COUNT'] = numCPU
        ins['CPU_CORES'] = numCoresPerSocket
        ins['IS_VIRTUAL'] = 1
        serialNumber = host.hardware.systemInfo.serialNumber
        host_uuid = host.hardware.systemInfo.uuid
        if serialNumber is None:
            serialNumber = ''
        ins['MACHINE_UUID'] = host_uuid
        ins['MACHINE_SN'] = serialNumber
        ins['HOST_ON'] = [{'_OBJ_CATEGORY': 'HOST', '_OBJ_TYPE': 'HOST', 'BOARD_SERIAL': serialNumber, '_OBJ_CATEGORY': 'HOST', '_OBJ_TYPE': 'HOST', 'ESXI_IP': host.name, 'UUID': host_uuid}]
        ins['CLUSTERED_ON'] = [{'_OBJ_CATEGORY': 'VIRTUALIZED', '_OBJ_TYPE': 'VCENTER', 'MOID': cluster._moId, '_OBJ_CATEGORY': 'VMWARE-CLUSTER', '_OBJ_TYPE': 'VMWARE-CLUSTER', 'MGMT_IP': self.ip}]
        return ins

    def get_vmlist(self, cluster):
        data_list = []
        if(hasattr(cluster, 'host')):
            host_list = cluster.host
            if host_list != None:
                for host in host_list:
                    vm_list = host.vm
                    if vm_list != None:
                        for vm in vm_list:
                            vmIns = self.get_vm(host, vm, cluster)
                            if vmIns is not None:
                                data_list.append(vmIns)
        return data_list

    def disconnect(self):
        Disconnect(self.service_instance)

    def get_alarms(self):
        alarms = []
        for trigger in self.vcontent.rootFolder.triggeredAlarmState:
            alarm = {}
            alarm['KEY'] = trigger.key
            alarm['NAME'] = trigger.alarm.info.name
            alarm['ENTITY'] = trigger.entity.name
            alarm['STATUS'] = trigger.overallStatus
            alarm['TIME'] = str(trigger.time)
            alarm['MESSAGE'] = trigger.alarm.info.description
            alarms.append(alarm)
        return alarms

    def collect(self):
        vsphere = {}
        about = self.vcontent.about
        vsphere['VERSION'] = about.version
        vsphere['VENDOR'] = about.vendor
        vsphere['NAME'] = about.name
        vsphere['OS_TYPE'] = about.osType
        vsphere['FULLNAME'] = about.fullName
        vsphere['INSTANCEUUID'] = about.instanceUuid
        vsphere['MGMT_IP'] = self.ip
        vsphere['MGMT_PORT'] = self.port

        datacenter_list = []
        for datacenter in self.vcontent.rootFolder.childEntity:
            datacenter_ins = {}
            datacenter_name = datacenter.name
            datacenter_moid = datacenter._moId
            datacenter_ins['NAME'] = datacenter_name
            datacenter_ins['MOID'] = datacenter_moid
            cluster_list = []
            for cluster in datacenter.hostFolder.childEntity:
                cluster_ins = {}
                cluster_name = cluster.name
                cluster_moid = cluster._moId
                cluster_ins['NAME'] = cluster_name
                cluster_ins['MOID'] = cluster_moid
                # datastore
                cluster_ins['DATASTORE'] = self.get_datastore(cluster)
                # network
                cluster_ins['NETWORK'] = self.get_network(cluster)
                # host
                cluster_ins['HOST'] = self.get_hostlist(cluster)
                # vm
                cluster_ins['VM'] = self.get_vmlist(cluster)

                cluster_list.append(cluster_ins)
            datacenter_ins['CLUSTER'] = cluster_list
            datacenter_list.append(datacenter_ins)

        vsphere['DATACENTER'] = datacenter_list
        # 告警
        vsphere['ALARMS'] = self.get_alarms()
        # 关闭会话
        self.disconnect()
        return vsphere
