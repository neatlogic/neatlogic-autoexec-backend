#!/usr/bin/python
import ConfigParser
import os
import os.path
import sys
import time
import subprocess
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
        print("ERROR:use as was-stop.py config-name instance-name\n")
        sys.exit(1)


wasprofile = config.get(confname,'was_profile')
nodename = config.get(confname, 'nodename')
servername = config.get(confname,'servername')
was_user = config.get(confname,'was_user')
was_pwd = config.get(confname,'was_pwd')

servername = servername.replace(' ', '')
servername = servername.replace("\t", '')
servernames = servername.split(',')

ihs_dir = None
try:
        ihs_dir = config.get(confname,'ihs_dir')
except:
        pass


if wasprofile is not None and wasprofile != '' and servername is not None and servername != '':

	for servername in servernames:
		cmd = '%s/bin/stopServer.sh  %s -username %s -password %s' % (wasprofile,servername,was_user,was_pwd)
		os.system(cmd)

		pid = ''
		checkCount = 30
		while checkCount > 0:
			pscmd = "ps auxww |grep '%s %s' | grep -v grep | awk '{print $2}'" % (nodename, servername)
			pipe = subprocess.Popen(pscmd, universal_newlines=True, bufsize=128, stderr=subprocess.STDOUT, stdout=subprocess.PIPE, shell=True)
			pid = pipe.stdout.read().strip()
			pid = re.sub(r'\s+', ' ', pid)
			checkCount = checkCount - 1
			if pid == ' ' or pid == '':
				break
			time.sleep(2)
	
		if pid != '' and pid != ' ':
			print('INFO: WAS pid %s, try to kill it.\n' % pid)
			os.system('kill %s' % pid)

			time.sleep(3)
		
			pipe = subprocess.Popen(pscmd, universal_newlines=True, bufsize=128, stderr=subprocess.STDOUT, stdout=subprocess.PIPE, shell=True)
			pid = pipe.stdout.read()
			pid = re.sub(r'\s+', ' ', pid)
			if pid != '' and pid != ' ':
				print('INFO: WAS pid %s, kill it failed, try to kill -9.\n' % pid)
				os.system('kill -9 %s' % pid)
				time.sleep(3)
		else:
			print("INFO: WAS server is stopped.\n")
	
if ihs_dir is not None and ihs_dir != '' and os.path.exists(ihs_dir):
	cmd = '%s/bin/apachectl stop' % (ihs_dir)
	os.system(cmd)

	pid = ''
	checkCount = 30
	while checkCount > 0:
		pscmd = "ps auxww |grep '%s' | grep -v grep | awk '{print $2}'" % (ihs_dir)
		pipe = subprocess.Popen(pscmd, universal_newlines=True, bufsize=128, stderr=subprocess.STDOUT, stdout=subprocess.PIPE, shell=True)
		pid = pipe.stdout.read().strip()
		pid = re.sub(r'\s+', ' ', pid)
		checkCount = checkCount - 1
		if pid == '' or pid == ' ':
			break
		time.sleep(2)

	if pid != '' and pid != ' ':
		print('INFO: IHS pid %s, try to kill it.\n' % pid)
		os.system('kill %s' % pid)
	
		time.sleep(3)
	
		pipe = subprocess.Popen(pscmd, universal_newlines=True, bufsize=128, stderr=subprocess.STDOUT, stdout=subprocess.PIPE, shell=True)
		pid = pipe.stdout.read()
		pid = re.sub(r'\s+', ' ', pid)
	
		if pid != '' and pid != ' ':
			print('INFO: IHS pid %s, kill it failed, try to kill -9.\n' % pid)
			os.system('kill -9 %s' % pid)
			time.sleep(3)
	else:
		print("INFO: IHS server is stopped.\n")


