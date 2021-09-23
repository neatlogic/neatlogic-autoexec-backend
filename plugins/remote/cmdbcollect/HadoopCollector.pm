#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package HadoopCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjType;

sub getConfig {
    return {
        regExps  => ['\borg.apache.hadoop.hdfs.server.namenode.SecondaryNameNode\b'],    #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },                                                  #ps的属性的精确匹配
        envAttrs => {}                                                                   #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
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
    my $envMap           = $procInfo->{ENVRIONMENT};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{OBJECT_TYPE} = CollectObjType->get('INS');

    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};

    my $homePath;
    my $logPath;
    my $version;

    my $workPath = readlink("/proc/$pid/cwd");

    if ( $cmdLine =~ /-Dhadoop.home.dir=(.*?)\s+-D/ ) {
        $homePath = $1;
        if ( defined($workPath) and $homePath =~ /^\.{1,2}[\/\\]/ ) {
            $homePath = "$workPath/$homePath";
        }
        $homePath = Cwd::abs_path($homePath);
    }
    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: Can not find elasticsearch home.dir in $cmdLine, failed.\n");
        return;
    }

    $self->getJavaAttrs($appInfo);

    if ( $cmdLine =~ /-DDhadoop.log.dir=(.*?)\s+-D/ ) {
        $logPath = $1;
        if ( defined($workPath) and $logPath =~ /^\.{1,2}[\/\\]/ ) {
            $logPath = "$workPath/$logPath";
        }
        $logPath = Cwd::abs_path($logPath);
    }

    my $binPath = "$homePath/bin/hadoop";
    my $version;
    my $verInfoLines;
    if ( -e $binPath ) {
        $verInfoLines = $self->getCmdOutLines( "$binPath version", $procInfo->{USER} );
    }
    else {
        $binPath = 'hadoop';
        $verInfoLines = $self->getCmdOutLines( "hadoop version", $procInfo->{USER} );
    }
    if ( $verInfoLines and scalar(@$verInfoLines) > 0 ) {
        $version = $$verInfoLines[0];
        $version =~ s/^\s*|\s*$//g;
    }

    $appInfo->{INSTALL_PATH} = $homePath;
    $appInfo->{LOG_PATH}     = $logPath;
    $appInfo->{VERSION}      = $version;

    my $reportInfoLines = $self->getCmdOutLines( "$binPath dfsadmin -report", $procInfo->{USER} );

    # Configured Capacity: 105689374720 (98.43 GB)
    # Present Capacity: 96537456640 (89.91 GB)
    # DFS Remaining: 96448180224 (89.82 GB)
    # DFS Used: 89276416 (85.14 MB)
    # DFS Used%: 0.09%
    # Under replicated blocks: 0
    # Blocks with corrupt replicas: 0
    # Missing blocks: 0

    # -------------------------------------------------
    # Datanodes available: 2 (2 total, 0 dead)

    # Name: 192.168.1.16:50010
    # Decommission Status : Normal
    # Configured Capacity: 52844687360 (49.22 GB)
    # DFS Used: 44638208 (42.57 MB)
    # Non DFS Used: 4986138624 (4.64 GB)
    # DFS Remaining: 47813910528(44.53 GB)
    # DFS Used%: 0.08%
    # DFS Remaining%: 90.48%
    # Last contact: Tue Aug 20 13:23:32 EDT 2013

    # Name: 192.168.1.17:50010
    # Decommission Status : Normal
    # Configured Capacity: 52844687360 (49.22 GB)
    # DFS Used: 44638208 (42.57 MB)
    # Non DFS Used: 4165779456 (3.88 GB)
    # DFS Remaining: 48634269696(45.29 GB)
    # DFS Used%: 0.08%
    # DFS Remaining%: 92.03%
    # Last contact: Tue Aug 20 13:23:34 EDT 2013

    #TODO: 收集配置路径和读取配置文件路径
    #$appInfo->{CONFIG_PATH} = $confPath;

    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = $appInfo->{JMX_PORT};

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}
