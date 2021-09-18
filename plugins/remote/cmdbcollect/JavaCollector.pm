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
use CollectObjType;

sub getConfig {
    return {
        seq      => 9999,
        regExps  => ['\bjava\s'],
        psAttrs  => { COMM => 'java' },
        envAttrs => {}
    };
}

sub collect {
    my ($self) = @_;
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo = $self->{procInfo};
    my $cmdLine  = $procInfo->{COMMAND};
    my $appInfo  = {};
    $appInfo->{OBJECT_TYPE} = $CollectObjType::APP;

    $self->getJavaAttrs($appInfo);

    $appInfo->{MON_PORT} = $appInfo->{JMX_PORT};

    my @ports = ();

    my $minPort  = 65535;
    my $lsnPorts = $procInfo->{CONN_INFO}->{LISTEN};
    foreach my $lsnPort ( keys(%$lsnPorts) ) {
        $lsnPort =~ s/^.*://;
        if ( $lsnPort ne $appInfo->{JMX_PORT} and $lsnPort < $minPort ) {
            $minPort = $lsnPort;
        }
        push( @ports, $lsnPort );
    }
    $appInfo->{PORT}  = $minPort;
    $appInfo->{PORTS} = \@ports;

    return $appInfo;
}

1;
