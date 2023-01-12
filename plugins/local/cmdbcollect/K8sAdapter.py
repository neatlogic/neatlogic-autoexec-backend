#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
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


class K8sAdapter:

    def __init__(self, ip, port, token=None):
        ssl._create_default_https_context = ssl._create_unverified_context

        # api路径的映射
        self.apiMap = {
            'version': 'version',
            'namespaces': 'api/v1/namespaces',
            'nodes': 'api/v1/nodes',
            'pods': 'api/v1/namespaces/{namespace}/pods',
            'deployments': 'apis/apps/v1/namespaces/{namespace}/deployments',
            'replicasets': 'apis/apps/v1/namespaces/{namespace}/replicasets',
            'services': 'api/v1/namespaces/{namespace}/services',
            'ingresses': 'apis/networking.k8s.io/v1/namespaces/{namespace}/ingresses'
        }
        self.serverBaseUrl = "https://{}:{}/".format(ip, port)
        if(self.serverBaseUrl[-1] != '/'):
            self.serverBaseUrl = self.serverBaseUrl + '/'
        self.authToken = 'Bearer ' + token
        self.ip = ip
        self.port = port

    def addHeaders(self, request, headers):
        for k, v in headers.items():
            request.add_header(k, v)

    def httpPOST(self, apiUri, authToken, params=None):
        url = self.serverBaseUrl + apiUri
        userAgent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'

        headers = {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
                   'User-Agent': userAgent,
                   'Authorization': authToken}
        if params != None:
            data = urllib.parse.urlencode(params)
            req = urllib.request.Request(url, bytes(data, 'utf-8'))
        else:
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
                errMsg = errObj['Message']
            print("ERROR: :Request url:{} failed, {}".format(url, errMsg))
        except URLError as ex:
            print("ERROR: :Request url:{} failed, {}\n".format(url, ex.reason))
        return response

    def httpGET(self, apiUri, authToken, params=None):
        url = self.serverBaseUrl + apiUri
        userAgent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'
        headers = {'User-Agent': userAgent,
                   'Authorization': authToken}
        if params != None:
            data = urllib.parse.urlencode(params)
            url = url + '?' + data
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
                errMsg = errObj['Message']
                print("ERROR: :Request url:{} failed, {}".format(url, errMsg))
        except URLError as ex:
            print("ERROR: :Request url:{} failed, {}".format(url, ex.reason))

        return response

    def httpJSON(self, apiUri, authToken, params=None):
        url = self.serverBaseUrl + apiUri
        userAgent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'
        headers = {'Content-Type': 'application/json; charset=utf-8',
                   'User-Agent': userAgent,
                   'Authorization': authToken, }

        req = urllib.request.Request(url, bytes(json.dumps(params), 'utf-8'))
        self.addHeaders(req, headers)
        response = None
        try:
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            errMsg = ex.code
            if ex.code > 500:
                content = ex.read()
                errObj = json.loads(content)
                errMsg = errObj['Message']
            print("ERROR: :Request url:{} failed, {}".format(url, errMsg))
        except URLError as ex:
            print("ERROR: :Request url:{} failed, {}".format(url, ex.reason))
        return response

    def getKeyValue(self, data):
        labels = []
        if data is None:
            return labels

        for label in data:
            value = data[label]
            if value == '':
                value = '-'
            labels.append({'KEY': label, 'VALUE': value})
        return labels

    def getNodes(self):
        nodes = []
        response = self.httpGET(self.apiMap['nodes'], self.authToken)
        if response is None:
            return nodes
        if response.status == 200:
            rs = json.loads(response.read())
            items = rs['items']
            for obj in items:
                node = {}
                node['_OBJ_CATEGORY'] = 'K8S'
                node['_OBJ_TYPE'] = 'K8S_NODE'
                node['KIND'] = rs['kind']

                metadata = obj['metadata']
                node['NAME'] = metadata['name']
                node['UID'] = metadata['uid']
                node['CREATEDATA'] = metadata['creationTimestamp']

                node_roles = ''
                lables = []
                if 'labels' in metadata:
                    lables = self.getKeyValue(metadata['labels'])
                    for label in lables:
                        if 'master' in label['KEY']:
                            node_roles = 'master'
                node['LABELS'] = lables
                node['ROLE'] = node_roles

                annotations = []
                if 'annotations' in metadata:
                    annotations = self.getKeyValue(metadata['annotations'])
                node['ANNOTATIONS'] = annotations

                spec = obj['spec']
                node['PODCIDR'] = spec['podCIDR']
                podCIDRs = []
                podCIDRObj = spec['podCIDRs']
                for podci in podCIDRObj:
                    podCIDRs.append({'NAME': podci})
                node['PODCIDRS'] = podCIDRs

                taints = []
                if 'taints' in spec:
                    taintObj = spec['taints']
                    for taint in taintObj:
                        taints.append({'KEY': taint['key'], 'EFFECT': taint['effect']})

                status = obj['status']
                capacityObj = status['capacity']
                capacity = {}
                capacity['CPU'] = capacityObj['cpu']
                capacity['MEMORY'] = capacityObj['memory']
                capacity['PODS'] = capacityObj['pods']
                capacity['EPHEMERAL-STORAGE'] = capacityObj['ephemeral-storage']

                hugepages1g = ''
                if 'hugepages-1Gi' in capacityObj:
                    hugepages1g = capacityObj['hugepages-1Gi']
                capacity['HUGEPPAGES-1GI'] = hugepages1g

                hugepages2mi = ''
                if 'hugepages-2Mi' in capacityObj:
                    hugepages2mi = capacityObj['hugepages-2Mi']
                capacity['HUGEPPAGES-2MI'] = hugepages2mi

                node['CAPACITY'] = capacity

                allocatableObj = status['allocatable']
                allocatable = {}
                allocatable['CPU'] = allocatableObj['cpu']
                allocatable['MEMORY'] = allocatableObj['memory']
                allocatable['PODS'] = allocatableObj['pods']
                allocatable['EPHEMERAL-STORAGE'] = allocatableObj['ephemeral-storage']

                alloc_hugepages1g = ''
                if 'hugepages-1Gi' in allocatableObj:
                    alloc_hugepages1g = allocatableObj['hugepages-1Gi']
                capacity['HUGEPPAGES-1GI'] = alloc_hugepages1g

                alloc_hugepages2mi = ''
                if 'hugepages-2Mi' in allocatableObj:
                    alloc_hugepages2mi = allocatableObj['hugepages-2Mi']
                capacity['HUGEPPAGE-2MI'] = alloc_hugepages2mi

                node['ALLOCATABLE'] = allocatable

                conditionsObj = status['conditions']
                conditions = []
                for condition in conditionsObj:
                    condi = {}
                    for key in condition:
                        condi[key.upper()] = condition[key]
                    conditions.append(condi)
                node['CONDITIONS'] = conditions

                os_ip = ''
                addressesObj = status['addresses']
                addresses = []
                for address in addressesObj:
                    addr = {}
                    for key in address:
                        addr[key.upper()] = address[key]
                    addresses.append(addr)
                    if address['type'] == 'InternalIP':
                        os_ip = address['address']

                node['ADDRESS'] = addresses

                nodeInfoObj = status['nodeInfo']
                for key in nodeInfoObj:
                    node[key.upper()] = nodeInfoObj[key]

                node['OS_IP'] = os_ip
                # 与属主机关系
                os_type = node['OPERATINGSYSTEM']
                os_type = "".join(os_type[:1].upper() + os_type[1:])
                node['RUN_OS'] = {"_OBJ_CATEGORY": "OS", "_OBJ_TYPE": os_type, "MGMT_IP": os_ip}
                nodes.append(node)
        else:
            print("ERROR: :Request k8s nodes info failed .\n")
        return nodes

    def getNamespaces(self):
        namespaces = []
        response = self.httpGET(self.apiMap['namespaces'], self.authToken)
        if response is None:
            return namespaces
        if response.status == 200:
            namespacers = json.loads(response.read())
            for namespaceObj in namespacers['items']:
                namespace = {}
                namespace['_OBJ_CATEGORY'] = 'K8S'
                namespace['_OBJ_TYPE'] = 'K8S_NAMESPACE'
                namespace['KIND'] = namespacers['kind']

                metadataObj = namespaceObj['metadata']
                namespace['UID'] = metadataObj['uid']
                namespace['NAME'] = metadataObj['name']
                namespace['CREATEDATA'] = metadataObj['creationTimestamp']
                namespace['STATUS'] = namespaceObj['status']['phase']
                namespaces.append(namespace)
        else:
            print("ERROR: :Request k8s namespaces failed . \n")
        return namespaces

    def getDeployment(self, namespace):
        deployments = []
        url = self.apiMap['deployments']
        url = url.replace('{namespace}', namespace['NAME'])
        response = self.httpGET(url, self.authToken)
        if response is None:
            return deployments
        if response.status == 200:
            deployrs = json.loads(response.read())
            for deployObj in deployrs['items']:
                deploy = {}
                deploy['_OBJ_CATEGORY'] = 'K8S'
                deploy['_OBJ_TYPE'] = 'K8S_DEPLOYMENT'
                deploy['KIND'] = deployrs['kind']

                metadataObj = deployObj['metadata']
                deploy['UID'] = metadataObj['uid']
                deploy['NAME'] = metadataObj['name']
                deploy['CREATEDATE'] = metadataObj['creationTimestamp']
                deploy['NAMESPACE'] = metadataObj['namespace']
                deploy['GENERATION'] = metadataObj['generation']

                lables = []
                if 'labels' in metadataObj:
                    lables = self.getKeyValue(metadataObj['labels'])
                deploy['LABELS'] = lables

                annotations = []
                if 'annotations' in metadataObj:
                    annotations = self.getKeyValue(metadataObj['annotations'])
                deploy['ANNOTATIONS'] = annotations

                ownerReferences = []
                if 'ownerReferences' in metadataObj:
                    ownerReferencObj = metadataObj['ownerReferences']
                    for ownerRe in ownerReferencObj:
                        ownerRefer = {}
                        ownerRefer['UID'] = ownerRe['uid']
                        ownerRefer['NAME'] = ownerRe['name']
                        ownerRefer['KIND'] = ownerRe['kind']
                        controller = False
                        if 'controller' in ownerRe:
                            controller = ownerRe['controller']
                        ownerRefer['CONTROLLER'] = controller
                        ownerRefer['BLOCKOWNERDELETION'] = ownerRe['blockOwnerDeletion']
                        ownerRefer['_OBJ_CATEGORY'] = 'K8S'
                        ownerRefer['_OBJ_TYPE'] = 'K8S_DEPLOYMENTS'
                        ownerReferences.append(ownerRefer)
                deploy['OWNERREFERENCES'] = ownerReferences

                specObj = deployObj['spec']
                deploy['REPLICAS'] = specObj['replicas']
                deploy['REVISIONHISTORYLIMIT'] = specObj['revisionHistoryLimit']
                deploy['PROGRESSDEADLINESECONDS'] = specObj['progressDeadlineSeconds']
                deploy['STRATEGY'] = specObj['strategy']['type']

                # todo template? 先不采集
                #templateObj = specObj['template']

                statusObj = deployObj['status']
                observedGeneration = 0
                if 'observedGeneration' in statusObj:
                    observedGeneration = statusObj['observedGeneration']
                deploy['OBSERVEDGENERATION'] = observedGeneration

                updatedReplicas = 0
                if 'updatedReplicas' in statusObj:
                    updatedReplicas = statusObj['updatedReplicas']
                deploy['UPDATEDREPLICAS'] = updatedReplicas

                readyReplicas = 0
                if 'readyReplicas' in statusObj:
                    readyReplicas = statusObj['readyReplicas']
                deploy['READYREPLICAS'] = readyReplicas

                availableReplicas = 0
                if 'availableReplicas' in statusObj:
                    availableReplicas = statusObj['availableReplicas']
                deploy['AVAILABLEREPLICAS'] = availableReplicas

                conditions = []
                if 'conditions' in statusObj:
                    conditionsObj = statusObj['conditions']
                    for condition in conditionsObj:
                        condi = {}
                        for key in condition:
                            condi[key.upper()] = condition[key]
                        conditions.append(condi)
                deploy['CONDITIONS'] = conditions

                deployments.append(deploy)
        else:
            print("ERROR: :Request k8s deployment failed . \n")
        return deployments

    def getReplicasets(self, namespace):
        replicasets = []
        url = self.apiMap['replicasets']
        url = url.replace('{namespace}', namespace['NAME'])
        response = self.httpGET(url, self.authToken)
        if response is None:
            return replicasets
        if response.status == 200:
            replicasetrs = json.loads(response.read())
            for replObj in replicasetrs['items']:
                replicaset = {}
                metadataObj = replObj['metadata']
                replicaset['_OBJ_CATEGORY'] = 'K8S'
                replicaset['_OBJ_TYPE'] = 'K8S_REPLICASET'
                replicaset['KIND'] = replicasetrs['kind']

                replicaset['UID'] = metadataObj['uid']
                replicaset['NAME'] = metadataObj['name']
                replicaset['NAMESPACE'] = metadataObj['namespace']
                replicaset['GENERATION'] = metadataObj['generation']
                replicaset['CREATEDATE'] = metadataObj['creationTimestamp']

                lables = []
                if 'labels' in metadataObj:
                    lables = self.getKeyValue(metadataObj['labels'])
                replicaset['LABELS'] = lables

                annotations = []
                if 'annotations' in metadataObj:
                    annotations = self.getKeyValue(metadataObj['annotations'])
                replicaset['ANNOTATIONS'] = annotations

                # 被Deployments管理关系
                ownerReferences = []
                if 'ownerReferences' in metadataObj:
                    ownerReferencesObj = metadataObj['ownerReferences']
                    for owner in ownerReferencesObj:
                        ownerReferences.append({"_OBJ_CATEGORY": "K8S", "_OBJ_TYPE": 'K8S_DEPLOYMENT', "UID": owner['uid'], 'NAME': owner['name'], 'KIND': owner['kind']})
                replicaset['OWNERREFERENCES'] = ownerReferences

                if 'spec' in replObj:
                    specObj = replObj['spec']
                    replicaset['REPLICAS'] = specObj['replicas']

                    selectors = []
                    selectorObj = specObj['selector']['matchLabels']
                    for st in selectorObj:
                        selectors.append({'KEY': st, 'VALUE': selectorObj[st]})
                    replicaset['SELECTOR'] = selectors

                if 'status' in replObj:
                    statusObj = replObj['status']
                    fullyLabeledReplicas = ''
                    if 'fullyLabeledReplicas' in statusObj:
                        fullyLabeledReplicas = statusObj['fullyLabeledReplicas']
                    replicaset['FULLYLABELEDREPLICAS'] = fullyLabeledReplicas

                    readyReplicas = 0
                    if 'readyReplicas' in statusObj:
                        readyReplicas = statusObj['readyReplicas']
                    replicaset['READYREPLICAS'] = readyReplicas

                    availableReplicas = 0
                    if 'availableReplicas' in statusObj:
                        availableReplicas = statusObj['availableReplicas']
                    replicaset['AVAILABLEREPLICAS'] = availableReplicas

                    observedGeneration = 0
                    if 'observedGeneration' in statusObj:
                        observedGeneration = statusObj['observedGeneration']
                    replicaset['OBSERVEDGENERATION'] = observedGeneration

                    replicasets.append(replicaset)
        else:
            print("ERROR: :Request k8s replicasets failed . \n")
        return replicasets

    def getPods(self, namespace, nodes):
        pods = []
        url = self.apiMap['pods']
        url = url.replace('{namespace}', namespace['NAME'])
        response = self.httpGET(url, self.authToken)
        if response is None:
            return pods
        if response.status == 200:
            podrs = json.loads(response.read())
            for podObj in podrs['items']:
                pod = {}
                pod['_OBJ_CATEGORY'] = 'K8S'
                pod['_OBJ_TYPE'] = 'K8S_POD'
                pod['KIND'] = podrs['kind']

                metadataObj = podObj['metadata']
                pod['UID'] = metadataObj['uid']
                pod['NAME'] = metadataObj['name']
                pod['NAMESPACE'] = metadataObj['namespace']

                generateName = ''
                if 'generateName' in metadataObj:
                    generateName = metadataObj['generateName']
                pod['GENERATENAME'] = generateName
                pod['CREATEDATE'] = metadataObj['creationTimestamp']

                lables = []
                if 'labels' in metadataObj:
                    lables = self.getKeyValue(metadataObj['labels'])
                pod['LABELS'] = lables

                # 被replicasets管理关系
                ownerReferences = []
                if 'ownerReferences' in metadataObj:
                    ownerReferencesObj = metadataObj['ownerReferences']
                    for owner in ownerReferencesObj:
                        ownerReferences.append({"_OBJ_CATEGORY": "K8S", "_OBJ_TYPE": 'K8S_REPLICASET', "UID": owner['uid'], 'NAME': owner['name'], 'KIND': owner['kind']})
                pod['OWNERREFERENCES'] = ownerReferences

                containerList = [] 
                if 'spec' in podObj:
                    specObj = podObj['spec']
                    pod['RESTARTPOLICY'] = specObj['restartPolicy']
                    pod['TERMINATIONGRACEPERIODSECONDS'] = specObj['terminationGracePeriodSeconds']
                    pod['DNSPOLICY'] = specObj['dnsPolicy']

                    serviceAccountName = ''
                    if 'serviceAccountName' in specObj:
                        serviceAccountName = specObj['serviceAccountName']
                    pod['SERVICEACCOUNTNAME'] = serviceAccountName

                    serviceAccount = ''
                    if 'serviceAccount' in specObj:
                        serviceAccount = specObj['serviceAccount']
                    pod['SERVICEACCOUNT'] = serviceAccount

                    nodeName = ''
                    if 'nodeName' in specObj:
                        nodeName = specObj['nodeName']
                    pod['NODENAME'] = nodeName

                    hostNetwork = ''
                    if 'hostNetwork' in specObj:
                        hostNetwork = specObj['hostNetwork']
                    pod['HOSTNETWORK'] = hostNetwork
                    pod['PRIORITY'] = specObj['priority']
                    pod['ENABLESERVICELINKS'] = specObj['enableServiceLinks']
                    pod['SCHEDULERNAME'] = specObj['schedulerName']

                    containers = specObj = specObj['containers']
                    for container in containers:
                        containerIns = {}
                        name = container['name']
                        image = container['image']
                        containerIns['NAME'] = name
                        containerIns['IMAGE'] = image
                        containerList.append(containerIns)

                newContainerList = [] 
                if 'status' in podObj:
                    statusObj = podObj['status']
                    pod['PHASE'] = statusObj['phase']

                    hostIP = ''
                    if 'hostIP' in statusObj:
                        hostIP = statusObj['hostIP']
                    pod['HOSTIP'] = hostIP

                    startTime = ''
                    if 'startTime' in statusObj:
                        startTime = statusObj['startTime']
                    pod['STARTTIME'] = startTime

                    podIP = ''
                    if 'podIP' in statusObj:
                        podIP = statusObj['podIP']
                    pod['PODIP'] = podIP

                    podIPs = []
                    if 'podIPs' in statusObj:
                        podIPsObj = statusObj['podIPs']
                        for podci in podIPsObj:
                            podIPs.append({'NAME': podci['ip']})
                    pod['PODIPS'] = podIPs

                    conditions = []
                    for condtionObj in statusObj['conditions']:
                        cds = {}
                        for key in condtionObj:
                            cds[key.upper()] = condtionObj[key]
                        conditions.append(cds)
                    pod['CONDITIONS'] = conditions

                    refContainers = []
                    if 'containerStatuses' in statusObj :
                        containerStatuses = statusObj['containerStatuses']
                        for container in containerStatuses:
                            name = container['name']
                            image = container['image']
                            imageID = container['imageID']
                            if 'containerID' not in container :
                                continue 
                            
                            containerID = container['containerID']
                            state = container['started']
                            
                            containerIns = {}
                            for containerd in containerList:
                                if name == containerd['NAME'] and  image == containerd['IMAGE'] :
                                    containerIns = containerd
                                    break
                            
                            containerIns['IMAGEID'] = imageID
                            containerIns['CONTAINERID'] = containerID
                            status = 'Exited'
                            if state :
                                status = 'Running'
                            containerIns['STATE'] = status
                            newContainerList.append(containerIns)

                            ref_containerId = None
                            ref_containerType = None
                            if 'docker' in containerID :
                                ref_containerId = containerID.replace('docker://','')
                                ref_containerType = "Docker"

                            if ref_containerId is not None :
                                ref_containerId = ref_containerId.strip()
                                refContainers.append({"_OBJ_CATEGORY": "CONTAINER", "_OBJ_TYPE": ref_containerType , "CONTAINER_ID": ref_containerId })

                    # 容器信息
                    pod['CONTAINER_INFO'] = newContainerList

                    # 与容器关系
                    pod['CONTAINS_CONTAINER'] = refContainers

                    # 与node关系
                    if hostIP != '':
                        for node in nodes:
                            if node['OS_IP'] == hostIP:
                                pod['RUN_NODE'] = {"_OBJ_CATEGORY": "K8S", "_OBJ_TYPE": 'K8S_NODE', "UID": node['UID']}
                    else:
                        pod['RUN_NODE'] = {}
                pods.append(pod)
        else:
            print("ERROR: :Request k8s pods failed . \n")
        return pods

    def getServices(self, namespace, pods):
        services = []
        url = self.apiMap['services']
        url = url.replace('{namespace}', namespace['NAME'])
        response = self.httpGET(url, self.authToken)
        if response is None:
            return services
        if response.status == 200:
            servicesrs = json.loads(response.read())
            for servicesObj in servicesrs['items']:
                service = {}
                service['_OBJ_CATEGORY'] = 'K8S'
                service['_OBJ_TYPE'] = 'K8S_SERVICE'
                service['KIND'] = servicesrs['kind']

                metadataObj = servicesObj['metadata']
                service['UID'] = metadataObj['uid']
                service['NAME'] = metadataObj['name']
                service['NAMESPACE'] = metadataObj['namespace']
                service['CREATEDATE'] = metadataObj['creationTimestamp']

                lables = []
                if 'labels' in metadataObj:
                    lables = self.getKeyValue(metadataObj['labels'])
                service['LABELS'] = lables

                specObj = servicesObj['spec']
                ports = []
                if 'ports' in specObj:
                    for pt in specObj['ports']:
                        instance = {}
                        for key in pt:
                            instance[key.upper()] = pt[key]
                        if 'NAME' not in instance:
                            instance['NAME'] = '-'
                        ports.append(instance)
                service['PORTS'] = ports

                clusterIP = ''
                if 'clusterIP' in specObj:
                    clusterIP = specObj['clusterIP']
                service['CLUSTERIP'] = clusterIP
                service['TYPE'] = specObj['type']

                sessionAffinity = ''
                if 'sessionAffinity' in specObj:
                    sessionAffinity = specObj['sessionAffinity']
                service['SESSIONAFFINITY'] = sessionAffinity

                ipFamilyPolicy = ''
                if 'ipFamilyPolicy' in specObj:
                    ipFamilyPolicy = specObj['ipFamilyPolicy']
                service['IPFAMILYPOLICY'] = ipFamilyPolicy

                externalTrafficPolicy = ''
                if 'externalTrafficPolicy' in specObj:
                    externalTrafficPolicy = specObj['externalTrafficPolicy']
                service['EXTERNALTRAFFICPOLICY'] = externalTrafficPolicy

                internalTrafficPolicy = ''
                if 'internalTrafficPolicy' in specObj:
                    internalTrafficPolicy = specObj['internalTrafficPolicy']
                service['INTERNALTRAFFICPOLICY'] = internalTrafficPolicy

                clusterIPs = []
                if 'clusterIPs' in specObj:
                    for ip in specObj['clusterIPs']:
                        clusterIPs.append({'NAME': ip})
                service['CLUSTERIPS'] = clusterIPs

                selectorObj = {}
                if 'selector' in specObj:
                    for key in specObj['selector']:
                        selectorObj['KEY'] = key
                        selectorObj['VALUE'] = specObj['selector'][key]
                service['SELECTOR'] = selectorObj

                if 'status' in specObj:
                    service['LOADBALANCER'] = specObj['status']['loadBalancer']

                # 与pod关系
                contain_pods = []
                if pods != None and 'KEY' in selectorObj:
                    podRef = None
                    flag = True
                    for pod in pods:
                        for lb in pod['LABELS']:
                            if lb['KEY'] == selectorObj['KEY'] and lb['VALUE'] == selectorObj['VALUE']:
                                flag = False
                                podRef = pod
                                break
                        if not flag:
                            break
                    if podRef != None:
                        contain_pods.append({'_OBJ_CATEGORY': 'K8S', '_OBJ_TYPE': 'K8S_POD', 'UID': podRef['UID'], 'name': podRef['NAME']})
                service['CONTAIN_PODS'] = contain_pods

                services.append(service)
        else:
            print("ERROR: :Request k8s servicess failed . \n")
        return services

    def getIngressRules(self, rule):
        host = rule['host']
        paths = []
        method = ''
        if 'http' in rule:
            method = 'http'
            paths = rule['http']['paths']
        if 'https' in rule:
            method = 'https'
            paths = rule['https']['paths']
        configs = []
        for item in paths:
            config = {}
            config['METHOD'] = method
            config['HOST'] = host
            config['PATH'] = item['path']
            config['PATHTYPE'] = item['pathType']
            serviceObj = item['backend']['service']
            config['NAME'] = serviceObj['name']
            config['PORT'] = serviceObj['port']['number']
            configs.append(config)
        return configs

    def getIngress(self, namespace, services):
        ingress = []
        url = self.apiMap['ingresses']
        url = url.replace('{namespace}', namespace['NAME'])
        response = self.httpGET(url, self.authToken)
        if response is None:
            return ingress
        if response.status == 200:
            ingressrs = json.loads(response.read())

            for ingressObj in ingressrs['items']:
                ingre = {}
                ingre['_OBJ_CATEGORY'] = 'K8S'
                ingre['_OBJ_TYPE'] = 'K8S_INGRESS'
                ingre['KIND'] = ingressrs['kind']

                metadataObj = ingressObj['metadata']
                ingre['UID'] = metadataObj['uid']
                ingre['NAME'] = metadataObj['name']
                ingre['NAMESPACE'] = metadataObj['namespace']
                ingre['GENERATION'] = metadataObj['generation']
                ingre['CREATEDATE'] = metadataObj['creationTimestamp']

                annotations = []
                if 'annotations' in metadataObj:
                    annotations = self.getKeyValue(metadataObj['annotations'])
                ingre['ANNOTATIONS'] = annotations

                specObj = ingressObj['spec']
                rules = []
                if 'rules' in specObj:
                    rulesObj = specObj['rules']
                    for rule in rulesObj:
                        for rs in self.getIngressRules(rule):
                            rules.append(rs)
                ingre['RULES'] = rules

                statusObj = ingressObj['status']
                ingre['LOADBALANCER'] = statusObj['loadBalancer']

                # 与service关系
                contain_services = []
                for rule in rules:
                    for svc in services:
                        if svc['NAME'] == rule['NAME']:
                            contain_services.append({'_OBJ_CATEGORY': 'K8S', '_OBJ_TYPE': 'K8S_SERVICE', 'NAME': rule['NAME'], 'UID': svc['UID']})
                            break
                ingre['CONTAIN_SERVICES'] = contain_services

                ingress.append(ingre)
        else:
            print("Request k8s ingress failed . \n")

        return ingress

    def getVersion(self):
        k8s = {}
        k8s['_OBJ_CATEGORY'] = 'K8S'
        k8s['_OBJ_TYPE'] = 'K8S'
        k8s['MGMT_IP'] = self.ip
        k8s['MGMT_PORT'] = self.port
        k8s['PK'] = ["MGMT_IP"]

        url = self.apiMap['version']
        response = self.httpGET(url, self.authToken)
        if response.status == 200:
            versionObj = json.loads(response.read())
            k8s['BUILDDATE'] = versionObj['buildDate']
            k8s['GOVERSION'] = versionObj['goVersion']
            k8s['PLATFORM'] = versionObj['platform']
            k8s['VERSION'] = versionObj['gitVersion']
            k8s['URL'] = self.serverBaseUrl
        else:
            print("Request k8s version  failed . \n")
        return k8s

    def collect(self):

        k8s = self.getVersion()
        nodes = self.getNodes()
        k8s['NODES'] = nodes

        namespaces = self.getNamespaces()
        for namespace in namespaces:
            deployments = self.getDeployment(namespace)
            namespace['DEPLOYMENTS'] = deployments

            replicasets = self.getReplicasets(namespace)
            namespace['REPLICASETS'] = replicasets

            pods = self.getPods(namespace, nodes)
            namespace['PODS'] = pods

            services = self.getServices(namespace, pods)
            namespace['SERVICES'] = services

            ingress = self.getIngress(namespace, services)
            namespace['INGRESS'] = ingress

        k8s['NAMESPACES'] = namespaces

        return k8s
