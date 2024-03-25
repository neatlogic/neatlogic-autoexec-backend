#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package IBMMQCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use XML::MyXML qw(xml_to_object);
use CollectObjCat;

sub getConfig {
    return {
        regExps  => ['\brunmqlsr\b'],             #正则表达是匹配ps输出
        psAttrs  => { COMM    => 'runmqlsr' },    #IBMMQ listener
        envAttrs => { MQCCSID => undef }
    };
}

sub init {
    my ($self) = @_;
    $self->{mqmUser}          = undef;
    $self->{qmgrName2PortMap} = {};
}

sub getQmgrNames {
    my ($self) = @_;

    my $mqmUser = $self->{mqmUser};

    # # su - mqm -c 'dspmq'
    # QMNAME(QMEPS2)                                         STATUS(Running)
    # QMNAME(QMFEA)                                          STATUS(Running)
    my $qmgrNames = [];
    my ( $status, $cmdOutLines ) = $self->getCmdOutLines( 'dspmq', $mqmUser );
    foreach my $cmdOutLine (@$cmdOutLines) {
        if ( $cmdOutLine =~ /QMNAME\((.*?)\)/ ) {
            push( @$qmgrNames, $1 );
        }
    }

    if ( $status != 0 ) {
        undef($qmgrNames);
    }

    return $qmgrNames;
}

sub getQmgrPortsMap {
    my ( $self, $qmgrNames ) = @_;

    my $qmgrNameMap = {};
    map { $qmgrNameMap->{$_} = 0; } (@$qmgrNames);

    # # ps -efww |grep runmqlsr
    # mqm      18773 18647  0 Mar12 ?        00:00:00 /opt/mqm/bin/runmqlsr -r -m QMUBA -t TCP -p 1000
    # mqm      26945 26927  0  2021 ?        00:00:00 /opt/mqm/bin/runmqlsr -r -m QMCNPS2 -t TCP -p 2000
    my $cmdOutLines = $self->getCmdOutLines('ps -efww |grep runmqlsr');

    foreach my $cmdOutLine (@$cmdOutLines) {
        if ( $cmdOutLine =~ /\s-m\s+(.*?)\s-/ ) {
            my $qmgrName = $1;
            if ( defined( $qmgrNameMap->{$qmgrName} ) ) {
                if ( $cmdOutLine =~ /\s-p\s+(\d+)/ ) {
                    $qmgrNameMap->{$qmgrName} = int($1);
                }
            }
        }
    }

    $self->{qmgrName2PortMap} = $qmgrNameMap;
    return $qmgrNameMap;
}

sub getQmgrCCSID {
    my ( $self, $qmgrName ) = @_;

    my $mqmUser  = $self->{mqmUser};
    my $procInfo = $self->{procInfo};
    my $envMap   = $procInfo->{ENVIRONMENT};

    my $ccsid = $envMap->{MQCCSID};
    if ( not defined($ccsid) or $ccsid eq '' ) {

        # # echo 'dis qmgr ccsid'|runmqsc QMEPS2
        # 5724-H72 (C) Copyright IBM Corp. 1994, 2005.  ALL RIGHTS RESERVED.
        # Starting MQSC for queue manager QMECNAPS2.

        #      1 : dis qmgr ccsid
        # AMQ8408: Display Queue Manager details.
        #    QMNAME(QMEPS2)                       CCSID(819)
        # One MQSC command read.
        my $cmdOutLines = $self->getCmdOutLines( qq{echo "dis qmgr ccsid"|runmqsc $qmgrName}, $mqmUser );
        foreach my $cmdOutLine (@$cmdOutLines) {
            if ( $cmdOutLine =~ /CCSID\(.*?\)/ ) {
                $ccsid = $1;
                last;
            }
        }
    }

    return $ccsid;
}

sub getQueuesInQmgr {
    my ( $self, $qmgrName, $qmgrPort ) = @_;

    my $procInfo = $self->{procInfo};
    my $mgmtIp   = $procInfo->{MGMT_IP};

    # # echo 'dis q(*)'|runmqsc QMEPS2
    # 5724-H72 (C) Copyright IBM Corp. 1994, 2005.  ALL RIGHTS RESERVED.
    # Starting MQSC for queue manager QMECNAPS2.

    #      1 : dis q(*)
    # AMQ8409: Display Queue details.
    #    QUEUE(DEADQ)                            TYPE(QLOCAL)
    # AMQ8409: Display Queue details.
    #    QUEUE(DTTPMTS)                          TYPE(QLOCAL)
    # AMQ8409: Display Queue details.
    #    QUEUE(ERRMSG)                           TYPE(QLOCAL)
    my $mqmUser     = $self->{mqmUser};
    my $cmdOutLines = $self->getCmdOutLines( qq{echo "dis q(\*)"|runmqsc $qmgrName}, $mqmUser );

    my @queues = ();

    foreach my $cmdOutLine (@$cmdOutLines) {
        if ( $cmdOutLine =~ /QUEUE\((.*?)\)\s+TYPE\((.*?)\)/ ) {
            my $queueName  = $1;
            my $queueType  = $2;
            my $uniqueName = "$mgmtIp:$qmgrPort:$queueName";
            push(
                @queues,
                {
                    _OBJ_CATEGORY => CollectObjCat->get('INS'),
                    _OBJ_TYPE     => 'IBMMQ_QUEUE',
                    UNIQUE_NAME   => $uniqueName,
                    NAME          => $queueName,
                    TYPE          => $queueType,
                    PORT          => $qmgrPort
                }
            );
        }
    }

    return \@queues;
}

sub getChannelsInQmgr {
    my ( $self, $qmgrName, $qmgrPort ) = @_;

    my $procInfo = $self->{procInfo};
    my $mgmtIp   = $procInfo->{MGMT_IP};

    # # echo 'dis chl(*)'|runmqsc QMEPS2
    # 5724-H72 (C) Copyright IBM Corp. 1994, 2005.  ALL RIGHTS RESERVED.
    # Starting MQSC for queue manager QMECNAPS2.

    #      1 : dis chl(*)
    # AMQ8414: Display Channel details.
    #    CHANNEL(CNAPS2.ECDS)                    CHLTYPE(SDR)
    # AMQ8414: Display Channel details.
    #    CHANNEL(DC.SVRCONN)                     CHLTYPE(SVRCONN)
    # AMQ8414: Display Channel details.
    #    CHANNEL(ECDS.CNAPS2)                    CHLTYPE(RCVR)
    # AMQ8414: Display Channel details.
    #    CHANNEL(SYSTEM.AUTO.RECEIVER)           CHLTYPE(RCVR)
    my $mqmUser     = $self->{mqmUser};
    my $cmdOutLines = $self->getCmdOutLines( qq{echo "dis chl(\*)"|runmqsc $qmgrName}, $mqmUser );

    my @channels = ();

    foreach my $cmdOutLine (@$cmdOutLines) {
        if ( $cmdOutLine =~ /CHANNEL\((.*?)\)\s+CHLTYPE\((.*?)\)/ ) {
            my $chnlName   = $1;
            my $chnlType   = $2;
            my $uniqueName = "$mgmtIp:$qmgrPort:$chnlName";
            push(
                @channels,
                {
                    _OBJ_CATEGORY => CollectObjCat->get('INS'),
                    _OBJ_TYPE     => 'IBMMQ_CHANNEL',
                    UNIQUE_NAME   => $uniqueName,
                    NAME          => $chnlName,
                    TYPE          => $chnlType,
                    PORT          => $qmgrPort
                }
            );
        }
    }

    return \@channels;
}

sub collect {
    my ($self) = @_;
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo  = $self->{procInfo};
    my $envMap    = $procInfo->{ENVIRONMENT};
    my $listenMap = $procInfo->{CONN_INFO}->{LISTEN};
    my $mgmtIp    = $procInfo->{MGMT_IP};
    my $mqmUser   = $procInfo->{USER};
    $self->{mqmUser} = $mqmUser;

    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};

    my ( $exePath, $binPath, $homePath );
    if ( $cmdLine =~ /^\s*(.*?\brunmqlsr)/ ) {

        #优先用命令行信息判断
        my $executableFile = $1;
        if ( -e $executableFile ) {
            $exePath  = $executableFile;
            $binPath  = dirname($exePath);
            $homePath = dirname($binPath);
        }
    }
    if ( not defined($homePath) ) {
        $exePath  = readlink("/proc/$pid/exe");
        $binPath  = dirname($exePath);
        $homePath = dirname($binPath);
    }

    my ( $qmgrName, $qmgrPort );
    if ( $cmdLine =~ /\s-m\s*(.+?)\s-/ ) {
        $qmgrName = $1;
    }
    if ( $cmdLine =~ /\s-p\s*(\d+)/ ) {
        $qmgrPort = $1;
    }

    $appInfo->{EXE_PATH}     = $exePath;
    $appInfo->{BIN_PATH}     = $binPath;
    $appInfo->{INSTALL_PATH} = $homePath;

    my ( $ports, $port ) = $self->getPortFromProcInfo($appInfo);

    if ( $port == 65535 ) {
        print("WARN: Can not determine IBMMQ listen port.\n");
        return undef;
    }

    if ( $port < 65535 ) {
        $appInfo->{PORT} = $port;
    }

    $appInfo->{ADMIN_PORT}     = undef;
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    # Name:        WebSphere MQ
    # Version:     6.0.2.10
    # CMVC level:  p600-210-100825
    # BuildType:   IKAP - (Production)
    my $versionLines = $self->getCmdOutLines( 'dspmqver', $mqmUser );
    foreach my $verLine (@$versionLines) {
        if ( $verLine =~ /^Version:\s+(\S+)/ ) {
            $appInfo->{VERSION} = $1;
        }
    }
    if ( not defined( $appInfo->{VERSION} ) ) {
        print("WARN: Process is not IBMMQ listener.\n");
        return undef;
    }

    # #如果IBMMQ以OS作为实例
    # my $qmgrNames = $self->getQmgrNames();
    # if ( not defined($qmgrNames) ) {
    #     print("WARN: There is no queue manager, it is not IBMMQ server.\n");
    #     return undef;
    # }
    # my $qmgrPortsMap = $self->getQmgrPortsMap($qmgrNames);

    # my @queueManagers = ();
    # foreach my $qmgrName (@$qmgrNames) {
    #     my $mqmgrPort = $qmgrPortsMap->{$qmgrName};
    #     my $ccsId     = $self->getQmgrCCSID($qmgrName);

    #     my $queueManager = {
    #         _OBJ_CATEGORY => CollectObjCat->get('INS'),
    #         _OBJ_TYPE     => 'IBMMQ_MANGER',
    #         NAME          => $qmgrName,
    #         PORT          => $mqmgrPort,
    #         CCSID         => $self->getQmgrCCSID($qmgrName),
    #         QUEUES        => $self->getQueuesInQmgr($qmgrName, $qmgrPort),
    #         CHANNELS      => $self->getChannelsInQmgr($qmgrName, $qmgrPort)
    #     };

    #     push(@queueManagers, $queueManager);
    # }
    # $appInfo->{QMANAGERS} = \@queueManagers;

    #一个QManager作为一个实例，这个带端口，这个肯定是最好的
    $appInfo->{_OBJ_TYPE}     = 'IBMMQ';
    $appInfo->{_APP_TYPE}     = 'QManager';
    $appInfo->{SERVER_NAME} = $qmgrName;
    $appInfo->{PORT}          = $qmgrPort;
    $appInfo->{CCSID}         = $self->getQmgrCCSID($qmgrName);
    $appInfo->{QUEUES}        = $self->getQueuesInQmgr($qmgrName, $qmgrPort);
    $appInfo->{CHANNELS}      = $self->getChannelsInQmgr($qmgrName, $qmgrPort);

    return $appInfo;
}

1;
