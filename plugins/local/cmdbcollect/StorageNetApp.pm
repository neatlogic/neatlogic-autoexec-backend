#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../plib/lib/perl5";

use strict;

package StorageNetApp;

use NetExpect;
use JSON;
use CollectUtils;
use Data::Dumper;

sub new {
    my ( $type, %args ) = @_;
    my $self = {};

    my $node = $args{node};
    $self->{inspect} = $args{inspect};
    $self->{node}    = $node;

    my $timeout = $args{timeout};
    if ( not defined($timeout) or $timeout eq '0' ) {
        $timeout = 10;
    }
    $self->{timeout} = $timeout;
    my $utils = CollectUtils->new();
    $self->{collectUtils} = $utils;

    my $ssh = NetExpect->new(
        host     => $node->{host},
        port     => $node->{protocolPort},
        protocol => 'ssh',
        username => $node->{username},
        password => $node->{password},
        timeout  => $timeout
    );
    $ssh->login();

    $self->{ssh}  = $ssh;
    $self->{data} = {};

    bless( $self, $type );
    return $self;
}

sub getDiskSizeFormStr {
    my ( $self, $sizeStr ) = @_;
    my $utils = $self->{collectUtils};

    my $size = $utils->getDiskSizeFormStr($sizeStr);

    return $size;
}

sub getNicSpeedFromStr {
    my ( $self, $speedStr ) = @_;
    my $utils = $self->{collectUtils};

    my $speed = $utils->getNicSpeedFromStr($speedStr);

    return $speed;
}

sub parseCmdOut {
    my ( $self, $cmdOutLines ) = @_;
    my $linesCount = scalar(@$cmdOutLines);
    my @header     = split( '\|', $$cmdOutLines[0] );

    my $line;
    my @records = ();
    for ( my $i = 2 ; $i < $linesCount ; $i++ ) {
        $line = $$cmdOutLines[$i];
        $line =~ s/^\s*|\s*$//g;
        if ( $line ne '' ) {

            #print("DEBUG: $line\n");
            my @record = split( '\|', $line );

            my $recordInfo = {};
            for ( my $k = 0 ; $k <= $#record ; $k++ ) {
                $recordInfo->{ $header[$k] } = $record[$k];
            }
            push( @records, $recordInfo );
        }
    }

    return ( \@header, \@records );
}

sub getDeviceInfo {
    my ($self) = @_;
    my $ssh    = $self->{ssh};
    my $data   = $self->{data};
    my $cmd;

    my $controllersMap = {};
    my $header;
    my $records;

    $cmd = 'hostname';
    my $hostName = $ssh->runCmd($cmd);
    $hostName =~ s/^\s*|\s*$//g;
    $data->{DEV_NAME} = $hostName;

    $cmd = 'system controller show -fields node,model,part-number,revision,serial-number,controller-type,status,chassis-id';
    my @controllerLines = split( "\n", $ssh->runCmd($cmd) );
    ( $header, $records ) = $self->parseCmdOut( \@controllerLines );
    foreach my $record (@$records) {
        my $name           = $record->{'node'};
        my $controllerInfo = {
            NAME            => $name,
            MODEL           => $record->{'model'},
            PART_NUMBER     => $record->{'part-number'},
            REVISION        => $record->{'revision'},
            SN              => $record->{'serial-number'},
            CONTROLLER_TYPE => $record->{'controller-type'},
            STATUS          => $record->{'status'},
            CHASSIS_ID      => $record->{'chassis-id'}
        };
        $data->{SN} = $record->{'chassis-id'};
        $controllersMap->{$name} = $controllerInfo;
    }

    $cmd = 'node show -fields node,location,uptime,vendor,health';
    my @nodeLines = split( "\n", $ssh->runCmd($cmd) );
    ( $header, $records ) = $self->parseCmdOut( \@nodeLines );
    foreach my $record (@$records) {
        my $name           = $record->{'node'};
        my $controllerInfo = $controllersMap->{$name};
        $controllerInfo->{LOCATION} = $record->{'location'};
        $controllerInfo->{UPTIME}   = $record->{'uptime'};
        $controllerInfo->{VENDOR}   = $record->{'vendor'};
        $controllerInfo->{HEALTH}   = $record->{'health'};
    }

    my @controllers = values(%$controllersMap);
    $data->{CONTROLLERS} = \@controllers;
}

sub getIntiators {
    my ($self) = @_;
    my $ssh    = $self->{ssh};
    my $data   = $self->{data};

    # VMcDot1::> igroup show -fields vserver,igroup,protocol,ostype,initiator
    # vserver|igroup|protocol|ostype|initiator|
    # Vserver Name|Igroup Name|Protocol|OS Type|Initiators|
    # FC_VM1_SVM1|ESXi248_180|fcp|vmware|51:40:2e:c0:01:7a:e3:fc,51:40:2e:c0:01:7a:e5:b0|
    # FC_VM1_SVM1|ESXi248_181|fcp|vmware|51:40:2e:c0:01:7a:e2:90,51:40:2e:c0:01:7a:e6:b4|

    my $cmd             = 'igroup show -fields vserver,igroup,protocol,ostype,initiator';
    my @initiatorGroups = split( "\n", $ssh->runCmd($cmd) );
    my ( $header, $records ) = $self->parseCmdOut( \@initiatorGroups );

    my $initiatorGroupMap = {};
    foreach my $record (@$records) {
        my $name = $record->{'igroup'};
        my @wwns = split( ',', $record->{'initiator'} );
        $initiatorGroupMap->{$name} = \@wwns;
    }
    $self->{initiatorGroupMap} = $initiatorGroupMap;
    return $initiatorGroupMap;
}

sub getPoolInfo {
    my ($self) = @_;
    my $ssh    = $self->{ssh};
    my $data   = $self->{data};

    # VMcDot1::> aggr show -fields aggregate,node,availsize,size,state,usedsize,percent-used
    # aggregate|node|nodes|availsize|percent-used|size|state|usedsize|
    # Aggregate|Node|Node|Available Size|Used Percentage|Size|State|Used Size|
    # aggr0_VMcDot1_01|VMcDot1-01|VMcDot1-01|17GB|95%|368GB|online|350GB|
    # aggr0_VMcDot1_02|VMcDot1-02|VMcDot1-02|17GB|95%|368GB|online|350GB|

    my $cmd   = 'aggr show -fields aggregate,node,availsize,size,state,usedsize,percent-used,raidtype,volcount';
    my @aggrs = split( "\n", $ssh->runCmd($cmd) );
    my ( $header, $records ) = $self->parseCmdOut( \@aggrs );

    my @pools = ();
    foreach my $record (@$records) {
        my $poolInfo = {
            NAME            => $record->{'aggregate'},
            TYPE            => undef,
            CONTROLLER_NAME => $record->{'node'},
            CAPACITY        => $self->getDiskSizeFormStr( $record->{'size'} ),
            AVAILABLE       => $self->getDiskSizeFormStr( $record->{'availsize'} ),
            USED            => $self->getDiskSizeFormStr( $record->{'usedsize'} ),
            USED_PCT        => int( $record->{'percent-used'} ),
            RAID_TYPE       => $record->{'raidtype'},
            VOL_COUNT       => $record->{'volcount'},
            STATUS          => $record->{'state'}
        };
        push( @pools, $poolInfo );
    }

    $data->{POOLS} = \@pools;
    return \@pools;
}

sub getVolumeInfo {
    my ($self) = @_;
    my $ssh    = $self->{ssh};
    my $data   = $self->{data};

    # VMcDot1::> vol show -fields volume,aggregate,total,used,available,percent-used,state,nodes
    # vserver|volume|aggregate|state|available|total|used|percent-used|nodes|
    # Vserver Name|Volume Name|Aggregate Name|Volume State|Available Size|Total User-Visible Size|Used Size|Used Percentage|List of Nodes|
    # FC_VM1_SVM1|FC_VM_SVM1_root|aggr1_VMcDot1_01|online|0GB|0GB|0GB|5%|VMcDot1-01|
    # FC_VM1_SVM1|Mgmt_VMcDot1_01_vol|aggr1_VMcDot1_01|online|4221GB|4222GB|0GB|0%|VMcDot1-01|

    my $cmd  = 'vol show -fields volume,aggregate,total,used,available,percent-used,state';
    my @vols = split( "\n", $ssh->runCmd($cmd) );
    my ( $header, $records ) = $self->parseCmdOut( \@vols );

    my @volumes = ();
    foreach my $record (@$records) {
        my $volInfo = {
            NAME            => $record->{'volume'},
            POOL_NAME       => $record->{'aggregate'},
            CONTROLLER_NAME => $record->{'nodes'},
            CAPACITY        => $self->getDiskSizeFormStr( $record->{'total'} ),
            AVAILABLE       => $self->getDiskSizeFormStr( $record->{'available'} ),
            USED            => $self->getDiskSizeFormStr( $record->{'used'} ),
            USED_PCT        => int( $record->{'percent-used'} ),
            STATUS          => $record->{'state'}
        };
        push( @volumes, $volInfo );
    }

    $data->{VOLUMES} = \@volumes;
    return \@volumes;
}

sub getLunInfo {
    my ($self) = @_;
    my $ssh    = $self->{ssh};
    my $data   = $self->{data};

    my $cmd;
    my $header;
    my $records;

    # VMcDot1::> lun show -fields path,lun,uuid,serial-hex,size,size-used,state,mapped,node,state
    # vserver|path|lun|size|serial-hex|state|uuid|mapped|size-used|node|
    # Vserver Name|LUN Path|LUN Name|LUN Size|Serial Number (Hex)|State|LUN UUID|Mapped|Used Size|Node Hosting the LUN|
    # FC_VM1_SVM1|/vol/OA_VMcDot1_01_vol/OA-VMcDot1-01|OA-VMcDot1-01|4096GB|38304455355d4b704163546d|online|89809bd2-10e1-485d-928b-6e2136a963d0|mapped|2572GB|VMcDot1-02|
    $cmd = 'lun show -fields path,lun,uuid,serial-hex,size,size-used,state,mapped,node,state';
    my @lunLines = split( "\n", $ssh->runCmd($cmd) );
    ( $header, $records ) = $self->parseCmdOut( \@lunLines );

    my $lunsMap = {};
    foreach my $record (@$records) {
        my $lunInfo = {
            NAME               => $record->{'lun'},
            PATH               => $record->{'path'},
            WWN                => lc( $record->{'serial-hex'} ),
            POOL_NAME          => $record->{'aggregate'},
            CONTROLLER_NAME    => $record->{'node'},
            CAPACITY           => $self->getDiskSizeFormStr( $record->{'size'} ),
            USED               => $self->getDiskSizeFormStr( $record->{'size-used'} ),
            STATUS             => $record->{'state'},
            VISABLE_GROUPS     => [],
            VISABLE_INITIATORS => []
        };
        $lunsMap->{ $record->{'path'} } = $lunInfo;
    }

    # VMcDot1::> lun mapping show -fields path,igroup,initiators
    # vserver|path|igroup|initiators|
    # Vserver Name|LUN Path|Igroup Name|Initiators|
    # FC_VM1_SVM1|/vol/OA_VMcDot1_01_vol/OA-VMcDot1-01|ESXi248_180|51:40:2e:c0:01:7a:e3:fc,51:40:2e:c0:01:7a:e5:b0|
    # FC_VM1_SVM1|/vol/OA_VMcDot1_01_vol/OA-VMcDot1-01|ESXi248_181|51:40:2e:c0:01:7a:e2:90,51:40:2e:c0:01:7a:e6:b4|
    $cmd = 'lun mapping show -fields path,igroup,initiators';
    my @lunMapLines = split( "\n", $ssh->runCmd($cmd) );
    ( $header, $records ) = $self->parseCmdOut( \@lunMapLines );
    foreach my $record (@$records) {
        my $lunInfo = $lunsMap->{ $record->{'path'} };
        if ( defined($lunInfo) ) {
            my $vGroups    = $lunInfo->{VISABLE_GROUPS};
            my $initiators = $lunInfo->{VISABLE_INITIATORS};
            push( @$vGroups,    $record->{'igroup'} );
            push( @$initiators, split( ',', $record->{'initiators'} ) );
        }
    }

    my @luns = values(%$lunsMap);
    $data->{LUNS} = \@luns;
    return \@luns;
}

sub getHealthInfo {
    my ($self) = @_;
    my $ssh    = $self->{ssh};
    my $data   = $self->{data};

    my $cmd         = 'system health alert show -fields  alerting-resource,indication-time,perceived-severity,probable-cause,probable-cause-description,corrective-action';
    my @healthLines = split( "\n", $ssh->runCmd($cmd) );

    my $healthContent = '';
    for ( my $i = 1 ; $i <= $#healthLines ; $i++ ) {
        my $line = $healthLines[$i];
        $line =~ s/\|/\t/g;
        $healthContent = $healthContent . $line . "\n";
    }

    $data->{HEALTH_CHECK} = $healthContent;
    return $healthContent;
}

sub getEthInfo {
    my ($self) = @_;
    my $ssh    = $self->{ssh};
    my $data   = $self->{data};

    # VMcDot1::> network port show -fields port,mac,speed-oper,remote-device-id,health-status
    # node|port|speed-oper|mac|remote-device-id|health-status|
    # Node|Port|Speed Operational|MAC Address|Remote Device ID|Port Health Status|
    # VMcDot1-01|e0M|1000|00:a0:98:bc:0e:85|-|healthy|
    # VMcDot1-01|e0a|10000|00:a0:98:bc:0e:75|VMcDot1-02|healthy|
    # VMcDot1-01|e0b|10000|00:a0:98:bc:0e:76|VMcDot1-02|healthy|
    my $cmd      = 'network port show -fields port,mac,speed-oper,remote-device-id,health-status';
    my @ethLines = split( "\n", $ssh->runCmd($cmd) );
    my ( $header, $records ) = $self->parseCmdOut( \@ethLines );

    my @eths = ();
    foreach my $record (@$records) {
        my $ethInfo = {
            NAME            => $record->{'port'},
            MAC             => $record->{'mac'},
            SPEED           => $self->getNicSpeedFromStr( $record->{'speed-oper'} ),
            STATUS          => $record->{'health-status'},
            CONTROLLER_NAME => $record->{'node'}
        };
        push( @eths, $ethInfo );
    }

    $data->{ETH_INTERFACES} = \@eths;
    return \@eths;
}

sub getFcInfo {
    my ($self) = @_;
    my $ssh    = $self->{ssh};
    my $data   = $self->{data};

    # VMcDot1::> fcp adapter show -field node,adapter,description,speed,max-speed,portaddr,fc-wwnn,fc-wwpn
    # node|adapter|description|max-speed|portaddr|speed|fc-wwnn|fc-wwpn|
    # Node|Adapter|Description|Maximum Speed|Host Port Address|Configured Speed|Adapter WWNN|Adapter WWPN|
    # VMcDot1-01|0e|"Fibre Channel Target Adapter 0e (QLogic 8324 (8362), rev. 2, 16G)"|16|155600|16|50:0a:09:80:80:b3:9e:f7|50:0a:09:82:80:b3:9e:f7|
    # VMcDot1-01|0f|"Fibre Channel Target Adapter 0f (QLogic 8324 (8362), rev. 2, 16G)"|16|165600|auto|50:0a:09:80:80:b3:9e:f7|50:0a:09:81:80:b3:9e:f7|
    my $cmd      = 'fcp adapter show -fields node,adapter,description,speed,max-speed,portaddr,fc-wwnn,fc-wwpn,status';
    my @hbaLines = split( "\n", $ssh->runCmd($cmd) );
    my ( $header, $records ) = $self->parseCmdOut( \@hbaLines );

    my @hbas = ();
    foreach my $record (@$records) {
        my $hbaInfo = {
            NAME            => $record->{'adapter'},
            WWNN            => $record->{'fc-wwnn'},
            WWPN            => $record->{'fc-wwpn'},
            SPEED           => $self->getNicSpeedFromStr( $record->{'speed'} ),
            STATUS          => $record->{'status'},
            CONTROLLER_NAME => $record->{'node'}
        };
        push( @hbas, $hbaInfo );
    }

    $data->{HBA_INTERFACES} = \@hbas;
    return \@hbas;
}

sub getIPAddrs {
    my ($self) = @_;
    my $ssh    = $self->{ssh};
    my $data   = $self->{data};

    # VMcDot1::> network interface show -fields server,address,lif
    # vserver|server|lif|vif|address|
    # Vserver Name|Vserver Name|Logical Interface Name|Logical Interface Name|Network Address|
    # Cluster|Cluster|VMcDot1-01_clus1|VMcDot1-01_clus1|169.254.96.23|
    # Cluster|Cluster|VMcDot1-01_clus2|VMcDot1-01_clus2|169.254.252.58|
    my $cmd      = 'network interface show -fields server,address,netmask,lif';
    my @ethLines = split( "\n", $ssh->runCmd($cmd) );
    my ( $header, $records ) = $self->parseCmdOut( \@ethLines );

    my @ipAddrs = ();
    foreach my $record (@$records) {
        if ( $record->{'address'} ne '-' ) {
            my $ipInfo = {
                IP      => $record->{'address'},
                NETMASK => $record->{'netmask'},
                DESC    => $record->{'lif'},
                SERVER  => $record->{'server'}
            };
            push( @ipAddrs, $ipInfo );
        }
    }

    $data->{IP_ADDRS} = \@ipAddrs;
    return \@ipAddrs;
}

sub collect {
    my ($self) = @_;
    my $data   = $self->{data};
    my $ssh    = $self->{ssh};

    my $initCmd = 'set -units GB -showseparator "|" -rows 999999';
    $ssh->runCmd($initCmd);

    $data->{VENDOR} = 'NetApp';
    $data->{BRAND}  = 'NetApp';

    print("INFO: Try to collect device information.\n");
    $self->getDeviceInfo();
    print("INFO: Try to collect pool information.\n");
    $self->getPoolInfo();
    print("INFO: Try to collect volume information.\n");
    $self->getVolumeInfo();
    print("INFO: Try to collect lun information.\n");
    $self->getLunInfo();
    print("INFO: Try to collect ethernet information.\n");
    $self->getEthInfo();
    print("INFO: Try to collect fc information.\n");
    $self->getFcInfo();
    print("INFO: Try to collect ip address information.\n");
    $self->getIPAddrs();

    if ( $self->{inspect} == 1 ) {
        print("INFO: Try to do health check.\n");
        $self->getHealthInfo();
    }
    print("INFO: Information collected.\n");
    return $data;
}

1;

