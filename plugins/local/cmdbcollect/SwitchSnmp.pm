#!/usr/bin/perl
package SwitchSnmp;

use strict;
use JSON;
use Net::SNMP qw(:snmp);
use Data::Dumper;

sub new {
    my ( $class, %args ) = @_;
    my $self = {};
    $self->{DATA} = { PK => ['SN'] };
    bless( $self, $class );

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

    #单值定义
    my $scalarOidDef = {
        DEV_NAME    => '1.3.6.1.2.1.1.5.0',
        UPTIME      => '1.3.6.1.2.1.1.3.0',
        VENDOR      => '1.3.6.1.2.1.1.4.0',
        MODEL       => '1.3.6.1.2.1.1.1.0',
        IOS_INFO    => '1.3.6.1.2.1.1.1.0',
        SN          => [ '1.3.6.1.4.1.2011.10.2.6.1.2.1.1.2.0', '1.3.6.1.2.1.47.1.1.1.1.11.1' ],
        PORTS_COUNT => '1.3.6.1.2.1.2.1.0'
    };

    #列表值定义
    my $tableOidDef = { PORTS_TABLE_FOR_TEST => [ { DESC => '1.3.6.1.2.1.2.2.1.2' }, { MAC => '1.3.6.1.2.1.2.2.1.6' } ] };

    #通用列表值定义, 这部分不提供给外部修改
    my $commOidDef = {
        PORT_INDEX          => '1.3.6.1.2.1.17.1.4.1.2',
        PORT_DESC           => '1.3.6.1.2.1.2.2.1.2',
        PORT_MAC            => '1.3.6.1.2.1.2.2.1.6',
        MAC_TABLE           => '1.3.6.1.2.1.17.4.3.1.2',
        LLDP_LOCAL_PORT     => '1.0.8802.1.1.2.1.3.7.1.3',
        LLDP_REMOTE_PORT    => '1.0.8802.1.1.2.1.4.1.1.7',
        LLDP_REMOTE_SYSNAME => '1.0.8802.1.1.2.1.4.1.1.9'
    };

    $self->{commonOidDef} = $commOidDef;
    $self->{scalarOidDef} = $scalarOidDef;
    $self->{tableOidDef}  = $tableOidDef;

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

#提供给外部调用，通过此方法增加或修改单值OID的设置
#例如：addScalarOid(SN=>'1.3.6.1.4.1.2011.10.2.6.1.2.1.1.2.0', PORTS_COUNT=>'1.3.6.1.2.1.2.1.0');
sub addScalarOid {
    my ( $self, %args ) = @_;
    my $scalarOidDef = $self->{scalarOidDef};

    foreach my $key ( keys(%args) ) {
        $scalarOidDef->{$key} = $args{$key};
    }
}

#提供给外部调用，通过此方法增加或修改列表值OID的设置
#例如：addTableOid(PORTS_TABLE => [ { DESC => '1.3.6.1.2.1.2.2.1.2' }, { MAC => '1.3.6.1.2.1.2.2.1.6' } ]);
sub addTableOid {
    my ( $self, %args ) = @_;
    my $tableOidDef = $self->{tableOidDef};

    foreach my $key ( keys(%args) ) {
        $tableOidDef->{$key} = $args{$key};
    }
}

sub _errCheck {
    my ( $self, $queryResult, $oid ) = @_;
    my $snmp = $self->{snmpSession};
    if ( not defined($queryResult) ) {
        my $errMsg = sprintf( "WARN: %s, %s\n", $snmp->error(), $oid );
        print($errMsg);
    }
}

#get simple oid value
sub _getScalar {
    my ($self)       = @_;
    my $snmp         = $self->{snmpSession};
    my $scalarOidDef = $self->{scalarOidDef};

    my $value;

    my @scalarOids = ();
    foreach my $attr ( keys(%$scalarOidDef) ) {
        my $val = $scalarOidDef->{$attr};

        #支持单值oid可以定义多个oid进行尝试查询
        if ( ref($val) eq 'ARRAY' ) {
            push( @scalarOids, @$val );
        }
        else {
            push( @scalarOids, $val );
        }
    }

    my $result = $snmp->get_request( -varbindlist => \@scalarOids, );

    my $data = $self->{DATA};
    foreach my $attr ( keys(%$scalarOidDef) ) {
        my $oidDesc;
        my $oidVal;
        my $val = $scalarOidDef->{$attr};
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
            $oidDesc = join( ',', @$val );

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
}

#get table values from 1 or more than table oid
sub _getTable {
    my ($self)      = @_;
    my $snmp        = $self->{snmpSession};
    my $tableOidDef = $self->{tableOidDef};

    foreach my $attrName ( keys(%$tableOidDef) ) {
        my @attrTable = ();    #每个属性会生成一个table

        my $oidEntrys = $tableOidDef->{$attrName};
        foreach my $oidEntry (@$oidEntrys) {
            while ( my ( $name, $oid ) = each(%$oidEntry) ) {
                my $table = $snmp->get_table( -baseoid => $oid );
                $self->_errCheck( $table, $oid );

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
        }

        $self->{DATA}->{$attrName} = \@attrTable;
    }

    return;
}

sub _getPortIdx {
    my ($self)     = @_;
    my $snmp       = $self->{snmpSession};
    my $commOidDef = $self->{commonOidDef};

    my $portIdxToSeqMap = {};                                                      #序号到数字索引号的映射
    my $portIdxInfo = $snmp->get_table( -baseoid => $commOidDef->{PORT_INDEX} );
    $self->_errCheck( $portIdxInfo, $commOidDef->{PORT_INDEX} );

    #.1.3.6.1.2.1.17.1.4.1.2.1 = INTEGER: 514 #oid最后一位是序号，值是数字索引
    while ( my ( $oid, $val ) = each(%$portIdxInfo) ) {
        if ( $oid =~ /(\d+)$/ ) {
            $portIdxToSeqMap->{$val} = $1;
        }
    }

    return $portIdxToSeqMap;
}

sub _getPorts {
    my ($self)     = @_;
    my $snmp       = $self->{snmpSession};
    my $commOidDef = $self->{commonOidDef};

    my $portIdxToSeqMap = $self->_getPortIdx();

    my $portIdxToNameMap = {};
    my $portDescInfo = $snmp->get_table( -baseoid => $commOidDef->{PORT_DESC} );
    $self->_errCheck( $portDescInfo, $commOidDef->{PORT_DESC} );

    #.1.3.6.1.2.1.2.2.1.2.770 = STRING: Ethernet0/3
    while ( my ( $oid, $val ) = each(%$portDescInfo) ) {
        if ( $oid =~ /(\d+)$/ ) {
            $portIdxToNameMap->{$1} = $val;
        }
    }

    my $portIdxMap  = {};
    my $portSeqMap  = {};
    my @ports       = ();
    my $portMacInfo = $snmp->get_table( -baseoid => $commOidDef->{PORT_MAC} );
    $self->_errCheck( $portMacInfo, $commOidDef->{PORT_MAC} );

    #.1.3.6.1.2.1.2.2.1.6.514 => 0x000fe255d930
    while ( my ( $oid, $val ) = each(%$portMacInfo) ) {
        if ( $oid =~ /(\d+)$/ ) {
            my $idx = $1;

            #返回的值是16进制字串，需要去掉开头的0x以及每两个字节插入':'
            if ( $val !~ /\x00/ ) {
                $val = substr( $val, 2 );
                $val =~ s/..\K(?=.)/:/sg;
            }
            else {
                $val = '';
            }
            my $seq = $portIdxToSeqMap->{$idx};

            my $portInfo = {};
            $portInfo->{INDEX} = $idx;
            $portInfo->{SEQ}   = $seq;
            $portInfo->{NAME}  = $portIdxToNameMap->{$idx};
            $portInfo->{MAC}   = $val;

            push( @ports, $portInfo );

            $portIdxMap->{$idx} = $portInfo;
            $portSeqMap->{$seq} = $portInfo;
        }
    }

    $self->{DATA}->{PORTS} = \@ports;
    $self->{portIdxMap}    = $portIdxMap;
    $self->{portSeqMap}    = $portSeqMap;
}

sub _decimalMacToHex {
    my ( $self, $decimalMac ) = @_;

    my @hexParts = ();
    my @parts = split( /\./, $decimalMac );
    foreach my $part (@parts) {
        my $hexPart = sprintf( "%02x", $part );
        push( @hexParts, $hexPart );
    }

    my $mac;
    if ( scalar(@hexParts) > 1 ) {
        $mac = join( ':', @hexParts );
    }

    return $mac;
}

sub _getMacTable {
    my ($self)     = @_;
    my $snmp       = $self->{snmpSession};
    my $commOidDef = $self->{commonOidDef};

    my $portToMacMap = {};
    my $macTableInfo = $snmp->get_table( -baseoid => $commOidDef->{MAC_TABLE} );
    $self->_errCheck( $macTableInfo, $commOidDef->{MAC_TABLE} );

    #.1.3.6.1.2.1.17.4.3.1.2.228.112.184.173.172.60 = INTEGER: 2
    #最后6段是远端的mac地址，值是端口序号

    my $portSeqMap = $self->{portSeqMap};

    while ( my ( $oid, $val ) = each(%$macTableInfo) ) {
        if ( $oid =~ /(\d+\.\d+\.\d+\.\d+\.\d+\.\d+)$/ ) {
            my $mac      = $self->_decimalMacToHex($1);
            my $portInfo = $portSeqMap->{$val};
            my $portDesc = $portInfo->{NAME};

            my $portMacs = $portToMacMap->{$portDesc};
            if ( not defined($portMacs) ) {
                $portMacs = [];
                $portToMacMap->{$portDesc} = $portMacs;
            }
            push( @$portMacs, $mac );
        }
    }

    $self->{DATA}->{MAC_TABLE} = $portToMacMap;
}

sub _getLLDP {
    my ($self)     = @_;
    my $snmp       = $self->{snmpSession};
    my $commOidDef = $self->{commonOidDef};

    #获取邻居关系的本地端口名称列表（怀疑，这里的端口的idx和port信息里是一样的，如果是这样这里就不用采了
    my $portSeqToName = {};
    my $localPortInfo = $snmp->get_table( -baseoid => $commOidDef->{LLDP_LOCAL_PORT} );
    $self->_errCheck( $localPortInfo, $commOidDef->{LLDP_LOCAL_PORT} );

    #iso.0.8802.1.1.2.1.3.7.1.3.47=STRING:"Ten-GigabitEthernet1/0/47"
    #iso.0.8802.1.1.2.1.3.7.1.3.48=STRING:"Ten-GigabitEthernet1/0/48"
    while ( my ( $oid, $val ) = each(%$localPortInfo) ) {

        #oid中最后的一位数字是端口号
        if ( $oid =~ /(\d+)$/ ) {
            $portSeqToName->{$1} = $val;
        }
    }

    my $remoteSysInfoMap = {};
    my $remoteSysNameInfo = $snmp->get_table( -baseoid => $commOidDef->{LLDP_REMOTE_SYSNAME} );
    $self->_errCheck( $remoteSysNameInfo, $commOidDef->{LLDP_REMOTE_SYSNAME} );

    #iso.0.8802.1.1.2.1,4.1.1.9.569467705.48.1=STRING:"DCA_MAN_CSW_9850_02"
    #iso.0.8802.1.1.2.1.4.1.1.9.1987299041.47.1-STRING:"DCA_MAN_CSW_9850_01"
    while ( my ( $oid, $val ) = each(%$remoteSysNameInfo) ) {
        if ( $oid =~ /(\d+\.\d+)$/ ) {
            $remoteSysInfoMap->{$1} = $val;
        }
    }

    my @relations;
    my $remotePortInfo = $snmp->get_table( -baseoid => $commOidDef->{LLDP_REMOTE_PORT} );
    $self->_errCheck( $remotePortInfo, $commOidDef->{LLDP_REMOTE_PORT} );

    #iso.0.8802.1.1.2.1.4.1.1.7.569467705.47.1-STRING:"Ten-GigabitEtheznet1/1/6"
    #iso.0.8802.1.1.2.1.4.1.1.7.569467705.48.1-STRING:"Ten-GigabitEtheznet1/1/6"
    while ( my ( $oid, $val ) = each(%$remotePortInfo) ) {
        if ( $oid =~ /(\d+)\.(\d+)$/ ) {
            my $relation = {};
            $relation->{LOCAL_NAME} = $self->{DATA}->{DEV_NAME};
            $relation->{LOCAL_PORT} = $portSeqToName->{$1};

            $relation->{REMOTE_NAME} = $remoteSysInfoMap->{"$1.$2"};
            $relation->{REMOTE_PORT} = $val;
            push( @relations, $relation );
        }
    }

    $self->{DATA}->{RELATIONS} = \@relations;
}

sub collect {
    my ($self) = @_;

    $self->_getScalar();
    $self->_getTable();
    $self->_getPorts();
    $self->_getMacTable();
    $self->_getLLDP();

    return $self->{DATA};
}

1;

