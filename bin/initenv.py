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

os.environ['HISTSIZE'] = '0'
os.environ['PERL5LIB'] = '{}/plugins/local/lib:{}/lib:{}/plugins/local/pllib/lib/perl5:{}'.format(homePath, homePath, homePath, os.getenv('PERL5LIB'))
os.environ['PYTHONPATH'] = '{}/lib:{}/plib:{}'.format(homePath, homePath, os.getenv('PYTHONPATH'))
