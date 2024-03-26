#!/usr/bin/perl
use FindBin;

use lib $FindBin::Bin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../plib/lib/perl5";

use strict;

package FCSwitchBrocade;

use FCSwitchBase;
our @ISA = qw(FCSwitchBase);

use Net::OpenSSH;

#类的初始化
sub init {
    my ($self) = @_;
    my $nodeInfo = $self->{node};
    $self->{MGMT_IP} = $nodeInfo->{host};

    $self->{portIdent2wwpnMap}        = {};
    $self->{portPeerWwpn2wwpnMap}     = {};
    $self->{portPeerWwpn2portIndtMap} = {};
    $self->{portPeerWwpn2portNoMap}   = {};
    $self->{portIdent2peerwwpnMap}    = {};
    $self->{portNum2AliasMap}         = {};
    $self->{wwpn2Aliasmap}            = {};
    $self->{zonesMap}                 = {};

    return;
}

sub getBaseInfo {
    my ($self) = @_;

    my $data = $self->{DATA};
    my $ssh  = $self->{ssh};

    if ( not defined( $data->{UPTIME} ) ) {

        #uptime ：显示交换机工作时间
        #00:22:02 up 272 days, 23:01, 1 user, load average: 0.03, 0.05, 0.00
        #326 days, 01:11:41.00
        my @uptimeLines = $ssh->capture('uptime');
        foreach my $line (@uptimeLines) {

            #up 272 days, 23:01
            if ( $line =~ /up\s+(\d+)\s+days,\s+([\d:]+)/ ) {
                my $upDays    = $1;
                my $remainder = $2;
                $data->{UPTIME} = "$upDays, $remainder";
            }
        }
    }

    # Appl     Primary/Secondary Versions
    # ------------------------------------------
    # FOS      v8.1.2g
    #          v8.1.2g
    if ( not defined( $data->{FIRMWARE_VERSION} ) ) {
        my @firmWareInfoLines = $ssh->capture('firmwareshow');
        my $fmVerInfo         = $firmWareInfoLines[-1];
        $fmVerInfo =~ s/^\s+|\s+$//g;
        $data->{FIRMWARE_VERSION} = $fmVerInfo;
    }

    my @chassisLines = $ssh->capture('chassisshow');
    foreach my $line (@chassisLines) {

        #Factory Serial Num:     CCD4004N03F
        if ( $line =~ /.*Serial\s+Num:\s*(\S+)/ ) {
            my $sn = $1;
            $sn =~ s/^\s+|\s+$//g;
            $data->{SN} = $sn;
        }

        # Manufacture:            Day: 11  Month:  1  Year: 2017
        elsif ( $line =~ /Manufacture:\s*Day:\s*(\d+)\s*Month:\s*(\d+)\s*Year:\s*(\d+)/i ) {
            my $manufactureDate = "$3-$2-$1";
            $data->{MANUFACTURE_DATE} = $manufactureDate;
        }

        # Update:                 Day:  1  Month:  2  Year: 2024
        elsif ( $line =~ /Update:\s*Day:\s*(\d+)\s*Month:\s*(\d+)\s*Year:\s*(\d+)/i ) {
            my $updateDate = "$3-$2-$1";
            $data->{UPDATAE_DATE} = $updateDate;
        }
    }
}

sub getPortDetail {
    my ( $self, $portIdx, $portNo, $portIdent, $portInfo ) = @_;

    my $portIdent2wwpnMap        = $self->{portIdent2wwpnMap};
    my $portIdent2peerwwpnMap    = $self->{portIdent2peerwwpnMap};
    my $portPeerWwpn2wwpnMap     = $self->{portPeerWwpn2wwpnMap};
    my $portPeerWwpn2portIndtMap = $self->{portPeerWwpn2portIndtMap};
    my $portPeerWwpn2portNoMap   = $self->{portPeerWwpn2portNoMap};
    my $ssh                      = $self->{ssh};
    my @portShowLines            = $ssh->capture("portshow $portIdx");

    # portIndex:   9
    # portName: port9
    # portHealth: Fabric vision license not present. Please install the license and retry the operation.

    # Authentication: None
    # portDisableReason: None
    # portCFlags: 0x1
    # portFlags: 0x4001	 PRESENT U_PORT LED
    # LocalSwcFlags: 0x0
    # portType:  24.0
    # POD Port: Port is licensed
    # portState: 2	Offline
    # Protocol: FC
    # portPhys:  4	No_Light 	portScn:   0
    # port generation number:    0
    # state transition count:    0

    # portId:    040900
    # portIfId:    43020009
    # portWwn:   20:09:c4:f5:7c:b0:c3:5c
    # portWwn of device(s) connected:

    # Distance:  normal
    # portSpeed: N16Gbps

    # FEC: Inactive
    # Credit Recovery: Inactive
    # LE domain: 0
    # Peer beacon: Off
    # FC Fastwrite: OFF
    # Interrupts:        0          Link_failure: 0          Frjt:         0
    # Unknown:           0          Loss_of_sync: 0          Fbsy:         0
    # Lli:               2          Loss_of_sig:  0
    # Proc_rqrd:         0          Protocol_err: 0
    # Timed_out:         0          Invalid_word: 0
    # Rx_flushed:        0          Invalid_crc:  0
    # Tx_unavail:        0          Delim_err:    0
    # Free_buffer:       0          Address_err:  0
    my $portShowAttrsMap = {};
    for ( my $i = 0 ; $i <= $#portShowLines ; $i++ ) {
        my $line = $portShowLines[$i];
        if ( $line =~ /^portWwn: / ) {
            if ( $line =~ /^portWwn:\s*(\S+)/ ) {
                $portShowAttrsMap->{portWwn} = $1;
            }
        }

        #portWwn of device(s) connected
        elsif ( $line =~ /portWwn of device\(s\) connected/ ) {
            my @peerWWPNs = ();
            for ( my $j = $i + 1 ; $j <= $#portShowLines ; $j++ ) {
                my $nextLine = lc( $portShowLines[$j] );
                $nextLine =~ s/^\s+|\s*$//g;
                if ( $nextLine eq '' ) {
                    last;
                }
                while ( $nextLine =~ /([0-9a-f][0-9a-f])(:[0-9a-f]{2}){7}/g ) {
                    my $peerWWPN = $nextLine;
                    push( @peerWWPNs, $peerWWPN );
                }
                $i = $j;
            }
            $portShowAttrsMap->{peerWWPNS} = \@peerWWPNs;
        }
        elsif ( $line =~ /^([^:]+):\s*([^:]+?)\s*$/ ) {
            $portShowAttrsMap->{$1} = $2;
        }
        else {
            while ( $line =~ /([^:]+):\s*([^:]+?)\s+(?=\w+:|$)/sg ) {
                $portShowAttrsMap->{$1} = $2;
            }
        }
    }
    my $portWwn = $portShowAttrsMap->{portWwn};
    $portInfo->{WWPN} = $portWwn;
    $portIdent2wwpnMap->{$portIdent} = $portWwn;

    $portInfo->{NAME} = $portShowAttrsMap->{portName};

    my $peerWWPNs = $portShowAttrsMap->{peerWWPNS};
    $portInfo->{PEER_WWPNS} = $peerWWPNs;
    if ( scalar(@$peerWWPNs) > 0 ) {
        my $peerWWPN = $$peerWWPNs[0];
        $portInfo->{PEER_WWPN}                 = $peerWWPN;
        $portPeerWwpn2wwpnMap->{$peerWWPN}     = $portWwn;
        $portPeerWwpn2portIndtMap->{$peerWWPN} = $portIdent;
        $portPeerWwpn2portNoMap->{$peerWWPN}   = $portNo;
        $portIdent2peerwwpnMap->{$portIdent}   = $peerWWPN;
    }
    else {
        $portInfo->{PEER_WWPN} = undef;
    }

    $portInfo->{ADMIN_STATUS} = ( split( /\s+/, $portShowAttrsMap->{portState} ) )[-1];
    $portInfo->{PHY_STATUS}   = ( split( /\s+/, $portShowAttrsMap->{portPhys} ) )[-1];

    my $portSpeed = $portShowAttrsMap->{portSpeed};
    if ( $portSpeed =~ /(\d+)G/ ) {
        $portSpeed = int($1);
    }
    elsif ( $portSpeed =~ /(\d+)T/ ) {
        $portSpeed = 1024 * int($1);
    }
    $portInfo->{SPEED} = $portSpeed;

    if ( $self->{inspect} == 1 ) {
        $portInfo->{Interrupts}   = $portShowAttrsMap->{Interrupts};
        $portInfo->{Unknown}      = $portShowAttrsMap->{Unknown};
        $portInfo->{Lli}          = $portShowAttrsMap->{Lli};
        $portInfo->{Proc_rqrd}    = $portShowAttrsMap->{Proc_rqrd};
        $portInfo->{Timed_out}    = $portShowAttrsMap->{Timed_out};
        $portInfo->{Rx_flushed}   = $portShowAttrsMap->{Rx_flushed};
        $portInfo->{Tx_unavail}   = $portShowAttrsMap->{Tx_unavail};
        $portInfo->{Free_buffer}  = $portShowAttrsMap->{Free_buffer};
        $portInfo->{Link_failure} = $portShowAttrsMap->{Link_failure};
        $portInfo->{Loss_of_sync} = $portShowAttrsMap->{Loss_of_sync};
        $portInfo->{Loss_of_sig}  = $portShowAttrsMap->{Loss_of_sig};
        $portInfo->{Protocol_err} = $portShowAttrsMap->{Protocol_err};
        $portInfo->{Invalid_word} = $portShowAttrsMap->{Invalid_word};
        $portInfo->{Invalid_crc}  = $portShowAttrsMap->{Invalid_crc};
        $portInfo->{Delim_err}    = $portShowAttrsMap->{Delim_err};
        $portInfo->{Address_err}  = $portShowAttrsMap->{Address_err};
        $portInfo->{Frjt}         = $portShowAttrsMap->{Frjt};
        $portInfo->{Fbsy}         = $portShowAttrsMap->{Fbsy};
    }
}

sub getSwitchShow {
    my ($self) = @_;

    my $data              = $self->{DATA};
    my $ssh               = $self->{ssh};
    my $portNum2AliasMap  = $self->{portNum2AliasMap};
    my $wwpn2Aliasmap     = $self->{wwpn2Aliasmap};
    my $cascadeSwitchWwnn = '';

    my @showInfoLines = $ssh->capture('switchshow');

    # switchName:	SW6505
    # switchType:	118.1
    # switchState:	Online
    # switchMode:	Native
    # switchRole:	Subordinate
    # switchDomain:	4
    # switchId:	fffc04
    # switchWwn:	10:00:c4:f5:7c:31:ca:71
    # zoning:		ON (cfg-cs-E16)
    # switchBeacon:	OFF
    # HIF Mode:	OFF
    # LS Attribute:	[Inherited FID: 128]

    # Index Port Address  Media Speed   State       Proto
    # ==================================================
    #    0   0   040000   id    N8 	  Online      FC  E-Port  10:00:38:ba:b0:29:73:08 "cs_36_E16"
    #    1   1   040100   id    N8 	  Online      FC  E-Port  10:00:38:ba:b0:29:73:08 "cs_36_E16" (upstream)
    #    2   2   040200   id    N8 	  Online      FC  F-Port  10:00:00:10:9b:d8:03:ed
    #    3   3   040300   id    N8 	  Online      FC  F-Port  10:00:00:10:9b:db:10:d2
    #    4   4   040400   id    N8 	  Online      FC  F-Port  10:00:00:10:9b:d8:04:3f
    #    5   5   040500   id    N8 	  Online      FC  F-Port  10:00:00:10:9b:de:07:4e
    my $swAttrs       = {};
    my @portInfoLines = ();
    my $domainId      = 1;
    my $fcPortsCount  = 0;
    my $ePortsCount   = 0;
    foreach my $line (@showInfoLines) {
        $line =~ s/^\s*|\s*$//g;
        if ( $line eq '' ) {
            next;
        }
        if ( $line =~ /^([\w\s]+):\s*(.*?)$/ ) {
            $swAttrs->{$1} = $2;
        }
        else {
            push( @portInfoLines, $line );
        }
    }

    $domainId = $swAttrs->{switchDomain};
    if ( not defined( $data->{DOMAIN_ID} ) ) {
        $data->{DOMAIN_ID} = $domainId;
    }

    if ( not defined( $data->{DEV_NAME} ) ) {
        $data->{DEV_NAME} = $swAttrs->{switchName};
    }
    if ( not defined( $data->{WWNN} ) ) {
        $data->{WWNN} = $swAttrs->{switchWwn};
    }
    if ( not defined( $data->{SWITCH_STATE} ) ) {
        $data->{SWITCH_STATE} = $swAttrs->{switchState};
    }

    my @ports          = ();
    my @portAttrTitles = split( /\s+/, $portInfoLines[0] );

    #加入header：Misc对应最后面没有列头的内容
    push( @portAttrTitles, 'Misc' );

    for ( my $i = 2 ; $i <= $#portInfoLines ; $i++ ) {
        my @portAttrsArray = split( /\s+/, $portInfoLines[$i], $#portAttrTitles + 1 );
        my $portAttrMap    = {};
        foreach ( my $k = 0 ; $k <= $#portAttrsArray ; $k++ ) {
            $portAttrMap->{ $portAttrTitles[$k] } = $portAttrsArray[$k];
        }
        if ( $portAttrMap->{Proto} eq 'FC' ) {
            $fcPortsCount = $fcPortsCount + 1;

            #TODO：标准格式是1,3(domainId,序号),需要进一步确认
            my $portIdent = $domainId . ',' . $portAttrMap->{Port};

            #TODO：WWNN、WWPN都不足16字节，需要确认如何处理
            my $portInfo = {
                _OBJ_CATEGORY => 'FCDEV',
                _OBJ_TYPE     => 'FCSWITCH-PORT',
                PORT          => int( $portAttrMap->{Port} ),
                DOMAIN_IDX    => $portIdent,
                SPEED         => $portAttrMap->{Speed},
                STATE         => $portAttrMap->{State}
            };

            #miscInfo
            #E-Port  10:00:38:ba:b0:29:73:08 "cs_36_E16" (upstream)
            #E-Port  10:00:c4:f5:7c:d4:a9:54 "SW6510" (downstream)
            #F-Port  10:00:00:10:9b:db:10:d2
            my @miscInfo = split( /\s+/, $portAttrMap->{Misc} );
            if ( $#miscInfo >= 1 ) {
                $portInfo->{TYPE} = $miscInfo[0];
                if ( $miscInfo[0] eq 'E-Port' ) {
                    $cascadeSwitchWwnn = $miscInfo[1];
                }
                $portInfo->{PEER_WWPN} = $miscInfo[1];
            }
            else {
                $portInfo->{PEER_WWPN} = undef;
            }

            $self->getPortDetail( $portAttrMap->{Index}, int( $portAttrMap->{Port} ), $portIdent, $portInfo );

            #使用cfgshow命令输出的alias信息，反算端口的别名
            my $portWwn   = $portInfo->{WWPN};
            my $portAlias = $portNum2AliasMap->{$portIdent};
            if ( not defined($portAlias) ) {
                $portAlias = $wwpn2Aliasmap->{$portWwn};
            }
            $portInfo->{ALIAS} = $portAlias;

            push( @ports, $portInfo );
        }
    }
    if ( not defined( $data->{PORTS_COUNT} ) ) {
        $data->{PORTS_COUNT} = $fcPortsCount;
    }

    #设置级联光纤交换机的wwnn
    $data->{CASCADE_SWITCHWWNN} = $cascadeSwitchWwnn;

    if ( not defined( $data->{LINK_TABLE} ) ) {
        my @linkTableList;
        foreach my $portInfo (@ports) {
            my $portName      = $portInfo->{NAME};
            my $wwpn          = $portInfo->{WWPN};
            my $peerWwpns     = $portInfo->{PEER_WWPNS};
            my $portLinkCount = scalar(@$peerWwpns);
            foreach my $peerWwpn (@$peerWwpns) {
                my $linkInfo = {};
                $linkInfo->{PORT_NAME}  = $portName;
                $linkInfo->{DOMAIN_IDX} = $portInfo->{DOMAIN_IDX};
                $linkInfo->{WWPN}       = $wwpn;
                $linkInfo->{WWNN}       = $data->{WWNN} . ':00:00:00:00:00:00:00:00';
                $linkInfo->{PEER_WWPN}  = $peerWwpn;
                $linkInfo->{LINK_COUNT} = $portLinkCount;

                push( @linkTableList, $linkInfo );
            }
        }

        $data->{LINK_TABLE} = \@linkTableList;
    }

    $data->{PORTS} = \@ports;
}

sub getCfgShow {
    my ($self) = @_;

    my $data       = $self->{DATA};
    my $domainId   = $data->{DOMAIN_ID};
    my $ssh        = $self->{ssh};
    my $mgmtIp     = $self->{MGMT_IP};
    my $sn         = $data->{SN};
    my $cfgInfoOut = $ssh->capture('cfgshow');

    # Defined configuration:
    #  cfg:	cfg-cs-E16
    # 		zone1; zone2; zone3; zone4; zone5; zone6; zone7; zone8; zone9;
    #         ...
    # 		zone125; zone126; zone127; zone128
    #  zone:	zone1	HW5500_100005_AP3; R940XA_GFYPXW3_dzyhdb1_slot7-L
    #  ...
    #  zone:	zone98	8205-E6C_6287CT_tlhxdb1_C4-T1; HW5500_100005_BP3
    #  zone:	zone99	8205-E6C_6287CT_tlhxdb1_C4-T1; HW5500_100006_AP3
    #  alias:	2288HV6_000001_qdrhdb2_slot5-L
    # 		10:00:00:10:9b:d6:f8:4b
    #  alias:	2288HV6_000002_ydzfdb2_slot5-L
    # 		10:00:00:10:9b:d6:fc:ae
    #  alias: HW5600_000005_L_0
    #                 1,0; 21:00:2c:55:d3:e7:f7:fd; 26:10:2c:55:d3:e7:f7:fd
    #  alias: HW5600_000005_L_1
    #                 1,1; 21:00:2c:55:d3:e7:f7:fd; 26:11:2c:55:d3:e7:f7:fd
    # 		21:00:f4:c7:aa:0d:cb:da
    #  ...
    #  alias:	R940XA_GFYPXW3_dzyhdb1_slot7-L
    # 		21:00:f4:c7:aa:0d:ca:a8
    # Effective configuration:
    #  cfg:   sw6510_55

    #  zone:  DELL_R940_181_HW5600_000005
    #                 20:00:f4:c7:aa:0f:df:4e
    #                 21:00:f4:c7:aa:0f:df:4e
    #                 1,0
    #                 21:00:2c:55:d3:e7:f7:fd
    #                 26:10:2c:55:d3:e7:f7:fd
    #                 1,1
    #                 26:11:2c:55:d3:e7:f7:fd
    #                 1,2
    #                 26:12:2c:55:d3:e7:f7:fd
    #                 1,3
    #                 26:13:2c:55:d3:e7:f7:fd
    #  ...
    #  zone:  DELL_R940_182_HW5600_000005
    #                 20:00:f4:c7:aa:0f:df:3c
    #                 21:00:f4:c7:aa:0f:df:3c
    #                 1,0
    #                 21:00:2c:55:d3:e7:f7:fd
    #                 26:10:2c:55:d3:e7:f7:fd
    #                 1,1
    #                 26:11:2c:55:d3:e7:f7:fd
    #                 1,2
    #                 26:12:2c:55:d3:e7:f7:fd
    #                 1,3
    #                 26:13:2c:55:d3:e7:f7:fd
    #切分开defined configuration和effective configuration
    my ( $definedConf, $effectiveConf ) = split( /Effective configuration:/, $cfgInfoOut );

    #抽取cfg、zone、alias配置
    my @cfgList          = ();
    my $zoneName2CfgMap  = ();
    my $zoneAliasMap     = {};
    my $aliasMap         = {};
    my $wwpn2Aliasmap    = $self->{wwpn2Aliasmap};
    my $portNum2AliasMap = $self->{portNum2AliasMap};
    while ( $definedConf =~ /(cfg|zone|alias):\s*(\S+)\s*(.*?)(?=(cfg|zone|alias))/isg ) {
        my $cfgType    = $1;
        my $cfgName    = $2;
        my $cfgContent = $3;
        $cfgContent =~ s/^\s*|\s*$//g;
        my @cfgItems = split( /\s*;\s*/, $cfgContent );
        if ( $cfgType eq 'cfg' ) {
            my @cfgItemList = ();
            foreach my $cfgItem (@cfgItems) {
                $zoneName2CfgMap->{$cfgItem} = $cfgName;
                push(
                    @cfgItemList,
                    {
                        _OBJ_CATEGORY => 'FCDEV',
                        _OBJ_TYPE     => 'FCSWITCH-ZONE',
                        NAME          => $cfgItem
                    }
                );
            }

            push(
                @cfgList,
                {
                    _OBJ_CATEGORY => 'FCDEV',
                    _OBJ_TYPE     => 'FCSWITCH-CFG',
                    NAME          => $cfgName,
                    ZONES         => \@cfgItemList
                }
            );
        }
        elsif ( $cfgType eq 'zone' ) {
            $zoneAliasMap->{$cfgName} = \@cfgItems;
        }
        elsif ( $cfgType eq 'alias' ) {
            $aliasMap->{$cfgName} = \@cfgItems;
            foreach my $cfgItem (@cfgItems) {
                if ( $cfgItem - ~/^\d+,\d+$/ ) {

                    #端口编号
                    $portNum2AliasMap->{$cfgItem} = $cfgName;
                }
                else {
                    #wwpn
                    $wwpn2Aliasmap->{$cfgItem} = $cfgName;
                }
            }
        }
    }

    my $zonesMap       = $self->{zonesMap};
    my @zoneList       = ();
    my @zoneMemberList = ();
    while ( my ( $zoneName, $zoneMembers ) = each(%$zoneAliasMap) ) {
        my @zoneWWPNS = ();
        foreach my $zoneMember (@$zoneMembers) {
            push( @zoneMemberList, { NAME => $zoneMember } );
            my $zoneMemberCfg = $aliasMap->{$zoneMember};
            if ( defined($zoneMemberCfg) ) {
                foreach my $cfgItem (@$zoneMemberCfg) {
                    my $zonePortInfo = {
                        _OBJ_CATEGORY => 'FCDEV',
                        _OBJ_TYPE     => 'FCSWITCH-PORT',
                        SN            => $data->{SN},
                        DOMAIN_IDX    => undef,
                        PORT          => undef,
                        WWPN          => undef
                    };

                    if ( $cfgItem =~ /^\d+,(\d+)$/ ) {
                        my $portNo = int($1);
                        $zonePortInfo->{DOMAIN_IDX} = $cfgItem;
                        $zonePortInfo->{PORT}       = $portNo;
                    }
                    else {
                        $zonePortInfo->{PEER_WWPN} = $cfgItem;
                    }
                    push( @zoneWWPNS, $zonePortInfo );
                }
            }
            else {
                print("WARN: Alias $zoneMember config not found.\n");
            }
        }
        my $zoneInfo = {
            _OBJ_CATEGORY => 'FCDEV',
            _OBJ_TYPE     => 'FCSWITCH-ZONE',
            NAME          => $zoneName,
            CFG_NAME      => $zoneName2CfgMap->{$zoneName},
            MEMBERS       => \@zoneMemberList,
            WWPN_MEMBERS  => \@zoneWWPNS
        };
        push( @zoneList, $zoneInfo );
        $zonesMap->{$zoneName} = $zoneInfo;
    }

    $data->{ZONES}   = \@zoneList;
    $data->{CONFIGS} = \@cfgList;

    return;
}

sub fillZoneMemberWwpn {
    my ($self) = @_;

    my $data                     = $self->{DATA};
    my $zoneList                 = $data->{ZONES};
    my $cascadeSwitchWwnn        = $data->{CASCADE_SWITCHWWNN};
    my $portIdent2wwpnMap        = $self->{portIdent2wwpnMap};
    my $portPeerWwpn2wwpnMap     = $self->{portPeerWwpn2wwpnMap};
    my $portPeerWwpn2portIndtMap = $self->{portPeerWwpn2portIndtMap};
    my $portPeerWwpn2portNoMap   = $self->{portPeerWwpn2portNoMap};
    my $portIdent2peerwwpnMap    = $self->{portIdent2peerwwpnMap};

    foreach my $zoneInfo (@$zoneList) {
        my @newWwpnMembers    = ();
        my $wwpnMembers       = $zoneInfo->{WWPN_MEMBERS};
        my $zoneName          = $zoneInfo->{NAME};
        my $wwpnZoneMap       = {};
        my $domain_idxZoneMap = {};
        my $peerwwpnZoneMap   = {};
        foreach my $wwpnMember (@$wwpnMembers) {
            if ( not defined( $wwpnMember->{PEER_WWPN} ) ) {
                if ( defined( $wwpnMember->{DOMAIN_IDX} ) ) {
                    my $domain_idx = $wwpnMember->{DOMAIN_IDX};
                    my $wwpn       = $portIdent2wwpnMap->{$domain_idx};
                    if ( $wwpn ne '' ) {
                        my $peerwwpn = $portIdent2peerwwpnMap->{$domain_idx};
                        if ( $peerwwpn ne '' ) {
                            $wwpnMember->{WWPN}      = $wwpn;
                            $wwpnMember->{PEER_WWPN} = $peerwwpn;

                            #去重
                            if ( $wwpnZoneMap->{$wwpn} ne 1 ) {
                                $wwpnZoneMap->{$wwpn} = 1;
                                push( @newWwpnMembers, $wwpnMember );
                            }
                        }
                        else {
                            print("WARN: domain_idx:$domain_idx 找到对应的本地端口wwpn,没有找到对应连接的对端端口wwpn\n");
                        }
                    }
                    else {
                        if ( $cascadeSwitchWwnn ne '' ) {
                            print("INFO: domain_idx:$domain_idx 没有找到对应的本地端口wwpn，是级联端口\n");
                            $wwpnMember->{SN} = undef;

                            #去重
                            if ( $domain_idxZoneMap->{$domain_idx} ne 1 ) {
                                $domain_idxZoneMap->{$domain_idx} = 1;
                                push( @newWwpnMembers, $wwpnMember );
                            }
                        }
                        else {
                            print("WARN: domain_idx:$domain_idx 没有找到对应的本地端口wwpn，是垃圾数据\n");
                        }
                    }
                }
            }
            else {
                #找到PEER_WWPN对应的本地端口的WWPN
                my $peerWWPN = $wwpnMember->{PEER_WWPN};
                my $wwpn     = $portPeerWwpn2wwpnMap->{$peerWWPN};
                if ( $wwpn ne '' ) {
                    $wwpnMember->{WWPN}       = $wwpn;
                    $wwpnMember->{DOMAIN_IDX} = $portPeerWwpn2portIndtMap->{$peerWWPN};
                    $wwpnMember->{PORT}       = $portPeerWwpn2portNoMap->{$peerWWPN};

                    #去重
                    if ( $wwpnZoneMap->{$wwpn} ne 1 ) {
                        $wwpnZoneMap->{$wwpn} = 1;
                        push( @newWwpnMembers, $wwpnMember );
                    }
                }
                else {
                    if ( $cascadeSwitchWwnn ne '' ) {
                        print("INFO: peerWWPN:$peerWWPN 没有找到peerwwpn对应的本地wwpn，是级联端口\n");
                        push( @newWwpnMembers, $wwpnMember );

                        #去重
                        if ( $peerwwpnZoneMap->{$peerWWPN} ne 1 ) {
                            $peerwwpnZoneMap->{$peerWWPN} = 1;
                            push( @newWwpnMembers, $wwpnMember );
                        }
                    }
                    else {
                        print("WARN: peerWWPN:$peerWWPN  没有找到peerwwpn对应的本地wwpn，垃圾数据\n");
                    }
                }
            }
        }
        $zoneInfo->{WWPN_MEMBERS} = \@newWwpnMembers;
    }
}

sub fillZoneDetailInCfg {
    my ($self) = @_;

    my $data       = $self->{DATA};
    my $configlist = $data->{CONFIGS};
    my $zoneList   = $data->{ZONES};
    my $zonesMap   = $self->{zonesMap};

    foreach my $configInfo (@$configlist) {
        my $configZoneList = $configInfo->{ZONES};
        my @newZoneList    = ();
        foreach my $zone (@$configZoneList) {
            my $zoneName = $zone->{NAME};
            my $zoneInfo = $zonesMap->{$zoneName};
            if ( defined($zoneInfo) ) {
                push( @newZoneList, $zoneInfo );
                print("INFO: CONFIG ZONENAME:$zoneName,找到对应的zone\n");
            }
        }
        $configInfo->{ZONES} = \@newZoneList;
    }
}

sub before {
    my ($self) = @_;

    #SN可能要调整，如果有多个可能，就在数组里添加
    #$self->addScalarOid( SN => [ '1.3.6.1.4.1.9.3.6.3.0', '1.3.6.1.4.1.9.5.1.2.19.0', '1.3.6.1.2.1.47.1.1.1.1.11.1001', '1.3.6.1.2.1.47.1.1.1.1.11.2001', '1.3.6.1.4.1.9.9.92.1.1.1.2.0' ] );
}

sub after {
    my ($self) = @_;

    my $mgmtIp     = $self->{MGMT_IP};
    my $nodeInfo   = $self->{node};
    my $sshAccount = $self->{sshAccount};

    if ( not %$sshAccount ) {
        print("WARN: SSH account not defined, can not collect detail information.\n");
    }

    if (%$sshAccount) {
        print("INFO: Try collect more information by ssh.\n");
        my $ssh = Net::OpenSSH->new(
            $mgmtIp,
            port        => $sshAccount->{protocolPort},
            user        => $sshAccount->{username},
            password    => $sshAccount->{password},
            timeout     => $self->{timeout},
            master_opts => [ -o => "StrictHostKeyChecking=no" ]
        );

        if ( $ssh->error ) {
            print( "ERROR: Can not establish ssh connection for $mgmtIp:$nodeInfo->{protocolPort}, " . $ssh->error . "\n" );
            exit(-1);
        }

        $self->{ssh} = $ssh;

        END {
            if ( defined($ssh) ) {
                $ssh->disconnect();
            }
        }

        #下面的方法调用数据关联，不可以更换顺序
        $self->getBaseInfo();
        $self->getCfgShow();
        $self->getSwitchShow();
        $self->fillZoneMemberWwpn();

        #给CONFIGS集合里的ZONES集合中的ZONE补充数据
        $self->fillZoneDetailInCfg();
    }
}

1;

