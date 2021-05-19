#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import os
import sys
binPaths = os.path.split(os.path.realpath(__file__))
libPath = os.path.realpath(binPaths[0]+'/../lib')
sys.path.append(libPath)
