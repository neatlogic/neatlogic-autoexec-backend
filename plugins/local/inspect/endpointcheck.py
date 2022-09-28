#!/usr/bin/python
# -*- coding:UTF-8 -*-

import re
import os
import traceback
import argparse
import json
import re
import time

import AutoExecUtils
import LocalRemoteExec


def saveInspectData(inspectData):
    out = {'DATA': inspectData}
    AutoExecUtils.saveOutput(out)

def usage():
    pname = os.path.basename(__file__)
    exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--node', default='', help='Execution node json')
    parser.add_argument('--timeout', default=10, help='Timeout seconds')
    args = parser.parse_args()

    timeOut = int(args.timeout)
    if timeOut == 0:
        timeOut = 5

    node = args.node

    try:
        nodeInfo = {}
        hasOptError = False
        if node is None or node == '':
            node = os.getenv('AUTOEXEC_NODE')
        if node is None or node == '':
            print("ERROR: Can not find node definition.")
            hasOptError = True
        else:
            nodeInfo = json.loads(node)

        if hasOptError:
            usage()

        hasError = False

        ip = nodeInfo['host']
        port = None
        if 'port' in nodeInfo:
            port = nodeInfo['port']
        else:
            port = nodeInfo['protocolPort']

        resourceId = nodeInfo['resourceId']
        ciAttrs = AutoExecUtils.getCmdbCiAttrs(resourceId, ['access_type', 'access_endpoint'])

        accessEndPoint = ''
        if 'access_endpoint' in ciAttrs:
            accessEndPoint = ciAttrs['access_endpoint']
        accessType = None
        if 'access_type' in ciAttrs:
            accessType = ciAttrs['access_type']

        if accessType is None:
            if accessEndPoint.startswith('https://'):
                accessType = 'HTTPS'
            elif accessEndPoint.startswith('http://'):
                accessType = 'HTTP'
            elif re.match(':\d+$', accessEndPoint):
                accessType = 'TCP'
            else:
                accessType = 'PING'
                accessEndPoint = ip

        if accessEndPoint == '':
            if accessType in ['HTTP', 'HTTPS']:
                if port is not None:
                    accessEndPoint = '{}://{}:{}'.format(accessType.lower(), ip, port)
                else:
                    accessEndPoint = '{}://{}'.format(accessType.lower(), ip)
            elif ip is not None:
                if port is not None and accessType != 'PING':
                    accessEndPoint = '{}:{}'.format(ip, port)
                else:
                    accessEndPoint = ip

        try:
            print('--------------------------------------------------------------------')
            exec = LocalRemoteExec.LocalRemoteExec()
            ret = False
            errorMsg = None
            startTime = time.time()
            if accessType in ('HTTP', 'HTTPS'):
                # url check
                (ret, errorMsg) = exec.urlCheck(accessEndPoint, timeOut)
            elif accessType == 'TCP':
                # ip:port tcp
                (ret, errorMsg) = exec.tcpCheck(accessEndPoint, timeOut)
            elif accessType == 'URL-SEQUENCE':
                (ret, errorMsg) = exec.urlSeqCheck(accessEndPoint, nodeInfo, timeOut)
            elif accessType == 'BATCH':
                print("WARN: Use script in script store to check batch service, input or output parameters not support.")
                errorMsg = ''
                resourceId = nodeInfo['resourceId']
                endPointConf = AutoExecUtils.getAccessEndpointConf(resourceId)
                if 'config' in endPointConf:
                    scriptConf = endPointConf['config']
                    if scriptConf['type'] != 'script':
                        errorMsg = "ERROR: Config error, not script, {}".format(json.dumps(endPointConf))
                        print(errorMsg)
                    else:
                        scriptId = scriptConf['script']
                        scriptDef = exec.getScriptDef(scriptId)
                        (ret, errorMsg) = exec._remoteExecute(nodeInfo, scriptDef, None)
                else:
                    errorMsg = "ERROR: Script config error."
            else:
                # ping
                (ret, errorMsg) = exec.pingCheck(accessEndPoint, timeOut)

            if not ret:
                hasError = True

            timeConsume = round(time.time() - startTime, 4)
            inspectInfo = {'_OBJ_CATEGORY': 'EMPTY',
                           '_OBJ_TYPE': 'EMPTY',
                           'ACCESS_TYPE': accessType,
                           'ACCESS_ENDPOINT': accessEndPoint}
            if hasError:
                inspectInfo['AVAILABILITY'] = 0
                inspectInfo['ERROR_MESSAGE'] = errorMsg
                inspectInfo['RESPONSE_TIME'] = timeConsume
            else:
                inspectInfo['AVAILABILITY'] = 1
                inspectInfo['ERROR_MESSAGE'] = None
                inspectInfo['RESPONSE_TIME'] = timeConsume

            saveInspectData(inspectInfo)
            if (exec.IS_FAIELD):
                exit(1)
        except Exception as ex:
            print('ERROR: Unknow Error, {}'.format(traceback.format_exc()))
            inspectInfo = {'AVAILABILITY': 0,
                           'ERROR_MESSAGE': str(ex)}
            saveInspectData(inspectInfo)
            exit(2)
    except Exception as ex:
        print('ERROR: Unknow Error, {}'.format(traceback.format_exc()))
        exit(-1)
    finally:
        print('--------------------------------------------------------------------')
