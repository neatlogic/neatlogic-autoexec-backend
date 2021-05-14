#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import sys
import time
import binascii

PYTHON_VER = sys.version_info.major


def _rc4(key, data):
    x = 0
    box = list(range(256))
    for i in range(256):
        x = (x + box[i] + ord(key[i % len(key)])) % 256
        box[i], box[x] = box[x], box[i]
    x = y = 0
    out = []
    for char in data:
        x = (x + 1) % 256
        y = (y + box[x]) % 256
        box[x], box[y] = box[y], box[x]
        out.append(chr(ord(char) ^ box[(box[x] + box[y]) % 256]))
    return ''.join(out)


def _rc4_encrypt_hex(key, data):
    if PYTHON_VER == 2:
        return binascii.hexlify(_rc4(key, data))
    elif PYTHON_VER == 3:
        return binascii.hexlify(_rc4(key, data).encode("latin-1")).decode("latin-1")


def _rc4_decrypt_hex(key, data):
    if PYTHON_VER == 2:
        return _rc4(key, binascii.unhexlify(data))
    elif PYTHON_VER == 3:
        return _rc4(key, binascii.unhexlify(data.encode("latin-1")).decode("latin-1"))


def getDateTimeStr():
    nowTime = time.localtime(time.time())
    timeStr = '{}-{:0>2d}-{:0>2d} {:0>2d}:{:0>2d}:{:0>2d}'.format(nowTime.tm_year, nowTime.tm_mon, nowTime.tm_mday, nowTime.tm_hour, nowTime.tm_min, nowTime.tm_sec)
    return timeStr


def getTimeStr():
    nowTime = time.localtime(time.time())
    timeStr = '{:0>2d}:{:0>2d}:{:0>2d} '.format(nowTime.tm_hour, nowTime.tm_min, nowTime.tm_sec)
    return timeStr
