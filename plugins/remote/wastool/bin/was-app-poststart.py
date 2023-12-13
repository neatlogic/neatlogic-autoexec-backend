import ConfigParser
import os

homepath = os.getenv('TS_WASDEPLOYTOOL_HOME')
confname = os.getenv('TS_WASCONF_NAME')
insname = os.getenv('TS_WASINS_NAME')

config = ConfigParser.ConfigParser()
config.readfp(open("%s/conf/wastool.ini" % homepath))

nodename = config.get(confname,'nodename')
appfile = config.get(confname,'appfile')
appname= config.get(confname,'appname')

clustername = None
try:
	clustername = config.get(confname, 'clustername')
except:
	pass

appname = appname.replace(' ', '')
appname = appname.replace("\t", '')
appnames = appname.split(',')

appfile = appfile.replace(' ', '')
appfile = appfile.replace("\t", '')
appfiles = appfile.split(',')

servername = config.get(confname, 'servername')
servername = servername.replace(' ', '')
servername = servername.replace("\t", '')
servernames = servername.split(',')

nodename = config.get(confname, 'nodename')

execfile('%s/bin/utils.py' % homepath)
execfile('%s/bin/wsadminlib.py' % homepath)

deployedAppnames = listApplications()
for appname in appnames:
	precheckurl = None
	checkurl = None
	try:
		checkurl = config.get(confname, '%s.checkurl' % appname)
	except:
		pass
	
	try:
		precheckurl = config.get(confname, '%s.precheckurl' % appname)
	except:
		pass
	
	if appname in deployedAppnames:
		checkUtilUrlAvaliable(precheckurl)
		for servername in servernames:
			#startApplication(appname)
			startApplicationOnServer(appname,nodename,servername)
		checkUtilUrlAvaliable(checkurl)
	else:
		print('ERROR: WAS app %s not exists.\n' % appname);

