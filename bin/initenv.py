#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import os
import sys
binPaths = os.path.split(os.path.realpath(__file__))
homePath = os.path.realpath(binPaths[0]+'/..')
sys.path.append(homePath + '/lib')
sys.path.append(homePath + '/plib')
sys.path.append(homePath + '/plugins/local/bin')
sys.path.append(homePath + '/plugins/local/lib')
sys.path.append(homePath + '/plugins/local/tools')

os.environ['AUTOEXEC_HOMEPATH'] = homePath

if 'PERLLIB' in os.environ:
    os.environ['PERLLIB'] = '{}:{}'.format(homePath + '/plugins/local/lib', os.environ['PERLLIB'])
else:
    os.environ['PERLLIB'] = homePath + '/plugins/local/lib'
