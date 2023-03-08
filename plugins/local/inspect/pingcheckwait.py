#!/usr/bin/python3
# -*- coding:UTF-8 -*-

import argparse
import sys
import os
import traceback
from ping3 import ping


def usage():
    pname = os.path.basename(__file__)
    print("{} --node <node> --timeout <timeout seconds> .\n".format(pname))
    exit(-1)


def pingCheck(host, timeOut):
    second = ping(dest_addr=host, timeout=timeOut)
    if second:
        second = round(second, 4)
        print('INFO: {} is reachable, took {} second'.format(host, second))
        return (True, None)
    else:
        loopCount = 2
        while not second and loopCount > 0:
            second = ping(dest_addr=host, timeout=5)
            loopCount = loopCount - 1
        if second:
            second = round(second, 4)
            print('INFO: {} is reachable, took {} second'.format(host, second))
            return (True, None)
        else:
            errorMsg = 'WARN: {} is unreachable.'.format(host, second)
            print(errorMsg)
            return (False, errorMsg)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='127.0.0.1', help='Execution host')
    parser.add_argument('--retrycount', default='1', help='Execution retry count')
    parser.add_argument('--timeout', default=10, help='Output json file path for node')

    args = parser.parse_args()

    host = args.host
    if args.timeout == '':
        timeout = 10
    else:
        timeout = int(args.timeout)

    retryCount = int(args.retrycount)

    try:
        isFailed = 1
        for loop in range(0, retryCount):
            try:
                print("INFO: Try to ping {}...".format(host))
                (ret, errMsg) = pingCheck(host, timeout)
                if ret:
                    isFailed = 0
                    break
            except Exception as ex:
                errMsg = str(ex)
                print('WARN: ' + errMsg)

        if isFailed:
            print("ERROR: Ping failed(timeout).")
        else:
            print("FINE: Ping succeed.")
        sys.exit(isFailed)
    except Exception as ex:
        print('ERROR: Unknow Error, {}'.format(traceback.format_exc()))
        sys.exit(2)
