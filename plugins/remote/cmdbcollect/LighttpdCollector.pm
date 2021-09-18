#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package LighttpdCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjType;

sub getConfig {
    return {
        regExps  => ['\blighttpd\b'],          #正则表达是匹配ps输出
        psAttrs  => { COMM => 'lighttpd' },    #ps的属性的精确匹配
        envAttrs => {}                         #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
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

    my $pid      = $procInfo->{PID};
    my $cmdLine  = $procInfo->{COMMAND};
    my $workPath = readlink("/proc/$pid/cwd");

    my $homePath;
    my $binPath;
    if ( $cmdLine =~ /^(.*?lighttpd)\s+-/ ) {
        $binPath = $1;
        if ( $binPath =~ /^\.{1,2}[\/\\]/ ) {
            $binPath = "$workPath/$binPath";
        }
        $binPath  = Cwd::abs_path($binPath);
        $homePath = dirname($binPath);
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: $cmdLine not a lighttpd process.\n");
        return;
    }

    my $confFile;
    my $confPath;
    if ( defined($homePath) or $homePath ne '' ) {
        if ( $cmdLine =~ /(\s-f\s+.+\s+-.*|\s-f\s+.+)$/ ) {
            $confFile = $1;
            $confFile =~ s/^\s*-f\s*//;
            if ( $confFile =~ /^\.{1,2}[\/\\]/ ) {
                $confFile = "$workPath/$confFile";
            }
            if ( defined($confFile) and $confFile ne '' ) {
                $confFile = Cwd::abs_path($confFile);
                $confPath = dirname($confFile);
            }
        }
    }

    $appInfo->{INSTALL_PATH} = $homePath;
    $appInfo->{BIN_PATH}     = $binPath;
    $appInfo->{CONFIG_PATH}  = $confPath;
    $appInfo->{CONFIG_FILE}  = $confFile;

    my $version;
    my $verInfo = $self->getCmdOut(qq{"$binPath" -v});

    #lighttpd/1.4.54 (ssl) - a light and fast webserver
    if ( $verInfo =~ /lighttpd\/([\d\.]+)/ ) {
        $version = $1;
    }
    $appInfo->{VERSION} = $version;

    my $portsMap    = {};
    my $lsnPortsMap = $procInfo->{CONN_INFO}->{LISTEN};
    foreach my $lsnPortInfo ( keys(%$lsnPortsMap) ) {
        if ( $lsnPortInfo =~ /:(\d+)$/ or $lsnPortInfo =~ /^(\d+)$/ ) {
            $portsMap->{$1} = 1;
        }
    }

    my $port;
    my $sslPort;
    my $conf = $self->getFileContent($confFile);
    while ( $conf =~ /\n\s*server\.port\s*=\s*(\d+)\s*\n/sg ) {
        if ( defined( $portsMap->{$1} ) ) {
            $port = $1;
        }
    }
    if ( $conf =~ /\n\s*ssl\.engine\s*=\s*"enable"\s*\n/s ) {
        while ( $conf =~ /\n\s*\$SERVER\["socket"\]\s*==\s*"\d+\.\d+\.\d+\.\d+:(\d+)"\s*\{(.*?)\}/sg ) {
            $sslPort = $1;
            my $sslDetail = $2;
            if ( $sslDetail !~ /\n\s*ssl\.engine\s*=\s*"enable"\s*\n/s ) {
                undef($sslPort);
            }
            if ( defined($sslPort) and defined( $portsMap->{$sslPort} ) ) {
                last;
            }
            else {
                undef($sslPort);
            }
        }
    }

    $appInfo->{PORT}           = $port;
    $appInfo->{SSL_PORT}       = $sslPort;
    $appInfo->{ADMIN_PORT}     = $port;
    $appInfo->{ADMIN_SSL_PORT} = $sslPort;
    $appInfo->{MON_PORT}       = $port;

    my $logPath;
    my $serverRoot;
    if ( $conf =~ /\n\s*var\.log_root\s*=\s*(.*?)\s*\n/s ) {
        $logPath = $1;
    }
    if ( $conf =~ /\n\s*var\.server_root\s*=\s*(.*?)\s*\n/s ) {
        $serverRoot = $1;
    }
    $appInfo->{LOG_PATH}    = $logPath;
    $appInfo->{SERVER_ROOT} = $serverRoot;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}
