#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package ZookeeperCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjType;

sub getConfig {
    return {
        regExps  => ['\borg.apache.zookeeper.server.quorum.QuorumPeerMain\b'],    #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },                                           #ps的属性的精确匹配
        envAttrs => {}                                                            #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
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

    my $procInfo         = $self->{procInfo};
    my $envMap           = $procInfo->{ENVRIONMENT};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{OBJECT_TYPE} = $CollectObjType::APP;

    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};

    my $zooLibPath;
    my $homePath;
    my $version;

    my $zooLibPath;
    if ( $cmdLine =~ /-cp\s+.*[:;]([\/\\].*[\/\\]zookeeper.*?.jar)/ ) {
        $zooLibPath = Cwd::abs_path( dirname($1) );
    }
    elsif ( $envMap->{CLASSPATH} =~ /.*[:;]([\/\\].*[\/\\]zookeeper.*?.jar)/ ) {
        $zooLibPath = Cwd::abs_path( dirname($1) );
    }

    if ( defined($zooLibPath) ) {
        $homePath = dirname($zooLibPath);
        foreach my $lib ( glob("$zooLibPath/zookeeper-*.jar") ) {
            if ( $lib =~ /zookeeper-([\d\.]+)\.jar/ ) {
                $version = $1;
                $appInfo->{MAIN_LIB} = $lib;
            }
        }
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: Can not get home path from command:$cmdLine, failed.\n");
        return;
    }

    $appInfo->{INSTALL_PATH} = $homePath;
    $appInfo->{VERSION}      = $version;

    my $pos = rindex( $cmdLine, 'QuorumPeerMain' ) + 15;
    my $confPath = substr( $cmdLine, $pos );
    if ( $confPath =~ /^\.{1,2}[\/\\]/ ) {
        $confPath = Cwd::abs_path("$homePath/bin/$confPath");
    }
    $appInfo->{CONFIG_PATH} = $confPath;

    $self->getJavaAttrs($appInfo);

    my @members;
    my $confMap   = {};
    my $confLines = $self->getFileLines($confPath);
    foreach my $line (@$confLines) {
        $line =~ s/^\s*|\s*$//g;
        if ( $line !~ /^#/ ) {
            my ( $key, $val ) = split( /\s*=\s*/, $line );
            $confMap->{$key} = $val;
            if ( $key =~ /server\.\d+/ ) {
                push( @members, $val );
            }
        }
    }

    $appInfo->{DATA_DIR}     = $confMap->{dataDir};
    $appInfo->{PORT}         = $confMap->{clientPort};
    $appInfo->{ADMIN_PORT}   = $confMap->{'admin.serverPort'};
    $appInfo->{ADMIN_ENABLE} = $confMap->{'admin.enableServer'};
    $appInfo->{MEMBERS}      = \@members;

    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = $appInfo->{JMX_PORT};

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}
