#!/usr/bin/perl
use strict;
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");

package StorageRPA;

use SSHExpect;
use XML::MyXML qw(xml_to_object);
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

    my $ssh = SSHExpect->new(
        host     => $node->{host},
        port     => $node->{protocolPort},
        username => $node->{username},
        password => $node->{password},
        timeout  => $timeout,
        PROMPT   => '[\]\$\>\#]\s*\x1b..\x1b..$',
        exitCmd  => 'quit',
    );
    $ssh->login();

    $self->{ssh}  = $ssh;
    $self->{data} = {};

    bless( $self, $type );
    return $self;
}

sub up2Ancestor{
    my ($self, $obj, $upCount) = @_;
    for(my $i=0; $i<$upCount; $i++){
        $obj = $obj->parent();
    }
    return $obj;
}

sub getValByPath{
    my ($self, $obj, $path) = @_;

    my $result;
    my $subObj = $obj->path($path);
    if (defined($subObj)){
        $result = $subObj->value();
    }
    return $result;
}

sub bytesToG{
    my ($self, $size) = @_;
    return int($size * 100 / 1000 / 1000 / 1000) / 100;
}

sub bytesToM{
    my ($self, $size) = @_;
    return int($size * 100 / 1000 / 1000 ) / 100;
}

sub getMemSizeFormStr {
    my ( $self, $sizeStr ) = @_;
    my $utils = $self->{collectUtils};

    my $size = $utils->getMemSizeFromStr($sizeStr);

    return $size;
}

sub parseRpaInfo{
    my ($self, $myRpa, $myRpaState) = @_;

    my $rpaInfo = {};

    $rpaInfo->{NAME} = $myRpa->attr('key');
    $rpaInfo->{VERSION} = $self->getValByPath($myRpa, 'string[name="version"]');
    $rpaInfo->{SN} = $self->getValByPath($myRpa, 'HardwareDetailsOutput/string[name="hardwareSerialID"]');
    $rpaInfo->{CPU_CORES} = int($self->getValByPath($myRpa, 'HardwareDetailsOutput/u16[name="numberOfCPUs"]'));
    $rpaInfo->{MEM_SIZE} = $self->getMemSizeFormStr($self->getValByPath($myRpa, 'HardwareDetailsOutput/string[name="amountOfMemory"]'));
    $rpaInfo->{STATUS} = $self->getValByPath($myRpaState, 'string[name="status"]');
    $rpaInfo->{REPOSITORY_VOL_STATUS} = $self->getValByPath($myRpaState, 'string[name="repositoryVolStatus"]');

    my @nics = ();
    my @nicObjs = $myRpa->path('map[name="networkInterfaces"]/NICInfoOutput');
    for my $nicObj (@nicObjs){
        my $nicName = $nicObj->attr('key');
        my $nicStateObj = $myRpaState->path(qq{map[name="nics"]/RPANicStateOutput[key="$nicName"]});
        my $nicInfo = {
            NAME => $nicName,
            IP => $nicObj->path('ips/IPInfoOutput/string[name="ip"]')->value(),
            SPEED => $nicStateObj->path('string[name="speed"]')->value(),
            STATUS => $nicStateObj->path('string[name="status"]')->value()
        };
        push(@nics, $nicInfo);
    }
    $rpaInfo->{ETH_INTERFACES} = \@nics;

    my @hbas = ();
    my @hbaObjs = $myRpa->path('interfaces/InterfaceOutput');
    foreach my $hbaObj (@hbaObjs){
        my $wwpn = $hbaObj->path('string[name="initiatorID"]')->value();
        $wwpn = join( ':', ( $wwpn =~ m/../g ) );
        my $hbaInfo = {
            WWPN => $wwpn,
            TYPE => $hbaObj->path('string[name="type"]')->value(),
            SPEED => $myRpaState->path('string[name="fcSpeed"]')->value()
        };
        push(@hbas, $hbaInfo);
    }
    $rpaInfo->{HBA_INTERFACES} = \@hbas;

    return $rpaInfo;
}

sub getDeviceInfo{
    my ($self) = @_;
    my $data = $self->{data};
    my $ssh    = $self->{ssh};

    my $cmd;
    $cmd = 'get_rpa_states -xml -f cluster=';
    my $stateXml = $ssh->runCmd($cmd);
    my $stateObj = xml_to_object($stateXml);

    my $clustersStateMap = {};
    my @clusterStateObjs = $stateObj->path('/returnValue/map/ClusterRPAStateOutput');
    foreach my $clusterObj (@clusterStateObjs){
        my $clusterInfo = {};
        my $clusterName = $clusterObj->attr('key');
        $clustersStateMap->{$clusterName} = $clusterObj;
    }

    $cmd = 'get_rpa_settings -xml -f cluster=';
    my $xml = $ssh->runCmd($cmd);
    my $obj = xml_to_object($xml);

    my @clusters = ();
    my $currentClusterName;
    my $currentRpa;
    my @clusterObjs = $obj->path('/returnValue/map/ClusterRPASettingsOutput');
    foreach my $clusterObj (@clusterObjs){
        my $clusterInfo = {};
        my $clusterName = $clusterObj->attr('key');
        my $clusterStateObj = $clustersStateMap->{$clusterName};
        $clusterInfo = {
            NAME => $clusterName,
            RPAS => []
        };
        my @rpaObjs = $clusterObj->path('map/RPASettingsOutput');
        foreach my $rpaObj (@rpaObjs){
            my $rpaName = $rpaObj->attr('key');
            my $rpaStateObj = $clusterStateObj->path(qq{map/RPAStateOutput[key="$rpaName"]});
            my $rpaInfo = $self->parseRpaInfo($rpaObj, $rpaStateObj);
            my $rpas = $clusterInfo->{RPAS};
            push(@$rpas, $rpaInfo);
            my $nics = $rpaInfo->{ETH_INTERFACES};
            foreach my $nic (@$nics){
                if ( $nic->{IP} eq '10.0.255.11' ){
                    $currentRpa = $rpaInfo;
                    $currentClusterName = $clusterName;
                }
            }
        }
        push(@clusters, $clusterInfo);
    }

    foreach my $key (keys(%$currentRpa)){
        $data->{$key} = $currentRpa->{$key};
    }
    $data->{DEV_NAME} = $currentClusterName . '/' . $currentRpa->{NAME};
    
    $data->{CLUSTERS} = \@clusters;

    return $data;
}

sub parseGroupStat{
    my ($self, $groupObj, $groupsMap) = @_;

    my $groupName = $groupObj->attr('key');
    my $groupInfo = $groupsMap->{$groupName};
    my $copiesMap = $groupInfo->{COPIES};
    my $linksMap = $groupInfo->{LINKS};

    my @copies = $groupObj->path('map[name="groupCopyStatisticsOutput"]/GroupCopyStatisticsOutput');
    foreach my $copy (@copies){
        my $copyName = $copy->attr('key');
        my $copyInfo = $copiesMap->{$copyName};

        my $journalObj = $copy->path('JournalStatisticsOutput');
        if ( defined($journalObj) ){
            $copyInfo->{TOTAL_SIZE} = $self->bytesToG($self->getValByPath($journalObj, 'u64[name="totalBytes"]'));
            $copyInfo->{USED_SIZE} = $self->bytesToG($self->getValByPath($journalObj, 'u64[name="bytesUsed"]'));
            $copyInfo->{JOURNAL_LAG} = $self->bytesToM($self->getValByPath($journalObj, 'u64[name="journalLagInBytes"]'));
            
            $copyInfo->{PORTECTION_WINDOW} = int($self->getValByPath($journalObj, 'u64[name="protectionWindow"]') / 8640000) / 10000;
            my $predictWinObj = $journalObj->path('ProtectionWindowsOutput/ProtectionWindowOutput[name="predicted"]');
            if ( defined($predictWinObj) ){
                $copyInfo->{PREDICT_PORTECTION_WINDOW} = int($self->getValByPath($predictWinObj, 'u64')/8640000)/10000;
            }

            my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst );
            my $latestSnapTime = $self->getValByPath($journalObj, 'u64[name="latest"]') / 1000 / 1000;
            ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($latestSnapTime);
            my $latestSnapTimeStr = sprintf( '%4d-%02d-%02d %02d:%02d:%02d', $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
            $copyInfo->{LATEST_SNAPSHOT} = $latestSnapTimeStr;
            
            my $storSnapTime = $self->getValByPath($journalObj, 'u64[name="imageInStorage"]') / 1000 / 1000;
            ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($storSnapTime);
            my $storSnapTimeStr = sprintf( '%4d-%02d-%02d %02d:%02d:%02d', $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
            $copyInfo->{STORAGE_SNAPSHOT} = $storSnapTimeStr;
        }

        my $sanTrafficObj = $copy->path('SanTrafficOutput');
        if ( defined ($sanTrafficObj) ){
            my $throughPut = $self->getValByPath($sanTrafficObj, 'u64[name="currentThroughput "]');
            if ( not defined($throughPut) ){
              $throughPut = $self->getValByPath($sanTrafficObj, 'u64[name="currentThroughput"]');
            }
            $copyInfo->{THROUGHPUT} = $self->bytesToM($throughPut);
            $copyInfo->{AVG_THROUGHPUT} = $self->bytesToM($self->getValByPath($sanTrafficObj, 'u64[name="averageThroughput"]'));
            $copyInfo->{WRITE_IOPS} = $self->getValByPath($sanTrafficObj, 'u64[name="currentWriteIOPS"]');
            $copyInfo->{AVG_WRITE_IOPS} = $self->getValByPath($sanTrafficObj, 'u64[name="averageWriteIOPS"]');
        }
    }

    my @links = $groupObj->path('map[name="groupLinkStatisticsOutput"]/GroupLinkStatisticsOutput');
    foreach my $link (@links){
        my $linkName = $link->attr('key');
        my $linkInfo = $linksMap->{$linkName};
        if ( not defined($linkInfo) ){
            $linkInfo = {
                NAME => $linkName
            };
            $linksMap->{$linkName} = $linkInfo;
        }
        my $linkStat = $link->path('ReplicationStatisticsOutput[name="replication"]');
        if ( defined($linkStat) ){
            $linkInfo->{LAG_TIME} = $self->getValByPath($linkStat, 'LagOutput[name="lag"]/u64[name="time"]');
            $linkInfo->{LAG_SIZE} = $self->bytesToM($self->getValByPath($linkStat, 'LagOutput[name="lag"]/u64[name="bytes"]'));
            $linkInfo->{LAG_WRITES} = $self->getValByPath($linkStat, 'LagOutput[name="lag"]/u64[name="writes"]');
            $linkInfo->{WAN_SIZE_PER_SEC} = $self->bytesToM($self->getValByPath($linkStat, 'u64[name="wanBytesPerSec"]'));
            $linkInfo->{BANDWITH_RATIO} = $self->getValByPath($linkStat, 'double[name="currentBandwidthReductionRatio"]');
            $linkInfo->{AVG_BANDWITH_RATIO} = $self->getValByPath($linkStat, 'double[name="averageBandwidthReductionRatio"]');
        }
    }
}

sub getGroupInfo{
    my ($self) = @_;
    my $data = $self->{data};
    my $ssh    = $self->{ssh};

    my $cmd;
    $cmd = 'get_groups -xml -f';
    my $cgXml = $ssh->runCmd($cmd);
    my $obj = xml_to_object($cgXml);
    
    my $groupsMap = ();
    my @groupObjs = $obj->path('map/GroupClusterCopiesOutput');
    foreach my $groupObj (@groupObjs){
        my $groupName = $groupObj->attr('key');
        my $groupInfo = {
            NAME => $groupName,
            COPIES => {},
            LINKS => {}
        };
        my @copies = $groupObj->path('map[name="copies"]/string');
        foreach my $copy (@copies){
            my $clusterName = $copy->attr('key');
            my $copyName = $copy->value();
            my $copiesMap = $groupInfo->{COPIES};
            $copiesMap->{$copyName} = {
                NAME => $copyName,
                CLUSTER_NAME => $clusterName
            };
        }
        $groupsMap->{$groupName} = $groupInfo;
    }

    $cmd = 'get_group_statistics -f -xml group=';
    my $gstatXml = $ssh->runCmd($cmd);
    my $obj = xml_to_object($gstatXml);
    @groupObjs = $obj->path('map/GroupStatisticsOutput');
    foreach my $groupObj (@groupObjs){
        $self->parseGroupStat($groupObj, $groupsMap);
    }

    my @groups = ();
    foreach my $groupInfo (values(%$groupsMap)){
        my $copiesMap = $groupInfo->{COPIES};
        my @copies = values(%$copiesMap);
        $groupInfo->{COPIES} = \@copies;

        my $linksMap = $groupInfo->{LINKS};
        my @links = values(%$linksMap);
        $groupInfo->{LINKS} = \@links;

        push(@groups, $groupInfo);
    }
    $data->{CONSISTENCY_GROUPS} = \@groups;
}

sub collect {
    my ($self) = @_;
    my $data   = $self->{data};

    $data->{_OBJ_TYPE} = 'RPA';
    $data->{APP_TYPE}  = 'RPA';
    $data->{VENDOR}    = 'EMC';
    $data->{BRAND}     = 'RPA';

    $self->getDeviceInfo();
    $self->getGroupInfo();

    return $data;
}

1;

