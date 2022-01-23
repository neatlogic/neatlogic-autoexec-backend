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
    if ( $cmdLine =~ /\s+-jar\s+(.*?)\.jar\b/i ) {
        my $jarName = basename($1);
        $jarName =~ s/[\-\d\.\_]+$//;
        $appInfo->{SERVER_NAME} = $jarName;
    }
    elsif ( $cmdLine =~ /(\w[-\w]+)\s*$/ or $cmdLine =~ /(\w[-\w]+)\s*$/ ) {
        my $className = $1;
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

    if ( not defined( $envMap->{TS_INSNAME} ) or $envMap->{TS_INSNAME} eq '' ) {

        #没有标记的Java进程，忽略
        return undef;
    }

    my $cmdLine = $procInfo->{COMMAND};
    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    $self->getJavaAttrs($appInfo);

    $appInfo->{MON_PORT} = $appInfo->{JMX_PORT};

    my @ports = ();

    my $minPort  = 65535;
    my $lsnPorts = $procInfo->{CONN_INFO}->{LISTEN};
    foreach my $lsnPort ( keys(%$lsnPorts) ) {
        $lsnPort =~ s/^.*://;
        $lsnPort = int($lsnPort);
        if ( $lsnPort ne $appInfo->{JMX_PORT} and $lsnPort < $minPort ) {
            $minPort = int($lsnPort);
        }
        push( @ports, $lsnPort );
    }

    if ( $minPort < 65535 ) {
        $appInfo->{PORT}  = $minPort;
        $appInfo->{PORTS} = \@ports;
    }

    $self->getServerName($appInfo);

    return $appInfo;
}

1;
