#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package JavaCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;

sub getConfig {
    return {
        seq      => 9999,
        regExps  => ['\bjava\s'],
        psAttrs  => { COMM => 'java' },
        envAttrs => {}
    };
}

sub getServerName {
    my ( $self, $appInfo ) = @_;
    my $procInfo = $self->{procInfo};
    my $cmdLine  = $procInfo->{COMMAND};
    if ( $cmdLine =~ /\s+-jar\s+.*?([-\w\.]+)\.jar\b/i ) {
        my $jarName = $1;
        $jarName =~ s/^["']|["']$//g;
        my $jarName = basename($jarName);
        $jarName =~ s/[\-\d\.\_]+$//;
        $appInfo->{SERVER_NAME} = $jarName;
    }
    elsif ( $cmdLine =~ /(\w[-\w]+)\s*$/ or $cmdLine =~ /(\w[-\w]+)\s*$/ ) {
        my $className = $1;
        $className =~ s/^["']|["']$//g;
        $className =~ s/.*[\/\.]//;
        $appInfo->{SERVER_NAME} = $className;
    }
}

sub collect {
    my ($self) = @_;
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo = $self->{procInfo};
    my $envMap   = $procInfo->{ENVIRONMENT};

    my $pFinder     = $self->{pFinder};
    my $procEnvName = $pFinder->{procEnvName};
    if ( defined($procEnvName) and $procEnvName eq '' ) {
        if ( not defined( $envMap->{TS_INSNAME} ) or $envMap->{TS_INSNAME} eq '' ) {

            #没有标记的Java进程，忽略
            return undef;
        }
    }

    my $cmdLine = $procInfo->{COMMAND};
    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    $self->getJavaAttrs($appInfo);

    my ( $ports, $port ) = $self->getPortFromProcInfo($appInfo);

    if ( $port == 65535 ) {
        print("WARN: Can not determine Java listen port.\n");
    }

    $appInfo->{PORT}     = $port;
    $appInfo->{MON_PORT} = $appInfo->{JMX_PORT};

    $self->getServerName($appInfo);

    return $appInfo;
}

1;
