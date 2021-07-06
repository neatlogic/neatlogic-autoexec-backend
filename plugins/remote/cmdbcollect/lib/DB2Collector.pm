#!/usr/bin/perl
use strict;

package DB2Collector;
use parent 'BASECollector';    #继承BASECollector

use File::Basename;

sub getConfig {
    return {
        DB2 => {
            regExps  => [],
            psAttrs  => { COMM => 'db2sysc' },
            envAttrs => { DB2_HOME => undef, DB2INSTANCE => undef }
        }
    };
}

sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo = $self->{procInfo};
    my $appInfo  = {};

    my $db2InstUser = $procInfo->{USER};

    my $db2InstArray = $self->getCmdOutLines( 'db2ilist', $db2InstUser );
    my @db2Insts = grep { $_ !~ /mail/i } @$db2InstArray;
    if ( scalar(@db2Insts) == 0 ) {
        print("WARN: No db2 instance found.\n");
        return;
    }
    chomp(@db2Insts);

    my $version;
    my $user = $db2Insts[0];
    my $verInfo = $self->getCmdOut( 'db2level', $user );
    if ( $verInfo =~ /"DB2\s+(v\S+)"/ ) {
        $version = $1;
        $appInfo->{VERSION} = $version;

        #$appInfo->{DB_ID}   = $version;    #为什么DB_ID是version？
    }
    else {
        print("WARN: No db2 instance found, can not execute command:db2level.\n");
        return;
    }

    my $envMap = $procInfo->{ENVRIONMENT};
    $appInfo->{DB2_HOME} = $envMap->{DB2_HOME};
    $appInfo->{DB2LIB}   = $envMap->{DB2LIB};

    $appInfo->{INSTANCE_NAME} = $user;

    #TCP/IP Service name                          (SVCENAME) = DB2_db2inst1
    #SSL service name                         (SSL_SVCENAME) =
    my $svcName;
    my $sslSvcName;
    my $svcDef = $self->getCmdOutLines( 'db2 get dbm cfg|grep SVCENAME', $user );
    foreach my $line (@$svcDef) {
        if ( $line =~ /\(SVCENAME\)\s+=\s+(.*)\s*$/ ) {
            $svcName = $1;
        }
        elsif ( $line =~ /\(SSL_SVCENAME\)\s+=\s+(.*)\s*$/ ) {
            $sslSvcName = $1;
        }
    }
    my $port;
    my $sslPort;
    if ( $svcName =~ /^\d+$/ ) {
        $port = $svcName;
    }
    if ( $sslSvcName =~ /^\d+$/ ) {
        $sslPort = $sslSvcName;
    }

    if ( not defined($port) ) {
        my $cmd = qw{grep "$svcName" /etc/services};
        if ( defined($sslSvcName) and $sslSvcName ne '' ) {
            $cmd = qw{grep "$svcName\|$sslSvcName" /etc/services};
        }
        my $portDef = $self->getCmdOutLines($cmd);
        foreach my $line (@$portDef) {
            if ( $line =~ /^$svcName\s+(\d+)\/tcp/ ) {
                $port = $1;
            }
            elsif ( $line =~ /^$sslSvcName\s+(\d+)\/tcp/ ) {
                $sslPort = $1;
            }
        }
    }
    if ( not defined($port) ) {
        print("WARN: DB2 service $svcName not found in /etc/services.\n");
        $port = '50000';
    }
    $appInfo->{PORT}     = $port;
    $appInfo->{SSL_PORT} = $sslPort;
    $appInfo->{PORTS}    = [ $port, $sslPort ];

    # Database 1 entry:

    #  Database alias                       = DB1
    #  Database name                        = DB1
    #  Local database directory             = /home/db2inst1
    #  Database release level               = d.00
    #  Comment                              =
    #  Directory entry type                 = Indirect
    #  Catalog database partition number    = 0
    #  Alternate server hostname            =
    #  Alternate server port number         =
    my @dbNames = ();
    my @dbTypes = ();
    my @dbDirs  = ();
    my @dbDef   = $self->getCmdOut( 'db2 list db directory', $user );
    foreach my $line (@dbDef) {
        if ( $line =~ /^\s*Database name\s+=\s+(.*)$/ ) {
            push( @dbNames, $1 );
        }
        elsif ( $line =~ /^\s*Directory entry type\s+=\s+(.*)$/ ) {
            push( @dbTypes, $1 );
        }
        elsif ( $line =~ /^\s*Local database directory\s+=\s+(.*)$/ ) {
            push( @dbDirs, $1 );
        }
    }

    my @localDbs;
    for ( my $i = 0 ; $i < scalar(@dbTypes) ; $i++ ) {
        my $dbType = $dbTypes[$i];
        if ( $dbType !~ /remote/i ) {
            my $localDb = {};
            $localDb->{DB_NAME}      = $dbNames[$i];
            $localDb->{DB_DIRECTORY} = $dbDirs[$i];
            push( @localDbs, $localDb );
        }
    }
    $appInfo->{DATABASES} = \@localDbs;

    my @allDbUsers = ();
    foreach my $db (@localDbs) {
        my $dbName   = $db->{DB_NAME};
        my $selCmd   = qq{db2 connect to "$dbName" && db2 "select distinct cast((grantee) as char(20)) as GRANTEE from syscat.tabauth"};
        my $userInfo = $self->getCmdOutLines( $selCmd, $user );
        if ( $$userInfo[-1] =~ /not\s+exist/ ) {
            print("WARN: No user found.\n");
        }
        my @dbUsers = grep { $_ !~ /aaa|sql|local|database|grantee|--|selected|^\s*$|mail/i } @$userInfo;
        foreach my $dbUser (@dbUsers) {
            $dbUser =~ s/^\s*|\s*$//g;
            push( @allDbUsers, $dbUser );
        }
    }
    $appInfo->{USERS} = \@allDbUsers;

    return $appInfo;
}

1;
