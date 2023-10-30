# 安装本地工具需要的perl的第三方库
```shell
cd autoexec/plugins/local/media
./setup.sh
```

# 重新安装本地工具需要的perl的某些第三方库
- 以安装Config-Tiny-2.28和XML-Simple-2.22.tar为例
```shell
cd autoexec/plugins/local/media
./setupone.sh Net-SSLeay-1.92 Config-Tiny-2.28 XML-Simple-2.22
```
perl第三方库会安装到autoexec/plugins/local/pllib

# 使用工具cpan安装perl模块到系统
## 例如：
- 1) sudo cpan
- 2) force install Net::SSLeay
- 3) force install IO::Socket::SSL

# 使用cpnm批量下载perl模块（包括依赖）
## 例子，下载MogoDB的包和依赖，保存到/tmp/perl5目录下
```bash
cpanm --scandeps --save-dists  /tmp/perl5 -L local::lib MongoDB
#执行完成后，/tmp/perl5下会出现多个子目录，下面存放着所有的tar.gz就是主包和依赖包
```

# 使用cpan安装perl模块（包括依赖）
## 输入cpan命令，然后设置perl模块及其依赖安装的目录(命令：o conf )，然后install 模块
```shell
wenhaibodeMacBook-Pro:~ wenhb$ cpan
cpan shell -- CPAN exploration and modules installation (v2.34)
Enter 'h' for help.
nolock_cpan[1]> o conf makepl_arg
    makepl_arg         []
Type 'o conf' to view all configuration items


nolock_cpan[2]> o conf mbuildpl_arg
    mbuildpl_arg       []
Type 'o conf' to view all configuration items


nolock_cpan[3]> o conf makepl_arg 'INSTALL_BASE=/mydir/perl'                  
    makepl_arg         [INSTALL_BASE=/mydir/perl]
Please use 'o conf commit' to make the config permanent!


nolock_cpan[4]> o conf mbuildpl_arg '--install_base /mydir/perl'
    mbuildpl_arg       [--install_base /mydir/perl]
Please use 'o conf commit' to make the config permanent!


nolock_cpan[5]> o conf commit
commit: wrote '/Users/wenhb/.cpan/CPAN/MyConfig.pm'

nolock_cpan[6]> o conf makepl_arg
    makepl_arg         [INSTALL_BASE=/mydir/perl]
Type 'o conf' to view all configuration items


nolock_cpan[7]> o conf mbuildpl_arg
    mbuildpl_arg       [--install_base /mydir/perl]
Type 'o conf' to view all configuration items


nolock_cpan[8]> install NetSNMP
```

## 重置cpan的自定义安装目录
```shell
wenhaibodeMacBook-Pro:~ wenhb$ cpan
cpan shell -- CPAN exploration and modules installation (v2.34)
Enter 'h' for help.
nolock_cpan[1]> o conf makepl_arg
    makepl_arg         [INSTALL_BASE=/mydir/perl]
Type 'o conf' to view all configuration items


nolock_cpan[2]> o conf makepl_arg ''
    makepl_arg         []
Please use 'o conf commit' to make the config permanent!


nolock_cpan[3]> o conf mbuildpl_arg
    mbuildpl_arg       [--install_base /mydir/perl]
Type 'o conf' to view all configuration items


nolock_cpan[4]> o conf mbuildpl_arg ''
    mbuildpl_arg       []
Please use 'o conf commit' to make the config permanent!


nolock_cpan[5]> o conf commit
commit: wrote '/Users/wenhb/.cpan/CPAN/MyConfig.pm'

nolock_cpan[6]> exit

```
