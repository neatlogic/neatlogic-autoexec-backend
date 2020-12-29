#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import binascii
import socket
import platform
import locale
import re
import os
import sys
import time
import traceback
import subprocess
import json

try:
    import urllib2
except ImportError:
    import urllib.request as urllib2
import struct

PROTOCOL_VER = 'Tagent1.1'
SECURE_PROTOCOL_VER = 'Tagent1.1s'
PYTHON_VER = sys.version_info.major


def _rc4(key, data):
    x = 0
    box = list(range(256))
    for i in range(256):
        x = (x + box[i] + ord(key[i % len(key)])) % 256
        box[i], box[x] = box[x], box[i]
    x = y = 0
    out = bytearray()
    for by in data:
        x = (x + 1) % 256
        y = (y + box[x]) % 256
        box[x], box[y] = box[y], box[x]
        if PYTHON_VER == 2:
            out.append(ord(by) ^ box[(box[x] + box[y]) % 256])
        else:
            out.append(by ^ box[(box[x] + box[y]) % 256])
    return bytes(out)


def strEncodeToHex(data):
    hexStr = binascii.hexlify(data.encode('latin-1')).decode()
    return hexStr


def _rc4_encrypt_hex(key, data):
    if PYTHON_VER == 2:
        return binascii.hexlify(_rc4(key, data))
    elif PYTHON_VER == 3:
        return binascii.hexlify(_rc4(key, data)).decode("latin-1")


def _rc4_decrypt_hex(key, data):
    if PYTHON_VER == 2:
        return _rc4(key, binascii.unhexlify(data))
    elif PYTHON_VER == 3:
        return _rc4(key, binascii.unhexlify(data))


class AuthError(RuntimeError):

    def __init__(self, value):
        self.value = value

    def __str__(self):
        return repr(self.value)


class ExecError(RuntimeError):

    def __init__(self, value):
        self.value = value

    def __str__(self):
        return repr(self.value)


class TagentClient:

    def __init__(self, host='', port='', password='', readTimeout=0, writeTimeout=0, agentCharset=''):
        if host == '':
            host = '127.0.0.1'
        if port == '':
            port = 3939
        self.protocolVer = PROTOCOL_VER
        self.host = host
        self.port = int(port)
        self.password = password
        self.readTimeout = readTimeout
        self.writeTimeout = writeTimeout
        self.agentCharset = agentCharset
        self.encrypt = False
        uname = platform.uname()
        ostype = uname[0].lower()

        # 获取os类型名称，只区分windows和unix
        self.ostype = 'windows' if ostype == 'windows' else 'unix'
        charset = locale.getdefaultlocale()[1]
        self.charset = charset

    def __readChunk(self, sock, encrypt=None):
        """
        读取一个chunk，chunk开头是两个字节的unsigned short(big endian)，用于说明chunk的长度
        先读取chunk的长度，然后依据长度读取payload
        如果chunk的长度是0，则读取到连接关闭为止, chunk长度为0只会出现在最后一个chunk
        使用异常进行异常处理，譬如：连接被reset， 连接已经关闭，返回错误等
        """
        if encrypt is None:
            encrypt = self.encrypt

        readLen = 0
        readTimeout = self.readTimeout
        while readLen >= 2:
            if readTimeout > 0:
                sock.timeout(readTimeout)

        chunk = bytes()
        chunkHead = sock.recv(2)
        if chunkHead:
            chunkLen = struct.unpack('>H', chunkHead)
            if chunkLen:
                chunkLen = chunkLen[0]
            else:
                raise ExecError("Connection reset!")

            if chunkLen > 0:
                while readLen < chunkLen:
                    buf = sock.recv(chunkLen - readLen)
                    if buf:
                        chunk += buf
                        readLen = readLen + len(buf)
                    else:
                        print("Connection reset or closed!")
            else:
                while True:
                    buf = sock.recv(4096)
                    if not buf:
                        break
                    chunk += buf
                    if chunk:
                        if encrypt:
                            chunk = _rc4(self.password, chunk)
                        raise ExecError(chunk)
        else:
            raise ExecError("Connection reset!")

        if encrypt and chunk:
            chunk = _rc4(self.password, chunk)
        return chunk

    def __writeChunk(self, sock, chunk=b'', chunkLen=None, encrypt=None):
        if encrypt is None:
            encrypt = self.encrypt

        if encrypt and chunk:
            chunk = _rc4(self.password, chunk)

        if not chunkLen:
            chunkLen = len(chunk)
        else:
            chunkLen = 0

        if chunkLen > 65535:
            raise ExecError("chunk is too long, max is 65535 bytes!")
        try:
            sock.sendall(struct.pack('>H', chunkLen))
            sock.sendall(chunk)
            if chunkLen == 0:
                sock.shutdown(1)
        except socket.error as msg:
            print("Connection closed:{}".format(str(msg)))

    def getConnection(self, isVerbose=0):
        # 创建Agent连接，并完成验证, 返回TCP连接
        host = self.host
        port = self.port
        password = self.password

        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)  # 定义socket类型，TCP
        except AuthError:
            sock = None
        try:
            sock.connect((host, port))
        except AuthError:
            sock.close()
            sock = None
        if sock:
            ret = self.auth(sock, password, isVerbose)
            if ret != 1:
                print("ERROR: Authenticate failed while connect to {0}:{1}.".format(host, port))
                sys.exit(1)
        else:
            print("ERROR: Authenticate failed while connect to {0}:{1}.".format(host, port))
            sys.exit(1)
        return sock

    def auth(self, sock, authKey, isVerbose=0):
        host = self.host
        port = self.port
        try:
            # 读取agent服务端发来的"ostype|charset|challenge",
            # agent os类型|agent 字符集|加密的验证挑战token, '|'相隔
            challenge = self.__readChunk(sock, False).decode()
            agentOsType, agentCharset, challenge, protocolVer = challenge.split('|')
            if protocolVer == SECURE_PROTOCOL_VER:
                self.encrypt = True
            elif protocolVer != self.protocolVer:
                sock.shutdown(2)
                print("ERROR: server protocol version is {}, not match client protocol version {}.".format(
                    protocolVer, self.protocolVer))

            self.agentOsType = agentOsType
            self.agentCharset = agentCharset
            # 挑战解密后，是逗号相隔的两个整数，把乘积加密发回Agent服务端
            plainChlg = _rc4_decrypt_hex(str(authKey), challenge).decode('latin-1')
            if ',' not in plainChlg:
                return 0
            chlgArray = plainChlg.split(',')
            factor1 = chlgArray[0]
            factor2 = chlgArray[1]
            if str(factor1).isdigit() == False or str(factor2).isdigit() == False:
                return 0
            reverseChlg = str(int(factor1) * int(factor2)) + ',' + str(time.time())
            encryptChlg = _rc4_encrypt_hex(authKey, reverseChlg.encode("latin-1"))
            self.__writeChunk(sock, encryptChlg.encode(encoding="utf-8"))
            authResult = self.__readChunk(sock).decode()
            # 如果返回内容中不出现auth succeed，则验证失败
            if authResult != "auth succeed":
                if isVerbose == 1:
                    agentCharset = self.agentCharset
                    charset = self.charset
                    if charset != agentCharset:
                        print("ERROR:{}".format(authResult.decode(agentCharset).encode(charset)))
                return 0
            return 1
        except AuthError:
            print("ERROR: Authenticate failed while connect to {0}:{1}.".format(host, port))
            sys.exit(1)

    def updateCred(self, cred, isVerbose=0):
        # 更改密码
        cred = cred.strip()
        sock = self.getConnection()
        if sock:
            agentCharset = self.agentCharset
            charset = self.charset
            if agentCharset != charset:
                cred = cred.decode(charset).encode(agentCharset)
            try:
                self.__writeChunk(sock, "none|updatecred|{0}|{1}\r\n".format(agentCharset, cred).encode(agentCharset))
                status = 0
                statusLine = self.__readChunk(sock).decode()
                if statusLine:
                    status = -1
                    if isVerbose == 1:
                        print("ERROR: Change credential failed:{}.".format(statusLine))
                else:
                    status = 0
                    if isVerbose == 1:
                        print("INFO: Change credential succeed.")
            except BaseException:
                status = -1
                if isVerbose == 1:
                    traceback.print_exc()
            sock.close()
        else:
            status = -1
        return status

    def reload(self, isVerbose=0):
        sock = self.getConnection()
        agentCharset = self.agentCharset
        self.__writeChunk(sock, "none|reload|{}".format(agentCharset).encode(agentCharset))
        try:
            buf = self.__readChunk(sock).decode()
            if buf.startswith("Status:200"):
                status = 0
                if isVerbose == 1:
                    print("INFO: reload succeed.")
            else:
                status = -1
                if isVerbose == 1:
                    print("ERROR: reload failed.")
        except ExecError as msg:
            status = -1
            if isVerbose == 1:
                print(msg)
        sock.close()
        return status

    def echo(self, user, data, isVerbose=0):
        sock = self.getConnection()
        agentCharset = self.agentCharset
        self.__writeChunk(sock, "none|echo|{}|{}".format(agentCharset, strEncodeToHex(data)).encode(agentCharset))
        try:
            buf = self.__readChunk(sock).decode()
            print(buf)
        except ExecError as msg:
            if isVerbose == 1:
                print(msg)
        sock.close()

    # 执行远程命令

    def execCmd(self, user, cmd, isVerbose=0, env=None, eofStr='', callback=None, cbparams=()):
        cmd = cmd.strip()
        sock = self.getConnection(isVerbose)
        agentCharset = self.agentCharset
        charset = self.charset

        envJson = ''
        if env is not None:
            envJson = json.dumps(env)

        if agentCharset != charset:
            cmd = cmd.decode(charset).encode(agentCharset)
            user = user.decode(charset).encode(agentCharset)
            eofStr = eofStr.decode(charset).encode(agentCharset)
            envJson = envJson.decode(charset).encode(agentCharset)

        # 相比老版本，因为用了chunk协议，所以请求里的dataLen就不需要了
        self.__writeChunk(sock, "{}|execmd|{}|{}|{}|{}".format(user, agentCharset, strEncodeToHex(cmd), strEncodeToHex(eofStr), strEncodeToHex(envJson)).encode(agentCharset))
        status = 0
        try:
            while True:
                line = self.__readChunk(sock)
                if not line:
                    break
                if agentCharset != '':
                    line = line.decode(agentCharset)
                else:
                    line = line.decode()
                if isVerbose == 1:
                    print(line.strip())
                if callback:
                    callback(line, *cbparams)
        except ExecError as errMsg:
            status = -1
            errContent = errMsg.value.split('\n')
            for line in errContent:
                if str(line).isdigit():
                    status = int(line)
                elif isVerbose == 1:
                    print(line)
        sock.close()
        return status

    # 获取远程命令的所有输出
    def getCmdOut(self, user, cmd, isVerbose=0):
        content = []

        def callback(line, content):
            content.append(line)

        status = self.execCmd(user, cmd, isVerbose, callback, content)
        if status != 0:
            print(content)
        return content

    # 异步执行远程命令，不需要等待远程命令执行完
    def execCmdAsync(self, user, cmd, isVerbose=0, env=None):
        cmd = cmd.strip()
        sock = self.getConnection()
        agentCharset = self.agentCharset
        charset = self.charset

        envJson = ''
        if env is not None:
            envJson = json.dumps(env)

        if agentCharset != charset:
            cmd = cmd.decode(charset).encode(agentCharset)
            user = user.decode(charset).encode(agentCharset)
            envJson = envJson.decode(charset).encode(agentCharset)

        # 相比老版本，因为用了chunk协议，所以请求里的dataLen就不需要了
        #sock.sendall("{}|execmdasync|{}|{}\r\n".format(user, agentCharset, strEncodeToHex(cmd)))
        self.__writeChunk(sock, "{}|execmdasync|{}|{}|{}|{}".format(user, agentCharset, strEncodeToHex(cmd), '', strEncodeToHex(envJson)).encode(agentCharset))
        try:
            statusLine = self.__readChunk(sock).decode()
            if statusLine:
                status = -1
                if isVerbose == -1:
                    print("ERROR: " + statusLine)
            else:
                status = 0
                if isVerbose == 1:
                    print("INFO: Launch command asynchronized succeed.")
        except ExecError as errMsg:
            status = -1
            print("ERROR:" + errMsg)
        sock.close()
        return status

    # 把从连接中接收的文件下载数据写入文件，用于文件的下载
    def __writeSockToFile(self, sock, destFile, isVerbose=0):
        status = 0
        try:
            with open(destFile, 'wb') as f:
                while True:
                    chunk = self.__readChunk(sock)
                    if chunk:
                        f.write(chunk)
                    else:
                        break
        except ExecError:
            print("ERROR: Write to file {0} failed.".format(destFile))
            status = -1
        return status

    # 下载文件或者目录
    def download(self, user, src, dest, isVerbose=0, followLinks=0):
        src = src.replace('\\', '/')
        dest = dest.replace('\\', '/')
        sock = self.getConnection()
        param = src
        agentCharset = self.agentCharset
        charset = self.charset
        if agentCharset != charset:
            param = param.decode(charset).encode(agentCharset)
            user = user.decode(charset).encode(agentCharset)

        self.__writeChunk(sock, "{}|download|{}|{}|{}".format(user, agentCharset, strEncodeToHex(param), followLinks).encode(agentCharset))
        statusLine = self.__readChunk(sock).decode()
        status = 0
        fileType = 'file'

        tmp = re.findall(r"^Status:200,FileType:(\w+)", statusLine)
        if tmp and tmp[0]:
            # firstLine = "Status:200,FileType:{0}\r\n".format(tmp[0])
            status = 0
            fileType = tmp[0]
            if isVerbose == 1:
                print("INFO: Download {0} {1} to {2} begin...".format(fileType, src, dest))
        else:
            status = -1
            if isVerbose == 1:
                print("ERROR: " + statusLine)
                print("ERROR: Download {0} {1} to {2} failed.".format(fileType, src, dest))
                sock.close()
            return status

        if fileType == 'file':
            if os.path.isdir(dest):
                destFile = os.path.basename(src)
                dest = dest + "/" + destFile
            # first_part_res = re.search("^Status:200,FileType:(\w+)\r\n(.+)", buf, re.M | re.DOTALL)
            # if first_part_res:
            #     first_part = first_part_res.group(2)
            status = self.__writeSockToFile(sock, dest, isVerbose)

        else:
            if dest.endswith('/') or dest.endswith('\\'):
                dest = dest + os.path.basename(src)

            try:
                if fileType == 'dir' or fileType == 'windir':
                    destDir = os.path.dirname(dest)
                    if os.path.exists(destDir):
                        os.chdir(destDir)
                        try:
                            if self.ostype == 'windows':
                                p = subprocess.Popen(
                                    ["7z.exe", "x", "-aoa", "-y", "-si", "-ttar"],
                                    stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE)
                            else:
                                p = subprocess.Popen(["tar", "-xf-"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
                        except ExecError:
                            if isVerbose == 1:
                                print("ERROR: Launch tar command failed.")
                            status = -1
                            return status

                        try:
                            while True:
                                chunk = self.__readChunk(sock)
                                if not chunk:
                                    break
                                p.stdin.write(chunk)
                            cmd_out, cmd_err = p.communicate()
                            if isVerbose == 1:
                                if cmd_out:
                                    print(cmd_out)
                                if cmd_err:
                                    print(cmd_err)
                        except ExecError as errMsg:
                            status = -1
                            if isVerbose == 1:
                                print("ERROR: download failed, {}".format(errMsg))
                            return status
                        status = p.returncode
                    else:
                        if isVerbose == 1:
                            print("ERROR: directory {} not exist.".format(destDir))
                            status = -1
                else:
                    print("ERROR: FileType {0} not supported.".format(fileType))
                    status = -1
            except ExecError as errMsg:
                if isVerbose == 1:
                    print("ERROR: download failed, {}".format(errMsg))
                status = -1
            sock.close()
        if isVerbose == 1:
            if status == 0:
                print("INFO: Download succeed.")
            else:
                print("ERROR: Download failed.")
        return status

    # 用于读取tar或者7-zip的打包输出内容，并写入网络连接中
    def __readCmdOutToSock(self, sock, cmd, isVerbose=0):
        status = 0
        buf_size = 4096
        try:
            p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        except ExecError as errMsg:
            status = -1
            if isVerbose == 1:
                if isVerbose == 1:
                    print("ERROR: Can not launch command {}.".format(cmd))
            sock.shutdown(2)
            return status

        while True:
            try:
                buf = p.stdout.read(buf_size)
                if not buf:
                    break
                self.__writeChunk(sock, buf)
            except ExecError as errMsg:
                status = -1
                break

        p.communicate()
        exitStatus = p.returncode
        if exitStatus:
            status = -1
            print("ERROR: request ended with status:{}.".format(exitStatus))
        else:
            self.__writeChunk(sock)
        try:
            self.__readChunk(sock)
        except ExecError as errMsg:
            status = -1
            if isVerbose == 1:
                print(errMsg)
        return status

    # 读取文件内容，并写入网络连接中
    def __readFileToSock(self, sock, filePath, isVerbose=0, convertCharset=0):
        buf_size = 4096
        agentCharset = self.agentCharset
        charset = self.charset
        status = 0
        try:
            with open(filePath, "rb") as f:
                while True:
                    buf = f.read(buf_size)
                    if not buf:
                        break
                    if convertCharset == 1:
                        buf = buf.decode(charset).encode(agentCharset)
                    try:
                        self.__writeChunk(sock, buf)
                    except ExecError:
                        status = -1
                        break
            if status == 0:
                self.__writeChunk(sock)

            try:
                self.__readChunk(sock)
            except ExecError as errMsg:
                status = -1
                if isVerbose == 1:
                    print(errMsg)

        except ExecError:
            status = -1
            if isVerbose == 1:
                print("ERROR: Can not download file:{}".format(filePath))
            sock.shutdown(2)
        return status

    # 下载URL中的文件内容，写入网络连接中
    def __readUrlToSock(self, sock, url, isVerbose=0, convertCharset=1):
        buf_size = 4096
        agentCharset = self.agentCharset
        charset = ""
        status = 0
        file = urllib2.urlopen(url)

        if file.getcode() == 200:
            while True:
                buf = file.read(buf_size)
                if not buf:
                    break
                if convertCharset == 1:
                    contentType = file.headers.get('content-type')
                    if contentType:
                        tmp = re.findall(r"charset==(.*?)$", contentType)
                        if tmp and tmp[0]:
                            charset = tmp
                    if charset:
                        buf = buf.decode(charset).encode(agentCharset)
                # sock.sendall(buf)
                try:
                    self.__writeChunk(sock, buf)
                except ExecError:
                    status = -1
        else:
            status = 3
        if status == 0:
            self.__writeChunk(sock)
            try:
                self.__readChunk(sock)
            except ExecError as errMsg:
                status = -1
                if isVerbose == 1:
                    print(errMsg)
        elif status == 3:
            if isVerbose == 1:
                print("ERROR: Can not open file:{}.".format(url))
            sock.shutdown(2)
        else:
            sock.shutdown(2)
        return status

    def upload(self, user, src, dest, isVerbose=0, convertCharset=0, followLinks=1):
        src = src.replace('\\', '/')
        dest = dest.replace('\\', '/')
        ostype = self.ostype

        fileType = 'file'
        if os.path.isdir(src):
            fileType = 'windir' if ostype == 'windows' else 'dir'
        elif src.startswith("http://") or src.startswith("https://"):
            fileType = 'url'

        if fileType != 'url' and not os.path.exists(src):
            if isVerbose == 1:
                print("ERROR: {0} not exists.".format(src))
            return -1

        sock = self.getConnection()

        agentCharset = self.agentCharset
        charset = self.charset
        if agentCharset != charset:
            dest = dest.decode(charset).encode(agentCharset)
            user = user.decode(charset).encode(agentCharset)

        param = "{}|{}|{}|{}".format(strEncodeToHex(fileType), strEncodeToHex(src), strEncodeToHex(dest), str(followLinks))

        self.__writeChunk(sock, "{}|upload|{}|{}".format(user, agentCharset, param).encode(agentCharset))

        preStatus = self.__readChunk(sock).decode(agentCharset)
        if not preStatus.lstrip().startswith('Status:200'):
            sock.close()
            if isVerbose == 1:
                print("ERROR: Upload failed:{}.".format(preStatus))
            return -1
        if isVerbose == 1:
            print("INFO: Upload {} {} to {} begin...".format(fileType, src, dest))

        status = 0
        if fileType == 'file':
            status = self.__readFileToSock(sock, src, isVerbose, convertCharset)
        elif fileType == 'dir' or fileType == 'windir':
            srcDir = os.path.dirname(src)
            src = os.path.basename(src)
            os.chdir(srcDir)
            if ostype == 'windows':
                cmd = ["7z.exe", "a", "dummy", "-ttar", "-y", "-so", src]
            else:
                tarOpt = "cvf" if isVerbose == 1 else "cf"
                cmd = ["tar", "-{}-".format(tarOpt), src]
            status = self.__readCmdOutToSock(sock, cmd, isVerbose)
        elif fileType == 'url':
            status = self.__readUrlToSock(sock, src, isVerbose, convertCharset)

        if isVerbose == 1:
            if status == 0:
                print("INFO: Upload succeed.")
            else:
                print("ERROR: Upload failed.")
        sock.close()
        return status

    def writeFile(self, user, content, dest, isVerbose=0, convertCharset=0):
        dest = dest.replace('\\', '/')
        destName = os.path.basename(dest)
        destEncode = dest
        destNameEncode = dest

        sock = self.getConnection(isVerbose)

        agentCharset = self.agentCharset
        charset = self.charset
        if agentCharset != charset:
            if convertCharset == 1:
                content = content.decode(charset).encode(agentCharset)
            destNameEncode = destName.decode(charset).encode(agentCharset)
            destEncode = dest.decode(charset).encode(agentCharset)
            user = user.decode(charset).encode(agentCharset)

        param = "{}|{}|{}".format(strEncodeToHex('file'), strEncodeToHex(destNameEncode), strEncodeToHex(destEncode))
        self.__writeChunk(sock, "{}|upload|{}|{}".format(user, agentCharset, param).encode(agentCharset))

        preStatus = self.__readChunk(sock).decode()
        if not preStatus.lstrip().startswith("Status:200"):
            sock.close()
            if isVerbose == 1:
                print("ERROR: Upload failed:{}.".format(preStatus))
            return -1
        if isVerbose == 1:
            print("INFO: Write file {} begin...".format(dest))

        status = 0
        try:
            self.__writeChunk(sock, content.decode())
            self.__writeChunk(sock)
            self.__readChunk(sock)
        except ExecError as errMsg:
            status = -1
            print("ERROR: {}".format(errMsg.value))

        if isVerbose == 1:
            if status == 0:
                print("INFO: Write file succeed.")
            else:
                print("ERROR: Write file failed.")

        sock.close()
        return status
