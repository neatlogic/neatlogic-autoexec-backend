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

wasprofile = config.get(confname,'was_profile')
was_user = config.get(confname,'was_user')
was_pwd = config.get(confname,'was_pwd')


if wasprofile is not None and wasprofile != '' and os.path.exists(wasprofile):
	cmd = '%s/bin/startNode.sh '  %(wasprofile)
	os.system(cmd)


