#!/usr/bin/python3
import traceback
import time
import sys
from pyVim.connect import SmartConnectNoSSL, Disconnect
from pyVmomi import vim, vmodl

class VmManage(object):

    def __init__(self, ip, user, password, port):
        self.config = None
        self.host = ip
        self.user = user
        self.pwd = password
        self.port = port
        try:
            self.client = SmartConnectNoSSL(host=ip,user=user,pwd=password,port=443)
            self.content = self.client.RetrieveContent()
            print("INFO:: connect vsphere {} success".format(ip))
        except Exception as e:
            print("ERROR: Connection failed ,operat is  ocurred.\n{}\n".format(traceback.format_exc()))
            exit(1)
    
    def close(self):
        client = self.client
        if(client) :
            Disconnect(client)

    def _get_all_objs(self, obj_type, folder=None):
        if folder is None:
            container = self.content.viewManager.CreateContainerView(self.content.rootFolder, obj_type, True)
        else:
            container = self.content.viewManager.CreateContainerView(folder, obj_type, True)
        return container.view

    def _get_obj(self, obj_type, name):
        obj = None
        content = self.client.RetrieveContent()
        container = content.viewManager.CreateContainerView(content.rootFolder, obj_type, True)
        for c in container.view:
            if c.name == name:
                obj = c
                break
        return obj

    def get_datacenters(self):
        return self._get_all_objs([vim.Datacenter])

    def wait_for_task(self, action , task, param):
        task_done = False
        while not task_done:
            if param['verbose'] == 1:
                print("INFO:: VM {} task status {} ... ".format(action,task.info.state))
            if task.info.state == 'success':
                task_done = True
                return 0

            if task.info.state == 'error':
                return 1

    def get_cluster_by_name(self, name=None, datacenter=None):
        if datacenter:
            folder = datacenter.hostFolder
        else:
            folder = self.content.rootFolder

        container = self.content.viewManager.CreateContainerView(folder, [vim.ClusterComputeResource], True)
        clusters = container.view
        for cluster in clusters:
            if cluster.name == name:
                return cluster
        return None

    def get_datastore_by_name(self, name, datacenter):
        datastores = datacenter.datastore
        for datastore in datastores:
            if datastore.name == name:
                return datastore
        return None

    def get_host_by_name(self, name, datastore):
        hosts = datastore.host
        for host in hosts:
            if host.key.summary.config.name == name:
                return host.key
        return None

    def get_vms_by_cluster(self, vmFolder):
        content = self.client.content
        objView = content.viewManager.CreateContainerView(vmFolder, [vim.VirtualMachine], True)
        vmList = objView.view
        objView.Destroy()
        return vmList

    def get_customspec(self, param):
        nicSpec = vim.vm.customization.IPSettings()
        #nicSpec.dnsDomain = dnsDomain
        nicSpec.gateway = param['gateway']
        nicSpec.subnetMask = param['netmask']
        nicSpec.ip = vim.vm.customization.FixedIp()
        nicSpec.ip.ipAddress = param['vm_ip']

        linuxprep = vim.vm.customization.LinuxPrep()
        #linuxprep.domain = dnsDomain
        linuxprep.hostName = vim.vm.customization.FixedName()
        linuxprep.hostName.name = param['hostname']
        linuxprep.hwClockUTC = True
        linuxprep.timeZone = "Asia/Shanghai"

        globalIPSettings = vim.vm.customization.GlobalIPSettings()
        globalIPSettings.dnsServerList =  param['dns']

        nic_adapter_specs = []
        nic_adapter_config = vim.vm.customization.AdapterMapping()
        nic_adapter_config.adapter = nicSpec
        nic_adapter_specs.append(nic_adapter_config) 

        nic_adapter = vim.vm.customization.Specification()
        nic_adapter.nicSettingMap = nic_adapter_specs
        nic_adapter.identity = linuxprep
        nic_adapter.globalIPSettings = globalIPSettings
        return nic_adapter
    
    def add_disk(self,param):
        spec = vim.vm.ConfigSpec()
        unit_number = 0
        controller = None
        vm = self._get_obj([vim.VirtualMachine], param['vm_name'])
        if vm is None :
            return -1
        print("INFO:: VM {} add disk start.".format(param['vm_name']))
        for device in vm.config.hardware.device:
            if hasattr(device.backing, 'fileName'):
                unit_number = int(device.unitNumber) + 1
                # unit_number 7 reserved for scsi controller
                if unit_number == 7:
                    unit_number += 1
                if unit_number >= 16:
                    print("WARN:: don't support this many disks.")
                    return -1
            if isinstance(device, vim.vm.device.VirtualSCSIController):
                controller = device
        if controller is None:
            print("WARN::Disk SCSI controller not found!")
            return -1
        # add disk here
        dev_changes = []
        new_disk_kb = int(param['disk_size']) * 1024 * 1024
        disk_spec = vim.vm.device.VirtualDeviceSpec()
        disk_spec.fileOperation = "create"
        disk_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add
        disk_spec.device = vim.vm.device.VirtualDisk()
        disk_spec.device.backing = \
            vim.vm.device.VirtualDisk.FlatVer2BackingInfo()
        if param['disk_type'] == 'thin':
            disk_spec.device.backing.thinProvisioned = True
        disk_spec.device.backing.diskMode = 'persistent'
        disk_spec.device.unitNumber = unit_number
        disk_spec.device.capacityInKB = new_disk_kb
        disk_spec.device.controllerKey = controller.key
        dev_changes.append(disk_spec)
        spec.deviceChange = dev_changes
        self.wait_for_task('add disk',vm.ReconfigVM_Task(spec=spec) , param)
        print("INFO:: %sGB disk added to %s" % (param['disk_size'], vm.config.name))
        print("INFO:: VM {} add disk end.".format(param['vm_name']))
        return 0

    def add_nic(self,param):
        spec = vim.vm.ConfigSpec()
        nic_changes = []

        nic_spec = vim.vm.device.VirtualDeviceSpec()
        nic_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add

        nic_spec.device = vim.vm.device.VirtualE1000()

        nic_spec.device.deviceInfo = vim.Description()
        nic_spec.device.deviceInfo.summary ='create ' + param['vm_name']

        vm = self._get_obj([vim.VirtualMachine], param['vm_name'])
        network = self._get_obj([vim.Network], param['network_name'])
        if isinstance(network, vim.OpaqueNetwork):
            nic_spec.device.backing = \
                vim.vm.device.VirtualEthernetCard.OpaqueNetworkBackingInfo()
            nic_spec.device.backing.opaqueNetworkType = \
                network.summary.opaqueNetworkType
            nic_spec.device.backing.opaqueNetworkId = \
                network.summary.opaqueNetworkId
        else:
            nic_spec.device.backing = \
                vim.vm.device.VirtualEthernetCard.NetworkBackingInfo()
            nic_spec.device.backing.useAutoDetect = False
            nic_spec.device.backing.deviceName = param['network_name']

        nic_spec.device.connectable = vim.vm.device.VirtualDevice.ConnectInfo()
        nic_spec.device.connectable.startConnected = True
        nic_spec.device.connectable.allowGuestControl = True
        nic_spec.device.connectable.connected = False
        nic_spec.device.connectable.status = 'untried'
        nic_spec.device.wakeOnLanEnabled = True
        nic_spec.device.addressType = 'assigned'

        nic_changes.append(nic_spec)
        spec.deviceChange = nic_changes

        ret = self.wait_for_task('add nic',vm.ReconfigVM_Task(spec=spec) , param)
    
    def destroy_vm(self, param):
        vm = self._get_obj([vim.VirtualMachine], param['vm_name'])
        if vm is None: 
            print("WARN:: not Found virtual machine : {}".format(vm.name))
        else:
            print("INFO:: {} virtual machine powerState is: {}".format(vm.name , vm.runtime.powerState))

        if format(vm.runtime.powerState) == "poweredOn":
            print("Attempting to power off {0}".format(vm.name))
            
            ret = self.wait_for_task('poweroff vm', vm.PowerOffVM_Task(),param)
            if ret == 0:
                self.wait_for_task('destroy vm', vm.Destroy_Task() , param)
        else :
            self.wait_for_task('destroy vm', vm.Destroy_Task() , param)
        print("INFO:: {} virtual machine destroy vm.".format(param["vm_name"]))

    def create_vm(self, param):
        datacenter = self._get_obj([vim.Datacenter], param['datacenter_name'])
        if datacenter is None:
            print("ERROR:: VM datacenter {} not found .".format(param['datacenter_name']))
            exit(1)
        vmfolder = datacenter.vmFolder

        cluster = self.get_cluster_by_name(param['cluster_name'], datacenter)
        if cluster is None:
            print("ERROR:: VM datastore {} not found cluster {}.".format(param['datacenter_name'] ,param['cluster_name'] ))
            exit(1)

        vms = self.get_vms_by_cluster(cluster)
        vms_name = [i.name for i in vms]
        if param['vm_name'] in vms_name:
            print("ERROR:: VM virtual machine {} already exists.".format(param['vm_name']))
            exit(1)

        destination_host = self._get_obj([vim.HostSystem], param['host_name'])
        if destination_host is None:
            print("ERROR:: VM host machine {} anot found.".format(param['host_name']))
            exit(1)

        source_pool = destination_host.parent.resourcePool
        datastore_name = param['datastore_name']
        if datastore_name is None or datastore_name == '':
            datastore_name = destination_host.datastore[0].name
            param['datastore_name'] = datastore_name

        if param['datastore_name']:
            datastore = self.get_datastore_by_name(param['datastore_name'], datacenter)
            if datastore is None:
                print("ERROR:: VM datastore {} not found .".format(param['datastore_name']))
                exit(1)
            else:
                datastore = self.get_datastore_by_name(datastore_name, datacenter)
                if datastore is None:
                    print("ERROR:: VM datacenter {} not found template {} .".format(param['datacenter_name'] , param['template_name']))
                    exit(1)

        if param['guest'] is None or  param['guest'] == '' :
            print("ERROR:: VM guest client os version must defined.")
            exit(1)

        config = vim.vm.ConfigSpec()
        config.name = param['vm_name']
        #config.powerOn = True
        config.cpuHotAddEnabled = True
        config.cpuHotRemoveEnabled = True
        config.memoryHotAddEnabled = True
        #操作系统版本
        config.guestId = param['guest']

        tools = vim.vm.ToolsConfigInfo()
        tools.afterPowerOn = True
        #新建虚拟机个性化设置
        #if all([param['vm_ip'], param['netmask'], param['gateway']]):
        #    customization = self.get_customspec(param)
        #    tools.pendingCustomization = customization
        config.tools = tools

        if param['cup_num']:
            config.numCPUs = int(param['cup_num'])
            config.numCoresPerSocket = 2
        if param['memory']:
            config.memoryMB = int(param['memory']) * 1024
        
        files = vim.vm.FileInfo()
        files.vmPathName = "["+param['datastore_name']+"]"
        config.files = files
        ret = 0
        try:
            task = vmfolder.CreateVm(config, pool=source_pool, host=destination_host)
            ret = self.wait_for_task('create vm',task , param)
            if (ret == 0):
                print("INFO:: VM {} created success .".format(param['vm_name']))
                if param['network_name'] is not None :
                    self.add_nic(param)

                if param['disk_size'] is not None :
                    ret = self.add_disk(param)
                    if ret == 0 :
                        print("INFO:: {} add {} {} disk success.".format(param['vm_name'] , param['disk_type'] , param['disk_size']))
                    else :
                        print("ERRORR:: {} add {} type {} disk failed.".format(param['vm_name'] , param['disk_type'] , param['disk_size']))
            else:
                print("ERROR:: VM {} created failed ,reason:{} .".format(param['vm_name']),task.info.error.msg)

        except vim.fault.DuplicateName:
            print("ERROR:: VM duplicate name: %s" % param['vm_name'], file=sys.stderr)
        except vim.fault.AlreadyExists:
            print("ERROR:: VM name %s already exists." % param['vm_name'], file=sys.stderr)
        return ret

    def clone_vm(self, param):
        template = self._get_obj([vim.VirtualMachine], param['template_name'])
        if template is None:
            print("ERROR:: VM template {} not found .".format(param['template_name']))
            exit(1)
        
        datacenter = self._get_obj([vim.Datacenter], param['datacenter_name'])
        if datacenter is None:
            print("ERROR:: VM datacenter {} not found .".format(param['datacenter_name']))
            exit(1)
        vmfolder = datacenter.vmFolder

        if param['datastore_name']:
            datastore = self.get_datastore_by_name(param['datastore_name'], datacenter)
            if datastore is None:
                print("ERROR:: VM datastore {} not found .".format(param['datastore_name']))
                exit(1)
        else:
            datastore = self.get_datastore_by_name(template.datastore[0].info.name, datacenter)
            if datastore is None:
                print("ERROR:: VM datacenter {} not found template {} .".format(param['datacenter_name'] , param['template_name']))
                exit(1)

        cluster = self.get_cluster_by_name(param['cluster_name'], datacenter)
        if cluster is None:
            print("ERROR:: VM datastore {} not found cluster {}.".format(param['datacenter_name'] ,param['cluster_name'] ))
            exit(1)

        vms = self.get_vms_by_cluster(cluster)
        vms_name = [i.name for i in vms]
        if param['vm_name'] in vms_name:
            print("ERROR:: VM virtual machine {} already exists.".format(param['vm_name']))
            exit(1)

        resource_pool = cluster.resourcePool
        relospec = vim.vm.RelocateSpec()
        relospec.datastore = datastore
        relospec.pool = resource_pool
        
        if param['host_name']:
            host = self.get_host_by_name(param['host_name'], datastore)
            if host is None:
                print("ERROR:: VM host machine {} anot found.".format(param['host_name']))
                exit(1)
            else:
                relospec.host = host

        clonespec = vim.vm.CloneSpec()
        clonespec.location = relospec
        clonespec.powerOn = True

        # 克隆个性化设置
        if all([param['vm_ip'], param['netmask'], param['gateway']]):
            clonespec.customization = self.get_customspec(param)
        vmconf = vim.vm.ConfigSpec()
        vmconf.cpuHotAddEnabled = True
        vmconf.cpuHotRemoveEnabled = True
        vmconf.memoryHotAddEnabled = True

        if param['cup_num']:
            vmconf.numCPUs = int(param['cup_num'])
            vmconf.numCoresPerSocket = 2
        if param['memory']:
            vmconf.memoryMB = int(param['memory']) * 1024
        if vmconf is not None:
            clonespec.config = vmconf

        print("INFO:: cloning VM start...")
        task = template.Clone(folder=vmfolder, name=param['vm_name'], spec=clonespec)
        ret = self.wait_for_task('clone vm',task , param)
        if ret == 0 : 
            print("INFO:: VM clone task exec success")
            ret = self.add_disk(param)
        else : 
            print("ERROR:: VM clone task exec failed , reason :{}. ".format(task.info.error.msg))
            if('Customization of the guest operating system is not supported' in task.info.error.msg):
                print("ERROR:: Please check virtual template or virtual machine {} already installed vmtools .".format(param['template_name']))
        print("FINST:: cloning VM end...")
        return ret