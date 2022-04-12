#!/usr/bin/python
import ConfigParser
import os
import os.path
import sys
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


wasprofile = None
cellname = None
appname = None
was_user = None
was_pwd = None
appname = None
appfile = None

try:
        wasprofile = config.get(confname,'was_profile')
except:
        pass

try:
        cellname = config.get(confname,'cellname')
except:
        pass

try:
        appname= config.get(confname,'appname')
except:
        pass

try:
        appfile = config.get(confname,'appfile')
except:
        pass

try:
        was_user = config.get(confname,'was_user')
except:
        pass

try:
        was_pwd = config.get(confname,'was_pwd')
except:
        pass



ihs_dir = None
ihs_docroot = None
try:
        ihs_dir = config.get(confname,'ihs_dir')
        ihs_docroot = config.get(confname,'ihs_docroot')
except:
        pass


appnames = []
if appname is not None:
        appname = appname.replace(' ', '')
        appname = appname.replace("\t", '')
        appnames = appname.split(',')

appfiles = []
if appfile is not None:
        appfile = appfile.replace(' ', '')
        appfile = appfile.replace("\t", '')
        appfiles = appfile.split(',')

if appname is not None and appfile is not None:
        if len(appfiles) != len(appnames):
                print('appfiles#####')
                print(appfiles)
                print('appnames#####')
                print(appnames)
                print('ERROR: config item:appname and appfile count not match.\n')
if (appname is not None and appfile is None) or (appname is None and appfile is None):
        print('ERROR: appname and appfile must mapping correct.\n')


isFirstDeploy = 1

celldir = '%s/installedApps/%s' %  (wasprofile, cellname)
if os.path.exists(celldir):
        print('SUCCESS: WAS cell dir check OK, %s exists.\n' % celldir)
else:
        print('ERROR: WAS cell dir %s not exists, check config item:wasprofile and cellname.\n' %celldir)

if ihs_docroot is not None and ihs_docroot != '':
        if os.path.exists(ihs_docroot):
                print('SUCCESS: IHS doc root check OK, %s exists.\n' % ihs_docroot)
        else:
                print('ERROR: IHS doc root %s not exists. check config item:ihs_docroot.\n' % ihs_docroot)

        if os.path.exists(ihs_dir):
                print('SUCCESS: IHS dir check OK, %s exists.\n' % ihs_dir)
        else:
                print('ERROR: IHS dir %s not exists. check config item:ihs_dir.\n' % ihs_dir)
i = 0

if appname is not None and appfile is not None:
        for appname in appnames:
                appfile = appfiles[i]
                i = i + 1
                if appfile.endswith('.war'):
                        targetdir = '%s/installedApps/%s/%s.ear/%s' % (wasprofile, cellname, appname, appfile)
                        if os.path.exists(targetdir):
                                print ('SUCCESS: WAS app dir check OK, %s exists.\n' % targetdir)

                #TODO: ear extract must to be tested.
                elif appfile.endswith('.ear'):
                        targetdir = '%s/installedApps/%s/%s' % (wasprofile, cellname, appname, appfile)
                        if os.path.exists(targetdir):
                                print ('SUCCESS: WAS app dir check OK, %s exists.\n' % targetdir)


if isFirstDeploy == 1 and wasprofile is not None and wasprofile != '':
        cmd = '%s/bin/wsadmin.sh  -lang jython -user %s -password %s -f %s/bin/was-postcheck.py' % (wasprofile,was_user,was_pwd,homepath)
        os.environ['TS_WASDEPLOYTOOL_HOME'] = homepath
        os.environ['TS_WASCONF_NAME'] = confname
        os.environ['TS_WASINS_NAME'] = insname
        os.system(cmd)

