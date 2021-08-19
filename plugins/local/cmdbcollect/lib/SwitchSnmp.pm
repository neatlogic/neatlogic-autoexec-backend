#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package SwitchSnmp;

use strict;
use File::Basename;
use JSON;
use Net::SNMP qw(:snmp);
use Data::Dumper;

my $BRANDS = [ 'HuaWei', 'Cisco', 'H3C', 'HillStone', 'Juniper' ];

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
    my $tableOidDef = {

        #PORTS_TABLE_FOR_TEST => [ { NAME => '1.3.6.1.2.1.2.2.1.2' }, { MAC => '1.3.6.1.2.1.2.2.1.6' } ]
    };

    #通用列表值定义, 这部分不提供给外部修改
    my $commOidDef = {

        #端口信息
        PORT_INDEX        => '1.3.6.1.2.1.17.1.4.1.2',
        PORT_NAME         => '1.3.6.1.2.1.2.2.1.2',
        PORT_TYPE         => '1.3.6.1.2.1.2.2.1.3',
        PORT_MAC          => '1.3.6.1.2.1.2.2.1.6',
        PORT_ADMIN_STATUS => '1.3.6.1.2.1.2.2.1.7',
        PORT_OPER_STATUS  => '1.3.6.1.2.1.2.2.1.8',
        PORT_SPEED        => '1.3.6.1.2.1.2.2.1.5',
        PORT_MTU          => '1.3.6.1.2.1.2.2.1.4',

        #MAC地址和端口对照表
        MAC_TABLE => '1.3.6.1.2.1.17.4.3.1.2',

        #交换机邻居表
        LLDP_LOCAL_PORT     => '1.0.8802.1.1.2.1.3.7.1.3',
        LLDP_REMOTE_PORT    => '1.0.8802.1.1.2.1.4.1.1.7',
        LLDP_REMOTE_SYSNAME => '1.0.8802.1.1.2.1.4.1.1.9',

        #Cisco CDP 邻居表
        CDP_REMOTE_SYSNAME  => '1.3.6.1.4.1.9.9.23.1.2.1.1.6',
        CDP_REMOTE_PORT     => '1.3.6.1.4.1.9.9.23.1.2.1.1.7',
        CDP_TYPE            => '1.3.6.1.4.1.9.9.23.1.2.1.1.3',
        CDP_IP              => '1.3.6.1.4.1.9.9.23.1.2.1.1.4'
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

sub setCommonOid {
    my ( $self, %args ) = @_;
    my $commonOidDef = $self->{commOidDef};

    foreach my $key ( keys(%args) ) {
        $commonOidDef->{$key} = $args{$key};
    }
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

#根据文件顶部预定义的$BRANDS匹配sysDescr信息，得到设备的品牌
sub _getBrand {
    my ($self) = @_;
    my $snmp = $self->{snmpSession};

    my $sysDescrOid = '1.3.6.1.2.1.1.1.0';

    my $sysDescr;
    my $brand;
    my $result = $snmp->get_request( -varbindlist => [$sysDescrOid] );
    if ( $self->_errCheck( $result, $sysDescrOid ) ) {
        die("ERROR: Snmp request failed.\n");
    }
    else {
        $sysDescr = $result->{$sysDescrOid};
        foreach my $aBrand (@$BRANDS) {
            if ( $sysDescr =~ /$aBrand/is ) {
                $brand = $aBrand;
            }
        }
    }

    if ( not defined($brand) ) {
        print("WARN: Can not get predefined brand from sysdescr:\n$sysDescr\n");
        $self->{DATA}->{BRAND} = undef;
        $self->{DATA}->{APP_TYPE} = undef;
    }
    else {
        $self->{DATA}->{BRAND} = $brand;
        $self->{DATA}->{APP_TYPE} = $brand;
    }

    return $brand;
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

    my @ports;
    my $portsMap   = {};
    my $portIdxMap = {};
    my $portSeqMap = {};

    my $portIdxToSeqMap = $self->_getPortIdx();
    while ( my ( $idx, $seq ) = each(%$portIdxToSeqMap) ) {
        my $portInfo = { INDEX => $idx, SEQ => $seq };
        $portsMap->{$idx}   = $portInfo;
        $portIdxMap->{$idx} = $portInfo;
        $portSeqMap->{$seq} = $portInfo;
    }

    my $portStatusMap = {
        1 => 'up',
        2 => 'down',
        3 => 'testing'
    };

    my $portTypeMap = {
        1  => 'other(1)',
        2  => 'regular1822(2)',
        3  => 'hdh1822(3)',
        4  => 'ddn-x25(4)',
        5  => 'rfc877-x25(5)',
        6  => 'ethernet-csmacd(6)',
        7  => 'iso88023-csmacd(7)',
        8  => 'iso88024-tokenBus(8)',
        9  => 'iso88025-tokenRing(9)',
        10 => 'iso88026-man(10)',
        11 => 'starLan(11)',
        12 => 'proteon-10Mbit(12)',
        13 => 'proteon-80Mbit(13)',
        14 => 'hyperchannel(14)',
        15 => 'fddi(15)',
        16 => 'lapb(16)',
        17 => 'sdlc(17)',
        18 => 'ds1(18)',
        19 => 'e1(19)',
        20 => 'basicISDN(20)',
        21 => 'primaryISDN(21)',
        22 => 'propPointToPointSerial(22)',
        23 => 'ppp(23)',
        24 => 'softwareLoopback(24)',
        25 => 'eon(25)',
        26 => 'ethernet-3Mbit(26)',
        27 => 'nsip(27)',
        28 => 'slip(28)',
        29 => 'ultra(29)',
        30 => 'ds3(30)',
        31 => 'sip(31)',
        32 => 'frame-relay(32)'
    };

    foreach my $portInfoKey ( 'TYPE', 'NAME', 'MAC', 'ADMIN_STATUS', 'OPER_STATUS', 'SPEED', 'MTU' ) {
        my $result = $snmp->get_table( -baseoid => $commOidDef->{"PORT_$portInfoKey"} );
        $self->_errCheck( $result, $commOidDef->{"PORT_$portInfoKey"} );

        #.1.3.6.1.2.1.2.2.1.6.514 => 0x000fe255d930
        #.1.3.6.1.2.1.2.2.1.2.770 = STRING: Ethernet0/3
        #.1.3.6.1.2.1.2.2.1.8.770 = INTEGER: down(2)
        while ( my ( $oid, $val ) = each(%$result) ) {
            if ( $oid =~ /(\d+)$/ ) {
                my $idx      = $1;
                my $portInfo = $portsMap->{$idx};
                if ( not defined($portInfo) ){
                    $portInfo = { INDEX => $idx, SEQ => undef };
                }
                
                if ( $portInfoKey eq 'MAC' ) {

                    #返回的值是16进制字串，需要去掉开头的0x以及每两个字节插入':'
                    if ( $val !~ /\x00/ ) {
                        $val = substr( $val, 2 );
                        $val =~ s/..\K(?=.)/:/sg;
                    }
                    else {
                        $val = '';
                    }
                }
                elsif ( $portInfoKey eq 'ADMIN_STATUS' or $portInfoKey eq 'OPER_STATUS' ) {
                    $val = $portStatusMap->{$val};
                }
                elsif ( $portInfoKey eq 'TYPE' ) {
                    $val = $portTypeMap->{$val};
                }
                elsif ( $portInfoKey eq 'SPEED' ) {
                    $val = $val / 1000 / 1000;
                }

                $portInfo->{$portInfoKey} = $val;
            }
        }
    }

    my @ports = values(%$portsMap);
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

    my @macTable = ();
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

            push(@macTable, {PORT=>$portDesc, REMOTE_MAC=>$mac});
        }
    }

    $self->{DATA}->{MAC_TABLE} = \@macTable;
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

    my @neighbors;
    my $remotePortInfo = $snmp->get_table( -baseoid => $commOidDef->{LLDP_REMOTE_PORT} );
    $self->_errCheck( $remotePortInfo, $commOidDef->{LLDP_REMOTE_PORT} );

    #iso.0.8802.1.1.2.1.4.1.1.7.569467705.47.1-STRING:"Ten-GigabitEtheznet1/1/6"
    #iso.0.8802.1.1.2.1.4.1.1.7.569467705.48.1-STRING:"Ten-GigabitEtheznet1/1/6"
    while ( my ( $oid, $val ) = each(%$remotePortInfo) ) {
        if ( $oid =~ /(\d+)\.(\d+)$/ ) {
            my $neighbor = {};
            $neighbor->{LOCAL_NAME} = $self->{DATA}->{DEV_NAME};
            $neighbor->{LOCAL_PORT} = $portSeqToName->{$1};

            $neighbor->{REMOTE_NAME} = $remoteSysInfoMap->{"$1.$2"};
            $neighbor->{REMOTE_PORT} = $val;
            push( @neighbors, $neighbor );
        }
    }

    $self->{DATA}->{NEIGHBORS} = \@neighbors;
}

sub _getCDP {
    my ($self)     = @_;
    my $snmp       = $self->{snmpSession};
    my $commOidDef = $self->{commonOidDef};


    my $remoteSysInfoMap = {};
    my $remoteSysNameInfo = $snmp->get_table( -baseoid => $commOidDef->{CDP_REMOTE_SYSNAME} );
    $self->_errCheck( $remoteSysNameInfo, $commOidDef->{CDP_REMOTE_SYSNAME} );

    #iso.0.8802.1.1.2.1,4.1.1.9.569467705.48.1=STRING:"DCA_MAN_CSW_9850_02"
    #iso.0.8802.1.1.2.1.4.1.1.9.1987299041.47.1-STRING:"DCA_MAN_CSW_9850_01"
    while ( my ( $oid, $val ) = each(%$remoteSysNameInfo) ) {
        if ( $oid =~ /(\d+\.\d+)$/ ) {
            $remoteSysInfoMap->{$1} = $val;
        }
    }

    my @neighbors;
    my $remotePortInfo = $snmp->get_table( -baseoid => $commOidDef->{CDP_REMOTE_PORT} );
    $self->_errCheck( $remotePortInfo, $commOidDef->{CDP_REMOTE_PORT} );

    #iso.0.8802.1.1.2.1.4.1.1.7.569467705.47.1-STRING:"Ten-GigabitEtheznet1/1/6"
    #iso.0.8802.1.1.2.1.4.1.1.7.569467705.48.1-STRING:"Ten-GigabitEtheznet1/1/6"
    while ( my ( $oid, $val ) = each(%$remotePortInfo) ) {
        if ( $oid =~ /(\d+)\.(\d+)$/ ) {
            my $portIdx = $1;
            my $localPortInfo = $self->{portIdxMap}->{$portIdx};
            my $neighbor = {};
            $neighbor->{LOCAL_NAME} = $self->{DATA}->{DEV_NAME};
            $neighbor->{LOCAL_PORT} = $localPortInfo->{$portIdx};

            $neighbor->{REMOTE_NAME} = $remoteSysInfoMap->{"$portIdx.$2"};
            $neighbor->{REMOTE_PORT} = $val;
            push( @neighbors, $neighbor );
        }
    }

    $self->{DATA}->{NEIGHBORS} = \@neighbors;
}

sub collect {
    my ($self) = @_;

    my $brand = $self->_getBrand();
    print("INFO: SWitch brand: $brand.\n");

    my $pkgFile = __FILE__ ;
    my $libPath = dirname($pkgFile);
    my $switchIns;
    my $switchClass = "Switch$brand";
    if ( -e "$libPath/$switchClass.pm" ) {
        print("INFO: Has defined class Switch$brand, try to load it.\n");
        eval {
            require "$switchClass.pm";
            #our @ISA = ($switchClass);
            $switchIns = $switchClass->new();

            #调用对应品牌的pm进行采集前的oid的设置
            $switchIns->before($self);
        };
        if ($@) {
            print("WARN: Load $switchClass failed, $@");
        }
        else{
            print("INFO: Class SWitch$brand loaded.\n");
        }
    }

    $self->_getScalar();
    $self->_getTable();
    $self->_getPorts();
    $self->_getMacTable();

    if ($brand =~ /Cisco/i){
        $self->_getCDP();
    }
    else{
        $self->_getLLDP();
    }

    if ( defined($switchIns) ) {

        #调用对应品牌的pm进行采集后的数据处理，用户补充数据或者调整数据
        $switchIns->after($self);
    }

    return $self->{DATA};
}

1;

