#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package BASECollector;

use strict;
use File::Basename;
use Data::Dumper;

#参数：
#procInfo：进程的基本信息，就是ps输出的各种字段
#PID,PPID,PGID,USER,GROUP,RUSER,RGROUP,%CPU %MEM,TIME,ELAPSED,COMMAND,COMMAND
#ENVIRONMENT
#CONN_INFO
#matchedProcsInfo: 前面的处理过程中已经找到的matched的进程信息的HashMap，以进程的pid作为key
#                  当遇到多进程应用时需要通过其父进程或者group进程进行判断是否是主进程时需要用到
sub new {
    my ( $type, $procInfo, $matchedProcsInfo ) = @_;
    my $self = {};
    $self->{procInfo}         = $procInfo;
    $self->{matchedProcsInfo} = $matchedProcsInfo;

    bless( $self, $type );
    return $self;
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

                my $gatherClass = $procInfo->{CONN_GATHER_CLASS};
                my $connGather  = $gatherClass->new();
                my $connInfo    = $connGather->getConnInfo( $procInfo->{PID} );

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

    my $appInfo          = {};
    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};
    #TODO: 各个不同应用的信息采集逻辑
    return $appInfo;
}

1;
