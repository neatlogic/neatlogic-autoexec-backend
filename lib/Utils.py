#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import time


def rc4(key, data):
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


def getDateTimeStr():
    nowTime = time.localtime(time.time())
    timeStr = '{}-{:0>2d}-{:0>2d} {:0>2d}:{:0>2d}:{:0>2d}'.format(nowTime.tm_year, nowTime.tm_mon, nowTime.tm_mday, nowTime.tm_hour, nowTime.tm_min, nowTime.tm_sec)
    return timeStr


def getTimeStr():
    nowTime = time.localtime(time.time())
    timeStr = '{:0>2d}:{:0>2d}:{:0>2d} '.format(nowTime.tm_hour, nowTime.tm_min, nowTime.tm_sec)
    return timeStr
