#!/usr/bin/python
import ConfigParser
import os
import os.path
import sys
import utils
import re

if len(sys.argv) < 2:
	progName = os.path.basename(__file__)
	print("ERROR:use as %s config-name\n" % progName)
	sys.exit(1)
homepath = os.path.split(os.path.realpath(__file__))[0]
os.chdir(homepath)

config = ConfigParser.ConfigParser()
config.readfp(open('../conf/was.ini'))

mainname = sys.argv[1]
confname = mainname

dmgrprofile = None
try:
	dmgrprofile = config.get(confname,'dmgr_profile')
	dmgrprofile = dmgrprofile.replace(' ', '')
except:
	pass

was_user = config.get(confname,'was_user')
was_pwd = config.get(confname,'was_pwd')

if dmgrprofile is not None and dmgrprofile != '' and os.path.exists(dmgrprofile):
	cmd = '%s/bin/stopManager.sh  -user %s  -password %s'  %(dmgrprofile,was_user,was_pwd)
	os.system(cmd)
else:
	print('WARN: Dmgr not defined on this server.\n')


