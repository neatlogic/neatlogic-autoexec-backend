#!/usr/bin/perl
use strict;

package SnmpHelper;
use Net::SNMP qw(:snmp);

sub new {
    my ($class) = @_;
    my $self = {};
    bless( $self, $class );
    return $self;
}

sub _errCheck {
    my ( $self, $snmp, $queryResult, $oid ) = @_;
    my $hasError = 0;
    if ( not defined($queryResult) ) {
        $hasError = 1;
        my $errMsg = sprintf( "WARN: %s, %s\n", $snmp->error(), $oid );
        print($errMsg);
    }

    return $hasError;
}

#get simple oid value
sub getScalar {
    my ( $self, $snmp, $oidDefMap ) = @_;

    my $value;

    my @scalarOids = ();
    foreach my $attr ( keys(%$oidDefMap) ) {
        my $val = $oidDefMap->{$attr};

        #支持单值oid可以定义多个oid进行尝试查询
        if ( ref($val) eq 'ARRAY' ) {
            push( @scalarOids, @$val );
        }
        else {
            push( @scalarOids, $val );
        }
    }

    my $result = $snmp->get_request( -varbindlist => \@scalarOids, );

    my $data = {};
    foreach my $attr ( keys(%$oidDefMap) ) {
        my $oidDesc;
        my $oidVal;
        my $val = $oidDefMap->{$attr};
        if ( ref($val) ne 'ARRAY' ) {
            $oidDesc = $val;
            my $oid    = $val;
            my $tmpVal = $result->{$oid};
            if (    defined($tmpVal)
                and $tmpVal ne 'noSuchObject'
                and $tmpVal ne 'noSuchInstance'
                and $tmpVal ne 'endOfMibView' )
            {
                $oidVal = $tmpVal;
            }
        }
        else {
            $oidDesc = join( ', ', @$val );

            #如果某个属性定义的是多个oid，则按照顺序获取值
            foreach my $oid (@$val) {
                my $tmpVal = $result->{$val};
                if (    defined($oidVal)
                    and $tmpVal ne 'noSuchObject'
                    and $tmpVal ne 'noSuchInstance'
                    and $tmpVal ne 'endOfMibView' )
                {
                    $oidVal = $tmpVal;
                    last;
                }
            }
        }

        if ( defined($oidVal) ) {
            $data->{$attr} = $oidVal;
        }
        else {
            print("WARN: Can not find value for attr $attr(oid:$oidDesc).\n");
        }
    }

    return $data;
}

#get table values from 1 or more than table oid
sub getTable {
    my ( $self, $snmp, $oidDefMap ) = @_;

    my $data = {};
    foreach my $attrName ( keys(%$oidDefMap) ) {
        my @attrTable = ();    #每个属性会生成一个table

        my $oidEntrys = $oidDefMap->{$attrName};
        while ( my ( $name, $oid ) = each(%$oidEntrys) ) {
            my $table = $snmp->get_table( -baseoid => $oid );
            $self->_errCheck( $snmp, $table, $oid );

            my @sortedOids = oid_lex_sort( keys(%$table) );
            for ( my $i = 0 ; $i < scalar(@sortedOids) ; $i++ ) {
                my $sortedOid = $sortedOids[$i];
                my $entryInfo = $attrTable[$i];
                if ( not defined($entryInfo) ) {
                    $entryInfo = {};
                    $attrTable[$i] = $entryInfo;
                }
                $entryInfo->{$name} = $table->{$sortedOid};
            }
        }

        $data->{$attrName} = \@attrTable;
    }

    return $data;
}

1;

