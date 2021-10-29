#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package JettyCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;

sub getConfig {
    return {
        regExps  => ['\b-Djetty.home=|start\.jar'],    #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },                #ps的属性的精确匹配
        envAttrs => {}                                 #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
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
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};

    my $homePath;
    my $basePath;

    $homePath = $envMap->{JETTY_HOME};
    if ( not defined($homePath) or $homePath eq '' ) {
        if ( $cmdLine =~ /-Djetty.home=(.*?)\s+-/ ) {
            $homePath = Cwd::abs_path($1);
        }
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: $cmdLine not a jetty process.\n");
        return;
    }

    $self->getJavaAttrs($appInfo);

    $basePath = $envMap->{JETTY_BASE};
    if ( not defined($basePath) or $basePath eq '' ) {
        if ( $cmdLine =~ /-Djetty.base=(.*?)\s+-/ ) {
            $basePath = Cwd::abs_path($1);
        }
    }
    if ( not defined($basePath) or $basePath eq '' ) {
        $basePath = $homePath;
    }

    $appInfo->{INSTALL_PATH} = $homePath;
    $appInfo->{JETTY_HOME}   = $homePath;
    $appInfo->{JETTY_BASE}   = $basePath;

    my $confPath = "$basePath/etc";
    if ( -d $confPath ) {
        $appInfo->{CONFIG_PATH} = $confPath;
    }
    else {
        $appInfo->{CONFIG_PATH} = undef;
    }

    my $javaHome = $appInfo->{JAVA_HOME};
    my $javaPath = "$javaHome/bin/java";
    my $jmxPort  = $appInfo->{JMX_PORT};

    my $version = $self->getCmdOut("'$javaPath' -jar '$homePath/start.jar' --version | grep jetty-server | awk '{print \$2}'");
    $version =~ s/^\s*|\s*$//g;
    $appInfo->{VERSION} = $version;

    my @ports       = ();
    my $minPort     = 65535;
    my $lsnPortsMap = $procInfo->{CONN_INFO}->{LISTEN};
    foreach my $lsnPortInfo ( keys(%$lsnPortsMap) ) {
        if ( $lsnPortInfo =~ /:(\d+)$/ or $lsnPortInfo =~ /^(\d+)$/ ) {
            my $lsnPort = int($1);
            if ( $jmxPort ne $lsnPort and $lsnPort < $minPort ) {
                $minPort = $lsnPort;
            }
            push( @ports, $lsnPort );
        }
    }
    $appInfo->{PORTS}      = \@ports;
    $appInfo->{PORT}       = $minPort;
    $appInfo->{ADMIN_PORT} = undef;

    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = $jmxPort;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}

1;
