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

    my $data     = $self->{DATA};
    my $nodeInfo = $self->{node};

    if ( not defined( $data->{DEV_NAME} ) and defined( $nodeInfo->{username} ) and lc( $nodeInfo->{username} ) ne 'snmp' ) {
        print("INFO: Can not find DEV_NAME by snmp, try ssh.\n");

        my $ssh = Net::OpenSSH->new(
            $nodeInfo->{host},
            port        => $nodeInfo->{protocolPort},
            user        => $nodeInfo->{username},
            password    => $nodeInfo->{password},
            timeout     => $self->{timeout},
            master_opts => [ -o => "StrictHostKeyChecking=no" ]
        );

        if ( $ssh->error ) {
            print( "ERROR: Can not establish ssh connection for $nodeInfo->{host}:$nodeInfo->{protocolPort}, " . $ssh->error . "\n" );
            exit(-1);
        }

        my @firmWareInfoLines = $ssh->capture('firmwareshow');
        my $fmVerInfo         = $firmWareInfoLines[-1];
        $fmVerInfo =~ s/^\s+|\s+$//g;
        $data->{FIRMWARE_VERSION} = $fmVerInfo;

        my $sn;
        my $chassisLine = $ssh->capture('chassisshow');
        if ( $chassisLine =~ /.*Serial\s+Num:\s*(\S+)/ ) {
            $sn = $1;
            $sn =~ s/^\s+|\s+$//g;
            $data->{SN} = $sn;
        }

        my $domainId;
        my @showInfoLines = $ssh->capture('switchshow');
        foreach my $line (@showInfoLines) {
            if ( $line =~ /switchDomain/ ) {
                $domainId = ( split( /:/, $line ) )[1];
                $domainId =~ s/^\s+|\s+$//g;
            }
        }
        $data->{DOMAIN_ID} = $domainId;

        # alias:	DD4200_A0port1
        #         50:02:18:81:36:61:11:0b
        # alias:	DS8100_io233
        #         50:05:07:63:09:13:c2:a5
        # alias:	DS8100_io303
        #         50:05:07:63:09:18:c2:a5
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

            if ( $line =~ /\s+F-Port\s+/ ) {

                # 1    1    1   010100   id    N8	   No_Light    FC
                # 2    1    2   010200   id    N8	   Online      FC  F-Port  50:00:09:79:f0:02:79:80
                # 3    1    3   010300   id    N8	   Online      FC  F-Port  50:00:09:79:f0:02:79:81
                my @portSplit = split( /\s+/, $line );
                my $port      = $portSplit[$portIdx];
                my $portDesc  = $domainId . ',' . $port;
                my $portSpeed = $portSplit[$speedIdx];
                my $portWWN;
                if ( $portSplit[-1] !~ /\w+:\w+/ ) {
                    my $showPortInfo = $ssh->capture("portshow $port");
                    if ( $showPortInfo =~ /portWwn:\s*(.+)\s+/ ) {
                        $portWWN = $1;
                    }
                }
                else {
                    $portWWN = $portSplit[-1];
                }

                my $portInfo = {};
                $portInfo->{NAME}  = $portDesc;
                $portInfo->{SPEED} = $portSpeed;
                $portInfo->{WWN}   = $portWWN;

                push( @portList, $portInfo );
            }
        }

        # zone:	DD4200_A0port1_pzhqzpt1_fcs1
        #         50:02:18:81:36:61:11:0b
        #         10:00:00:90:fa:38:ba:25
        # zone:	DS8700_DS8100
        #         50:05:07:63:09:13:c2:a5
        #         50:05:07:63:09:18:c2:a5
        #         50:05:07:63:09:18:86:87
        #         50:05:07:63:09:13:06:87
        my @zones;
        my $cfgInfo = $ssh->capture('cfgshow');

        #my @data = $cfgInfo =~ /alias:.*?Effective\s*configuration/si;
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
                    while ( my ( $index, $element ) = each(@splits) ) {
                        my $zoneAlias = $element;
                        $zoneAlias =~ s/^\s*|\s*$//g;
                        if ( $index != 0 ) {
                            push( @zoneAliases, { VALUE => $zoneAlias } );
                        }
                    }
                    my $zoneInfo = {};
                    $zoneInfo->{NAME}    = $zoneName;
                    $zoneInfo->{ALIASES} = \@zoneAliases;
                    push( @zones, $zoneInfo );
                }
            }
        }

        my $cfgName;
        if ( $cfgInfo =~ /cfg:\s+(\S+)\s+\n/ ) {
            $cfgName = $1;
        }

        my @cfglist;
        my $cfgInfo = {};
        $cfgInfo->{NAME}  = $cfgName;
        $cfgInfo->{ZONES} = \@zones;
        push( @cfglist, $cfgInfo );

        $data->{PORTS}   = \@portList;
        $data->{CONFIGS} = \@cfglist;

        $ssh->disconnect();
    }

    return $data;
}

1;

