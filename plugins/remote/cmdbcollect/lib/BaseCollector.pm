#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package BaseCollector;

use strict;
use File::Basename;
use ConnGather;
use CollectObjType;
use CollectUtils;
use Data::Dumper;

#参数：
#procInfo：进程的基本信息，就是ps输出的各种字段
#PID,PPID,PGID,USER,GROUP,RUSER,RGROUP,%CPU %MEM,TIME,ELAPSED,COMMAND,COMMAND
#ENVIRONMENT
#CONN_INFO
#matchedProcsInfo: 前面的处理过程中已经找到的matched的进程信息的HashMap，以进程的pid作为key
#                  当遇到多进程应用时需要通过其父进程或者group进程进行判断是否是主进程时需要用到
sub new {
    my ( $type, $passArgs, $procInfo, $matchedProcsInfo ) = @_;
    my $self = {};
    my $appType = substr( $type, 0, -9 );
    $self->{procInfo}         = $procInfo;
    $self->{matchedProcsInfo} = $matchedProcsInfo;
    $self->{defaultAppType}   = $appType;
    $self->{collectUtils}     = CollectUtils->new();

    if ( defined($passArgs) ) {
        my $myDef = $passArgs->{$appType};
        if ( defined($myDef) ) {
            $self->{defaultUsername} = $myDef->{username};
            $self->{defaultPassword} = $myDef->{password};
        }
    }

    bless( $self, $type );
    return $self;
}

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {};
}

#采集数据对象的Primary Key设置，只需要在返回多种类型对象的收集器里定义
#注意：！！如果是返回单类型对象的采集器不需要定义此函数，可以删除此函数
sub getPK {
    my ($self) = @_;
    return {
        #默认KEY用类名去掉Collector，对应APP_TYPE属性值
        #配置值就是作为PK的属性名
        $self->{defaultAppType} => [ 'MGMT_IP', 'PORT' ]

            #如果返回的是多种对象，需要手写APP_TYPE对应的PK配置
    };
}

#su运行命令，并返回输出的文本
sub getCmdOut {
    my ( $self, $cmd, $user ) = @_;
    my $utils = $self->{collectUtils};
    return $utils->getCmdOut( $cmd, $user );
}

#su运行命令，并返回输出的行数组
sub getCmdOutLines {
    my ( $self, $cmd, $user ) = @_;
    my $utils = $self->{collectUtils};
    return $utils->getCmdOutLines( $cmd, $user );
}

sub getFileContent {
    my ( $self, $filePath ) = @_;
    my $utils = $self->{collectUtils};
    return $utils->getFileContent($filePath);
}

#读取文件所有行
sub getFileLines {
    my ( $self, $filePath ) = @_;
    my $utils = $self->{collectUtils};
    return $utils->getFileLines($filePath);
}

#判断当前进程是否是主进程，如果存在命令行一样的父进程或者Group主进程，则当前进程就不是主进程
#如果有特殊的实现，需要重写此方法
#Return：1:主进程，0:不是主进程
sub isMainProcess {
    my ($self) = @_;

    my $isMainProcess = 1;

    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $ppid = $procInfo->{PPID};
    my $pgid = $procInfo->{PGID};

    #如果父进程或者GroupId（事实上就是进程组的第一个父亲进程）也是httpd，那么当前进程就不是主进程
    for my $parentProcInfo ( $matchedProcsInfo->{$ppid}, $matchedProcsInfo->{$pgid} ) {
        if ( defined($parentProcInfo) ) {
            if ( $parentProcInfo->{COMMAND} eq $procInfo->{COMMAND} ) {
                $isMainProcess = 0;

                my $connGather = ConnGather->new();
                my $connInfo   = $connGather->getConnInfo( $procInfo->{PID} );

                my $parentLsnInfo = $parentProcInfo->{CONN_INFO}->{LISTEN};
                map { $parentLsnInfo->{$_} = 1 } keys( %{ $connInfo->{LISTEN} } );

                my $parentPeerInfo = $parentProcInfo->{CONN_INFO}->{PEER};
                map { $parentPeerInfo->{$_} = 1 } keys( %{ $connInfo->{PEER} } );

                last;
            }
        }
    }

    return $isMainProcess;
}

sub getPortFromProcInfo {
    my ($self) = @_;

    my $listenAddrs = $self->{procInfo}->{CONN_INFO}->{LISTEN};
    my $refType     = ref($listenAddrs);
    my @lsnAddrs;
    if ( $refType eq 'HASH' ) {
        @lsnAddrs = keys(%$listenAddrs);
    }
    elsif ( $refType eq 'ARRAY' ) {
        @lsnAddrs = @$listenAddrs;
    }

    my $port;

    if ( scalar(@lsnAddrs) > 1 ) {
        foreach my $lsnAddr (@lsnAddrs) {
            if ( $lsnAddr =~ /^\d+$/ ) {
                $port = $lsnAddr;
                last;
            }
        }

        if ( not defined($port) ) {
            $port = $$listenAddrs[0];
            if ( $port =~ /^(.*?):(\d+)$/ ) {
                $port = $2;
            }
        }
    }

    return $port;
}

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
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $appInfo          = {};
    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    #TODO: 各个不同应用的信息采集逻辑
    return $appInfo;
}

1;
