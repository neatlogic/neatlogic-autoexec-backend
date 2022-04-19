#!/usr/bin/perl
use strict;

package ORACLEWALLETSQLRunner;

use base 'ORACLESQLRunner';
use FindBin;
use Expect;
use Encode;
use File::Basename;

use DeployUtils;
use SQLFileStatus;

sub new {
    my ( $pkg, $sqlFile, %args ) = @_;

    my $sqlFileStatus = $args{sqlFileStatus};
    my $dbInfo        = $args{dbInfo};
    my $charSet       = $args{charSet};
    my $logFilePath   = $args{logFilePath};
    my $toolsDir      = $args{toolsDir};
    my $tmpDir        = $args{tmpDir};

    my $dbType         = $dbInfo->{dbType};
    my $dbName         = $dbInfo->{sid};
    my $host           = $dbInfo->{host};
    my $port           = $dbInfo->{port};
    my $user           = $dbInfo->{user};
    my $pass           = $dbInfo->{pass};
    my $isAutoCommit   = $dbInfo->{autocommit};
    my $dbVersion      = $dbInfo->{version};
    my $dbArgs         = $dbInfo->{args};
    my $dbServerLocale = $dbInfo->{locale};
    my $oraWallet      = $dbInfo->{oraWallet};

    my $self = {};
    bless( $self, $pkg );

    my $oraClientDir = 'oracle-client';
    if ( defined($dbVersion) and -e "$toolsDir/oracle-client-$dbVersion" ) {
        $oraClientDir = "oracle-client-$dbVersion";
    }

    $ENV{ORACLE_HOME}     = "$toolsDir/$oraClientDir";
    $ENV{LD_LIBRARY_PATH} = $ENV{ORACLE_HOME} . '/lib:' . $ENV{ORACLE_HOME} . '/bin' . $ENV{LD_LIBRARY_PATH};
    $ENV{PATH}            = "$toolsDir/$oraClientDir/bin:" . $ENV{PATH};

    if ( defined($dbServerLocale) and ( $dbServerLocale eq 'ISO-8859-1' or $dbServerLocale =~ /\.WE8ISO8859P1/ ) ) {
        $ENV{NLS_LANG} = 'AMERICAN_AMERICA.WE8ISO8859P1';
    }
    else {
        if ( $charSet eq 'UTF-8' ) {
            $ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
        }
        elsif ( $charSet eq 'GBK' ) {
            $ENV{NLS_LANG} = 'AMERICAN_AMERICA.ZHS16GBK';
        }
    }

    $sqlFile =~ s/^\s*'|'\s*$//g;

    $self->{sqlFileStatus} = $sqlFileStatus;
    $self->{toolsDir}      = $toolsDir;
    $self->{tmpDir}        = $tmpDir;

    $self->{dbType}       = $dbType;
    $self->{host}         = $host;
    $self->{port}         = $port;
    $self->{sqlFile}      = $sqlFile;
    $self->{charSet}      = $charSet;
    $self->{user}         = $user;
    $self->{pass}         = $pass;
    $self->{logFilePath}  = $logFilePath;
    $self->{isAutoCommit} = $isAutoCommit;
    $self->{dbName}       = $dbName;
    $self->{dbVersion}    = $dbVersion;
    $self->{dbArgs}       = $dbArgs;

    $self->{PROMPT}       = qr/\nSQL> $/s;
    $self->{hasLogon}     = 0;
    $self->{ignoreErrors} = $dbInfo->{ignoreErrors};

    my $spawn;

    my $sqlDir      = dirname($sqlFile);
    my $sqlFileName = basename($sqlFile);
    $self->{sqlFileName} = $sqlFileName;

    chdir($sqlDir);

    if ( $sqlFile =~ /\.ctl/i ) {
        $ENV{LANG}     = 'en_US.ISO-8859-1';
        $ENV{LC_ALL}   = 'en_US.ISO-8859-1';
        $ENV{NLS_LANG} = 'AMERICAN_AMERICA.WE8ISO8859P1';

        $self->{fileType} = 'CTL';
        print("INFO:sqlldr userid=/\@$oraWallet $dbArgs control='$sqlFileName'\n");
        $spawn = Expect->spawn("sqlldr /\@$oraWallet $dbArgs control='$sqlFileName'");
    }
    elsif ( $sqlFile =~ /\.dmp/i ) {
        $ENV{LANG}     = 'en_US.ISO-8859-1';
        $ENV{LC_ALL}   = 'en_US.ISO-8859-1';
        $ENV{NLS_LANG} = 'AMERICAN_AMERICA.WE8ISO8859P1';

        $self->{fileType} = 'DMP';

        # oracle import
        print("INFO: imp /\@$oraWallet $dbArgs file='$sqlFileName'\n");
        $spawn = Expect->spawn("imp /\@$oraWallet $dbArgs file='$sqlFileName'");
    }
    else {
        $self->{fileType} = 'SQL';

        #execute by wallet
        #sqlplus /@walletname @db/oratest.scott/1.a.sql
        print("INFO: sqlplus -R 1 -L /\@$oraWallet \@'$sqlFileName'\n");

        $spawn = Expect->spawn("sqlplus -R 1 -L /\@$oraWallet");
    }

    if ( not defined($spawn) ) {
        die("launch oracle client failed, check if it exists and it's permission.\n");
    }

    $spawn->max_accum(2048);
    $self->{spawn} = $spawn;

    return $self;
}

sub run {
    my ($self) = @_;
    $self->SUPER::run();
}

1;
