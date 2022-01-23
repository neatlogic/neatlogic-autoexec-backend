#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package KafkaCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;

sub getConfig {
    return {
        regExps  => ['\bkafka.Kafka\b'],    #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },     #ps的属性的精确匹配
        envAttrs => {}                      #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
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
    my $envMap           = $procInfo->{ENVIRONMENT};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};

    my $zooLibPath;
    my $homePath;
    my $version;

    my $zooLibPath;
    if ( $cmdLine =~ /-cp\s+.*[:;]([\/\\].*[\/\\]kafka.*?.jar)/ ) {
        $zooLibPath = Cwd::abs_path( dirname($1) );
    }
    elsif ( $envMap->{CLASSPATH} =~ /.*[:;]([\/\\].*[\/\\]kafka.*?.jar)/ ) {
        $zooLibPath = Cwd::abs_path( dirname($1) );
    }

    if ( defined($zooLibPath) ) {
        $homePath = dirname($zooLibPath);
        foreach my $lib ( glob("$zooLibPath/kafka_*.jar") ) {
            if ( $lib =~ /kafka_([\d\.]+).*?\.jar/ ) {
                $version = $1;
                $appInfo->{MAIN_LIB} = $lib;
            }
        }
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: Can not find homepath for Kafka command:$cmdLine, failed.\n");
        return;
    }

    $appInfo->{INSTALL_PATH} = $homePath;
    $appInfo->{VERSION}      = $version;

    my $pos = rindex( $cmdLine, 'kafka.Kafka' ) + 12;
    my $confPath = substr( $cmdLine, $pos );
    $confPath =~ s/^\s*|\s*$//g;

    my $realConfPath;
    if ( $confPath =~ /^\.{1,2}[\/\\]/ ) {
        if ( -e "/proc/$pid/cwd" ) {
            my $workPath = readlink("/proc/$pid/cwd");
            $realConfPath = Cwd::abs_path("$workPath/$confPath");
        }
        if ( not -e $realConfPath ) {
            $realConfPath = Cwd::abs_path("$homePath/$confPath");
        }
        if ( not -e $realConfPath ) {
            $realConfPath = Cwd::abs_path("$homePath/bin/$confPath");
        }
    }
    else {
        $realConfPath = Cwd::abs_path($confPath);
    }

    if ( defined($realConfPath) ) {
        $realConfPath = dirname($realConfPath);
    }

    $appInfo->{CONFIG_PATH} = $realConfPath;

    $self->getJavaAttrs($appInfo);
    my ( $ports, $port ) = $self->getPortFromProcInfo($appInfo);

    my @members;
    my $confMap   = {};
    my $confLines = $self->getFileLines($confPath);
    foreach my $line (@$confLines) {
        $line =~ s/^\s*|\s*$//g;
        if ( $line !~ /^#/ ) {
            my ( $key, $val ) = split( /\s*=\s*/, $line );
            $confMap->{$key} = $val;
        }
    }
    $appInfo->{BROKER_ID} = $confMap->{'broker.id'};
    my $lsnAddr = $confMap->{'advertised.listeners'};
    $appInfo->{ACCESS_ADDR} = $lsnAddr;
    if ( $lsnAddr =~ /:(\d+)$/ ) {
        $port = int($1);
    }

    if ( $port == 65535 ) {
        print("WARN: Can not determine Kafaka listen port.\n");
        return undef;
    }

    $appInfo->{PORT}  = $port;
    $appInfo->{PORTS} = $ports;

    my @logDirs = ();
    foreach my $logDir ( split( ',', $confMap->{'log.dirs'} ) ) {
        push( @logDirs, { VALUE => $logDir } );
    }
    $appInfo->{LOG_DIRS} = \@logDirs;

    my @zookeeperConnects = ();
    foreach my $zookeeperConn ( split( ',', $confMap->{'zookeeper.connect'} ) ) {
        push( @zookeeperConnects, { VALUE => $zookeeperConn } );
    }
    $appInfo->{ZOOKEEPER_CONNECTS} = \@zookeeperConnects;

    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = $appInfo->{JMX_PORT};

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}

1;
