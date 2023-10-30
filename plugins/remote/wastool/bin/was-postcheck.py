import ConfigParser
import os
import string

homepath = os.getenv('TS_WASDEPLOYTOOL_HOME')
confname = os.getenv('TS_WASCONF_NAME')
insname = os.getenv('TS_WASINS_NAME')

config = ConfigParser.ConfigParser()
config.readfp(open("%s/conf/wastool.ini" % homepath))

appfile = config.get(confname,'appfile')
appname= config.get(confname,'appname')
servername = config.get(confname, 'servername')

execfile('%s/bin/wsadminlib.py' % homepath)

servername = config.get(confname,'servername')

servername = servername.replace(' ', '')
servername = servername.replace("\t", '')
servernames = servername.split(',')


deployAppnames = listApplications()
if deployAppnames is not None:
	print('INFO: Installed apps:', deployAppnames)
else:
	print('ERROR: Call wsadmin failed, check was config items.\n')

servers = listAllServers()
print('INFO: Servers:', servers)

for servername in servernames:
	nodeAndServer = None
	if nodeAndServer in servers:
		if servername in nodeAndServer:
			print('SUCCESS: servername:%s is OK.\n')
		else:
			print('ERROR: Config item servername:%s not exists.\n' % servername)

