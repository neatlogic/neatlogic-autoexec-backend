#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package PythonCollector;

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
        regExps  => ['\bpython\d?\s'],
        psAttrs  => { COMM => 'python' },
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

    my $version;
    my $pythonPath = $procInfo->{EXECUTABLE_FILE};
    if ( not defined($pythonPath) or not -e $pythonPath ) {
        if ( $cmdLine =~ /^"?(.*?\bpython[\d\.]*)"?\s/ or $cmdLine =~ /^"?(.*?\bpython[\d\.]*.exe)"?\s/ ) {
            $pythonPath = $1;
            if ( $pythonPath =~ /^\.{1,2}[\/\\]/ ) {
                $pythonPath = "$workPath/$pythonPath";
            }
        }

        if ( $pythonPath eq 'python' and $self->{ostype} ne 'windows' ) {
            $pythonPath = $self->getCmdOut( 'which python', $procInfo->{USER} );
        }

        if ( -e $pythonPath ) {
            $pythonPath = Cwd::abs_path($pythonPath);
        }
    }

    if ( -e $pythonPath ) {
        my $verInfo = $self->getCmdOut(qq{"$pythonPath" --version});
        if ( $verInfo =~ /([\d\.]+)/ ) {
            $version = $1;
        }
    }

    $appInfo->{EXE_PATH} = $pythonPath;
    $appInfo->{VERSION}  = $version;
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
    $appInfo->{_OBJ_TYPE}     = 'Python';

    my @ports = ();

    my $minPort  = 65535;
    my $lsnPorts = $procInfo->{CONN_INFO}->{LISTEN};
    foreach my $lsnPort ( keys(%$lsnPorts) ) {
        $lsnPort =~ s/^.*://;
        $lsnPort = int($lsnPort);
        if ( $minPort < $lsnPort ) {
            $minPort = $lsnPort;
        }
        push( @ports, $lsnPort );
    }

    if ( $minPort < 65535 ) {
        $appInfo->{PORT}  = $minPort;
        $appInfo->{PORTS} = \@ports;
    }

    $self->getServerName();
    $self->getVersion();

    return $appInfo;
}

1;
