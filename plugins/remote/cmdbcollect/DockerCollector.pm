#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package DockerCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use ProcessFinder;
use OSGather;
use ConnGather;
use ProcessFinder;

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;
use JSON;

sub getConfig {
    return {
        seq      => 10000,
        regExps  => [],
        psAttrs  => { COMM => 'dockerd' },
        envAttrs => {}
    };
}

sub trim {
    my ( $self, $value ) = @_;
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub getContainerProcess {
    my ( $self, $osPid, $containerId ) = @_;
    my @psList = ();
    $osPid = int($osPid);
    if ( $osPid < 1 ) {
        return @psList;
    }
    my $psCmd  = qq{nsenter -t $osPid -p -n -r  ps -eo pid,ppid,pgid,user,group,ruser,rgroup,pcpu,pmem,time,etime,comm,args};
    my $psInfo = $self->getCmdOutLines($psCmd);
    my @fields;
    my $fieldsCount;
    foreach my $line (@$psInfo) {
        if ( $line =~ /PID/ ) {
            $line =~ s/^\s*|\s*$//g;
            $line =~ s/^.*?PID/PID/g;
            my $cmdPos = rindex( $line, ' ' );
            @fields      = split( /\s+/, substr( $line, 0, $cmdPos ) );
            $fieldsCount = scalar(@fields);
        }
        else {
            my $ins = {};
            $line =~ s/^\s*|\s*$//g;
            my @vars = split( /\s+/, $line );
            for ( my $i = int(0) ; $i < $fieldsCount ; $i++ ) {
                if ( $fields[$i] eq 'COMMAND' ) {
                    $ins->{COMM} = shift(@vars);
                }
                else {
                    $ins->{ $fields[$i] } = shift(@vars);
                }
            }
            $ins->{COMMAND} = join( ' ', @vars );
            push( @psList, $ins );
        }
    }

=pod
    if (scalar(@psList) == 0 ){
        my $dockerTop = $self->getCmdOutLines("docker top $containerId"); 
        foreach my $line (@$dockerPs){
            if( $line =~ /PID/){
                $line =~ s/^\s*|\s*$//g;
                $line =~ s/^.*?PID/PID/g;
                my $cmdPos      = rindex( $line, ' ' );
                @fields      = split( /\s+/, substr( $line, 0, $cmdPos ) );
                $fieldsCount = scalar(@fields);
            }else{
                my $ins ={};
                $line =~ s/^\s*|\s*$//g;
                my @vars = split( /\s+/, $line );
                for ( my $i = int(0); $i < $fieldsCount ; $i++ ) {
                    if ( $fields[$i] eq 'COMMAND' ) {
                        $ins->{COMM} = shift(@vars);
                    }
                    else {
                        $ins->{ $fields[$i] } = shift(@vars);
                    }
                }
                $ins->{COMMAND} = join( ' ', @vars );
                push(@psList , $ins );
            }
        }
    }
=cut

    return @psList;
}

sub getContainerId {
    my ( $self, $pid ) = @_;
    my $fh          = IO::File->new("</proc/$pid/cgroup");
    my $containerId = '';
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            $line =~ s/^\s*|\s*$//g;
            my $len = rindex( $line, '/' );
            if ( index( $line, '.slice' ) >= 0 ) {
                $containerId = substr( $line, $len + 1, length($line) );
                $containerId =~ s/docker-//g;
                $containerId =~ s/\.scope//g;
                last;
            }
            else {
                $containerId = substr( $line, $len + 1, length($line) );
                last;
            }
        }
        $fh->close();
    }
    $containerId =~ s/(^s+|s+$)//g;
    return $containerId;
}

sub getContainerInfo {
    my ( $self, $containerId, $docker ) = @_;
    my $dockerPs = $self->getCmdOutLines("docker ps --no-trunc | grep $containerId");
    foreach my $line (@$dockerPs) {
        my @lineInfo    = split( /  +/, $line );
        my $containerId = $self->trim( @lineInfo[0] );
        $docker->{CONTAINER_ID} = $containerId;
        $docker->{IMAGE}        = $self->trim( @lineInfo[1] );
        $docker->{COMMAND}      = $self->trim( @lineInfo[2] );
        $docker->{CREATED}      = $self->trim( @lineInfo[3] );
        $docker->{UPTIME}       = $self->trim( @lineInfo[4] );
        $docker->{PORTS}        = $self->trim( @lineInfo[5] );
        $docker->{NAME}         = $self->trim( @lineInfo[6] );

        #docker 容器详情
        my $dockerInfo    = $self->getCmdOut("docker inspect $containerId");
        my $dockerInspect = from_json($dockerInfo);
        my $dockerObj     = @$dockerInspect[0];
        my $osPid         = $dockerObj->{State}->{Pid};
        my $cgroup        = $dockerObj->{HostConfig}->{CgroupParent};

        $docker->{OS_PID}     = $osPid;
        $docker->{PLATFORM}   = $dockerObj->{Platform};
        $docker->{DRIVER}     = $dockerObj->{Driver};
        $docker->{IPADDRESS}  = $dockerObj->{NetworkSettings}->{IPAddress};
        $docker->{GATEWAY}    = $dockerObj->{NetworkSettings}->{Gateway};
        $docker->{MACADDRESS} = $dockerObj->{NetworkSettings}->{MacAddress};
        $docker->{HOSTNAME}   = $dockerObj->{Hostname};
        $docker->{STATUS}     = $dockerObj->{State}->{Status};

        my $managedMethod = 'Standalone';
        if ( $cgroup =~ /kubepods/ ) {
            $managedMethod = 'K8s';
        }
        $docker->{MANAGED_METHOD} = $managedMethod;
        my @mountList = ();
        my $mounts    = $dockerObj->{Mounts};
        foreach my $mt (@$mounts) {
            my $ins = {};
            $ins->{TYPE}        = $mt->{Type};
            $ins->{SOURCE}      = $mt->{Source};
            $ins->{DESTINATION} = $mt->{Destination};
            $ins->{MODE}        = $mt->{Mode};
            $ins->{RW}          = $mt->{RW};
            $ins->{PROPAGATION} = $mt->{Propagation};
            push( @mountList, $ins );
        }
        $docker->{MOUNTS} = \@mountList;

        my @envList = ();
        my $env     = $dockerObj->{Config}->{Env};
        foreach my $line (@$env) {
            my @lineInfo = split( /=/, $line );
            if ( scalar(@lineInfo) < 1 ) {
                next;
            }
            my $ins   = {};
            my $key   = @lineInfo[0];
            my $value = @lineInfo[1];
            if ( $key =~ /PASSWORD/ or $key =~ /password/ ) {
                $value = '******';
            }
            $ins->{KEY}   = $key;
            $ins->{VALUE} = $value;
            push( @envList, $ins );
        }
        $docker->{ENV} = \@envList;
    }
    return $docker;
}

sub getContainerImages {
    my ( $self, $imagesId ) = @_;
    my $dockerImages = $self->getCmdOutLines("docker images  --no-trunc | grep $imagesId");
    my $imageIns     = {};
    foreach my $line (@$dockerImages) {
        my @lineInfo   = split( /  +/, $line );
        my $repository = $self->trim( @lineInfo[0] );
        my $tag        = $self->trim( @lineInfo[1] );
        my $name       = "$repository:$tag";
        my $imageId    = $self->trim( @lineInfo[2] );

        $imageIns->{REPOSITORY} = $repository;
        $imageIns->{TAG}        = $tag;
        $imageIns->{NAME}       = $name;
        $imageIns->{IMAGE_ID}   = $imageId;
        $imageIns->{CREATED}    = $self->trim( @lineInfo[3] );
        $imageIns->{SIZE}       = $self->trim( @lineInfo[4] );
    }
    return $imageIns;
}

sub getContainerStats {
    my ( $self, $containerId, $docker ) = @_;
    my $dockerStats = $self->getCmdOutLines("docker stats --no-stream  --no-trunc | grep $containerId");
    foreach my $line (@$dockerStats) {

        my @lineInfo    = split( /  +/, $line );
        my $containerId = $self->trim( @lineInfo[0] );

        $docker->{CONTAINER_ID} = $containerId;
        $docker->{NAME}         = $self->trim( @lineInfo[1] );
        $docker->{CPU_USAGE}    = $self->trim( @lineInfo[2] );

        my @menInfo = split( /\//, @lineInfo[3] );
        $docker->{MEM_USED}  = $self->trim( @menInfo[0] );
        $docker->{MEM_LIMIT} = $self->trim( @menInfo[1] );
        $docker->{MEM_USAGE} = $self->trim( @lineInfo[4] );

        $docker->{NET_IO}   = $self->trim( @lineInfo[5] );
        $docker->{BLOCK_IO} = $self->trim( @lineInfo[6] );
        $docker->{PIDS}     = $self->trim( @lineInfo[7] );
    }
    return $docker;
}

sub mergeMultiProcs {
    my (@psList) = @_;
    print("INFO: Begin to merge connection information with parent processes...\n");
    my $parentPsMap = {};
    foreach my $info (@psList) {
        my ( $parentConnStats, $parentOutBoundStat );
        if ( defined( $parentPsMap->{ConnStats} ) ) {
            $parentConnStats    = $parentPsMap->{ConnStats};
            $parentOutBoundStat = $parentPsMap->{OutBoundStat};
        }
        else {
            $parentConnStats->{TOTAL_COUNT}          = int(0);
            $parentConnStats->{INBOUND_COUNT}        = int(0);
            $parentConnStats->{OUTBOUND_COUNT}       = int(0);
            $parentConnStats->{SYN_RECV_COUNT}       = int(0);
            $parentConnStats->{CLOSE_WAIT_COUNT}     = int(0);
            $parentConnStats->{RECV_QUEUED_COUNT}    = int(0);
            $parentConnStats->{SEND_QUEUED_COUNT}    = int(0);
            $parentConnStats->{RECV_QUEUED_SIZE}     = int(0);
            $parentConnStats->{SEND_QUEUED_SIZE}     = int(0);
            $parentConnStats->{RECV_QUEUED_RATE}     = int(0);
            $parentConnStats->{SEND_QUEUED_RATE}     = int(0);
            $parentConnStats->{RECV_QUEUED_SIZE_AVG} = int(0);
            $parentConnStats->{SEND_QUEUED_SIZE_AVG} = int(0);

            $parentOutBoundStat->{OUTBOUND_COUNT}       = int(0);
            $parentOutBoundStat->{SEND_QUEUED_SIZE}     = int(0);
            $parentOutBoundStat->{SYN_SENT_COUNT}       = int(0);
            $parentOutBoundStat->{SEND_QUEUED_RATE}     = int(0);
            $parentOutBoundStat->{SEND_QUEUED_SIZE_AVG} = int(0);

        }
        my $currentConnStats = $info->{statInfo}->{STATS};
        $parentConnStats->{TOTAL_COUNT}       = $parentConnStats->{TOTAL_COUNT} + $currentConnStats->{TOTAL_COUNT};
        $parentConnStats->{INBOUND_COUNT}     = $parentConnStats->{INBOUND_COUNT} + $currentConnStats->{INBOUND_COUNT};
        $parentConnStats->{OUTBOUND_COUNT}    = $parentConnStats->{OUTBOUND_COUNT} + $currentConnStats->{OUTBOUND_COUNT};
        $parentConnStats->{SYN_RECV_COUNT}    = $parentConnStats->{SYN_RECV_COUNT} + $currentConnStats->{SYN_RECV_COUNT};
        $parentConnStats->{CLOSE_WAIT_COUNT}  = $parentConnStats->{CLOSE_WAIT_COUNT} + $currentConnStats->{CLOSE_WAIT_COUNT};
        $parentConnStats->{RECV_QUEUED_COUNT} = $parentConnStats->{RECV_QUEUED_COUNT} + $currentConnStats->{RECV_QUEUED_COUNT};
        $parentConnStats->{SEND_QUEUED_COUNT} = $parentConnStats->{SEND_QUEUED_COUNT} + $currentConnStats->{SEND_QUEUED_COUNT};
        $parentConnStats->{RECV_QUEUED_SIZE}  = $parentConnStats->{RECV_QUEUED_SIZE} + $currentConnStats->{RECV_QUEUED_SIZE};
        $parentConnStats->{SEND_QUEUED_SIZE}  = $parentConnStats->{SEND_QUEUED_SIZE} + $currentConnStats->{SEND_QUEUED_SIZE};

        if ( $parentConnStats->{TOTAL_COUNT} > 0 ) {
            $parentConnStats->{RECV_QUEUED_RATE}     = int( $parentConnStats->{RECV_QUEUED_COUNT} * 10000 / $parentConnStats->{TOTAL_COUNT} + 0.5 ) / 100;
            $parentConnStats->{SEND_QUEUED_RATE}     = int( $parentConnStats->{SEND_QUEUED_COUNT} * 10000 / $parentConnStats->{TOTAL_COUNT} + 0.5 ) / 100;
            $parentConnStats->{RECV_QUEUED_SIZE_AVG} = int( $parentConnStats->{RECV_QUEUED_SIZE} * 100 / $parentConnStats->{TOTAL_COUNT} + 0.5 ) / 100;
            $parentConnStats->{SEND_QUEUED_SIZE_AVG} = int( $parentConnStats->{SEND_QUEUED_SIZE} * 100 / $parentConnStats->{TOTAL_COUNT} + 0.5 ) / 100;
        }

        #基于调用OutBound（目标）的统计信息合并
        my $parentOutBoundStats  = $parentConnStats->{OUTBOUND_STATS};
        my $currentOutBoundStats = $currentConnStats->{OUTBOUND_STATS};
        while ( my ( $remoteAddr, $outBoundStat ) = each(%$currentOutBoundStats) ) {
            my $parentOutBoundStat = $parentOutBoundStats->{$remoteAddr};
            $parentOutBoundStat->{OUTBOUND_COUNT}   = $parentOutBoundStat->{OUTBOUND_COUNT} + $outBoundStat->{OUTBOUND_COUNT};
            $parentOutBoundStat->{SEND_QUEUED_SIZE} = $parentOutBoundStat->{SEND_QUEUED_SIZE} + $outBoundStat->{SEND_QUEUED_SIZE};
            $parentOutBoundStat->{SYN_SENT_COUNT}   = $parentOutBoundStat->{SYN_SENT_COUNT} + $outBoundStat->{SYN_SENT_COUNT};

            if ( $parentOutBoundStat->{OUTBOUND_COUNT} > 0 ) {
                $parentOutBoundStat->{SEND_QUEUED_RATE}     = int( $parentOutBoundStat->{SEND_QUEUED_RATE} * 10000 / $parentOutBoundStat->{OUTBOUND_COUNT} + 0.5 ) / 100;
                $parentOutBoundStat->{SEND_QUEUED_SIZE_AVG} = int( $parentOutBoundStat->{SEND_QUEUED_SIZE} * 100 / $parentOutBoundStat->{OUTBOUND_COUNT} + 0.5 ) / 100;
            }
        }
        $parentPsMap->{ConnStats}    = $parentConnStats;
        $parentPsMap->{OutBoundStat} = $parentOutBoundStat;
    }
    print("INFO: Connection information merged.\n");
    return $parentPsMap;
}

sub getContainerConn {
    my ( $self, $osPid, $containerId, $docker ) = @_;
    if ( not defined($docker) or not defined($osPid) or $osPid eq '' ) {
        next;
    }
    my $isContainer = 1;
    my @psList      = $self->getContainerProcess( $osPid, $containerId );
    my $pFinder     = ProcessFinder->new();
    foreach my $process (@psList) {
        my $pid         = $process->{PID};
        my $connGather  = ConnGather->new(1);
        my $connInfo    = $connGather->getListenInfo( $pid, 1 );
        my $portInfoMap = $pFinder->getListenPortInfo( $connInfo->{LISTEN} );
        $process->{PORT_BIND} = $portInfoMap;
        $process->{CONN_INFO} = $connInfo;
        my $statInfo = $connGather->getStatInfo( $pid, $connInfo->{LISTEN}, $isContainer );
        $process->{statInfo} = $statInfo;
    }
    $docker->{PROCESS} = \@psList;

    my $connMap             = $self->mergeMultiProcs(@psList);
    my $CONN_STATS          = $connMap->{ConnStats};
    my $CONN_OUTBOUND_STATS = $connMap->{OutBoundStat};
    $docker->{CONN_STATS}          = $CONN_STATS;
    $docker->{CONN_OUTBOUND_STATS} = $CONN_OUTBOUND_STATS;

    return $docker;
}

sub collect {
    my ($self) = @_;
    my $utils = $self->{collectUtils};

    my $procInfo    = $self->{procInfo};
    my $cmdLine     = $procInfo->{COMMAND};
    my $MGMT_PORT   = $procInfo->{MGMT_PORT};
    my $MGMT_IP     = $procInfo->{MGMT_IP};
    my $osPid       = $procInfo->{PID};
    my $osPPid      = int( $procInfo->{PPID} );
    my $containerId = $self->getContainerId($osPid);
    if ( not defined($containerId) or $containerId eq '' or $osPPid <= 1 or $containerId eq 'docker.service' ) {
        return undef;
    }

    my $docker = {};
    $docker->{_OBJ_CATEGORY} = CollectObjCat->get('CONTAINER');
    $docker->{_OBJ_TYPE}     = 'Docker';
    $docker->{MGMT_PORT}     = $MGMT_PORT;
    $docker->{MGMT_IP}       = $MGMT_IP;

    #计算RESOURCE_ID
    $docker->{RESOURCE_ID} = '0';

    $self->getContainerInfo( $containerId, $docker );
    my $images = $docker->{IMAGE};
    if ( $images =~ /sha256:\s*/ ) {
        my $dockerImages = $self->getContainerImages($images);
        $docker->{IMAGE} = $dockerImages->{NAME};
    }

    $self->getContainerStats( $containerId, $docker );

    $self->getContainerConn( $osPid, $containerId, $docker );
    return $docker;
}

1;
