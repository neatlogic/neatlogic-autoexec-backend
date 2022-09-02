#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package VcsCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;
use Data::Dumper;

sub getConfig {
    return {
        seq      => 80,
        regExps  => ['\bvcsauthserver\s'],
        psAttrs  => { COMM => 'vcsauthserver' },
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
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');
    $appInfo->{_OBJ_TYPE}     = 'Vcs';
    $appInfo->{_MULTI_PROC}   = 1;

    my $environment = $procInfo->{ENVIRONMENT};
    my $vcshome     = $environment->{VCS_HOME};
    my $vcsconf     = $environment->{VCS_CONF};
    my $clusterHome = $environment->{CLUSTER_HOME};
    $appInfo->{VCS_HOME}     = $vcshome;
    $appInfo->{VCS_CONF}     = $vcsconf;
    $appInfo->{CLUSTER_HOME} = $clusterHome;
    my $vcsbin = "$vcshome/bin";
    $appInfo->{VCS_BIN} = $vcsbin;
    my $sysname = $self->getCmdOut("cat $vcsconf/conf/sysname");
    chomp($sysname);
    $appInfo->{NAME} = $sysname;
    my $version = $self->getCmdOut("$vcsbin/hastart -v");
    chomp($version);
    $appInfo->{VERSION} = $version;
    my $clusLines = $self->getCmdOutLines("$vcsbin/haclus -display");

    for my $line (@$clusLines) {
        my @infos = split( /\s+/, $line );
        if ( $line =~ /ClusterName/ ) {
            $appInfo->{CLUSTER_NAME} = @infos[1];
        }
        if ( $line =~ /ClusterAddress/ ) {
            $appInfo->{CLUSTER_IP} = @infos[1];
        }
        if ( $line =~ /ClusState/ ) {
            $appInfo->{STATE} = @infos[1];
        }
        if ( $line =~ /EngineVersion/ ) {
            $appInfo->{ENGINEVERSION} = @infos[1];
        }
    }
    my $portsLines = $self->getCmdOutLines('grep "vcs" /etc/services |grep tcp');
    my @ports      = ();
    for my $line (@$portsLines) {
        $line =~ s/\/tcp//;
        my @infos = split( /\s+/, $line );
        if ( $line =~ /vcs-app/ ) {
            $appInfo->{PORT} = @infos[1];
        }
        push( @ports, { ADDR => $infos[1] } );
    }
    $appInfo->{LISTEN} = \@ports;

    my $port           = $appInfo->{PORT};
    my $hagrpLines     = $self->getCmdOutLines("$vcsbin/hagrp -state");
    my @clusters       = ();
    my @clusterMembers = ();
    for my $line (@$hagrpLines) {
        if ( $line !~ /#Group/ ) {
            my @infos = split( /\s+/, $line );
            my $ins   = {};
            $ins->{GROUP} = @infos[0];
            $ins->{NAME}  = @infos[2];
            my $hostState = @infos[3];
            $hostState =~ s/\|//g;
            $ins->{STATE} = $hostState;
            if ( $sysname eq @infos[2] ) {
                $appInfo->{CLUSTER_STATE} = $hostState;
            }
            my $host  = $self->getCmdOut("grep @infos[2] /etc/hosts");
            my @hosts = split( /\s+/, $host );
            $ins->{IP} = @hosts[0];
            push( @clusters,       $ins );
            push( @clusterMembers, "@hosts[0]:$port" );
        }
    }
    $appInfo->{CLUSTER_HOST} = \@clusters;

    my @clusterCollect = ();
    my $objCat         = CollectObjCat->get('CLUSTER');
    my $clusterInfo    = {
        _OBJ_CATEGORY => $objCat,
        _OBJ_TYPE     => 'VcsCluster',
        INDEX_FIELDS  => CollectObjCat->getIndexFields($objCat),
        MEMBERS       => []
    };

    my $vip = $appInfo->{CLUSTER_IP};
    $clusterInfo->{MGMT_IP}          = $vip;
    $clusterInfo->{PRIMARY_IP}       = $vip;
    $clusterInfo->{PORT}             = $port;
    $clusterInfo->{UNIQUE_NAME}      = "Vcs:$vip:$port";
    $clusterInfo->{CLUSTER_MODE}     = 'Cluster';
    $clusterInfo->{CLUSTER_SOFTWARE} = 'Vcs';
    $clusterInfo->{CLUSTER_VERSION}  = $version;
    $clusterInfo->{NAME}             = "$vip:$port";
    $clusterInfo->{MEMBER_PEER}      = \@clusterMembers;
    push( @clusterCollect, $clusterInfo );

    return ( $appInfo, @clusterCollect );
}

1;
