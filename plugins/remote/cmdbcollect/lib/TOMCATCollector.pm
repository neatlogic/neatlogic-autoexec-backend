#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package TOMCATCollector;

use strict;
use File::Basename;
use Data::Dumper;

sub new {
    my ($type) = @_;
    my $self = {};
    bless( $self, $type );
    return $self;
}

sub getCatalinaVal {
    my ( $self, $line, $varName ) = @_;

    my @vals = split( /:/, $line );
    my $val = $vals[1];
    $val =~ s/^\s+|\s+$//g;

    return $val;
}

sub collect {
    my ( $self, $procInfo ) = @_;

    my $appInfo = {};

    my $confPath;
    if ( $procInfo->{COMMAND} =~ /-Dcatalina.base=(\S+)\s+/ ) {
        $confPath = $1;
        $appInfo->{CATALINA_BASE} = $confPath;
    }

    my $installPath;
    if ( $procInfo->{COMMAND} =~ /-Dcatalina.home=(\S+)\s+/ ) {
        $installPath = $1;
        $appInfo->{CATALINA_HOME} = $installPath;
    }

    my $binPath = "$installPath/bin";
    my $verCmd  = "sh $binPath/version.sh";
    if ( $procInfo->{OS_TYPE} eq 'Windows' ) {
        $verCmd = `cmd /c $binPath/version.cmd`;
    }
    my @verOut = `$verCmd`;
    foreach my $line (@verOut) {
        if ( $line =~ /Server number/ ) {
            $appInfo->{VERSION} = $self->getCatalinaVal($line);
        }
        elsif ( $line =~ /JVM Vendor/ ) {
            $appInfo->{JVM_VENDER} = $self->getCatalinaVal($line);
        }
        elsif ( $line =~ /JRE_HOME/ ) {
            $appInfo->{JRE_HOME} = $self->getCatalinaVal($line);
        }
        elsif ( $line =~ /JVM Version/ ) {
            $appInfo->{JVM_VERSION} = $self->getCatalinaVal($line);
        }
    }

    if ( defined($confPath) ) {
        $appInfo->{SERVICE_NAME} = basename($confPath);
    }
    else {
        $appInfo->{SERVICE_NAME} = 'tomcat';
    }

    return $appInfo;
}

1;
