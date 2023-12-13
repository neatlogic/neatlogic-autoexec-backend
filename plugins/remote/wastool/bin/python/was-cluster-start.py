#!/usr/bin/python
import ConfigParser
import os
import sys
import utils
import re

if len(sys.argv) < 2:
	progName = os.path.basename(__file__)
	print("ERROR:use as %s config-name instance-name\n" % progName)
	sys.exit(1)

homepath = os.path.split(os.path.realpath(__file__))[0]
homepath = os.path.realpath("%s/.." % homepath)
os.chdir(homepath)

config = ConfigParser.ConfigParser()
config.readfp(open('conf/was.ini'))

#test section name, sequence: mainname.insname -> mainname.insprefix -> mainname
mainname = sys.argv[1]
insname = None
if len(sys.argv) == 3:
        insname = sys.argv[2]

confname = mainname
if insname is not None:
        insprefix = re.sub(r'\d*$', '', insname)
        sections = config.sections()
        if '%s.%s' % (mainname, insname) in sections:
                confname = '%s.%s' % (mainname, insname)
        elif '%s.%s' % (mainname, insprefix) in sections:
                confname = '%s.%s' % (mainname, insprefix)
else:
        print("ERROR:use as was-cluster-start.py config-name instance-name\n")
        sys.exit(1)


wasprofile = config.get(confname,'was_profile')
was_user = config.get(confname,'was_user')
was_pwd = config.get(confname,'was_pwd')
appname= config.get(confname,'appname')

appname = appname.replace(' ', '')
appname = appname.replace("\t", '')
appnames = appname.split(',')

for appname in appnames:
	precheckurl = None
	try:
		precheckurl = config.get(confname, '%s.precheckurl' % appname)
	except:
		pass
	utils.checkUtilUrlAvaliable(precheckurl)

cmd = '%s/bin/wsadmin.sh  -lang jython -user %s -password %s -f %s/bin/was-cluster-poststart.py' % (wasprofile,was_user,was_pwd,homepath)
os.environ['TS_WASDEPLOYTOOL_HOME'] = homepath
os.environ['TS_WASCONF_NAME'] = confname
os.environ['TS_WASINS_NAME'] = insname
os.system(cmd)


for appname in appnames:
	checkurl = None
	try:
		checkurl = config.get(confname, '%s.checkurl' % appname)
	except:
		pass
	utils.checkUtilUrlAvaliable(checkurl)

