#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package DB2Collector;
use parent 'BaseCollector';    #继承BASECollector

use File::Basename;

sub getConfig {
    return {
        seq      => 100,
        regExps  => ['\bdb2sysc\b'],
        psAttrs  => { COMM => 'db2sysc' },
        envAttrs => { DB2_HOME => undef, DB2INSTANCE => undef }
    };
}

sub getMemInfo {
    my ( $self, $appInfo ) = @_;

    # [db2inst1@sit-asm-123 tmp]$ db2pd -dbptnmem

    # Database Member 0 -- Active -- Up 0 days 05:54:57 -- Date 2021-07-06-20.28.13.373391

    # Database Member Memory Controller Statistics

    # Controller Automatic: Y
    # Memory Limit:         6647900 KB
    # Current usage:        140800 KB
    # HWM usage:            608832 KB
    # Cached memory:        7680 KB

    # Individual Memory Consumers:

    # Name             Mem Used (KB) HWM Used (KB) Cached (KB)
    # ========================================================
    # DBMS-db2inst1           106240        106240        7680
    # FMP_RESOURCES            22528         22528           0
    # PRIVATE                  12032         12544           0
}

sub getConnManInfo {
    my ( $self, $appInfo ) = @_;

    #db2pd -dbptnmem
}

sub getTablespaceInfo {
    my ( $self, $appInfo, $dbName ) = @_;

    #db2 connect to test2 && db2pd -tablespace -db test2
}

sub getTCPInfo {
    my ( $self, $appInfo ) = @_;

    #TCP/IP Service name                          (SVCENAME) = DB2_db2inst1
    #SSL service name                         (SSL_SVCENAME) =
    my $svcName;
    my $sslSvcName;
    my $svcDef = $self->getCmdOutLines( 'db2 get dbm cfg|grep SVCENAME', $appInfo->{OS_USER} );
    foreach my $line (@$svcDef) {
        if ( $line =~ /\(SVCENAME\)\s+=\s+(.*)\s*$/ ) {
            $svcName = $1;
        }
        elsif ( $line =~ /\(SSL_SVCENAME\)\s+=\s+(.*)\s*$/ ) {
            $sslSvcName = $1;
        }
    }

    my @ports;
    my $port;
    my $sslPort;
    if ( $svcName =~ /^\d+$/ ) {
        $port = $svcName;
    }
    if ( $sslSvcName =~ /^\d+$/ ) {
        $sslPort = $sslSvcName;
    }

    if ( not defined($port) ) {
        my $cmd = qq{grep "$svcName" /etc/services};
        if ( defined($sslSvcName) and $sslSvcName ne '' ) {
            $cmd = qq{grep "$svcName\|$sslSvcName" /etc/services};
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

    if ( defined($port) ) {
        push( @ports, $port );
    }
    else {
        print("WARN: DB2 service $svcName not found in /etc/services.\n");
        $port = '50000';
    }
    if ( defined($sslPort) ) {
        push( @ports, $port );
    }

    $appInfo->{PORT}     = $port;
    $appInfo->{SSL_PORT} = $sslPort;
    $appInfo->{PORTS}    = \@ports;
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

        #$appInfo->{DB_ID}   = $version;    #TODO：原来的，为什么DB_ID是version？
    }
    else {
        print("WARN: No db2 instance found, can not execute command:db2level.\n");
        return;
    }

    my $envMap = $procInfo->{ENVRIONMENT};
    $appInfo->{DB2_HOME} = $envMap->{DB2_HOME};
    $appInfo->{DB2LIB}   = $envMap->{DB2LIB};

    $appInfo->{INSTANCE_NAME} = $user;
    $appInfo->{OS_USER}       = $user;

    $self->getTCPInfo($appInfo);

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
    my $dbDef   = $self->getCmdOutLines( 'db2 list db directory', $user );
    foreach my $line (@$dbDef) {
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

    print Dumper ( \@dbNames );
    my @localDbs;
    for ( my $i = 0 ; $i < scalar(@dbTypes) ; $i++ ) {
        my $dbType = $dbTypes[$i];
        if ( $dbType !~ /remote/i ) {
            my $localDb = {};
            $localDb->{DB_NAME}      = $dbNames[$i];
            $localDb->{DB_DIRECTORY} = $dbDirs[$i];    #TODO: 需确认这个属性的意义
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
