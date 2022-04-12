#!/usr/bin/python
import ConfigParser
import os
import os.path
import sys
import re
import glob
import shutil
import utils

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
	print("ERROR:use as was-update.py config-name instance-name\n")
	sys.exit(1)

dmgrprofile = None
try:
	dmgrprofile = config.get(confname, 'dmgr_profile')
except:
	pass
	
standalone = 0
try:
	standalone_str = config.get(confname, 'standalone')
	if standalone_str in ['True', 'true', '1']:
		standalone = 1
except:
	pass

wasprofile = config.get(confname,'was_profile')
appfile = config.get(confname,'appfile')
appname = config.get(confname,'appname')
servername = config.get(confname, 'servername')

was_user = config.get(confname,'was_user')
was_pwd = config.get(confname,'was_pwd')

need_deploy = 1
try:
	need_deploy_str = config.get(confname,'need_deploy')
	if need_deploy_str in ['False', 'false', '0']:
		need_deploy = 0
except:
	pass


ihs_dir = None
ihs_docroot = None
try:
	ihs_dir = config.get(confname,'ihs_dir')
	ihs_docroot = config.get(confname,'ihs_docroot')
except:
	pass

servername = servername.replace(' ', '')
servername = servername.replace("\t", '')
servernames = servername.split(',')

appname = appname.replace(' ', '')
appname = appname.replace("\t", '')
appnames = appname.split(',')

appfile = appfile.replace(' ', '')
appfile = appfile.replace("\t", '')
appfiles = appfile.split(',')

if need_deploy == 1:
	if wasprofile is not None and os.path.isdir(wasprofile):
		cmd = '%s/bin/wsadmin.sh  -lang jython -user %s -password %s -f %s/bin/was-autodeploy.py' % (wasprofile,was_user,was_pwd,homepath)
		#if standalone == 0:
		#	cmd = '%s/bin/wsadmin.sh  -lang jython -user %s -password %s -f %s/bin/was-autodeploy.py' % (dmgrprofile,was_user,was_pwd,homepath)
		
		os.environ['TS_WASDEPLOYTOOL_HOME'] = homepath
		os.environ['TS_WASCONF_NAME'] = confname
		os.environ['TS_WASINS_NAME'] = insname
		ret = os.system(cmd)
		if ret != 0 and standalone == 1:
			print("INFO: autodeploy failed, maybe the server not started, restart it and try again.\n")
			stopSrvCmd = '%s/bin/was-stop.py %s %s' % (homepath,mainname,insname)
			os.system(stopSrvCmd)
			
			for servername in servernames:
				startSrvCmd = '%s/bin/startServer.sh  %s' % (wasprofile,servername)
				os.system(startSrvCmd)
			
			os.system(cmd)
			#os.system(stopSrvCmd)
			
			print("INFO: Deploy complete, it will take few minutes to sync the application to other nodes, please do not restart the servers immediately.\n")
			for appname in appnames:
				checkurl = None
				try:
						checkurl = config.get(confname, '%s.checkurl' % appname)
				except:
						pass
				utils.checkUtilUrlAvaliable(checkurl)


if ihs_docroot is not None and ihs_docroot != '' and os.path.exists(ihs_docroot):
	i = 0
	for appname in appnames:
		hasExtracted = 0
		appfile = appfiles[i]
		i = i + 1
		if appfile.endswith('.war'):
			contextroot = '/'
			try:
				contextroot = config.get(confname, '%s.contextroot' % appname)
			except:
				contextroot = config.get(confname, 'contextroot')
	
			ihs_targetdir = '%s/%s' % (ihs_docroot, contextroot)
			ihs_targetdir.replace('//', '/')
			if ihs_docroot is not None and ihs_docroot != '' and ihs_targetdir != '/' and os.path.exists(ihs_targetdir):
				if os.path.exists(ihs_targetdir):
					#remove the targetdir
					cleanCmd = 'rm -rf %s' % ihs_targetdir
					print ('INFO: Remove deploy dir %s.\n' % ihs_targetdir)
					os.system(cleanCmd)
				print ('INFO: Extract package to %s.') % ihs_targetdir
				cmd = 'unzip -qo %s/pkgs/%s/%s -d %s' % (homepath, insname, appfile, ihs_targetdir)
				rmcmd = 'rm -rf %s/WEB-INF' % (ihs_targetdir)
				os.system(cmd)
				os.system(rmcmd)
				hasExtracted = 1
	
			#if hasExtracted == 0:
				#print("ERROR: WAS target dir:%s and IHS target dir:%s are not exists.\n" % (targetdir, ihs_targetdir))
				#print("ERROR: WAS app and IHS web doc must be deploy correctly before use this programe to update app.\n")
				
	
		#TODO: ear extract must to be tested.
		elif appfile.endswith('.ear'):
	
	 		ihs_targetdir = ihs_docroot
			if ihs_docroot is not None and ihs_docroot != '' and ihs_targetdir != '/' and os.path.exists(ihs_targetdir):
				print ('INFO: Extract package to %s.') % ihs_targetdir
				cmd = 'unzip -qo %s/pkgs/%s/%s -d %s' % (homepath, insname, appfile, ihs_targetdir)
				os.system(cmd)
				
				warfiles = glob.glob('%s/*.war' % targetdir)
				for warfile in warfiles:
					cmd = 'unzip -qo %s -d %s.extract' % (warfile, warfile)
					os.system(cmd)
					shutil.remove(warfile)
					
					warContextRoot = None
					try:
						warContextRoot = config.get(confname,'%s.%s.contextroot' % (appname, warfile))
					except:
						pass
					if warContextRoot is None or warContextRoot == '':
						warContextRoot = '/'
					
					warContextRoot = re.sub(r'\/+', '', warContextRoot)
					
					shutil.move('%s.extract' % warfile, '%s/%s' % (targetdir, warContextRoot))
					rmcmd = 'rm -rf %s/WEB-INF' % (warfile)
					os.system(rmcmd)
					
				hasExtracted = 1
	
			#if hasExtracted == 0:
		#		print("ERROR: WAS target dir:%s and IHS target dir:%s are not exists.\n" % (targetdir, ihs_targetdir))
		#		print("ERROR: WAS app and IHS web doc must be deploy correctly before use this programe to update app.\n")


