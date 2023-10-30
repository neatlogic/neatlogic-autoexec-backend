import ConfigParser
import os

homepath = os.getenv('TS_WASDEPLOYTOOL_HOME')
confname = os.getenv('TS_WASCONF_NAME')
insname = os.getenv('TS_WASINS_NAME')

config = ConfigParser.ConfigParser()
config.readfp(open("%s/conf/wastool.ini" % homepath))

nodename = config.get(confname,'nodename')
appname= config.get(confname,'appname')
servername = config.get(confname, 'servername')

clustername = None
try:
	clustername = config.get(confname, 'clustername')
except:
	pass

servername = servername.replace(' ', '')
servername = servername.replace("\t", '')
servernames = servername.split(',')

appname = appname.replace(' ', '')
appname = appname.replace("\t", '')
appnames = appname.split(',')

nodename = config.get(confname, 'nodename')

execfile('%s/bin/wsadminlib.py' % (homepath))

startWeight = 0

for appname in appnames:
	startWeight = startWeight + 1

	deployedAppnames = listApplications()

	if appname in deployedAppnames :
		for servername in servernames:
			stopApplicationOnServer(appname,nodename,servername)
	else:
		print("ERROR: WAS app %s not exists.\n" % appname)
