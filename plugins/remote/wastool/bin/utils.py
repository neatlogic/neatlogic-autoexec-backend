#!/usr/bin/python
import httplib
import os
import time
import string


def checkUtilUrlAvaliable(checkurl):
    if checkurl is not None and checkurl != '':
        waitCount = 60

        start = checkurl.find('//') + 2
        end = checkurl.find('/', start)
        addr = checkurl[start:end]
        context = checkurl[end:]

        code = 500

        while 1:
            try:
                print("INFO: App start checking URL:%s, status code %d, waiting to start....\n" % (checkurl, code))
                if (waitCount <= 0):
                    break

                waitCount = waitCount - 1

                http = httplib.HTTP(addr)
                http.putrequest('GET', context)
                http.endheaders()
                code, msg, headers = http.getreply()

                if (code == 200 or code == 302):
                    print("INFO: App start checking status code %d, app started.\n" % code)
                    break
                time.sleep(5)
            except:
                time.sleep(5)
                pass

        if (waitCount > 0):
            print("INFO: App started.")
        else:
            print("WARN: App url check failed.")


def copyDeployDesc(appname, appfilePath, targetdir, desctarget):
    import os.path
    import shutil
    import glob

    descRoot = os.path.dirname(os.path.dirname(desctarget))

    dmgrtargetFile = '%s/%s.ear' % (descRoot, appname)
    if os.path.exists(dmgrtargetFile):
        pkgRoot = os.path.dirname(appfilePath)
        appfile = os.path.basename(appfilePath)

        (mode, ino, dev, nlink, uid, gid, size, atime, mtime, ctime) = os.stat(dmgrtargetFile)

        if appfilePath.endswith('.war'):
            cmd = 'cp -p %s.ear %s' % (appname, dmgrtargetFile)
        elif appfilePath.endswith('.ear'):
            cmd = 'cp -p %s %s' % (appfile, dmgrtargetFile)

        print('INFO: %s\n' % cmd)
        curdir = os.getcwd()
        os.chdir(pkgRoot)

        if appfilePath.endswith('.war'):
            os.system('cp %s %s/ && zip -qo %s.ear %s' % (dmgrtargetFile, pkgRoot, appname, appfile))

        if os.path.exists(appname):
            os.utime(appname, (atime, mtime))
        if os.path.exists('%s.ear' % appname):
            os.utime('%s.ear' % appname, (atime, mtime))

        ret = os.system(cmd)
        if (ret != 0):
            print("ERROR: Update dmgr app file for %s failed.\n" % appname)

        os.utime(dmgrtargetFile, (atime, mtime))
        os.chdir(curdir)

    curdir = os.getcwd()
    os.chdir(targetdir)
    descfiles = glob.glob('META-INF/*.*') + glob.glob('*.war/WEB-INF/web.xml') + glob.glob('*.war/META-INF/*.*') + glob.glob('*.jar/META-INF/*.*')

    for descfile in descfiles:
        descdest = '%s/%s' % (desctarget, descfile)
        descfile = '%s/%s' % (targetdir, descfile)
        if os.path.isfile(descfile):
            descdir = os.path.dirname(descdest)
            if not os.path.isdir(descdir):
                os.makedirs(descdir, exist_ok=True)
            if os.path.exists(descfile):
                shutil.copyfile(descfile, descdest)
                print('INFO: Update descriptor file:%s to %s\n' % (descfile, descdest))

    os.chdir(curdir)
