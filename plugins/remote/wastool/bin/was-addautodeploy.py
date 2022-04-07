import ConfigParser
import os
import httplib

homepath = os.getenv('TS_WASDEPLOYTOOL_HOME')
confname = os.getenv('TS_WASCONF_NAME')
insname = os.getenv('TS_WASINS_NAME')
serverpid = os.getenv('TS_SERVERPID')

config = ConfigParser.ConfigParser()
config.optionxform = str
config.readfp(open("%s/conf/wastool.ini" % homepath))

appfile = config.get(confname,'appfile')
appname= config.get(confname,'appname')
servername = config.get(confname, 'servername')
try:
	pkgsDir = config.get(confname, 'pkgs_dir')
except:
	pkgsDir = "%s/pkgs" % (homepath);
if pkgsDir is None or pkgsDir == '':
	pkgsDir = "%s/pkgs" % (homepath);

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


appfile = appfile.replace(' ', '')
appfile = appfile.replace("\t", '')
appfiles = appfile.split(',')

execfile('%s/bin/utils.py' % homepath)
execfile('%s/bin/wsadminlib.py' % (homepath))
startWeight = 0
deployedAppnames = listApplications()

for appname in appnames:
	appfile = "%s/%s/%s" % (pkgsDir, insname, appfiles[startWeight])

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
	
	installDir = None
	try:
		appdir = config.get(confname, '%s.targetdir' % appname)
		if appdir != '':
			installDir = appdir
	except:
		pass

	if appname in deployedAppnames :
		checkUtilUrlAvaliable(precheckurl)

		AdminApp.update(appname, 'partialapp', ['-operation', 'update', '-contents', appfile, ])
		AdminConfig.save()

		#checkUtilUrlAvaliable(checkurl)
	else:
		checkUtilUrlAvaliable(precheckurl)

		options = []
		contextroot = '/'

		nodename = config.get(confname, 'nodename')
		if appfile.endswith('.war'):
			print("INFO: Begin to deploy war.\n")
			try:
				contextroot = config.get(confname, '%s.contextroot' % appname)
			except:
				contextroot = config.get(confname, 'contextroot')

			options = ['-contextroot', contextroot, '-appname', appname]
		elif appfile.endswith('.ear'):
			print("INFO: Begin to deploy ear.\n")
			contextroot = '/'
			contextOpts = []
			opts = config.options(confname)
			for opt in opts:
				if opt.endswith('contextroot') and opt.startswith(appname):
					warFile = opt
					warFile = warFile.replace('.contextroot', '')
					warFile = warFile.replace('%s.' % appname, '')
					warAppName = warFile
					warAppName = warAppName.replace('.', '_')
					warContextRoot = config.get(confname, opt)
					if warContextRoot is None or warContextRoot == '':
						warContextRoot = '/'

					contextOpts.append([appname, '%s,WEB-INF/web.xml' % warFile, warContextRoot])

			#if len(contextOpts) > 0:
			#	options = ['-CtxRootForWebMod']
			#	options.append(contextOpts)

		if installDir is not None:
			options.extend(['-installed.ear.destination', installDir])
		
		extopt = None
		try:
			extopt = config.get(confname, '%s.options' % appname)
			print("extend options:%s\n" % extopt)
		except:
			pass

		if extopt != None and extopt != '':
			extoptions = eval(extopt)
			options.extend(extoptions)

		print("INFO: App options:%s\n" % options)

		if clustername != None and clustername != '':
			installApplication(appfile, [], [clustername], options)
			print("INFO: Begin deploy %s on cluster:%s with option:%s.\n" % (appfile, clustername, options))
		else:
			targets = []
			for servername in servernames:
				targets.append({'nodename':nodename, 'servername':servername})

			print("INFO: Begin deploy %s on target:%s with option:%s.\n" % (appfile, targets, options))
			installApplication(appfile, targets, [], options)

		print("INFO: App %s installed.\n" % appfile)

		dep = AdminConfig.getid("/Deployment:%s" % appname)
		depObject = AdminConfig.showAttribute(dep, "deployedObject")
		print("modify the startingWeight...")
		AdminConfig.modify(depObject, [['startingWeight', '%d' % startWeight]])
		print("modify the backgroundApplication to true:app start before server start.")
		AdminConfig.modify(depObject, [['backgroundApplication', 'true']])

		AdminConfig.save()
		print("config saved.\n")

		result = AdminApp.isAppReady(appname)
		while (result == "false"):
			print AdminApp.getDeployStatus(appname)
			time.sleep(5)
			result = AdminApp.isAppReady(appname)

		print("INFO: App DeployStatus finshed.")
		for servername in servernames:
			#startApplication(appname)
			if serverpid:
				print("Starting %s application %s...\n" % (servername , appname))
				startApplicationOnServer(appname,nodename,servername)
				print("startApplication %s complete.\n" % appname)
		#checkUtilUrlAvaliable(checkurl)
		#startApplicationOnCluster(appname,clustername)
		#startApplicationOnServer(appname,nodename,servername)
	startWeight = startWeight + 1
