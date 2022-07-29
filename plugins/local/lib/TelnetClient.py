#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import os
import telnetlib
import time
import traceback

class TelnetClient():

    def __init__(self, args ):
        self.telnet = telnetlib.Telnet()
        self.ip = args['ip'] 
        self.username = args['user']
        self.password = args['password']
        self.timeout = int(args['timeout'])
        self.port = int(args['port'])
        self.backupdir = args['backupdir']
        self.startLine = int(args['startLine'])
        self.verbose = int(args['verbose'])
        self.clsCmd = args['clsCmd']
        self.cfgCmd = args['cfgCmd']
        self.exitCmd = args['exitCmd']
        self.sleep = 2
        self.encode = 'utf-8'
        self.decode = 'utf-8'

    # 此函数实现telnet登录主机
    def login( self ):
        try:
            self.telnet.open( self.ip , self.port , self.timeout)
        except:
            if(self.telnet != None) :
                self.telnet.close()
            print('ERROR:: {} connect failed,reason:{}'.format(self.ip , traceback.print_exc()) )
            return False

        self.telnet.read_until(b'login: ',self.timeout )
        self.telnet.write(self.username.encode(self.encode) + b'\n')

        self.telnet.read_until(b'Password: ',self.timeout )
        self.telnet.write(self.password.encode(self.encode) + b'\n')

        time.sleep(self.sleep)
        # read_very_eager()获取到的是的是上次获取之后本次获取之前的所有输出
        result = self.telnet.read_very_eager().decode(self.decode)
        if 'Login incorrect' not in result:
            print('INFO:: %s login success .'%self.ip)
            return True
        else:
            print('ERROR:: %s login failed ，maybe wrong username or password.' %self.ip)
            if(self.telnet != None) :
                self.telnet.close()
            return False

    def configTerminal(self):
        command = self.clsCmd
        self.telnet.write(command.encode(self.encode)+b'\n')
        result = self.telnet.read_until(b'eof' ,self.timeout)
        result = result.decode(self.decode)
        if( self.verbose == 1) :
            print('INFO:: %s' % result)
            
    #执行命令
    def execCmd(self,command=None):
        if(command == None or command == ''):
            command = self.cfgCmd
        self.telnet.write(command.encode(self.encode)+b'\n')
        result = self.telnet.read_until(b'eof' ,self.timeout)
        result = result.decode(self.decode)
        output = ''
        content = result.split("\r\n")
        count = 0 
        for line in content :
            count = count + 1
            if ( (self.startLine > 0 and count <= self.startLine) or  count == len(content)) :
                continue 
            else:
               output = output + line + '\n' 

            if( self.verbose == 1) :
                print(line)
        return output
 
    # 退出telnet
    def logout( self ) :
        exitCmd = self.exitCmd
        self.telnet.write(exitCmd.encode(self.encode)+b'\n')
        if(self.telnet != None) :
            self.telnet.close()
