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
use CollectObjCat;

sub getConfig {
    return {
        regExps => ['\brabbitmq\b']    #正则表达是匹配ps输出
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
    my $envMap    = $procInfo->{ENVIRONMENT};
    my $listenMap = $procInfo->{CONN_INFO}->{LISTEN};

    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};

    my $workPath = readlink("/proc/$pid/cwd");
    my $homePath;
    if ( $cmdLine =~ /-pa\s(\S+)/ ) {
        $homePath = $1;
        $homePath =~ s/^["']|["']$//g;
        if ( $homePath =~ /^\.{1,2}[\/\\]/ ) {
            $homePath = Cwd::abs_path("$workPath/$homePath");
        }
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: $cmdLine is not a rabbitmq process.\n");
        return;
    }

    $homePath = dirname($homePath);
    $appInfo->{INSTALL_PATH} = $homePath;

    my $version;
    my $userHome = ( getpwnam( $procInfo->{USER} ) )[7];

    #TODO：下面获取版本和端口的方法缺少环境测试，需要优化
    my $rbctlPath   = "$homePath/sbin/rabbitmqctl";
    my $statusLines = $self->getCmdOutLines("HOME='$userHome' LANG=C '$rbctlPath' status");
    foreach my $line (@$statusLines) {
        if ( $line =~ /RabbitMQ\s+version:\s+([\d\.]+)/ ) {
            $version = $1;
        }
        elsif ( $line =~ /\{rabbit.*?([\d\.]+)/ ) {
            $version = $1;
        }
    }
    $appInfo->{VERSION} = $version;

    my ( $ports, $port ) = $self->getPortFromProcInfo($appInfo);

    if ( $port == 65535 ) {
        print("WARN: Can not determine RabbitMQ listen port.\n");
        return undef;
    }

    if ( $port < 65535 ) {
        $appInfo->{PORT} = $port;
    }

    $appInfo->{ADMIN_PORT}     = undef;
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = $port;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}

1;
