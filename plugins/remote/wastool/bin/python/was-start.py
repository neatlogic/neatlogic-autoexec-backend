#!/usr/bin/python
import ConfigParser
import os
import os.path
import sys
import utils
import re

if len(sys.argv) < 2:
	progName = os.path.basename(__file__)
	print("ERROR:use as %s config-name instance-name\n" % progName)
	sys.exit(1)

homepath = os.path.split(os.path.realpath(__file__))[0]
os.chdir(homepath)

config = ConfigParser.ConfigParser()
config.readfp(open('../conf/was.ini'))

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
        print("ERROR:use as was-start.py config-name instance-name\n")
        sys.exit(1)


try:
        lang = config.get(confname, 'lang')
        if lang != '':
                os.environ['LANG'] = lang
except:
        pass

try:
        lcAll = config.get(confname, 'lc_all')
        if lcAll != '':
                os.environ['LC_ALL'] = lcAll
except:
        pass


wasprofile = config.get(confname,'was_profile')
servername = config.get(confname,'servername')
was_user = config.get(confname,'was_user')
was_pwd = config.get(confname,'was_pwd')
appname= config.get(confname,'appname')

servername = servername.replace(' ', '')
servername = servername.replace("\t", '')
servernames = servername.split(',')

appname = appname.replace(' ', '')
appname = appname.replace("\t", '')
appnames = appname.split(',')

ihs_dir = None
try:
	ihs_dir = config.get(confname,'ihs_dir')
except:
	pass


if wasprofile is not None and wasprofile != '' and servername is not None and servername != '':

	for appname in appnames:
	        precheckurl = None
	        try:
	                precheckurl = config.get(confname, '%s.precheckurl' % appname)
	        except:
	                pass
	
		utils.checkUtilUrlAvaliable(precheckurl)

	for servername in servernames:
		cmd = '%s/bin/startServer.sh  %s' % (wasprofile,servername)
		os.system(cmd)

	for appname in appnames:
		checkurl = None
		try:
				checkurl = config.get(confname, '%s.checkurl' % appname)
		except:
				pass
		utils.checkUtilUrlAvaliable(checkurl)


if ihs_dir is not None and ihs_dir != '' and os.path.exists(ihs_dir):
	cmd = '%s/bin/apachectl start' % (ihs_dir)
	os.system(cmd)


