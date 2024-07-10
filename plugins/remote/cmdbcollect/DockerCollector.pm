#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package DockerCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;
use JSON;
use HTTP::Tiny;

use ProcessFinder;
use OSGather;
use ConnGather;
use NSSwitcher;

sub init {
    my ($self) = @_;
    $self->{http} = HTTP::Tiny->new(
        default_headers => {},
        timeout         => 5
    );
    $self->{nsSwitcher} = NSSwitcher->new();
}

sub getConfig {
    return {
        seq      => 10000,
        regExps  => [],
        psAttrs  => { COMM => 'dockerd' },
        envAttrs => {}
    };
}

sub getApiBaseUrl {
    my ( $self, $cmdLine ) = @_;

    my $apiBaseUrl = 'http://unix:///var/run/docker.sock';
    my @customUrls = ();
    if ( $cmdLine =~ /--config-file(=\S*)/ ) {
        my $confFile = $1;
        $confFile =~ s/^=//;
        if ( not defined($confFile) or $confFile eq '' ) {
            $confFile = '/etc/docker/daemon.json';
        }
        if ( -e $confFile ) {
            my $confContent = $self->getFileContent($confFile);
            my $confJson    = from_json($confContent);
            my $confUrls    = $confJson->{hosts};
            if (@$confUrls) {
                for my $confUrl (@$confUrls) {
                    push( @customUrls, $confUrl );
                }
            }
        }
    }
    while ( $cmdLine =~ /-H|--host=(\S+)/ ) {
        push( @customUrls, $1 );
    }
    if (@customUrls) {
        my @sortedCustomUrls = sort(@customUrls);
        my $customUrl        = pop(@sortedCustomUrls);

        if ( $customUrl =~ /^unix:\/\/.*/ ) {
            $apiBaseUrl = "http://$customUrl";
        }
        elsif ( $customUrl =~ /^tcp:\/\/(.*)/ ) {
            $apiBaseUrl = "http://$1";
        }
        else {
            $apiBaseUrl = $customUrl;
        }
    }

    $apiBaseUrl =~ s/\/+$//g;
    $self->{apiBaseUrl} = $apiBaseUrl;
    my $versionInfo = $self->callDockerApi("/version");
    $apiBaseUrl = $apiBaseUrl . '/v' . $versionInfo->{ApiVersion};
    $self->{apiBaseUrl} = $apiBaseUrl;

    return $apiBaseUrl;
}

sub callDockerApi {
    my ( $self, $apiUri ) = @_;
    my $apiBaseUrl = $self->{apiBaseUrl};
    my $http       = $self->{http};
    my $response   = $http->get("$apiBaseUrl$apiUri");
    if ( $response->{success} ) {
        return from_json( $response->{content} );
    }
    else {
        print( "WARN: " . $response->{content} );
        return '';
    }
}

sub getContainerProcesses {
    my ( $self, $dockerInfo, $containerId ) = @_;

    #/containers/containerId/top
    my $processesInfo = $self->callDockerApi("/containers/$containerId/top");

    my @processList = ();
    my $processMap  = {};
    my $titles      = $processesInfo->{Titles};
    my $processList = $processesInfo->{Processes};
    my $fieldsCount = scalar(@$titles);
    foreach my $procArray (@$processList) {
        my $process = {};
        for ( my $i = 0 ; $i < $fieldsCount ; $i++ ) {
            $process->{ $$titles[$i] } = $$procArray[$i];
        }
        push( @processList, $process );
        $processMap->{ $process->{PID} } = $process;
    }

    return ( \@processList, $processMap );
}

sub getContainerDetail {
    my ( $self, $dockerInfo, $containerId ) = @_;

    print("INFO: Begin to collect container $containerId.\n");

    #/v1.24/containers/97d1cae09135/json
    my $detailInfo = $self->callDockerApi("/containers/$containerId/json");

    my $osPid  = $detailInfo->{State}->{Pid};
    my $cgroup = $detailInfo->{HostConfig}->{CgroupParent};

    #$dockerInfo->{OS_PID}     = $osPid;
    $dockerInfo->{PLATFORM} = $detailInfo->{Platform};
    $dockerInfo->{DRIVER}   = $detailInfo->{Driver};
    $dockerInfo->{HOSTNAME} = $detailInfo->{Hostname};

    my $networks = $detailInfo->{NetworkSettings}->{Networks};
    if ( defined($networks) ) {
        my @netNics = values(%$networks);
        if (@netNics) {
            $dockerInfo->{IPADDRESS}  = $netNics[0]->{IPAddress};
            $dockerInfo->{GATEWAY}    = $netNics[0]->{Gateway};
            $dockerInfo->{MACADDRESS} = $netNics[0]->{MacAddress};
        }
    }
    else {
        $dockerInfo->{IPADDRESS}  = $detailInfo->{NetworkSettings}->{IPAddress};
        $dockerInfo->{GATEWAY}    = $detailInfo->{NetworkSettings}->{Gateway};
        $dockerInfo->{MACADDRESS} = $detailInfo->{NetworkSettings}->{MacAddress};
    }

    my $managedMethod = 'Standalone';
    if ( $cgroup =~ /kubepods/ ) {
        $managedMethod = 'K8s';
    }
    $dockerInfo->{MANAGED_METHOD} = $managedMethod;

    my @mountList = ();
    my $mounts    = $detailInfo->{Mounts};
    foreach my $mt (@$mounts) {
        my $mountInfo = {};
        $mountInfo->{TYPE}        = $mt->{Type};
        $mountInfo->{SOURCE}      = $mt->{Source};
        $mountInfo->{DESTINATION} = $mt->{Destination};
        $mountInfo->{MODE}        = $mt->{Mode};
        $mountInfo->{RW}          = $mt->{RW};
        $mountInfo->{PROPAGATION} = $mt->{Propagation};
        push( @mountList, $mountInfo );
    }
    $dockerInfo->{MOUNTS} = \@mountList;

    my @envList = ();
    my $env     = $detailInfo->{Config}->{Env};
    foreach my $line (@$env) {
        my @envInfo = split( /=/, $line, 2 );
        my $key     = @envInfo[0];
        my $value   = @envInfo[1];
        if ( $key =~ /PASSWORD/ or $key =~ /password/ ) {
            $value = '******';
        }
        push( @envList, { KEY => $key, VALUE => $value } );
    }
    $dockerInfo->{ENV} = \@envList;

    $self->getContainerStats( $dockerInfo, $containerId );

    my @processes = ();
    my ( $prcoessList, $processMap ) = $self->getContainerProcesses( $dockerInfo, $containerId );
    my $pFinder  = $self->{pFinder};
    my $nsTarget = $$prcoessList[0]->{PID};

    #获取收集网络信息的实现类
    my $inspect   = $self->{inspect};
    my $ipAddr    = $dockerInfo->{IPADDRESS};
    my @ipv4Addrs = ();
    my @ipv6Addrs = ();
    if ( $ipAddr =~ /^\d+\.\d+\.\d+\.\d+$/ ) {
        push( @ipv4Addrs, $ipAddr );
    }
    else {
        push( @ipv6Addrs, $ipAddr );
    }

    my $nsSwitcher = $self->{nsSwitcher};
    $nsSwitcher->joinNamespace($nsTarget);

    my $connGather = ConnGather->new( $self->{inspect}, 1 );

    #取容器内第一个进程作为namespace target
    my $dockerPFinder = ProcessFinder->new(
        $pFinder->{procFilters},
        connGather  => $connGather,
        passArgs    => $pFinder->{passArgs},
        inspect     => $inspect,
        bizIp       => $ipAddr,
        ipv4Addrs   => \@ipv4Addrs,
        ipv6Addrs   => \@ipv6Addrs,
        procEnvName => $pFinder->{procEnvName},
        container   => $pFinder->{container}
    );
    $dockerPFinder->{mgmtIp} = $ipAddr;

    my $appsMap = $dockerPFinder->findProcess( undef, $containerId );

    my $connInfo    = $connGather->getListenInfo();
    my $portInfoMap = $dockerPFinder->getListenPortInfo( $connInfo->{LISTEN} );
    $dockerInfo->{PORT_BIND} = $portInfoMap;
    $dockerInfo->{CONN_INFO} = $connInfo;
    my $statInfo = $connGather->getStatInfo( undef, $connInfo->{LISTEN} );
    $connInfo->{PEER}  = $statInfo->{PEER};
    $connInfo->{STATS} = $statInfo->{STATS};

    my $appsArray = $dockerPFinder->{appsArray};

    #处理存在父子关系的进程的连接信息，并合并到父进程
    my $apps = $dockerPFinder->mergeMultiProcs( $appsArray, $appsMap, [ { IP => $ipAddr } ], [] );
    $dockerInfo->{APPS} = $apps;

    $nsSwitcher->restoreNamespace();
}

sub getContainerStats {
    my ( $self, $dockerInfo, $containerId ) = @_;

    my $statInfo = $self->callDockerApi("/containers/$containerId/stats?stream=0");
    my $cpuUsage = int( ( $statInfo->{cpu_stats}->{cpu_usage}->{total_usage} - $statInfo->{precpu_stats}->{cpu_usage}->{total_usage} ) * 10000 / ( $statInfo->{cpu_stats}->{system_cpu_usage} - $statInfo->{precpu_stats}->{system_cpu_usage} ) ) / 100;
    my $memUsed  = int( $statInfo->{memory_stats}->{usage} / 1024 / 1024 );
    my $memLimit = int( $statInfo->{memory_stats}->{limit} / 1024 / 1024 );
    my $memUsage = int( $memUsed * 10000 / $memLimit ) * 100;

    $dockerInfo->{CPU_USAGE} = $cpuUsage;
    $dockerInfo->{MEM_USED}  = $memUsed;
    $dockerInfo->{MEM_LIMIT} = $memLimit;
    $dockerInfo->{MEM_USAGE} = $memUsage;

    # $dockerInfo->{NET_IO}   = $netIo;
    # $dockerInfo->{BLOCK_IO} = $blockIo;
    # $dockerInfo->{PIDS}     = $pids;
}

sub getAllContainers {
    my ($self) = @_;

    my $procInfo = $self->{procInfo};
    my $mgmtIp   = $procInfo->{MGMT_IP};

    my $objCat = CollectObjCat->get('CONTAINER');

    #/containers/json
    my $containerList = $self->callDockerApi('/containers/json');

    my @containers = ();
    foreach my $info (@$containerList) {
        my $dockerInfo = {
            _OBJ_CATEGORY => $objCat,
            _OBJ_TYPE     => 'Docker',
            RESOURCE_ID   => 0
        };

        $dockerInfo->{CONTAINER_ID} = $info->{Id};
        $dockerInfo->{NAME}         = $info->{Names}[0];
        $dockerInfo->{IMAGE}        = $info->{Image};
        $dockerInfo->{IMAGE_ID}     = $info->{ImageID};
        $dockerInfo->{COMMAND}      = $info->{Command};
        $dockerInfo->{CREATED}      = $info->{Created};
        $dockerInfo->{UPTIME}       = $info->{Status};
        $dockerInfo->{STATUS}       = $info->{State};
        $dockerInfo->{PORTS}        = $info->{Ports};

        my $detailInfo = $self->getContainerDetail( $dockerInfo, $info->{Id} );

        #把Docker的管理IP设置为OS IP
        $dockerInfo->{MGMT_IP}     = $mgmtIp;
        $dockerInfo->{NOT_PROCESS} = 1;
        $dockerInfo->{RUN_ON}      = [
            {
                '_OBJ_CATEGORY' => 'OS',
                '_OBJ_TYPE'     => $self->{ostype},
                'OS_ID'         => $procInfo->{OS_ID},
                'MGMT_IP'       => $mgmtIp
            }
        ];
        push( @containers, $dockerInfo );
    }

    return \@containers;
}

sub collect {
    my ($self) = @_;
    if ( $self->{ostype} !~ /Linux/i ) {
        print("WARN: Docker collect only support linux.\n");
        return;
    }

    my $pFinder = $self->{pFinder};
    if ( not $pFinder->{container} ) {
        return;
    }

    #获取docker的通讯地址
    print("INFO: Try to collect docker container detail information...\n");
    my $apiBaseUrl = $self->getApiBaseUrl();
    my $containers = $self->getAllContainers();
    print("INFO: Docker container detail information collected.\n");

    return @$containers;
}

1;
