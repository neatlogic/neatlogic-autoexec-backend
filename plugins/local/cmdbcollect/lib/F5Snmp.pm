#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package SwitchSnmp;

use strict;
use File::Basename;
use JSON;
use Net::SNMP qw(:snmp);
use Data::Dumper;

sub new {
    my ( $class, %args ) = @_;
    my $self = {};
    bless( $self, $class );

    my $scalarOidDef = {
        DEV_NAME => '1.3.6.1.2.1.1.5',
        SN       => '1.3.6.1.4.1.3375.2.1.3.3.3',
        IP       => '1.3.6.1.4.1.3375.2.1.2.1.1.2.1.2',
        MODEL    => '1.3.6.1.4.1.3375.2.1.3.5.2',
        VENDOR   => '1.3.6.1.4.1.3375.2.1.4.1',
        VERSION  => '1.3.6.1.4.1.3375.2.1.4.2'
    };

    my $tableOidDef = {
        VS => {
            NAME      => '1.3.6.1.4.1.3375.2.2.10.1.2.1.1',
            IP        => '1.3.6.1.4.1.3375.2.2.10.1.2.1.3',
            PORT      => '1.3.6.1.4.1.3375.2.2.10.1.2.1.6',
            POOL_NAME => '1.3.6.1.4.1.3375.2.2.10.1.2.1.19'
        },

        POOL => {
            NAME       => '1.3.6.1.4.1.3375.2.2.5.1.2.1.1',
            MON_METHOD => '1.3.6.1.4.1.3375.2.2.5.1.2.1.17',
            LB_METHOD  => '1.3.6.1.4.1.3375.2.2.5.1.2.1.2'
        },

        MEMBER => {
            POOL_NAME => '1.3.6.1.4.1.3375.2.2.5.3.2.1.1',
            IP        => '1.3.6.1.4.1.3375.2.2.5.3.2.1.3',
            PORT      => '1.3.6.1.4.1.3375.2.2.5.3.2.1.4'
        }
    };

    $self->{scalarOidDef} = $scalarOidDef;
    $self->{tableOidDef}  = $tableOidDef;

    my $version = $args{version};
    if ( not defined($version) or $version eq '' ) {
        $version = 'snmpv2';
        $args{version} = $version;
    }
    if ( not defined( $args{retries} ) ) {
        $args{retries} = 2;
    }

    my $options = {};
    foreach my $key ( keys(%args) ) {
        $options->{"-$key"} = $args{$key};
    }

    my ( $session, $error ) = Net::SNMP->session(%$options);

    if ( !defined $session ) {
        print("ERROR:Create snmp session to $args{host} failed, $error\n");
        exit(-1);
    }

    $self->{snmpSession} = $session;

    END {
        local $?;
        $session->close();
    }

    return $self;
}

sub _errCheck {
    my ( $self, $queryResult, $oid ) = @_;
    my $hasError = 0;
    my $snmp     = $self->{snmpSession};
    if ( not defined($queryResult) ) {
        $hasError = 1;
        my $errMsg = sprintf( "WARN: %s, %s\n", $snmp->error(), $oid );
        print($errMsg);
    }

    return $hasError;
}

#get simple oid value
sub _getScalar {
    my ($self)       = @_;
    my $snmp         = $self->{snmpSession};
    my $scalarOidDef = $self->{scalarOidDef};

    my $snmpHelper = $self->{snmpHelper};
    my $scalarData = $snmpHelper->getScalar( $snmp, $scalarOidDef );

    return $scalarData;
}

sub _getVS {
    my ($self)      = @_;
    my $snmp        = $self->{snmpSession};
    my $tableOidDef = $self->{tableOidDef};

    my $snmpHelper = $self->{snmpHelper};
    my $tableData = $snmpHelper->getTable( $snmp, $tableOidDef );

    my $vsData     = $tableData->{VS};
    my $poolData   = $tableData->{POOL};
    my $memberData = $tableData->{MEMBER};

    my $poolMap = {};
    foreach my $poolInfo (@$poolData) {
        $poolMap->{ $poolInfo->{NAME} } = $poolInfo;
    }

    foreach my $memberInfo (@$memberData) {
        my $poolInfo = $memberInfo->{POOL_NAME};
        my $members  = $poolInfo->{MEMBERS};
        if ( not defined($members) ) {
            $members = [];
            $poolInfo->{MEMBERS} = $members;
        }
        push( @$members, $memberInfo );
    }

    my @vsArray = ();
    foreach my $vsInfo (@$vsData) {
        $vsInfo->{POOL} = $poolMap->{ $vsInfo->{POOL_NAME} };
    }

    return $vsData;
}

sub collect {
    my ($self) = @_;

    my $devInfo = $self->_getScalar();
    $devInfo->{OBJECT_TYPE} = 'LOADBLANCER';
    $devInfo->{APP_TYPE}    = 'F5';

    my $vsArray = $self->_getVS();
    $devInfo->{VIRTUAL_SERVERS} = $vsArray;

    return $devInfo;
}

1;
