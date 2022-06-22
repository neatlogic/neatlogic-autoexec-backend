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
            if ( $lib =~ /zookeeper-([\d\.]+)\.jar/ ) {
                $version = $1;
                $appInfo->{MAIN_LIB} = $lib;
            }
        }
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: Can not get home path from command:$cmdLine, failed.\n");
        return;
    }

    $appInfo->{INSTALL_PATH} = $homePath;
    $appInfo->{VERSION}      = $version;

    my $pos      = rindex( $cmdLine, 'QuorumPeerMain' ) + 15;
    my $confPath = substr( $cmdLine, $pos );

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
        $confPath = $realConfPath;
        $appInfo->{CONFIG_PATH} = dirname($realConfPath);
    }

    $self->getJavaAttrs($appInfo);

    my $clusterMembers = [];
    my @members;
    my $confMap   = {};
    my $confLines = $self->getFileLines($confPath);
    foreach my $line (@$confLines) {
        $line =~ s/^\s*|\s*$//g;
        if ( $line !~ /^#/ ) {
            my ( $key, $val ) = split( /\s*=\s*/, $line );
            $confMap->{$key} = $val;

            # server.1=192.168.1.122:2182:2183
            # server.2=192.168.1.123:2182:2183
            # server.3=192.168.1.124:2182:2183
            if ( $key =~ /server\.\d+/ ) {
                push( @members, { NAME => $key, VALUE => $val } );
                my @ipInfos = split( ':', $val );
                push( @$clusterMembers, "$ipInfos[0]:$ipInfos[1]" );
                push( @$clusterMembers, "$ipInfos[0]:$ipInfos[2]" );
            }
        }
    }
    my @sortedMembers = sort (@$clusterMembers);
    @members                   = sort(@members);
    $appInfo->{DATA_DIR}       = $confMap->{dataDir};
    $appInfo->{PORT}           = $confMap->{clientPort};
    $appInfo->{ADMIN_PORT}     = $confMap->{'admin.serverPort'};
    $appInfo->{ADMIN_ENABLE}   = $confMap->{'admin.enableServer'};
    $appInfo->{MEMBERS}        = \@members;
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = $appInfo->{JMX_PORT};

    $appInfo->{NAME} = $procInfo->{HOST_NAME};

    my $clusterInfo = undef;
    if ( scalar(@$clusterMembers) > 1 ) {
        my $objCat      = CollectObjCat->get('CLUSTER');
        my $clusterInfo = {
            _OBJ_CATEGORY => $objCat,
            _OBJ_TYPE     => 'ZookeeperCluster',
            INDEX_FIELDS  => CollectObjCat->getIndexFields($objCat),
            MEMBERS       => []
        };
        my $uniqName = 'Zookeeper:' . $members[0];
        $clusterInfo->{UNIQUE_NAME}      = $uniqName;
        $clusterInfo->{NAME}             = $uniqName;
        $clusterInfo->{CLUSTER_MODE}     = 'Cluster';
        $clusterInfo->{CLUSTER_SOFTWARE} = 'Zookeeper';
        $clusterInfo->{CLUSTER_VERSION}  = $version;
        $clusterInfo->{MEMBER_PEER}      = $clusterMembers;
    }

    return ( $appInfo, $clusterInfo );
}

1;
