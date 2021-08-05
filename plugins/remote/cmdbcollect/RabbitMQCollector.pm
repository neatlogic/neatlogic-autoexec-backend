#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package RabbitMQCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use XML::MyXML qw(xml_to_object);
use CollectObjType;

sub getConfig {
    return {
        regExps => ['\brabbitmq\b']    #正则表达是匹配ps输出
                                       #psAttrs  => {},                  #ps的属性的精确匹配
                                       #envAttrs => {}                   #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

sub getPK {
    my ($self) = @_;
    return {
        #默认KEY用类名去掉Collector，对应APP_TYPE属性值
        #配置值就是作为PK的属性名
        $self->{defaultAppType} => [ 'MGMT_IP', 'PORT' ]

            #如果返回的是多种对象，需要手写APP_TYPE对应的PK配置
    };
}

sub collect {
    my ($self) = @_;
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo  = $self->{procInfo};
    my $envMap    = $procInfo->{ENVRIONMENT};
    my $listenMap = $procInfo->{CONN_INFO}->{LISTEN};

    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{OBJECT_TYPE} = $CollectObjType::APP;

    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};

    my $workPath = readlink("/proc/$pid/cwd");
    my $homePath;
    if ( $cmdLine =~ /-pa\s(\S+)/ ) {
        $homePath = $1;
        if ( $homePath =~ /^\.{1,2}[\/\\]/ ) {
            $homePath = Cwd::abs_path("$workPath/$homePath");
        }
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: $cmdLine is not a rabbitmq process.\n");
        return;
    }

    $appInfo->{INSTALL_PATH} = $homePath;

    #TODO：下面获取版本和端口的方法缺少环境测试，需要优化
    my $rbctlPath = "$homePath/sbin/rabbitmqctl";
    my $verInfo = $self->getCmdOut( "'$rbctlPath' status | grep {rabbit,", $procInfo->{USER} );
    if ( $verInfo =~ /(\d+\.\d+\.\d+)/ ) {
        $appInfo->{VERSION} = $1;
    }
    else {
        $appInfo->{VERSION} = undef;
    }

    my $port;
    my $portInfo = $self->getCmdOut( "'$rbctlPath' status | grep listeners", $procInfo->{USER} );
    my $lsnPort;
    while ( $portInfo =~ /(\d+)/sg ) {
        $lsnPort = $1;
        if ( $listenMap->{$lsnPort} ) {
            $port = $lsnPort;
            last;
        }
    }

    $appInfo->{PORT}           = $port;
    $appInfo->{ADMIN_PORT}     = undef;
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = $port;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}
