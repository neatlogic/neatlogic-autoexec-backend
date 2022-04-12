import ConfigParser
import os

homepath = os.getenv('TS_WASDEPLOYTOOL_HOME')
confname = os.getenv('TS_WASCONF_NAME')
insname  = os.getenv('TS_WASINS_NAME')

config = ConfigParser.ConfigParser()
config.readfp(open("%s/conf/wastool.ini" % homepath))

clustername = None
try:
	clustername = config.get(confname, 'clustername')
except:
	pass

execfile('%s/bin/wsadminlib.py' % (homepath))

stopCluster( clustername )
