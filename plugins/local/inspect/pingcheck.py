#!/usr/bin/python
# -*- coding:UTF-8 -*-

import argparse
import os
import traceback
import time
import json
from ping3 import ping
import AutoExecUtils


def usage():
    pname = os.path.basename(__file__)
    print("{} --node <node> --timeout <timeout seconds> .\n".format(pname))
    exit(-1)


def pingCheck(host, timeOut):
    second = ping(dest_addr=host, timeout=timeOut)
    second = round(second, 4)
    if second:
        print('INFO: {} is reachable, took {} second'.format(host, second))
        return (True, None)
    else:
        loopCount = 2
        while not second and loopCount > 0:
            second = ping(dest_addr=host, timeout=5)
            second = round(second, 4)
            loopCount = loopCount - 1
        if second:
            print('INFO: {} is reachable, took {} second'.format(host, second))
            return (True, None)
        else:
            errorMsg = 'ERROR: {} is unreachable, took {} second'.format(host, second)
            print(errorMsg)
            return (False, errorMsg)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--node', default='', help='Execution node json')
    parser.add_argument('--timeout', default=10, help='Output json file path for node')

    args = parser.parse_args()

    if args.timeout == '':
        timeout = 10
    else:
        timeout = int(args.timeout)

    node = args.node

    try:
        nodeInfo = {}
        hasOptError = False
        if node is None or node == '':
            node = os.getenv('AUTOEXEC_NODE')
        if node is None or node == '':
            print("ERROR: Can not find node definition.\n")
            hasOptError = True
        else:
            nodeInfo = json.loads(node)

        if hasOptError:
            usage()
            exit(1)

        errMsg = None
        print("INFO: Try to ping {}.\n".format(nodeInfo['host']))
        startTime = time.time()

        port = nodeInfo.get('port')
        if port is not None:
            port = int(port)

        data = {'MGMT_IP': nodeInfo.get('host'),
                'PORT': port,
                'RESOURCE_ID': nodeInfo.get('resourceId'),
                'AVAILABILITY': 0
                }

        try:
            (ret, errMsg) = pingCheck(nodeInfo.get('host'), timeout)
            timeConsume = round(time.time() - startTime, 4)
            data['RESPONSE_TIME'] = timeConsume
            if ret:
                data['AVAILABILITY'] = 1
                data['ERROR_MESSAGE'] = ''
                print("FINE: Ping success.\n")
            else:
                data['AVAILABILITY'] = 0
                data['ERROR_MESSAGE'] = errMsg
                print("ERROR: Ping failed.\n")
        except Exception as ex:
            timeConsume = round(time.time() - startTime, 4)
            errMsg = str(ex)
            data['AVAILABILITY'] = 0
            data['ERROR_MESSAGE'] = errMsg
            data['RESPONSE_TIME'] = timeConsume
            print("ERROR: Ping failed.\n")
            exit(2)

        out = {'DATA': data}
        AutoExecUtils.saveOutput(out)
    except Exception as ex:
        print('ERROR: Unknow Error, {}'.format(traceback.format_exc()))
        exit(2)
