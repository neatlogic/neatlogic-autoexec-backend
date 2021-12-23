#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package PHPCollector;

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
        regExps  => ['\bphp\s'],
        psAttrs  => { COMM => 'php' },
        envAttrs => {}
    };
}

sub getServerName {
    my ( $self, $appInfo ) = @_;
    my $procInfo = $self->{procInfo};
    my $cmdLine  = $procInfo->{COMMAND};
    if ( $cmdLine =~ /(\w[-\w]+)\s*$/ or $cmdLine =~ /(\w[-\w]+)\.\w+\s*$/ ) {
        my $prgName = $1;
        $appInfo->{SERVER_NAME} = $prgName;
    }
}

sub getVersion {
    my ( $self, $appInfo ) = @_;

    my $utils    = $self->{collectUtils};
    my $procInfo = $self->{procInfo};
    my $cmdLine  = $procInfo->{COMMAND};
    my $pid      = $procInfo->{PID};
    my $workPath = readlink("/proc/$pid/cwd");

    my $phpPath = $procInfo->{EXECUTABLE_FILE};
    if ( not defined($phpPath) or not -e $phpPath ) {
        if ( $cmdLine =~ /^"?(.*?\bphp[\d\.]*)"?\s/ or $cmdLine =~ /^"?(.*?\bphp[\d\.]*.exe)"?\s/ ) {
            $phpPath = $1;
            if ( $phpPath =~ /^\.{1,2}[\/\\]/ ) {
                $phpPath = "$workPath/$phpPath";
            }
        }

        if ( $phpPath eq 'php' and $self->{ostype} ne 'windows' ) {
            $phpPath = $self->getCmdOut( 'which php', $procInfo->{USER} );
        }

        if ( -e $phpPath ) {
            $phpPath = Cwd::abs_path($phpPath);
        }
    }

    # PHP 5.4.16 (cli) (built: Apr  1 2020 04:07:17)
    # Copyright (c) 1997-2013 The PHP Group
    # Zend Engine v2.4.0, Copyright (c) 1998-2013 Zend Technologies
    my $version;
    my $engineVer;
    if ( -e $phpPath ) {
        my $verInfo = $self->getCmdOut(qq{"$phpPath" -v});
        if ( $verInfo =~ /PHP\s+([\d\.]+)/is ) {
            $version = $1;
        }
        if ( $verInfo =~ /Engine\s([v\d\.]+)/is ) {
            $engineVer = $1;
        }
    }

    $appInfo->{EXE_PATH}       = $phpPath;
    $appInfo->{VERSION}        = $version;
    $appInfo->{ENGINE_VERSION} = $engineVer;
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
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');
    $appInfo->{_OBJ_TYPE}     = 'PHP';
    my @ports = ();

    my $minPort  = 65535;
    my $lsnPorts = $procInfo->{CONN_INFO}->{LISTEN};
    foreach my $lsnPort ( keys(%$lsnPorts) ) {
        $lsnPort =~ s/^.*://;
        $minPort = int($lsnPort);
        push( @ports, $lsnPort );
    }

    if ( $minPort == 65535 ) {
        return undef;
    }

    $appInfo->{PORT}  = $minPort;
    $appInfo->{PORTS} = \@ports;

    $self->getServerName();
    $self->getVersion();

    return $appInfo;
}

1;
