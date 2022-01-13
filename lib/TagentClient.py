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


def _rc4(key: str, data: bytes):
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


# def strEncodeToHex(data):
#    hexStr = binascii.hexlify(data.encode('latin-1', 'replace')).decode()
#    return hexStr


def bytesEncodeToHex(data: bytes):
    hexStr = binascii.hexlify(data).decode()
    return hexStr


def _rc4_encrypt_hex(key: str, data: bytes):
    if PYTHON_VER == 2:
        return binascii.hexlify(_rc4(key, data))
    elif PYTHON_VER == 3:
        return binascii.hexlify(_rc4(key, data)).decode("latin-1")


def _rc4_decrypt_hex(key: str, data: str):
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


class AgentError(RuntimeError):

    def __init__(self, value):
        self.value = value

    def __str__(self):
        return repr(self.value)


class TagentClient:

    def __init__(self, host='', port='', password='', readTimeout=0, writeTimeout=0, agentCharset='UTF-8'):
        if host == '':
            host = '127.0.0.1'
        if port == '':
            port = 3939
        self.protocolVer = PROTOCOL_VER
        self.host = host
        self.port = int(port)
        self.sock = None
        self.password = password
        self.agentCharset = agentCharset
        self.encrypt = False

        if readTimeout == 0:
            readTimeout = 15
        if writeTimeout == 0:
            writeTimeout = 15

        self.readTimeout = readTimeout
        self.writeTimeout = writeTimeout

        uname = platform.uname()
        ostype = uname[0].lower()

        # 获取os类型名称，只区分windows和unix
        self.ostype = 'windows' if ostype == 'windows' else 'unix'
        charset = locale.getdefaultlocale()[1]
        self.charset = charset

    def close(self):
        if self.sock:
            try:
                self.sock.shutdown(2)
            except:
                pass

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

        chunk = bytes()
        chunkHead = sock.recv(2)

        while chunkHead and len(chunkHead) < 2:
            h = sock.recv(2-len(chunkHead))
            chunkHead = chunkHead + h

        if chunkHead:
            chunkLen = struct.unpack('>H', chunkHead)
            if chunkLen:
                chunkLen = chunkLen[0]
            else:
                raise ExecError("Connection({}:{}) reset!".format(self.host, self.port))

            if chunkLen > 0:
                while readLen < chunkLen:
                    buf = sock.recv(chunkLen - readLen)
                    if buf:
                        chunk += buf
                        readLen = readLen + len(buf)
                    else:
                        raise ExecError("Connection({}:{}) reset or closed!".format(self.host, self.port))
            else:
                while True:
                    buf = sock.recv(4096)
                    if not buf:
                        break
                    chunk += buf
                    if chunk:
                        if encrypt:
                            chunk = _rc4(self.password, chunk)
                        raise ExecError(chunk.decode(self.agentCharset, 'ignore'))
        else:
            raise ExecError("Connection({}:{}) reset!".format(self.host, self.port))

        if encrypt and chunk:
            chunk = _rc4(self.password, chunk)
        return chunk

    def __writeChunk(self, sock, chunk: bytes = None, chunkLen=None, encrypt=None):
        if encrypt is None:
            encrypt = self.encrypt

        if encrypt and chunk:
            chunk = _rc4(self.password, chunk)

        if not chunkLen:
            if chunk:
                chunkLen = len(chunk)
            else:
                chunkLen = 0
        else:
            chunkLen = 0

        if chunkLen > 65535:
            raise ExecError("Chunk is too long, max is 65535 bytes!")
        try:
            sock.sendall(struct.pack('>H', chunkLen))
            if chunk:
                sock.sendall(chunk)
            if chunkLen == 0:
                sock.shutdown(1)
        except socket.error as msg:
            raise ExecError("Connection({}:{}) closed:{}".format(self.host, self.port, str(msg)))

    def getConnection(self, isVerbose=0):
        # 创建Agent连接，并完成验证, 返回TCP连接
        host = self.host
        port = self.port
        password = self.password

        isAuth = 0
        sock = None
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)  # 定义socket类型，TCP
            sock.settimeout(self.readTimeout)
            sock.connect((host, port))
        except Exception as err:
            raise AgentError("ERROR: Connect to {}:{} failed, {}.".format(host, port, err))

        try:
            isAuth = self.auth(sock, password, isVerbose)
            if isAuth == 0:
                sock.shutdown(2)
                sock = None
                raise AuthError("ERROR: Authenticate failed while connect to {0}:{1}, check the credential.".format(host, port))
            else:
                self.sock = sock
        except BaseException as ex:
            if sock:
                sock.shutdown(2)
                sock = None
            raise

        return sock

    def auth(self, sock, authKey, isVerbose=0):
        host = self.host
        port = self.port

        # 读取agent服务端发来的"ostype|charset|challenge",
        # agent os类型|agent 字符集|加密的验证挑战token, '|'相隔
        challenge = self.__readChunk(sock, False).decode()
        agentOsType, agentCharset, challenge, protocolVer = challenge.split('|')
        if protocolVer == SECURE_PROTOCOL_VER:
            self.encrypt = True
        elif protocolVer != self.protocolVer:
            sock.shutdown(2)
            raise AuthError("ERROR: Server({}:{}) protocol version is {}, not match client protocol version {}.".format(
                host, port, protocolVer, self.protocolVer))

        self.agentOsType = agentOsType
        if agentCharset:
            self.agentCharset = agentCharset

        # 挑战解密后，是逗号相隔的两个整数，把乘积加密发回Agent服务端
        plainChlg = _rc4_decrypt_hex(str(authKey), challenge).decode('latin-1')
        if ',' not in plainChlg:
            return 0
        chlgArray = plainChlg.split(',')
        factor1 = chlgArray[0]
        factor2 = chlgArray[1]
        serverTime = None
        if len(chlgArray) > 2:
            serverTime = chlgArray[2]
        if serverTime is None or serverTime == '0':
            serverTime = str(time.time())

        if str(factor1).isdigit() == False or str(factor2).isdigit() == False:
            return 0
        reverseChlg = str(int(factor1) * int(factor2)) + ',' + serverTime
        encryptChlg = _rc4_encrypt_hex(authKey, reverseChlg.encode('latin-1', 'replace'))
        self.__writeChunk(sock, encryptChlg.encode(encoding='utf-8'))
        authResult = self.__readChunk(sock).decode()
        # 如果返回内容中不出现auth succeed，则验证失败
        if authResult != "auth succeed":
            return 0
        return 1

    def updateCred(self, cred, isVerbose=0):
        # 更改密码
        cred = cred.strip()
        sock = self.getConnection()
        if sock:
            agentCharset = self.agentCharset

            try:
                self.__writeChunk(sock, "none|updatecred|{}|{}".format(agentCharset, bytesEncodeToHex(cred.encode())))
                status = 0
                statusLine = self.__readChunk(sock).decode()
                if statusLine:
                    status = -1
                    if isVerbose == 1:
                        print("ERROR: Change credential failed:{}.".format(statusLine))
                    raise AgentError("ERROR: Change credential failed:{}.".format(statusLine))
                else:
                    status = 0
                    if isVerbose == 1:
                        print("INFO: Change credential succeed.")
            except BaseException:
                status = -1
                if isVerbose == 1:
                    traceback.print_exc()
                raise
            finally:
                try:
                    if sock:
                        sock.shutdown(2)
                except:
                    pass
        else:
            status = -1
        return status

    def reload(self, isVerbose=0):
        sock = self.getConnection()
        agentCharset = self.agentCharset
        self.__writeChunk(sock, "none|reload|{}".format(agentCharset).encode(agentCharset, 'replace'))
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
                raise AgentError("ERROR: reload failed.")
        except BaseException:
            raise
        finally:
            try:
                if sock:
                    sock.shutdown(2)
            except:
                pass
        return status

    def echo(self, user, data, isVerbose=0):
        sock = self.getConnection()
        agentCharset = self.agentCharset
        self.__writeChunk(sock, "none|echo|{}|{}".format(agentCharset, bytesEncodeToHex(data.encode())).encode(agentCharset, 'replace'))
        try:
            buf = self.__readChunk(sock).decode()
            print(buf)
        except ExecError as msg:
            if isVerbose == 1:
                print(msg)
            raise
        finally:
            try:
                if sock:
                    sock.shutdown(2)
            except:
                pass

    # 执行远程命令

    def execCmd(self, user, cmd, isVerbose=0, env=None, eofStr='', callback=None, cbparams=()):
        cmd = cmd.strip()
        sock = self.getConnection(isVerbose)
        agentCharset = self.agentCharset

        envJson = ''
        if env is not None:
            envJson = json.dumps(env)

        # 相比老版本，因为用了chunk协议，所以请求里的dataLen就不需要了
        self.__writeChunk(sock, "{}|execmd|{}|{}|{}|{}".format(user, agentCharset, bytesEncodeToHex(cmd.encode(agentCharset, 'replace')), bytesEncodeToHex(eofStr.encode(agentCharset, 'replace')), bytesEncodeToHex(envJson.encode(agentCharset, 'replace'))).encode(agentCharset, 'replace'))
        status = 0
        try:
            while True:
                line = self.__readChunk(sock)
                if not line:
                    break
                if agentCharset != '':
                    line = line.decode(agentCharset, 'ignore')
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
                else:
                    if isVerbose == 1:
                        print(line.strip())
                    if callback:
                        callback(line, *cbparams)
        finally:
            try:
                if sock:
                    sock.shutdown(2)
            except:
                pass

        return status

    # 获取远程命令的所有输出
    def getCmdOut(self, user, cmd, isVerbose=0):
        content = []

        def callback(line, content):
            content.append(line)

        status = self.execCmd(user, cmd, isVerbose, callback, content)
        if status != 0:
            if isVerbose == 1:
                print(content)
            raise AgentError("\n".join(content))
        return content

    # 异步执行远程命令，不需要等待远程命令执行完
    def execCmdAsync(self, user, cmd, isVerbose=0, env=None):
        cmd = cmd.strip()
        sock = self.getConnection()
        agentCharset = self.agentCharset

        envJson = ''
        if env is not None:
            envJson = json.dumps(env)

        # 相比老版本，因为用了chunk协议，所以请求里的dataLen就不需要了
        #sock.sendall("{}|execmdasync|{}|{}\r\n".format(user, agentCharset, bytesEncodeToHex(cmd.encode(agentCharset, 'replace'))))
        self.__writeChunk(sock, "{}|execmdasync|{}|{}|{}|{}".format(user, agentCharset, bytesEncodeToHex(cmd.encode(agentCharset, 'replace')), '', bytesEncodeToHex(envJson.encode(agentCharset, 'replace'))).encode(agentCharset, 'replace'))
        try:
            statusLine = self.__readChunk(sock).decode()
            if statusLine:
                status = -1
                if isVerbose == 1:
                    print("ERROR: " + statusLine)
            else:
                status = 0
                if isVerbose == 1:
                    print("INFO: Launch command asynchronized succeed.")
        except ExecError as errMsg:
            status = -1
            if isVerbose == 1:
                print("ERROR:" + errMsg)
        finally:
            try:
                sock.shutdown(2)
            except:
                pass
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
        except BaseException as errMsg:
            raise AgentError("ERROR: Write to file {} failed, {}.".format(destFile, errMsg))
        return status

    # 下载文件或者目录
    def download(self, user, src, dest, isVerbose=0, followLinks=0):
        src = src.replace('\\', '/')
        dest = dest.replace('\\', '/')
        sock = self.getConnection()
        param = src
        agentCharset = self.agentCharset

        try:
            self.__writeChunk(sock, "{}|download|{}|{}|{}".format(user, agentCharset, bytesEncodeToHex(param.encode(agentCharset, 'replace')), followLinks).encode(agentCharset, 'replace'))
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
                raise AgentError("ERROR: Download {} {} to {} failed, {}".format(fileType, src, dest, statusLine))

            if fileType == 'file':
                if os.path.isdir(dest):
                    destFile = os.path.basename(src)
                    dest = dest + "/" + destFile
                # first_part_res = re.search("^Status:200,FileType:(\w+)\r\n(.+)", buf, re.M | re.DOTALL)
                # if first_part_res:
                #     first_part = first_part_res.group(2)
                status = self.__writeSockToFile(sock, dest, isVerbose)

            else:
                if fileType == 'dir' or fileType == 'windir':
                    if not os.path.exists(dest):
                        raise AgentError("ERROR: Download failed, directory {} not exist.".format(dest))

                    if dest.endswith('/') or dest.endswith('\\'):
                        dest = dest + os.path.basename(src)
                        if (not os.path.exists(dest)):
                            os.mkdir(dest)

                    # os.chdir(destDir) #多线程环境不可以这样用
                    try:
                        if self.ostype == 'windows':
                            p = subprocess.Popen(
                                ["7z.exe", "x", "-aoa", "-y", "-si", "-ttar"],
                                cwd=dest,
                                stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE)
                        else:
                            tarOpt = "-xf"
                            if isVerbose == 1:
                                tarOpt = "-xvf"
                            p = subprocess.Popen(["tar", tarOpt, "-"], cwd=dest, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
                    except Exception as ex:
                        raise AgentError("ERROR: Launch tar command failed, {}.".format(ex))

                    errOut = ''
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
                    if cmd_err:
                        errOut = errOut + "\n" + cmd_err

                    status = p.returncode
                    if status != 0:
                        raise AgentError("ERROR: Download {} to {} failed, {}".format(src, dest, errOut))
                else:
                    raise AgentError("ERROR: Download failed, file type {0} not supported.".format(fileType))
            if isVerbose == 1:
                if status == 0:
                    print("INFO: Download succeed.")
                else:
                    print("ERROR: Download failed.")
            return status
        except AgentError:
            raise
        finally:
            try:
                if sock:
                    sock.shutdown(2)
            except:
                pass

    # 用于读取tar或者7-zip的打包输出内容，并写入网络连接中
    def __readCmdOutToSock(self, sock, cmd, isVerbose=0, cwd=None):
        status = 0
        buf_size = 4096 * 8
        try:
            if cwd is None:
                p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
            else:
                p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, cwd=cwd)
        except BaseException as errMsg:
            raise AgentError("ERROR: Can not launch command {}, {}.".format(cmd, errMsg))

        while True:
            buf = p.stdout.read(buf_size)
            if not buf:
                break
            self.__writeChunk(sock, buf)

        p.communicate()
        exitStatus = p.returncode
        if exitStatus:
            raise AgentError("ERROR: Command:{} ended with status:{}.".format(cmd, exitStatus))
        else:
            self.__writeChunk(sock)
        self.__readChunk(sock)

        return status

    # 读取文件内容，并写入网络连接中
    def __readFileToSock(self, sock, filePath, isVerbose=0, convertCharset=0):
        buf_size = 4096 * 8
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
                        buf = buf.decode(charset).encode(agentCharset, 'replace')
                    self.__writeChunk(sock, buf)

            if status == 0:
                self.__writeChunk(sock)
            self.__readChunk(sock)
        except BaseException as errMsg:
            raise AgentError("ERROR: Download file {} failed, {}.".format(filePath, errMsg))
        return status

    # 下载URL中的文件内容，写入网络连接中
    def __readUrlToSock(self, sock, url, isVerbose=0, convertCharset=1):
        buf_size = 4096 * 8
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
                        buf = buf.decode(charset).encode(agentCharset, 'replace')
                self.__writeChunk(sock, buf)
        else:
            status = 3

        if status == 0:
            self.__writeChunk(sock)
            self.__readChunk(sock)
        elif status == 3:
            raise AgentError("ERROR: Can not open file:{}.".format(url))

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
            raise AgentError("ERROR: {0} not exists.".format(src))

        sock = self.getConnection()

        try:
            agentCharset = self.agentCharset
            param = "{}|{}|{}|{}".format(bytesEncodeToHex(fileType.encode(agentCharset, 'replace')), bytesEncodeToHex(src.encode(agentCharset, 'replace')), bytesEncodeToHex(dest.encode(agentCharset, 'replace')), followLinks)

            self.__writeChunk(sock, "{}|upload|{}|{}".format(user, agentCharset, param).encode(agentCharset, 'replace'))

            preStatus = self.__readChunk(sock).decode(agentCharset)
            if not preStatus.lstrip().startswith('Status:200'):
                raise AgentError("ERROR: Upload failed:{}.".format(preStatus))

            if isVerbose == 1:
                print("INFO: Upload {} {} to {} begin...".format(fileType, src, dest))

            status = 0
            if fileType == 'file':
                status = self.__readFileToSock(sock, src, isVerbose, convertCharset)
            elif fileType == 'dir' or fileType == 'windir':
                srcDir = os.path.dirname(src)
                src = os.path.basename(src)
                # os.chdir(srcDir) #多线程环境不可以这样用
                if ostype == 'windows':
                    cmd = ["7z.exe", "a", "dummy", "-ttar", "-y", "-so", src]
                else:
                    tarOpt = ''
                    if isVerbose == 1:
                        tarOpt = "v"
                    if followLinks == 1:
                        tarOpt = tarOpt + 'h'
                    tarOpt = 'c' + tarOpt + 'f'

                    cmd = ["tar", "-{}".format(tarOpt), '-', src]
                status = self.__readCmdOutToSock(sock, cmd, isVerbose=isVerbose, cwd=srcDir)
            elif fileType == 'url':
                status = self.__readUrlToSock(sock, src, isVerbose, convertCharset)

            if isVerbose == 1:
                if status == 0:
                    print("INFO: Upload succeed.")
                else:
                    print("ERROR: Upload failed.")
        finally:
            try:
                if sock:
                    sock.shutdown(2)
            except:
                pass

        return status

    def writeFile(self, user, content: bytes, dest, isVerbose=0, convertCharset=0):
        dest = dest.replace('\\', '/')
        destName = os.path.basename(dest)

        sock = self.getConnection(isVerbose)

        status = 0
        try:
            agentCharset = self.agentCharset
            charset = self.charset
            if agentCharset != charset:
                if convertCharset == 1:
                    content = content.decode(charset).encode(agentCharset, 'replace')

            param = "{}|{}|{}|{}".format(bytesEncodeToHex(b'file'), bytesEncodeToHex(destName.encode(agentCharset, 'replace')), bytesEncodeToHex(dest.encode(agentCharset, 'replace')), '00')
            self.__writeChunk(sock, "{}|upload|{}|{}".format(user, agentCharset, param).encode(agentCharset, 'replace'))

            preStatus = self.__readChunk(sock).decode()
            if not preStatus.lstrip().startswith("Status:200"):
                raise AgentError("ERROR: Upload failed:{}.".format(preStatus))
            if isVerbose == 1:
                print("INFO: Write file {} begin...".format(dest))

            if (len(content) > 0):
                self.__writeChunk(sock, content)

            self.__writeChunk(sock)
            self.__readChunk(sock)

            if isVerbose == 1:
                print("INFO: Write file {} success".format(dest))
        finally:
            try:
                if sock:
                    sock.shutdown(2)
            except:
                pass

        return status
