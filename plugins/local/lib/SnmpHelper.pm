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
    my $snmp     = $self->{snmpSession};
    if ( not defined($queryResult) ) {
        $hasError = 1;
        my $error = $snmp->error();
        if ( $error =~ /^No response/i ){
            print("ERROR: $error, snmp failed, exit.\n");
            exit(-1);
        }
        else{
            print( "WARN: $error, $oid\n");
        }
    }

    return $hasError;
}

sub hex2mac {
    my ($self, $hexMac) = @_;
    if ( $hexMac !~ /\x00/ ) {
        $hexMac = substr( $hexMac, 2 );
        $hexMac =~ s/..\K(?=.)/:/sg;
    }
    else {
        $hexMac = '';
    }

    return $hexMac;
}


sub hex2ip {
  my ($self, $hexIp) = @_;

  my $ip;
  #每两个字符作为一个数组元素
  my @array = ( $hexIp =~ m/../g );
  if ($#array >= 3) {
      if (lc($array[0]) eq '0x'){
          #去掉开头的0x
          shift(@array);
      }

      if ($#array == 3){
          #4个字节，IPV4
          @array = map {hex($_)} @array;
          $ip = join('.', @array);
      }
      else{
          #IPV6
          $ip = join(':', @array);
      }
  }
  return $ip;
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

#get table values from 1 or more than table oid
sub getTableOidAndVal {
    my ( $self, $snmp, $oidDefMap ) = @_;

    my $data = {};
    my $oids = {};
    foreach my $attrName ( keys(%$oidDefMap) ) {
        my @attrTable = ();    #每个属性会生成一个table
        my @oidTable = ();

        my $oidEntrys = $oidDefMap->{$attrName};
        while ( my ( $name, $oid ) = each(%$oidEntrys) ) {
            my $table = $snmp->get_table( -baseoid => $oid );
            $self->_errCheck( $snmp, $table, $oid );

            my @sortedOids = oid_lex_sort( keys(%$table) );
            for ( my $i = 0 ; $i < scalar(@sortedOids) ; $i++ ) {
                my $sortedOid = $sortedOids[$i];

                my $oidInfo = $oidTable[$i];
                if ( not defined($oidInfo) ){
                    $oidInfo = {};
                    $oidTable[$i] = $oidInfo;
                }
                $oidInfo->{$name} = $sortedOid;

                my $entryInfo = $attrTable[$i];
                if ( not defined($entryInfo) ) {
                    $entryInfo = {};
                    $attrTable[$i] = $entryInfo;
                }
                $entryInfo->{$name} = $table->{$sortedOid};
            }
        }

        $data->{$attrName} = \@attrTable;
        $oids->{$attrName} = \@oidTable;
    }

    return ($oids, $data);
}

1;

