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

sub before {
    my ($self) = @_;

    #SN可能要调整，如果有多个可能，就在数组里添加
    #$self->addScalarOid( SN => [ '1.3.6.1.4.1.9.3.6.3.0', '1.3.6.1.4.1.9.5.1.2.19.0', '1.3.6.1.2.1.47.1.1.1.1.11.1001', '1.3.6.1.2.1.47.1.1.1.1.11.2001', '1.3.6.1.4.1.9.9.92.1.1.1.2.0' ] );
}

sub after {
    my ($self) = @_;

    my $data       = $self->{DATA};
    my $nodeInfo   = $self->{node};
    my $sshAccount = $self->{sshAccount};

    if ( not $sshAccount ) {
        print("WARN: SSH account not defined, can not collect detail information.\n");
    }

    if ($sshAccount) {
        print("INFO: Try collect more information by ssh.\n");

        my $ssh = Net::OpenSSH->new(
            $nodeInfo->{host},
            port        => $sshAccount->{protocolPort},
            user        => $sshAccount->{username},
            password    => $sshAccount->{password},
            timeout     => $self->{timeout},
            master_opts => [ -o => "StrictHostKeyChecking=no" ]
        );

        if ( $ssh->error ) {
            print( "ERROR: Can not establish ssh connection for $nodeInfo->{host}:$nodeInfo->{protocolPort}, " . $ssh->error . "\n" );
            exit(-1);
        }

        if ( not defined( $data->{UPTIME} ) ) {

            #uptime ：显示交换机工作时间
            #00:22:02 up 272 days, 23:01, 1 user, load average: 0.03, 0.05, 0.00
            #326 days, 01:11:41.00
            my @uptimeLines = $ssh->capture('uptime');
            foreach my $line (@uptimeLines) {
                if ( $line =~ /up/ ) {
                    my $UPTIME = ( split( /,/, $line ) )[0];
                    my $time   = ( split( /,/, $line ) )[1];
                    $UPTIME =~ s/^\s+//g;
                    my @tmp  = ( split( /up/, $UPTIME ) );
                    my $days = @tmp[1];
                    $data->{UPTIME} = "$days, $time";
                }
            }
        }

        if ( not defined( $data->{FIRMWARE_VERSION} ) ) {
            my @firmWareInfoLines = $ssh->capture('firmwareshow');
            my $fmVerInfo         = $firmWareInfoLines[-1];
            $fmVerInfo =~ s/^\s+|\s+$//g;
            $data->{FIRMWARE_VERSION} = $fmVerInfo;
        }

        if ( not defined( $data->{SN} ) ) {
            my $sn;
            my $chassisLine = $ssh->capture('chassisshow');
            if ( $chassisLine =~ /.*Serial\s+Num:\s*(\S+)/ ) {
                $sn = $1;
                $sn =~ s/^\s+|\s+$//g;
            }
            $data->{SN} = $sn;
        }

        my @showInfoLines = $ssh->capture('switchshow');
        my $domainId;
        if ( not defined( $data->{DOMAIN_ID} ) ) {
            foreach my $line (@showInfoLines) {
                if ( $line =~ /switchDomain/ ) {
                    $domainId = ( split( /:/, $line ) )[1];
                    $domainId =~ s/^\s+|\s+$//g;
                }
            }
            $data->{DOMAIN_ID} = $domainId;
        }
        else {
            $domainId = $data->{DOMAIN_ID};
        }

        if ( not defined( $data->{WWNN} ) ) {
            my $switchWwn;

            #switchWwn:      10:00:00:27:f8:8b:07:80
            foreach my $line (@showInfoLines) {
                if ( $line =~ /switchWwn/ ) {
                    $switchWwn = ( split( /\s+/, $line ) )[1];
                    $switchWwn =~ s/^\s+|\s+$//g;
                }
                else {
                    next;
                }
            }
            $data->{WWNN} = $switchWwn;
        }

        my $switchState;

        #switchState:	Online
        foreach my $line (@showInfoLines) {
            if ( $line =~ /switchState/ ) {
                $switchState = ( split( /\s+/, $line ) )[1];
                $switchState =~ s/^\s+|\s+$//g;
            }
            else {
                next;
            }
        }
        $data->{SWITCH_STATE} = $switchState;

        if ( not defined( $data->{PORTS_COUNT} ) ) {
            my $ports_count = 0;
            foreach my $line (@showInfoLines) {
                $line =~ s/^\s*|\s*$//g;

                if ( $line =~ /\s+FC\s+/ ) {
                    $ports_count++;
                }
            }
            $data->{PORTS_COUNT} = $ports_count;
        }

        #alias: HW5600_000005_L_1
        #       26:11:2c:55:d3:e7:f7:fd
        #alias: HW5600_000005_L_2
        #        26:12:2c:55:d3:e7:f7:fd
        my $portNameAliasMap = {};
        my $portWwnAliasMap  = {};
        my $aliasPortWwnMap  = {};
        my $aliasPortNameMap = {};
        my $cfgInfo          = $ssh->capture('cfgshow');
        if ( $cfgInfo =~ /(alias:.*?)Effective\s*configuration:/s ) {
            my $aliasInfo = $1;

            my @aliasInfo = split( /alias:\s*.*?\s*/, $aliasInfo );
            foreach my $line (@aliasInfo) {
                $line =~ s/^\s*|\s*$//g;
                $line =~ s/;/\n/g;
                my @splits    = split( /\s+/, $line );
                my $aliasName = $splits[0];
                my $portWwn;
                my $portDesc;
                if ( defined $aliasName and $aliasName ne '' ) {
                    while ( my ( $index, $element ) = each(@splits) ) {
                        if ( $index != 0 ) {
                            $element =~ s/^\s*|\s*$//g;
                            if ( $element !~ /,/ ) {
                                $portWwn                       = $element;
                                $portWwnAliasMap->{$portWwn}   = $aliasName;
                                $aliasPortWwnMap->{$aliasName} = $portWwn;
                            }
                            else {
                                $portDesc                       = $element;
                                $portNameAliasMap->{$portDesc}  = $aliasName;
                                $aliasPortNameMap->{$aliasName} = $portDesc;
                            }
                        }
                    }
                }
            }
        }

        my @portList;
        my ( $portIdx, $speedIdx );
        foreach my $line (@showInfoLines) {
            $line =~ s/^\s*|\s*$//g;
            if ( $line =~ /speed/i and $line =~ /port/i ) {
                my @title = split( /\s+/, $line );
                while ( my ( $index, $element ) = each(@title) ) {
                    if ( $element =~ /port/i ) {
                        $portIdx = $index;
                    }
                    if ( $element =~ /speed/i ) {
                        $speedIdx = $index;
                    }
                }
            }

            if ( $line =~ /\s+FC/ ) {

                #Index Port Address Media Speed State     Proto
                # 1    1    1   010100   id    N8	   No_Light    FC
                # 2    1    2   010200   id    N8	   Online      FC  F-Port  50:00:09:79:f0:02:79:80
                # 3    1    3   010300   id    N8	   Online      FC  F-Port  50:00:09:79:f0:02:79:81
                my @portSplit = split( /\s+/, $line );
                my $port      = $portSplit[$portIdx];
                my $portDesc  = $domainId . ',' . $port;
                my $portSpeed = $portSplit[$speedIdx];
                my $portName;
                my $portState;

                my $port_LOCAL_WWPN;
                my $showPortInfo = $ssh->capture("portshow $port");
                if ( $showPortInfo =~ /portName:\s*(.+)/ ) {
                    $portName = $1;
                }
                if ( $showPortInfo =~ /portWwn:\s*(.+)\s+/ ) {
                    $port_LOCAL_WWPN = $1;
                }

                if ( $showPortInfo =~ /portState:\s*(.+)\s+/ ) {
                    my @tmp = split( /\s+/, $1 );
                    $portState = $tmp[1];
                }

                my $port_PEER_WWPN = $portSplit[-1];

                if ( $port_PEER_WWPN eq 'FC' or $port_PEER_WWPN eq 'Disabled' or $port_PEER_WWPN =~ /yet/ ) {
                    $port_PEER_WWPN = '';
                }
                else {
                    if ( $port_PEER_WWPN !~ /\w+:\w+/ ) {
                        if ( $line =~ /\s+E-Port\s+/ ) {

                            #22  22   041600   id    N16	   Online      FC  E-Port  10:00:c4:f5:7c:d4:a9:54 "SW6510"
                            #23  23   041700   id    N16	   Online      FC  E-Port  10:00:c4:f5:7c:d4:a9:54 "SW6510" (downstream)
                            my @portSplit2 = split( /\s+E-Port\s+/, $line );
                            my @tmp        = split( /\s+E-Port\s+/, $portSplit2[1] );
                            my @tmp2       = split( /\s/,           $tmp[0] );
                            $port_PEER_WWPN = $tmp2[0];
                        }
                    }
                }

                my $portInfo = {};
                $portInfo->{_OBJ_CATEGORY} = 'FCDEV';
                $portInfo->{_OBJ_TYPE}     = 'FCSWITCH-PORT';
                $portInfo->{NAME}          = $portDesc;
                $portInfo->{PORT}          = $port;
                $portInfo->{PORT_NAME}     = $portName;
                $portInfo->{SPEED}         = $portSpeed;
                $portInfo->{ADMIN_STATUS}  = $portState;
                $portInfo->{LOCAL_WWPN}    = $port_LOCAL_WWPN;
                $portInfo->{PEER_WWPN}     = $port_PEER_WWPN;

                if ( defined( $portWwnAliasMap->{PEER_WWPN} ) and $portWwnAliasMap->{PEER_WWPN} ne '' ) {
                    $portInfo->{ALIASES} = $portWwnAliasMap->{PEER_WWPN};
                }
                elsif ( defined( $portNameAliasMap->{$portDesc} ) and $portNameAliasMap->{$portDesc} ne '' ) {
                    $portInfo->{ALIASES} = $portNameAliasMap->{$portDesc};
                }

                push( @portList, $portInfo );
            }
        }
        $data->{PORTS} = \@portList;

        if ( not defined( $data->{LINK_TABLE} ) ) {
            my @linkTableList;
            foreach my $portInfo (@portList) {
                my $portName        = $portInfo->{NAME};
                my $port_LOCAL_WWPN = $portInfo->{LOCAL_WWPN};
                my $port_PEER_WWPN  = $portInfo->{PEER_WWPN};
                if ( $port_PEER_WWPN ne '' ) {
                    my $linkInfo = {};
                    $linkInfo->{PORT_NAME}  = $portName;
                    $linkInfo->{LOCAL_WWPN} = $port_LOCAL_WWPN;
                    $linkInfo->{LOCAL_WWNN} = $data->{WWNN} . ':00:00:00:00:00:00:00:00';
                    $linkInfo->{PEER_WWPN}  = $port_PEER_WWPN;

                    push( @linkTableList, $linkInfo );
                }
            }

            #计算本地端口往外连接的连接数量
            my $linkCountMap = {};

            foreach my $linkInfo (@linkTableList) {
                my $localWwnn = $linkInfo->{LOCAL_WWNN};
                my $localWwpn = $linkInfo->{LOCAL_WWPN};

                my $keyStr    = "$localWwnn-$localWwpn";
                my $linkCount = $linkCountMap->{$keyStr};
                if ( not defined($linkCount) ) {
                    $linkCount = 0;
                }
                $linkCountMap->{$keyStr} = $linkCount + 1;
            }
            foreach my $linkInfo (@linkTableList) {
                my $localWwnn = $linkInfo->{LOCAL_WWNN};
                my $localWwpn = $linkInfo->{LOCAL_WWPN};
                $linkInfo->{LINK_COUNT} = $linkCountMap->{"$localWwnn-$localWwpn"};
            }

            $data->{LINK_TABLE} = \@linkTableList;
        }

        #zone:  DELL_R940_181_HW5600_000005
        #                DELL_R940_181_solt6p1; HW5600_000005_L_0; HW5600_000005_L_1;
        #                HW5600_000005_L_2; HW5600_000005_L_3
        #zone:  DELL_R940_182_HW5600_000005
        #                DELL_R940_182_solt6p1; HW5600_000005_L_0; HW5600_000005_L_1;
        #                HW5600_000005_L_2; HW5600_000005_L_3
        my @zones;
        if ( $cfgInfo =~ /(zone:.*?)alias/s ) {
            my $zonesCfgInfo = $1;

            my @zoneCfgInfo = split( /zone:\s*.*?\s*/, $zonesCfgInfo );
            foreach my $line (@zoneCfgInfo) {
                $line =~ s/^\s*|\s*$//g;
                $line =~ s/;/\n/g;
                my @splits   = split( /\s+/, $line );
                my $zoneName = $splits[0];
                if ( defined $zoneName and $zoneName ne '' ) {
                    my @zoneAliases = ();
                    my @zone_wwn    = ();
                    while ( my ( $index, $element ) = each(@splits) ) {
                        my $zoneAlias = $element;
                        $zoneAlias =~ s/^\s*|\s*$//g;
                        if ( $index != 0 ) {
                            push( @zoneAliases, { VALUE => $zoneAlias } );
                            if ( defined( $aliasPortWwnMap->{$zoneAlias} ) and $aliasPortWwnMap->{$zoneAlias} ne '' ) {
                                my $portWWN = $aliasPortWwnMap->{$zoneAlias};
                                foreach my $a (@portList) {
                                    if ( $portWWN eq $a->{'PEER_WWPN'} ) {
                                        push( @zone_wwn, $a );
                                    }
                                }
                            }
                            elsif ( defined( $aliasPortNameMap->{$zoneAlias} ) and $aliasPortNameMap->{$zoneAlias} ne '' ) {
                                my $portDesc = $aliasPortNameMap->{$zoneAlias};
                                foreach my $a (@portList) {
                                    if ( $portDesc eq $a->{'NAME'} ) {
                                        push( @zone_wwn, $a );
                                    }
                                }
                            }
                        }

                        if ( scalar(@zone_wwn) > 0 ) {
                            if ( scalar(@zones) > 0 ) {
                                my $exist = 0;
                                foreach my $a (@zones) {
                                    if ( $zoneName eq $$a{'NAME'} ) {
                                        $exist = 1;
                                    }
                                }
                                if ( $exist == 0 ) {
                                    my $zoneInfo = {};
                                    $zoneInfo->{_OBJ_CATEGORY} = 'FCDEV';
                                    $zoneInfo->{_OBJ_TYPE}     = 'FCSWITCH-ZONE';
                                    $zoneInfo->{NAME}          = $zoneName;
                                    $zoneInfo->{PORT_ALIASES}  = \@zoneAliases;
                                    $zoneInfo->{PORTS}         = \@zone_wwn;
                                    push( @zones, $zoneInfo );
                                }
                            }
                            else {
                                my $zoneInfo = {};
                                $zoneInfo->{_OBJ_CATEGORY} = 'FCDEV';
                                $zoneInfo->{_OBJ_TYPE}     = 'FCSWITCH-ZONE';
                                $zoneInfo->{NAME}          = $zoneName;
                                $zoneInfo->{ALIASES}       = \@zoneAliases;
                                $zoneInfo->{PORTS}         = \@zone_wwn;
                                push( @zones, $zoneInfo );
                            }
                        }
                    }
                }
            }

            my $cfgName;
            if ( $cfgInfo =~ /cfg:\s+(\S+)\s+\n/ ) {
                $cfgName = $1;
            }

            my @cfglist;
            my $cfgInfo = {};
            $cfgInfo->{_OBJ_CATEGORY} = 'FCDEV';
            $cfgInfo->{_OBJ_TYPE}     = 'FCSWITCH-CFG';
            $cfgInfo->{NAME}          = $cfgName;
            $cfgInfo->{ZONES}         = \@zones;
            push( @cfglist, $cfgInfo );

            $data->{CONFIGS} = \@cfglist;
            $data->{ZONES}   = \@zones;
        }

        $ssh->disconnect();
    }
}

1;

