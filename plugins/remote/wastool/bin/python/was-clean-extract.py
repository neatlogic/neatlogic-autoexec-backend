#!/usr/bin/python
import ConfigParser
import os
import os.path
import sys
import re
import glob
import shutil
import utils

progName = os.path.basename(__file__)

if len(sys.argv) < 2:
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
	print("ERROR:use as %s config-name instance-name\n" % progName)
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
cellname = config.get(confname,'cellname')
nodename = config.get(confname,'nodename')
servername = config.get(confname,'servername')
appfile = config.get(confname,'appfile')
appname= config.get(confname,'appname')

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

isFirstDeploy = 1

i = 0
if need_deploy == 1:
	for appname in appnames:
		hasExtracted = 0
		appfile = appfiles[i]
		i = i + 1
		if appfile.endswith('.war'):
			desctarget = '%s/config/cells/%s/applications/%s.ear/deployments/%s' % (wasprofile, cellname, appname, appname)
			dmgrtarget = '%s/config/cells/%s/applications/%s.ear/deployments/%s' % (dmgrprofile, cellname, appname, appname)
			appfilePath = '%s/pkgs/%s/%s' % (homepath, insname, appfile)
			
			targetdir = ''
			try:
				appdir = config.get(confname, '%s.targetdir' % appname.lower())
				if appdir == '':
					targetdir = '%s/installedApps/%s/%s.ear/%s' % (wasprofile, cellname, appname, appfile)
				else: 
					targetdir = '%s/%s.ear/%s' % (appdir, appname, appfile)
			except:
				targetdir = '%s/installedApps/%s/%s.ear/%s' % (wasprofile, cellname, appname, appfile)
			
			if os.path.exists(targetdir) and os.path.exists(desctarget):
				isFirstDeploy = 0
				#remove the was tmp workdir for app
				for servername in servernames:
					#/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/temp/cooaap1uNode01/server1/cowork_war
					tmpdir = '%s/temp/%s/%s/%s' % (wasprofile, nodename, servername, appname)
					if os.path.exists(tmpdir):
						cleanCmd = 'rm -rf %s' % tmpdir
						os.system(cleanCmd)
						print('INFO: Remove temp dir:%s\n' % tmpdir)
				
				#remove the targetdir
				cleanCmd = 'rm -rf %s' % targetdir
				print ('INFO: Remove deploy dir %s.\n' % targetdir)
				os.system(cleanCmd)
	
				print ('INFO: Extract package to %s.') % targetdir
				if not os.path.exists(targetdir):
					os.makedirs(targetdir)
				
				cmd = 'unzip -qo %s/pkgs/%s/%s -d %s' % (homepath, insname, appfile, targetdir)
				os.system(cmd)
				
				utils.copyDeployDesc(appname, appfilePath, os.path.dirname(targetdir), desctarget);
				#wardescs = glob.glob('%s/config/cells/%s/applications/%s.ear/deployments/%s/%s/WEB-INF/*' % (wasprofile, cellname, appname, appname, appfile))
				#for wardesc in wardescs:
				#	wardescFile = os.path.basename(wardesc)
				#	wardescSrc = '%s/WEB-INF/%s' % (targetdir, wardescFile)
				#	if os.path.exists(wardescSrc):
				#		shutil.copyfile(wardescSrc, wardesc)
				#		print('INFO: Update descriptor file:%s\n' % wardesc)
				if os.path.exists(dmgrtarget):
					utils.copyDeployDesc(appname, appfilePath, os.path.dirname(targetdir), dmgrtarget)
					
				hasExtracted = 1

			contextroot = '/'
			try:
				contextroot = config.get(confname, '%s.contextroot' % appname)
			except:
				contextroot = config.get(confname, 'contextroot')
	
			ihs_targetdir = '%s/%s' % (ihs_docroot, contextroot)
			ihs_targetdir.replace('//', '/')
			if ihs_docroot is not None and ihs_docroot != '' and ihs_targetdir != '/':
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
	
		#TODO: ear extract must to be tested.
		elif appfile.endswith('.ear'):
			print("ERROR: ear deploy not suported by this python script.\n")
			sys.exit(-1)

			desctarget = '%s/config/cells/%s/applications/%s/deployments/%s' % (wasprofile, cellname, appfile, appname)
			dmgrtarget = '%s/config/cells/%s/applications/%s.ear/deployments/%s' % (dmgrprofile, cellname, appname, appname)
			appfilePath = '%s/pkgs/%s/%s' % (homepath, insname, appfile)
			
			appdir = config.get(confname, '%s.targetdir' % appname)
			if appdir == '':
				targetdir = '%s/installedApps/%s/%s.ear' % (wasprofile, cellname, appname)
			else:
				targetdir = '%s/%s.ear' % (appdir, appname)
			
			if os.path.exists(targetdir) and os.path.exists(desctarget):
				isFirstDeploy = 0
				#remove the was tmp workdir for app
				for servername in servernames:
					#/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/temp/cooaap1uNode01/server1/cowork_war
					tmpdir = '%s/temp/%s/%s/%s' % (wasprofile, nodename, servername, appname)
					if os.path.exists(tmpdir):
						cleanCmd = 'rm -rf %s' % tmpdir
						os.system(cleanCmd)
						print('INFO: Remove temp dir:%s\n' % tmpdir)
				
				#remove the targetdir
				cleanCmd = 'rm -rf %s' % targetdir
				print ('INFO: Remove deploy dir %s.\n' % targetdir)
				os.system(cleanCmd)
				
				wardirs = glob.glob('%s/*.war' % targetdir)
				for wardir in wardirs:
					shutil.move(wardir, '%s.extract' % wardir)
				
				print ('INFO: Extract package to %s.') % targetdir
				if not os.path.exists(targetdir):
					os.makedirs(targetdir)
				
				cmd = 'unzip -qo %s/pkgs/%s/%s -d %s' % (homepath, insname, appfile, targetdir)
				os.system(cmd)
				
				warfiles = glob.glob('%s/*.war' % targetdir)
				for warfile in warfiles:
					cmd = 'unzip -qo %s -d %s.extract' % (warfile, warfile)
					os.system(cmd)
					shutil.remove(warfile)
					shutil.move('%s.extract' % warfile, warfile)
				
				utils.copyDeployDesc(appname, appfilePath, targetdir, desctarget)
				#curdir = os.getcwd()
				#os.chdir(targetdir)
				#descfiles = glob.glob('*.war/WEB-INF/*.*') + glob.glob('*.war/META-INF/*.*')
				#for descfile in descfiles:
				#	descdest = '%s/%s' % (desctarget, descfile)
				#	descfile = '%s/%s' % (targetdir, descfile)
				#	if os.path.isfile(descfile):
				#		descdir = os.path.dirname(descdest)
				#		if not os.path.isdir(descdir):
				#			os.makedirs(descdir)
				#		if os.path.exists(descfile):
				#			shutil.copyfile(descfile, descdest)
				#			print('INFO: Update descriptor file:%s\n' % wardesc)
				#		
				#os.chdir(curdir)
				
				if os.path.exists(dmgrtarget):
					utils.copyDeployDesc(appname, appfilePath, targetdir, dmgrtarget)
				
				hasExtracted = 1
			
			if ihs_docroot is not None and ihs_docroot != '' and ihs_docroot != '/' and os.path.exists(ihs_docroot):
				#if os.path.exists(ihs_targetdir):
				#	#remove the targetdir
				#	cleanCmd = 'rm -rf %s' % ihs_targetdir
				#	print ('INFO: Remove deploy dir %s.\n' % ihs_targetdir)
				#	os.system(cleanCmd)
				
				extractTmp = "%s/pkgs/%s/%s.extract" % (homepath, insname, appfile)
				print ('INFO: Extract ear package to %s.') % extractTmp
				cmd = 'unzip -qo %s/pkgs/%s/%s -d %s' % (homepath, insname, appfile, extractTmp)
				os.system(cmd)
				
				chdir(extractTmp)
				warfiles = glob.glob('*.war')
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
					
					ihs_targetdir = '%s/%s' % (ihs_docroot, warContextRoot)
					if os.path.exists(ihs_targetdir):
						rmcmd = 'rm -rf %s' % (ihs_targetdir)
						os.system(rmcmd)
					
					rmcmd = 'rm -rf %s.extract/WEB-INF' % (warfile)
					os.system(rmcmd)
					shutil.move('%s.extract' % (warfile), ihs_targetdir)
					
				chdir('%s/..' % (extractTmp))
				if os.path.exists(extractTmp):
					rmcmd = 'rm -rf %s' % (extractTmp)
					os.system(rmcmd)
				
				hasExtracted = 1
				
if need_deploy == 1 and isFirstDeploy == 1:
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
		

