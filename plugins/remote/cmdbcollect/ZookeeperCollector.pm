#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package ZookeeperCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;

sub getConfig {
    return {
        regExps  => ['\borg.apache.zookeeper.server.quorum.QuorumPeerMain\b'],    #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },                                           #ps的属性的精确匹配
        envAttrs => {}                                                            #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

sub collect {
    my ($self) = @_;
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $envMap           = $procInfo->{ENVIRONMENT};
    my $matchedProcsInfo = $self->{matchedProcsInfo};
    my $exeFile          = $procInfo->{EXECUTABLE_FILE};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};

    my $zooLibPath;
    my $homePath;
    my $version;

    my $zooLibPath;
    if ( $cmdLine =~ /-cp\s+.*?[:;]([^:;]*?[\/\\]zookeeper[^\/\\]*?\.jar)/ ) {
        $zooLibPath = dirname($1);
    }
    elsif ( $envMap->{CLASSPATH} =~ /.*?[:;]([^:;]*?[\/\\]zookeeper[^\/\\]*?\.jar)/ ) {
        $zooLibPath = dirname($1);
    }

    if ( defined($zooLibPath) ) {
        if ( $zooLibPath =~ /^.\// or $zooLibPath =~ /^[^\/\\]/ ) {
            my $workPath = readlink("/proc/$pid/cwd");
            $zooLibPath = "$workPath/$zooLibPath";
        }
        print("INFO: Get zookeeper lib path:$zooLibPath\n");
        $zooLibPath = Cwd::abs_path($zooLibPath);
        print("INFO: Get zookeeper absolute lib path:$zooLibPath\n");

        $homePath = $zooLibPath;
        foreach my $lib ( glob("$zooLibPath/zookeeper-*.jar") ) {
            if ( $lib =~ /zookeeper-([\d\.\-]+)\.jar/ ) {
                $version = $1;
                $appInfo->{MAIN_LIB} = $lib;
            }
        }
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: Can not get home path from command:$cmdLine, failed.\n");
        return;
    }
    $appInfo->{BIN_PATH}     = dirname($exeFile);
    $appInfo->{EXE_PATH}     = $exeFile;
    $appInfo->{INSTALL_PATH} = $homePath;
    $appInfo->{VERSION}      = $version;

    if ( $version =~ /(\d+)/ ) {
        $appInfo->{MAJOR_VERSION} = "Zookeeper$1";
    }

    my $pos          = rindex( $cmdLine, 'QuorumPeerMain' ) + 15;
    my $confPath     = substr( $cmdLine, $pos );
    my $realConfPath = $confPath;
    if ( $confPath =~ /^\.{1,2}[\/\\]/ ) {
        if ( -e "/proc/$pid/cwd" ) {
            my $workPath = readlink("/proc/$pid/cwd");
            $realConfPath = Cwd::abs_path("$workPath/$confPath");
        }
        if ( not -e $realConfPath ) {
            $realConfPath = Cwd::abs_path("$homePath/$confPath");
        }
        if ( not -e $realConfPath ) {
            $realConfPath = Cwd::abs_path("$homePath/bin/$confPath");
        }
    }
    else {
        $realConfPath = Cwd::abs_path($confPath);
    }
    if ( defined($realConfPath) ) {
        $confPath                    = $realConfPath;
        $appInfo->{CONFIG_PATH}      = dirname($realConfPath);
        $appInfo->{CONFIG_FILE_PATH} = $realConfPath;
    }
    $self->getJavaAttrs($appInfo);
    my ( $ports, $port ) = $self->getPortFromProcInfo($appInfo);
    my $clusterMembers = [];
    my $confMap        = {};
    my $primaryMember;
    my $primaryMemberPort;

    my $primaryMemberNo = 0;
    my $confLines       = $self->getFileLines($confPath);

    foreach my $line (@$confLines) {
        $line =~ s/^\s*|\s*$//g;
        if ( $line !~ /^#/ ) {
            my ( $key, $val ) = split( /\s*=\s*/, $line );
            $confMap->{$key} = $val;

            #tickTime==>2000
            #initLimit==>10
            #syncLimit==>5
            #dataDir==>/app/app/zookeeper_home/data
            #dataLogDir==>/app/app/zookeeper_home/log
            #clientPort==>2181

            # server.1=192.168.1.122:2182:2183
            # server.2=192.168.1.123:2182:2183
            # server.3=192.168.1.124:2182:2183
            if ( $key =~ /server\.(\d+)/ ) {
                my @ipInfos = split( ':', $val );
                if ( scalar(@ipInfos) < 2 ) {
                    next;
                }

                push( @$clusterMembers, "$ipInfos[0]:$ipInfos[1]" );
                push( @$clusterMembers, "$ipInfos[0]:$ipInfos[2]" );
                my $memberNo = int($1);
                if ( $memberNo < $primaryMemberNo ) {
                    $primaryMemberNo   = $memberNo;
                    $primaryMember     = $ipInfos[0];
                    $primaryMemberPort = $ipInfos[1];
                }
            }
        }
    }

    $appInfo->{DATA_PATH}      = $confMap->{dataDir};
    $appInfo->{LOG_PATH}       = $confMap->{dataLogDir};
    $appInfo->{PORT}           = $confMap->{clientPort};
    $appInfo->{TICK_TIME}      = $confMap->{tickTime};
    $appInfo->{INIT_LIMIT}     = $confMap->{initLimit};
    $appInfo->{SYNC_LIMIT}     = $confMap->{syncLimit};
    $appInfo->{ADMIN_PORT}     = $confMap->{'admin.serverPort'};
    $appInfo->{ADMIN_ENABLE}   = $confMap->{'admin.enableServer'};
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;

    $appInfo->{SERVER_NAME}   = $procInfo->{HOST_NAME};
    $appInfo->{INSTANCE_NAME} = $procInfo->{HOST_NAME};

    my $clusterInfo = undef;
    if ( scalar(@$clusterMembers) > 1 ) {
        $clusterInfo = {
            _OBJ_CATEGORY => CollectObjCat->get('CLUSTER'),
            _OBJ_TYPE     => 'ZookeeperCluster'
        };
        my $uniqName = 'Zookeeper:' . $primaryMember;
        $clusterInfo->{UNIQUE_NAME} = $uniqName;
        $clusterInfo->{NAME}        = $uniqName;
        my $primaryIp = gethostbyname($primaryMember);
        if ( defined($primaryIp) ) {
            $clusterInfo->{PRIMARY_IP} = inet_ntoa($primaryIp);
        }

        $clusterInfo->{PORT}             = $primaryMemberPort;
        $clusterInfo->{CLUSTER_MODE}     = 'Cluster';
        $clusterInfo->{CLUSTER_SOFTWARE} = 'Zookeeper';
        $clusterInfo->{CLUSTER_VERSION}  = $version;
        $clusterInfo->{MEMBER_PEER}      = $clusterMembers;
    }

    return ( $appInfo, $clusterInfo );
}

1;
