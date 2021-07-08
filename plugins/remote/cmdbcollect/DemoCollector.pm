#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package DemoCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps  => ['\bjava\s'],              #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },        #ps的属性的精确匹配
        envAttrs => { TS_INSNAME => undef }    #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

#可用参数：
#$self->{procInfo}， 根据config命中的进程信息
#$self->{matchedProcsInfo}，之前已经matched的进程信息
#Return：应用信息的Hash，undef:不匹配
#采集器实现需要重载这个类
#Return：如果判断当前进程不是想要的进程，返回undef，否则返回应用信息的HashMap
# {
#           'SERVER_ROOT' => '/etc/httpd',
#           'INSTALL_PATH' => '/etc/httpd',
#           'BIN_PATH' => '/usr/sbin/',
#           'DEFAULT_PIDLOG' => '/run/httpd/httpd.pid',
#           'CONF_PATH' => '/etc/httpd/conf',
#           'AP_TYPES_CONFIG_FILE' => 'conf/mime.types',
#           'PORT' => '80',
#           'ERRORLOG' => 'logs/error_log',
#           'PROC_INFO' => {
#                            '%MEM' => '0.0',
#                            'RSS' => '5196',
#                            'MANAGE_PORT' => '',
#                            'TRS' => '485',
#                            'TTY' => '?',
#                            'RUSER' => 'root',
#                            'RGROUP' => 'root',
#                            'STAT' => 'Ss',
#                            'COMMAND' => '/usr/sbin/httpd -DFOREGROUND',
#                            'DRS' => '225830',
#                            'OS_TYPE' => 'Linux',
#                            'PGID' => '17228',
#                            'USER' => 'root',
#                            'PID' => '17228',
#                            'GROUP' => 'root',
#                            'CONN_INFO' => {
#                                             'PEER' => [],
#                                             'LISTEN' => [
#                                                           '80'
#                                                         ]
#                                           },
#                            'TIME' => '00:00:00',
#                            'PPID' => '1',
#                            '%CPU' => '0.0',
#                            'ELAPSED' => '02:12:33',
#                            'HOST_NAME' => 'centos7base',
#                            'MANAGE_IP' => '',
#                            'APP_TYPE' => 'Apache',
#                            'ENVRIONMENT' => {
#                                               'NOTIFY_SOCKET' => '/run/systemd/notify',
#                                               'LANG' => 'C',
#                                               'PATH' => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin'
#                                             },
#                            'COMM' => 'httpd',
#                            'MAJFL' => '0'
#                          },
#           'SERVER_MPM' => 'prefork',
#           'PORTS' => [
#                        '80'
#                      ],
#           'DEFAULT_ERRORLOG' => 'logs/error_log',
#           'HTTPD_ROOT' => '/etc/httpd',
#           'APP_TYPE' => 'Apache',
#           'DOCUMENT_ROOT' => '/var/www/html',
#           'VERSION' => 'Apache/2.4.6 (CentOS)',
#           'SERVER_CONFIG_FILE' => 'conf/httpd.conf'
#         }
#上面的数据以httpd为例
#其中PROC_INFO对应的就是collect使用的进程信息HashMap，里面的属性都可以使用
sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};

    #TODO：读取命令行输出或者读取配置文件，写入数据到hash map $appInfo

    #默认的APP_TYPE是类名去掉Collector，如果要特殊的名称则自行设置
    #$appInfo->{APP_TYPE} = 'DemoApp';

    #！！！下面的是标准属性，必须采集并转换提供出来
    #服务名, 要根据实际来设置
    $appInfo->{SERVER_NAME} = $procInfo->{APP_TYPE};
    $appInfo->{INSTALL_PATH}   = undef;
    $appInfo->{CONFIG_PATH}    = undef;
    $appInfo->{PORT}           = undef;
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_PORT}     = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = undef;

    return $appInfo;
}

1;
