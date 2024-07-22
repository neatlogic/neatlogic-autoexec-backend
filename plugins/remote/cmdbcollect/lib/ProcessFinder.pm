#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/../../lib";

package ProcessFinder;

use strict;
use FindBin;
use IPC::Open2;
use IO::File;
use File::Basename;
use Cwd qw(abs_path);
use POSIX qw(uname);
use JSON qw(from_json to_json);
use CollectUtils;
use NSSwitcher;
use LinuxPS;

sub new {
    my ( $type, $procFilters, %args ) = @_;

    #procFilters数组
    #objType=>'Tomcat',
    #className=>'TomcatCollector',
    # seq => 100,
    # regExps  => ['\borg.apache.catalina.startup.Bootstrap\s'],
    # psAttrs  => { COMM => 'java' },
    # envAttrs => {}

    #Callback param map:
    #_OBJ_TYPE=>'tomcat',
    #PID=>3844,
    #COMM=>'xxxx',
    #COMMAND=>'xxxxxxxxxxxxxxxxx'
    #......

    my $self = {

        #callback    => $args{callback},
        inspect     => $args{inspect},
        connGather  => $args{connGather},
        appsMap     => {},
        appsArray   => [],
        osInfo      => $args{osInfo},
        passArgs    => $args{passArgs},
        bizIp       => $args{bizIp},
        ipv4Addrs   => $args{ipv4Addrs},
        ipv6Addrs   => $args{ipv6Addrs},
        procEnvName => $args{procEnvName},
        container   => $args{container}
    };

    if ( not defined($procFilters) ) {
        $procFilters = [];
    }
    $self->{procFilters}      = $procFilters;
    $self->{filtersCount}     = scalar(@$procFilters);
    $self->{matchedProcsInfo} = {};

    my @uname  = uname();
    my $ostype = $uname[0];
    $ostype =~ s/\s.*$//;
    my $hostName = `hostname`;
    $hostName =~ s/^\s*|\s*$//g;

    $self->{ostype}       = $ostype;
    $self->{hostname}     = $hostName;
    $self->{topProcesses} = [];
    $self->{osId}         = '';
    $self->{mgmtIp}       = '';          #此主机节点Agent或ssh连接到此主机，主机节点端的IP
    $self->{mgmtPort}     = '';          #此主机节点Agent或ssh连接到此主机，主机节点端的port
    my $AUTOEXEC_NODE = $ENV{'AUTOEXEC_NODE'};

    if ( defined($AUTOEXEC_NODE) and $AUTOEXEC_NODE ne '' ) {
        my $nodeInfo = from_json($AUTOEXEC_NODE);
        $self->{mgmtIp}   = $nodeInfo->{host};
        $self->{mgmtPort} = $nodeInfo->{protocolPort};
        $self->{osId}     = $nodeInfo->{resourceId};
    }

    $self->{LinuxPS} = LinuxPS->new();

    my $utils = CollectUtils->new();
    $self->{utils} = $utils;

    #列出某个进程的信息，要求：前面的列的值都不能有空格，args（就是命令行）放后面，因为命令行有空格
    $self->{procEnvCmd} = 'ps eww';

    #列出所有进程的命令，包括环境变量，用于定位查找进程，命令行和环境变量放最后列，因为命令行有空格
    $self->{listProcCmd}      = 'ps -eo pid,ppid,pgid,user,group,ruser,rgroup,pcpu,pmem,time,etime,comm,args';
    $self->{listProcCmdByPid} = 'ps -o pid,ppid,pgid,user,group,ruser,rgroup,pcpu,pmem,time,etime,comm,args -p';

    if ( $ostype eq 'Windows' ) {

        #windows需要编写powershell脚本实现ps的功能，用于根据命令行过滤进程
        $self->{listProcCmd}      = $utils->getWinPs1Cmd("$FindBin::Bin/lib/windowsps.ps1") . ' getAllProcesses';
        $self->{listProcCmdByPid} = $utils->getWinPs1Cmd("$FindBin::Bin/lib/windowspsbypid.ps1") . ' getProcess';

        #根据pid获取进程环境变量的powershell脚本，实现类似ps读取进程环境变量的功能
        if ( $uname[4] =~ /64/ ) {
            $self->{procEnvCmd} = Cwd::abs_path("$FindBin::Bin/lib/windowspenv/getprocenv.exe");
        }
        else {
            $self->{procEnvCmd} = $utils->getWinPs1Cmd("$FindBin::Bin/lib/windowspenv.ps1") . ' getProcessEnv';
        }
    }

    bless( $self, $type );
    return $self;
}

sub convertEplapsed {
    my ( $self, $timeStr ) = @_;

    my $uptimeSeconds;

    if ( $self->{ostype} eq 'Windows' ) {
        $uptimeSeconds = int($uptimeSeconds);
    }
    else {
        if ( $timeStr =~ /^(\d+)-(\d+):(\d+):(\d+)$/ ) {
            $uptimeSeconds = 86400 * $1 + 3600 * $2 + 60 * $3 + $4;
        }
        elsif ( $timeStr =~ /^(\d+):(\d+):(\d+)$/ ) {
            $uptimeSeconds = 3600 * $2 + 60 * $3 + $4;
        }
        else {
            $uptimeSeconds = int($timeStr);
        }
    }

    return $uptimeSeconds;
}

#获取单个进程的环境变量信息
sub getProcEnv {
    my ( $self, $pid ) = @_;

    my $envMap = {};

    if ( not defined($pid) ) {
        print("WARN: PID is not defined, can not get process info.\n");
        return $envMap;
    }

    print("INFO: Begin to get process $pid environment.\n");

    my $envFilePath = "/proc/$pid/environ";
    if ( -f $envFilePath ) {
        my $content = $self->{utils}->getFileContent($envFilePath);
        my $line;
        foreach $line ( split( /\x0/, $content ) ) {
            if ( $line =~ /^(.*?)=(.*)$/ ) {
                $envMap->{$1} = $2;
            }
        }
    }
    else {
        my $cmd     = $self->{procEnvCmd} . " $pid";
        my $procTxt = `$cmd`;
        my $status  = $?;
        if ( $status != 0 ) {
            print("WARN: Get process info for pid:$pid failed.\n");
        }

        my ( $headLine, $envLine ) = split( /\n/, $procTxt );

        my $envName;
        my $envVal;
        while ( $envLine =~ /(\w+)=([^=]*?|[^\s]+?)\s(?=\w+=)/g ) {
            $envName = $1;
            $envVal  = $2;
            if ( $envName ne 'LS_COLORS' ) {
                $envMap->{$envName} = $envVal;
            }
        }

        my $lastEqualPos = rindex( $envLine, '=' );
        my $lastEnvPos   = rindex( $envLine, ' ', $lastEqualPos );
        my $lastEnvName  = substr( $envLine, $lastEnvPos + 1, $lastEqualPos - $lastEnvPos - 1 );
        my $lastEnvVal   = substr( $envLine, $lastEqualPos + 1 );
        chomp($lastEnvVal);
        if ( $lastEnvVal =~ /^\w+$/ ) {
            $envMap->{$lastEnvName} = $lastEnvVal;
        }
    }
    delete( $envMap->{LS_COLORS} );
    print("INFO: Get process $pid environment complete.\n");
    return $envMap;
}

#获取单个进程的打开文件数量
sub getProcOpenFilesCount {
    my ( $self, $pid ) = @_;
    my $fdDir = "/proc/$pid/fd";

    if ( not -e $fdDir ) {
        return undef;
    }

    my $count = 0;
    my $dh;
    opendir( $dh, $fdDir );
    if ( defined($dh) ) {
        while ( my $de = readdir($dh) ) {
            next if $de =~ /^\./;
            $count++;
        }
        closedir($dh);
        return $count;
    }

    return undef;
}

#获取进程最大打开文件数
sub getProcMaxOpenFilesCount {
    my ( $self, $pid ) = @_;
    my $maxCount;

    my $ostype = $self->{ostype};

    if ( $ostype eq 'Linux' ) {
        my $limitPath = "/proc/$pid/limits";
        if ( not -f $limitPath ) {
            return undef;
        }

        my $fh = IO::File->new("<$limitPath");
        if ( defined($fh) ) {
            while ( my $line = $fh->getline() ) {
                if ( $line =~ /^Max open files\s+\d+\s+(\d+)/ ) {
                    $maxCount = int($1);
                }
            }
        }
    }
    elsif ( $ostype eq 'AIX' ) {
        my $procLimitInfo = `procfiles $pid`;
        if ( $procLimitInfo =~ /rlimit:\s*(\d+)/ ) {
            $maxCount = int($1);
        }
    }

    return $maxCount;
}

sub isProcInContainer {
    my ( $self, $pid ) = @_;

    my $isContainer = 0;

    if ( $self->{ostype} eq 'Windows' ) {
        return $isContainer;
    }

    #如果进程有独立于OS的pid的namespace则运行于容器内
    my $nativeNs = readlink('/proc/1/ns/pid');
    my $selfNs   = readlink("/proc/$pid/ns/pid");

    if ( not defined($nativeNs) or not defined($selfNs) ) {
        return $isContainer;
    }

    if ( $selfNs ne $nativeNs ) {
        $isContainer = 1;
    }

    return $isContainer;
}

sub resolveSymlinks {
    my ( $self, $path ) = @_;

    if ( -l $path ) {
        my $target = readlink($path);

        if ( !File::Spec->file_name_is_absolute($target) ) {
            $target = File::Spec->rel2abs( $target, dirname($path) );
        }
        return $self->resolveSymlinks($target);
    }
    elsif ( -e $path ) {
        return abs_path($path);
    }
    else {
        return undef;
    }
}

sub getRealInstallPath {
    my ( $self, $appInfo, $procInfo ) = @_;

    my $realInstallPath = '';
    my $realBinPath;

    my $installPath = $appInfo->{INSTALL_PATH};
    if ( defined($installPath) and $installPath ne '' and -e $installPath ) {
        $realBinPath = $self->resolveSymlinks("$installPath/bin");
        if ( not defined($realBinPath) ) {
            $realBinPath = $self->resolveSymlinks("$installPath/sbin");
        }
        if ( not defined($realBinPath) ) {
            $realBinPath = $self->resolveSymlinks("$installPath/lib");
        }
        if ( not defined($realBinPath) ) {
            $realBinPath = $self->resolveSymlinks("$installPath");
        }
    }
    else {
        my $binPath = $appInfo->{BIN_PATH};
        if ( defined($binPath) and $binPath ne '' ) {
            $realBinPath = $self->resolveSymlinks($binPath);
        }
        else {
            my $exePath = $appInfo->{EXE_PATH};
            if ( defined($exePath) and $exePath ne '' ) {
                $binPath     = dirname($exePath);
                $realBinPath = $self->resolveSymlinks($binPath);
            }
            else {
                my $executableFile = $procInfo->{EXECUTABLE_FILE};
                if ( defined($executableFile) and $executableFile ne '' ) {
                    $binPath     = dirname($executableFile);
                    $realBinPath = $self->resolveSymlinks($binPath);
                }
            }
        }
    }

    if ( defined($realBinPath) and $realBinPath ne '' ) {
        $realInstallPath = dirname($realBinPath);
    }

    return $realInstallPath;
}

#提供给ProcessFinder调用的回调函数，当进程信息匹配配置的过滤配置时就会调用此函数
#此回调函数会初始化Collector类并调用其collect方法
sub doDetailCollect {
    my ( $self, $collectorClass, $procInfo ) = @_;

    #collectorClass: 收集器类名
    #procInfo；ps的进程信息

    #matchedProcsInfo：前面已经匹配上进程信息，用于多进程应用的连接去重
    my $matchedProcsInfo = $self->{matchedProcsInfo};
    my $appsMap          = $self->{appsMap};
    my $appsArray        = $self->{appsArray};
    my $osType           = $self->{ostype};
    my $passArgs         = $self->{passArgs};
    my $osInfo           = $self->{osInfo};
    my $connGather       = $self->{connGather};

    my $isMatched = 0;
    my $objCat;
    my $pid     = $procInfo->{PID};
    my $objType = $procInfo->{_OBJ_TYPE};

    print("INFO: Process $pid matched filter:$objType, begin to collect data...\n");
    my $connInfo;
    if ( $osType eq 'Windows' and $procInfo->{COMMAND} =~ /^System\b/ ) {

        #Windows System进程没有lisnten信息
        $connInfo = { PEER => {}, LOCAL_PEER => {}, LISTEN => {} };
    }
    else {
        $connInfo = $connGather->getListenInfo($pid);
        my $portInfoMap = $self->getListenPortInfo( $connInfo->{LISTEN} );
        $connInfo->{PORT_BIND} = $portInfoMap;
        $procInfo->{CONN_INFO} = $connInfo;
    }
    print("INFO: Process connection infomation collected.\n");

    my $collector;
    my @appInfos = ();

    eval {
        $collector = $collectorClass->new( $passArgs, $self, $procInfo, $matchedProcsInfo );
        my @appInfosTmp = $collector->collect($procInfo);

        foreach my $appInfo (@appInfosTmp) {
            if ( defined($appInfo) and ref($appInfo) eq 'HASH' ) {
                push( @appInfos, $appInfo );
            }
        }
        if ( scalar(@appInfos) > 0 ) {
            $connInfo = $procInfo->{CONN_INFO};

            #有些进程match并不是监听进程，可以通过设置procInfo的属性LISTENER_PID指定监听进程
            my $statInfo = {};
            my $lsnPid   = $procInfo->{LISTENER_PID};
            if ( defined($lsnPid) and $lsnPid ne '' and $lsnPid ne $pid ) {
                my $lsnInfo = $connGather->getListenInfo($lsnPid);
                map { $connInfo->{$_} = $lsnInfo->{$_} } keys(%$lsnInfo);
                my $portInfoMap = $self->getListenPortInfo( $connInfo->{LISTEN} );
                $connInfo->{PORT_BIND} = $portInfoMap;

                $statInfo = $connGather->getStatInfo( $lsnPid, $connInfo->{LISTEN} );
            }
            else {
                $statInfo = $connGather->getStatInfo( $pid, $connInfo->{LISTEN} );
            }
            map { $connInfo->{$_} = $statInfo->{$_} } keys(%$statInfo);
        }
    };

    if ($@) {
        print("ERROR: $collectorClass return failed, $@\n");
        return 0;
    }

    my $idx = 0;
    for ( $idx = 0 ; $idx < scalar(@appInfos) ; $idx++ ) {
        my $appInfo = $appInfos[$idx];
        $isMatched = 1;

        my $insObjCat   = CollectObjCat->get('INS');
        my $dbInsObjCat = CollectObjCat->get('DBINS');

        $objType = $appInfo->{_OBJ_TYPE};
        if ( not defined($objType) ) {
            $objType = $procInfo->{_OBJ_TYPE};
            $appInfo->{_OBJ_TYPE} = $objType;
        }

        $objCat = $appInfo->{_OBJ_CATEGORY};
        if ( not defined($objCat) or $objCat eq '' ) {
            $objCat = $insObjCat;
            $appInfo->{_OBJ_CATEGORY} = $objCat;
        }
        else {
            if ( not CollectObjCat->validate( $appInfo->{_OBJ_CATEGORY} ) ) {
                print("WARN: Invalid object category: $appInfo->{_OBJ_CATEGORY}.\n");
                return 0;
            }

            #从实例采集信息中抽取出软件资产
            if ( $objCat eq $insObjCat or $objCat eq $dbInsObjCat ) {
                my $softWare = {
                    _OBJ_CATEGORY => $objCat,
                    _OBJ_TYPE     => "Software-Asset",
                    NAME          => $objType,
                    VERSION       => $appInfo->{VERSION},
                    INSTALL_PATH  => $self->getRealInstallPath( $appInfo, $procInfo )
                };
                $appInfo->{SOFTWARE_ASSETS} = $softWare;
            }

            #从实例采集信息中抽取出服务，参考另外SERVICE_PORTS属性的处理
        }

        print("INFO: Matched Object Type:$objCat/$objType.\n");

        if ( not defined( $appInfo->{MGMT_IP} ) or $appInfo->{MGMT_IP} eq '' ) {
            $appInfo->{MGMT_IP}        = $procInfo->{MGMT_IP};
            $appInfo->{MGMT_PORT}      = $procInfo->{MGMT_PORT};
            $appInfo->{OS_ID}          = $procInfo->{OS_ID};
            $appInfo->{OS_USER}        = $procInfo->{USER};
            $appInfo->{_CONTAINERTYPE} = $procInfo->{_CONTAINERTYPE};
        }

        #PORT强制转int
        $appInfo->{PORT} = int( $appInfo->{PORT} );

        push( @$appsArray, $appInfo );

        if ( $idx == 0 ) {
            $appsMap->{ $procInfo->{PID} } = $appInfo;
        }
        else {
            #如果出现多个appInfo同一个进程号的情况，则是但进程多对象的情况，需要处理PID为不一样的PID
            if ( defined( $appsMap->{ $procInfo->{PID} } ) ) {
                my $realPid  = $procInfo->{REAL_PID};
                my $realPpid = $procInfo->{REAL_PPID};
                if ( not defined($realPid) ) {
                    $realPid               = $procInfo->{PID};
                    $realPpid              = $procInfo->{PPID};
                    $procInfo->{REAL_PID}  = $realPid;
                    $procInfo->{REAL_PPID} = $realPpid;
                }
                $procInfo->{PID}  = $procInfo->{REAL_PID} . '-' . $idx;
                $procInfo->{PPID} = $procInfo->{REAL_PPID} . '-' . $idx;
            }
            $appsMap->{ $procInfo->{PID} } = $appInfo;
        }

        my $notProcess = $appInfo->{NOT_PROCESS};
        if ( not defined($notProcess) ) {
            if ( not defined( $appInfo->{PROC_INFO} ) ) {
                $appInfo->{PROC_INFO} = $procInfo;
            }
            else {
                $procInfo = $appInfo->{PROC_INFO};
            }

            $appInfo->{PID}     = $procInfo->{PID};
            $appInfo->{COMMAND} = $procInfo->{COMMAND};

            my $cpuLogicCores = $osInfo->{CPU_LOGIC_CORES};
            $appInfo->{CPU_LOGIC_CORES} = $cpuLogicCores;
            if ( $cpuLogicCores > 0 ) {
                $appInfo->{CPU_USAGE} = int( ( $procInfo->{'%CPU'} + 0.0 ) * 100 / $cpuLogicCores ) / 100;
            }
            else {
                $appInfo->{CPU_USAGE} = $procInfo->{'%CPU'} + 0.0;
            }

            if ( $osType eq 'Windows' ) {
                $appInfo->{MEM_USED} = $procInfo->{MEMSIZE} + 0.0;
                if ( not defined( $appInfo->{MEM_USAGE} ) and $osInfo->{MEM_TOTAL} > 0 ) {
                    $appInfo->{MEM_USAGE} = int( $appInfo->{MEM_SIZE} * 10000 / $osInfo->{MEM_TOTAL} ) / 100;
                }
            }
            else {
                $appInfo->{MEM_USED}  = int( ( $procInfo->{'%MEM'} + 0.0 ) * $osInfo->{MEM_TOTAL} ) / 100;
                $appInfo->{MEM_USAGE} = $procInfo->{'%MEM'} + 0.0;
            }
        }

        my $envMap      = delete( $procInfo->{ENVIRONMENT} );
        my $insNamePath = $envMap->{TS_INSNAME};
        if ( defined($insNamePath) and $insNamePath ne '' ) {
            my @insPaths = split( '/', $insNamePath );
            if ( scalar(@insPaths) > 1 ) {
                $appInfo->{BELONG_APPLICATION} = [
                    {
                        _OBJ_CATEGORY => 'APPLICATION',
                        _OBJ_TYPE     => 'APPLICATION',
                        APP_NAME      => $insPaths[0],
                    }
                ];
                $appInfo->{BELONG_APPLICATION_MODULE} = [
                    {
                        _OBJ_CATEGORY  => 'APPLICATION',
                        _OBJ_TYPE      => 'APPLICATION_MODULE',
                        APP_NAME       => $insPaths[0],
                        APPMODULE_NAME => $insPaths[1],
                    }
                ];
            }
            else {
                $appInfo->{BELONG_APPLICATION}        = [];
                $appInfo->{BELONG_APPLICATION_MODULE} = [];
            }
        }

        if ( not defined( $appInfo->{PK} ) ) {
            my $pkConfig = CollectObjCat->getPK($objCat);
            if ( defined($pkConfig) ) {
                $appInfo->{PK} = $pkConfig;
            }
            else {
                $appInfo->{PK} = [ 'MGMT_IP', 'PORT' ];
                print("ERROR: $objType PK not defined for obj catetory:$objCat.\n");
            }
        }

        my @envEntries = ();
        while ( my ( $envName, $envVal ) = each(%$envMap) ) {
            push( @envEntries, { NAME => $envName, VALUE => $envVal } );
        }
        if ( scalar(@envEntries) > 0 ) {
            $appInfo->{MAIN_ENV} = \@envEntries;
        }

        #如果采集器自身未定义RUN_ON则自动添加
        my $collectedRunOn = $appInfo->{RUN_ON};
        if ( not defined($collectedRunOn) ) {
            $appInfo->{RUN_ON} = [
                {
                    '_OBJ_CATEGORY' => 'OS',
                    '_OBJ_TYPE'     => $osType,
                    'OS_ID'         => $procInfo->{OS_ID},
                    'MGMT_IP'       => $procInfo->{MGMT_IP}
                }
            ];
        }
        elsif ( scalar(@$collectedRunOn) == 0 ) {

            #如果采集器定义了空的RUN_ON，代表不需要RUN_ON，可能是集群相关的采集，RUN_ON在多个OS上，无法全部采集
            delete( $appInfo->{RUN_ON} );
        }
    }

    return $isMatched;
}

#处理存在父子关系的进程的连接信息，并合并到父进程
sub mergeMultiProcs {
    my ( $self, $appsArray, $appsMap, $ipv4Addrs, $ipv6Addrs ) = @_;

    my $inspect  = $self->{inspect};
    my $pidToDel = {};
    my @apps     = ();
    print("INFO: Begin to merge connection information with parent processes...\n");
    foreach my $pid ( keys(%$appsMap) ) {
        my $info = $appsMap->{$pid};
        if ( not defined( $info->{_MULTI_PROC} ) ) {
            next;
        }

        my $procInfo = $info->{PROC_INFO};

        my $parentInfo = $appsMap->{ $procInfo->{PPID} };

        my $currentInfo = $info;
        my $objCat      = $currentInfo->{_OBJ_CATEGORY};
        my $objType     = $currentInfo->{_OBJ_TYPE};

        my $parentTopInfo;
        while ( defined($parentInfo) and $parentInfo->{_OBJ_CATEGORY} eq $objCat and $parentInfo->{_OBJ_TYPE} eq $objType ) {
            $parentTopInfo = $parentInfo;
            $currentInfo   = $parentInfo;
            $parentInfo    = $appsMap->{ $currentInfo->{PROC_INFO}->{PPID} };
        }

        if ( defined($parentTopInfo) ) {
            $parentTopInfo->{CPU_USAGE} = $parentTopInfo->{CPU_USAGE} + $procInfo->{CPU_USAGE};
            $parentTopInfo->{MEM_USAGE} = $parentTopInfo->{MEM_USAGE} + $procInfo->{MEM_USAGE};
            $parentTopInfo->{MEM_USED}  = $parentTopInfo->{MEM_USED} + $procInfo->{MEM_USED};

            if ( index( $pid, '-' ) < 0 ) {
                my $maxOpenFilesCount = $self->getProcMaxOpenFilesCount($pid);
                my $openFilesCount    = $self->getProcOpenFilesCount($pid);
                my $openFilesRate     = 0;
                if ( defined($maxOpenFilesCount) and $maxOpenFilesCount > 0 ) {
                    $openFilesRate = int( $openFilesCount * 10000 / $maxOpenFilesCount ) / 100;
                }

                my $openFilesInfo = $info->{OPEN_FILES_INFO};
                if ( not defined($openFilesInfo) ) {
                    $openFilesInfo = [];
                    $info->{OPEN_FILES_INFO} = $openFilesInfo;
                }
                push( @$openFilesInfo, { PID => $pid, OPEN => $openFilesCount, MAX => $maxOpenFilesCount, RATE => $openFilesRate } );
            }

            $parentTopInfo->{OPEN_FILES_COUNT} = $parentTopInfo->{OPEN_FILES_COUNT} + $self->getProcOpenFilesCount($pid);

            my $parentConnInfo  = $parentTopInfo->{PROC_INFO}->{CONN_INFO};
            my $currentConnInfo = $procInfo->{CONN_INFO};

            my $parentLsnInfo = $parentConnInfo->{LISTEN};
            map { $parentLsnInfo->{$_} = 1 } keys( %{ $currentConnInfo->{LISTEN} } );

            #把基于端口统计的显式、隐式监听IP合并到父进程
            my $portInfoMap       = $currentConnInfo->{PORT_BIND};
            my $parentPortInfoMap = $parentConnInfo->{PORT_BIND};
            while ( my ( $port, $portInfo ) = each(%$portInfoMap) ) {
                my $parentPortInfo = $parentPortInfoMap->{$port};
                while ( my ( $key, $ipMap ) = each(%$portInfo) ) {
                    map { $parentPortInfo->{$key}->{$_} = 1 } keys(%$ipMap);
                }
            }

            my $parentPeerInfo = $parentConnInfo->{PEER};
            map { $parentPeerInfo->{$_} = 1 } keys( %{ $currentConnInfo->{PEER} } );

            #连接统计数据的合并
            my $parentConnStats  = $parentConnInfo->{STATS};
            my $currentConnStats = $currentConnInfo->{STATS};

            $parentConnStats->{TOTAL_COUNT}       = $parentConnStats->{TOTAL_COUNT} + $currentConnStats->{TOTAL_COUNT};
            $parentConnStats->{INBOUND_COUNT}     = $parentConnStats->{INBOUND_COUNT} + $currentConnStats->{INBOUND_COUNT};
            $parentConnStats->{OUTBOUND_COUNT}    = $parentConnStats->{OUTBOUND_COUNT} + $currentConnStats->{OUTBOUND_COUNT};
            $parentConnStats->{SYN_RECV_COUNT}    = $parentConnStats->{SYN_RECV_COUNT} + $currentConnStats->{SYN_RECV_COUNT};
            $parentConnStats->{CLOSE_WAIT_COUNT}  = $parentConnStats->{CLOSE_WAIT_COUNT} + $currentConnStats->{CLOSE_WAIT_COUNT};
            $parentConnStats->{RECV_QUEUED_COUNT} = $parentConnStats->{RECV_QUEUED_COUNT} + $currentConnStats->{RECV_QUEUED_COUNT};
            $parentConnStats->{SEND_QUEUED_COUNT} = $parentConnStats->{SEND_QUEUED_COUNT} + $currentConnStats->{SEND_QUEUED_COUNT};
            $parentConnStats->{RECV_QUEUED_SIZE}  = $parentConnStats->{RECV_QUEUED_SIZE} + $currentConnStats->{RECV_QUEUED_SIZE};
            $parentConnStats->{SEND_QUEUED_SIZE}  = $parentConnStats->{SEND_QUEUED_SIZE} + $currentConnStats->{SEND_QUEUED_SIZE};

            if ( $inspect == 1 ) {

                #基于调用OutBound（目标）的统计信息合并
                my $parentOutBoundStats  = $parentConnStats->{OUTBOUND_STATS};
                my $currentOutBoundStats = $currentConnStats->{OUTBOUND_STATS};
                while ( my ( $remoteAddr, $outBoundStat ) = each(%$currentOutBoundStats) ) {
                    my $parentOutBoundStat = $parentOutBoundStats->{$remoteAddr};
                    $parentOutBoundStat->{OUTBOUND_COUNT}   = $parentOutBoundStat->{OUTBOUND_COUNT} + $outBoundStat->{OUTBOUND_COUNT};
                    $parentOutBoundStat->{SEND_QUEUED_SIZE} = $parentOutBoundStat->{SEND_QUEUED_SIZE} + $outBoundStat->{SEND_QUEUED_SIZE};
                    $parentOutBoundStat->{SYN_SENT_COUNT}   = $parentOutBoundStat->{SYN_SENT_COUNT} + $outBoundStat->{SYN_SENT_COUNT};
                }
            }
            $pidToDel->{$pid} = 1;

        }
        elsif ( index( $pid, '-' ) < 0 ) {
            my $maxOpenFilesCount = $self->getProcMaxOpenFilesCount($pid);
            my $openFilesCount    = $self->getProcOpenFilesCount($pid);
            my $openFilesRate     = 0;
            if ( defined($maxOpenFilesCount) and $maxOpenFilesCount > 0 ) {
                $openFilesRate = int( $openFilesCount * 10000 / $maxOpenFilesCount ) / 100;
            }
            $info->{OPEN_FILES_INFO} = [ { PID => $pid, OPEN => $openFilesCount, MAX => $maxOpenFilesCount, RATE => $openFilesRate } ];
        }
    }
    print("INFO: Connection information merged.\n");

    #抽取所有的top层的进程，并对CONN_INFO信息进行整理，转换为数组的格式
    #while ( my ( $pid, $appInfo ) = each(%$appsMap) ) {
    foreach my $appInfo (@$appsArray) {
        my $pid = $appInfo->{PROC_INFO}->{PID};
        if ( not defined( $pidToDel->{$pid} ) ) {
            my $procInfo = $appInfo->{PROC_INFO};
            my $connInfo = {};
            if ( defined($procInfo) ) {
                $connInfo = $procInfo->{CONN_INFO};
            }

            my @lsnStats    = ();
            my @lsnPorts    = ();
            my @appLsnPorts = ();
            while ( my ( $lsnAddr, $backlogQ ) = each( %{ $connInfo->{LISTEN} } ) ) {
                push( @lsnPorts,    $lsnAddr );
                push( @appLsnPorts, { ADDR => $lsnAddr } );
                push( @lsnStats,    { ADDR => $lsnAddr, QUEUED => $backlogQ } );
            }
            $connInfo->{LISTEN} = \@lsnPorts;
            if ( not defined( $appInfo->{LISTEN} ) ) {
                $appInfo->{LISTEN} = \@appLsnPorts;
            }

            my $minPort      = 65535;
            my $insPort      = $appInfo->{PORT};
            my $portsMap     = {};
            my $bindAddrsMap = {};
            my @bindAddrs    = ();
            if ( defined($insPort) and $insPort ne '' ) {
                $portsMap->{$insPort} = 1;
            }
            foreach my $lsnPort (@lsnPorts) {
                if ( $lsnPort !~ /:\d+$/ ) {
                    $lsnPort = int($lsnPort);
                    if ( $lsnPort < $minPort ) {
                        $minPort = $lsnPort;
                    }
                    $portsMap->{$lsnPort} = 1;
                    foreach my $ipInfo (@$ipv4Addrs) {
                        $bindAddrsMap->{"$ipInfo->{IP}:$lsnPort"} = 1;
                    }
                    foreach my $ipInfo (@$ipv6Addrs) {
                        $bindAddrsMap->{"$ipInfo->{IP}:$lsnPort"} = 1;
                    }
                }
                else {
                    $bindAddrsMap->{$lsnPort} = 1;
                    push( @bindAddrs, $lsnPort );
                    my $myPort = $lsnPort;
                    $myPort =~ s/^.*://;
                    $myPort = int($myPort);
                    if ( $myPort < $minPort ) {
                        $minPort = $myPort;
                    }
                    $portsMap->{$myPort} = 1;
                }
            }
            @bindAddrs = keys(%$bindAddrsMap);
            $connInfo->{BIND} = \@bindAddrs;

            #把connInfo中的PEER信息，区分开local ip和远端IP，分开存放
            my @localPeerAddrs  = ();
            my @remotePeerAddrs = ();
            foreach my $rAddr ( keys( %{ $connInfo->{PEER} } ) ) {
                if ( $rAddr =~ /^127\./ or $rAddr =~ /^::1:/ ) {
                    push( @localPeerAddrs, $rAddr );
                }
                else {
                    push( @remotePeerAddrs, $rAddr );
                }
            }
            $connInfo->{PEER}       = \@remotePeerAddrs;
            $connInfo->{LOCAL_PEER} = \@localPeerAddrs;
            delete( $procInfo->{CONN_INFO} );

            #TCP连接统计信息中的比率指标统计
            my $connStats = $connInfo->{STATS};
            if ( $connStats->{TOTAL_COUNT} > 0 ) {
                $connStats->{RECV_QUEUED_RATE}     = int( $connStats->{RECV_QUEUED_COUNT} * 10000 / $connStats->{TOTAL_COUNT} + 0.5 ) / 100;
                $connStats->{SEND_QUEUED_RATE}     = int( $connStats->{SEND_QUEUED_COUNT} * 10000 / $connStats->{TOTAL_COUNT} + 0.5 ) / 100;
                $connStats->{RECV_QUEUED_SIZE_AVG} = int( $connStats->{RECV_QUEUED_SIZE} * 100 / $connStats->{TOTAL_COUNT} + 0.5 ) / 100;
                $connStats->{SEND_QUEUED_SIZE_AVG} = int( $connStats->{SEND_QUEUED_SIZE} * 100 / $connStats->{TOTAL_COUNT} + 0.5 ) / 100;
            }

            #TCP OutBound连接的比率指标统计
            if ( $inspect == 1 ) {
                while ( my ( $remoteAddr, $outBoundStat ) = each( %{ $connStats->{OUTBOUND_STATS} } ) ) {
                    if ( $outBoundStat->{OUTBOUND_COUNT} > 0 ) {
                        $outBoundStat->{SEND_QUEUED_RATE}     = int( $outBoundStat->{SEND_QUEUED_RATE} * 10000 / $outBoundStat->{OUTBOUND_COUNT} + 0.5 ) / 100;
                        $outBoundStat->{SEND_QUEUED_SIZE_AVG} = int( $outBoundStat->{SEND_QUEUED_SIZE} * 100 / $outBoundStat->{OUTBOUND_COUNT} + 0.5 ) / 100;
                    }
                }
            }

            #重新整理连接统计数据，从CONN_INFO中抽离出来CONN_STATS和CONN_OUTBOUND_STATS
            my @outBoundStats = ();
            while ( my ( $remoteAddr, $outBoundStat ) = each( %{ $connStats->{OUTBOUND_STATS} } ) ) {
                $outBoundStat->{REMOTE_ADDR} = $remoteAddr;
                push( @outBoundStats, $outBoundStat );
            }
            delete( $connStats->{OUTBOUND_STATS} );

            if ( scalar(@bindAddrs) > 0 ) {
                $appInfo->{CONN_OUTBOUND_STATS} = \@outBoundStats;
                my $inBoundStats = delete( $connInfo->{STATS} );
                if ( defined($inBoundStats) ) {
                    $appInfo->{CONN_STATS} = $inBoundStats;
                }
                else {
                    $appInfo->{CONN_STATS} = [];
                }

                $appInfo->{LISTEN_STATS} = \@lsnStats;

                $appInfo->{CONN_INFO} = $connInfo;

                if ( $minPort < 65535 and not defined( $appInfo->{PORT} ) ) {
                    $appInfo->{PORT} = $minPort;
                }

                #把SERVICE_PORTS格式从Map转换为可以支持导入的数组类型(应用实例提供的服务)
                my $insObjCat   = CollectObjCat->get('INS');
                my $dbInsObjCat = CollectObjCat->get('DBINS');
                my $objCat      = $appInfo->{_OBJ_CATEGORY};

                my @servicePortsArray = ();
                my $servicePortsMap   = {};
                my $servicePorts      = $appInfo->{SERVICE_PORTS};
                if ( defined($servicePorts) ) {

                    #如果存在服务端口，则加入SERVICE_PORTS对象
                    while ( my ( $svcName, $svcPort ) = each(%$servicePorts) ) {
                        my $existsService = $servicePortsMap->{$svcPort};
                        if ( defined($existsService) ) {
                            if ( $existsService->{NAME} =~ /^\d+$/ ) {
                                $servicePortsMap->{$svcPort} = {
                                    _OBJ_CATEGORY => $objCat,
                                    _OBJ_TYPE     => 'Service-Ports',
                                    NAME          => $svcName,
                                    PORT          => $svcPort
                                };
                            }
                        }
                        else {
                            $servicePortsMap->{$svcPort} = {
                                _OBJ_CATEGORY => $objCat,
                                _OBJ_TYPE     => 'Service-Ports',
                                NAME          => $svcName,
                                PORT          => $svcPort
                            };
                        }
                    }
                    @servicePortsArray = values(%$servicePortsMap);
                    $appInfo->{SERVICE_PORTS} = \@servicePortsArray;
                }

                if ( $objCat eq $insObjCat or $objCat eq $dbInsObjCat ) {

                    #如果是应用实例，补充其他监听的端口（未知协议或服务名）
                    foreach my $svcPort ( keys(%$portsMap) ) {
                        if ( not defined( $servicePortsMap->{$svcPort} ) ) {
                            $servicePortsMap->{$svcPort} = {
                                _OBJ_CATEGORY => $objCat,
                                _OBJ_TYPE     => 'Service-Ports',
                                NAME          => $svcPort,
                                PORT          => $svcPort
                            };
                        }
                    }

                    @servicePortsArray = values(%$servicePortsMap);
                    $appInfo->{SERVICE_PORTS} = \@servicePortsArray;
                }
            }

            #估算主业务IP和VIP，如果有特殊情况
            #需要定制修改ProcessFinder的方法predictBizIp（应用的VIP和主业务IP）, OSGatherBase的方法getBizIp（主机业务IP）
            if ( not defined( $appInfo->{PRIMARY_IP} ) or not defined( $appInfo->{VIP} ) ) {
                my ( $bizIp, $vip ) = $self->predictBizIp( $connInfo, $minPort );
                if ( not defined( $appInfo->{PRIMARY_IP} ) ) {
                    $appInfo->{PRIMARY_IP} = $bizIp;
                }
                if ( not defined( $appInfo->{VIP} ) ) {
                    $appInfo->{VIP} = $vip;
                }
            }

            $appInfo->{UPTIME} = $procInfo->{ELAPSED};

            #如果是非进程类别的信息采集信息，则清除PROC_INFO
            if ( delete( $appInfo->{NOT_PROCESS} ) ) {
                delete( $appInfo->{PROC_INFO} );
            }
            delete( $connInfo->{PORT_BIND} );

            push( @apps, $appInfo );
        }
    }

    return \@apps;
}

sub processMatch {
    my ( $self, $processAttrs ) = @_;

    my $matchedProc;

    my $procFilters  = $self->{procFilters};
    my $filtersCount = $self->{filtersCount};
    for ( my $i = 0 ; $i < $filtersCount ; $i++ ) {
        my $myPid = $processAttrs->{PID};

        my $config   = $$procFilters[$i];
        my $regExps  = $config->{regExps};
        my $psAttrs  = $config->{psAttrs};
        my $envAttrs = $config->{envAttrs};

        $processAttrs->{_OBJ_TYPE} = $config->{objType};

        my $isMatched = 1;
        foreach my $pattern (@$regExps) {
            if ( $processAttrs->{COMMAND} !~ /$pattern/ ) {
                $isMatched = 0;
                last;
            }
        }

        if ( $isMatched == 0 ) {
            next;
        }

        #容器内的进程不做单独采集
        if ( $self->isProcInContainer($myPid) == 1 ) {
            next;
        }

        my $envMap;
        if ( defined($psAttrs) ) {
            my $psAttrVal;
            foreach my $attr ( keys(%$psAttrs) ) {
                my $attrVal = $psAttrs->{$attr};
                $psAttrVal = $processAttrs->{$attr};
                if ( $attrVal ne $psAttrVal ) {
                    $isMatched = 0;
                    last;
                }
            }
        }

        if ( $isMatched == 0 ) {
            next;
        }

        if ( defined($envAttrs) ) {
            my $envAttrVal;
            foreach my $attr ( keys(%$envAttrs) ) {
                my $attrVal = $envAttrs->{$attr};
                if ( not defined($envMap) ) {
                    $envMap = $self->getProcEnv($myPid);
                }

                $envAttrVal = $envMap->{$attr};

                if ( not defined($envAttrVal) ) {
                    $isMatched = 0;
                    last;
                }

                if ( not defined($attrVal) or $attrVal eq '' ) {
                    if ( defined($envAttrVal) ) {
                        next;
                    }
                    else {
                        $isMatched = 0;
                        last;
                    }
                }

                if ( $envAttrVal !~ /$attrVal/ ) {
                    $isMatched = 0;
                    last;
                }
            }
        }

        if ( $isMatched == 0 ) {
            next;
        }

        if ( -e "/proc/$myPid/exe" ) {
            $processAttrs->{EXECUTABLE_FILE} = readlink("/proc/$myPid/exe");
        }
        if ( not defined($envMap) ) {
            $envMap = $self->getProcEnv($myPid);
        }
        $processAttrs->{ENVIRONMENT} = $envMap;

        $self->{matchedProcsInfo}->{$myPid} = $processAttrs;

        $matchedProc = { className => $config->{className}, procMap => $processAttrs };
        last;
    }

    return $matchedProc;
}

sub findProcess {
    my ( $self, $pidsInContainer, $containerId ) = @_;
    print("INFO: Begin to find and match processes.\n");

    my $ostype = $self->{ostype};

    #my $callback = $self->{callback};
    my @matchedProcs = ();
    my $procFilters  = $self->{procFilters};
    my $filtersCount = $self->{filtersCount};

    if ( $ostype eq 'Linux' ) {
        my $linuxPs       = $self->{LinuxPS};
        my $processesList = $linuxPs->getProcessList();
        foreach my $process (@$processesList) {

            #PID PPID PGID USER GID RUSER RGID %CPU %MEM TIME ELAPSED COMM ARGS
            my $processAttrs = {
                OS_ID     => $self->{osId},
                OS_TYPE   => $self->{ostype},
                HOST_NAME => $self->{hostname},
                MGMT_IP   => $self->{mgmtIp},
                MGMT_PORT => $self->{mgmtPort},
                PID       => $$process[0],
                PPID      => $$process[1],
                PGID      => $$process[2],
                USER      => $$process[3],
                GID       => $$process[4],
                RUSER     => $$process[5],
                RGID      => $$process[6],
                '%CPU'    => $$process[7],
                '%MEM'    => $$process[8],
                TIME      => $$process[9],
                ELAPSED   => $$process[10],
                COMM      => $$process[11],
                COMMAND   => $$process[12]
            };
            my $matchedProc = $self->processMatch($processAttrs);
            if ( defined($matchedProc) ) {
                push( @matchedProcs, $matchedProc );
            }
        }
    }
    else {
        my $chldOut;
        open( $chldOut, $self->{listProcCmd} . '|' );
        if ( defined($chldOut) ) {
            my $line;
            my $headLine = <$chldOut>;
            $headLine =~ s/^\s*|\s*$//g;
            $headLine =~ s/^.*?PID/PID/g;
            my $cmdPos      = rindex( $headLine, ' ' );
            my @fields      = split( /\s+/, substr( $headLine, 0, $cmdPos ) );
            my $fieldsCount = scalar(@fields);
            while ( $line = <$chldOut> ) {
                $line =~ s/^\s*|\s*$//g;
                my @vars = split( /\s+/, $line );

                my $processAttrs = {
                    OS_ID     => $self->{osId},
                    OS_TYPE   => $self->{ostype},
                    HOST_NAME => $self->{hostname},
                    MGMT_IP   => $self->{mgmtIp},
                    MGMT_PORT => $self->{mgmtPort}
                };

                for ( my $i = 0 ; $i < $fieldsCount ; $i++ ) {
                    if ( $fields[$i] eq 'COMMAND' ) {
                        $processAttrs->{COMM} = shift(@vars);
                    }
                    else {
                        $processAttrs->{ $fields[$i] } = shift(@vars);
                    }
                }
                $processAttrs->{COMMAND} = join( ' ', @vars );

                my $matchedProc = $self->processMatch($processAttrs);
                if ( defined($matchedProc) ) {
                    push( @matchedProcs, $matchedProc );
                }
            }

            close($chldOut);
            my $status = $?;

            if ( $status != 0 ) {
                print("ERROR: Get Process list failed.\n");
                exit(1);
            }
        }
        else {
            print("ERROR: Can not launch list process command:$self->{listProcCmd}\n");
        }
    }

    foreach my $matchedProc (@matchedProcs) {
        my $procInfo  = $matchedProc->{procMap};
        my $className = $matchedProc->{className};
        my $matched   = $self->doDetailCollect( $className, $procInfo );
        if ( $matched == 1 ) {
            $procInfo->{IPV4_ADDRS} = $self->{ipv4Addrs};
            $procInfo->{IPV6_ADDRS} = $self->{ipv6Addrs};
            if ( defined( $procInfo->{ELAPSED} ) ) {
                $procInfo->{ELAPSED} = $self->convertEplapsed( $procInfo->{ELAPSED} );
            }
        }
    }
    print("INFO: List all processes and find matched processes complete.\n");

    return $self->{appsMap};
}

sub getProcess {
    my ( $self, $pid, %args ) = @_;

    my $ostype        = $self->{ostype};
    my $parseListen   = $args{parseListen};
    my $parseConnStat = $args{parseConnStat};

    my $procInfo = {
        OS_ID      => $self->{osId},
        OS_TYPE    => $ostype,
        HOST_NAME  => $self->{hostname},
        MGMT_IP    => $self->{mgmtIp},
        MGMT_PORT  => $self->{mgmtPort},
        IPV4_ADDRS => $self->{ipv4Addrs},
        IPV6_ADDRS => $self->{ipv6Addrs}
    };

    my $containerId = $args{containerId};
    if ( defined($containerId) ) {
        $procInfo->{CONTAINER_ID} = $containerId;
    }

    if ( $ostype eq 'Linux' ) {
        my $linuxPs = $self->{LinuxPS};
        my $process = $linuxPs->_getProcess($pid);

        if ( defined($process) ) {

            #PID PPID PGID USER GID RUSER RGID %CPU %MEM TIME ELAPSED COMM ARGS
            $procInfo->{PID}     = $$process[0];
            $procInfo->{PPID}    = $$process[1];
            $procInfo->{PGID}    = $$process[2];
            $procInfo->{USER}    = $$process[3];
            $procInfo->{GID}     = $$process[4];
            $procInfo->{RUSER}   = $$process[5];
            $procInfo->{RGID}    = $$process[6];
            $procInfo->{'%CPU'}  = $$process[7];
            $procInfo->{'%MEM'}  = $$process[8];
            $procInfo->{TIME}    = $$process[9];
            $procInfo->{ELAPSED} = $$process[10];
            $procInfo->{COMM}    = $$process[11];
            $procInfo->{COMMAND} = $$process[12];
        }
    }
    else {
        my ($chldOut);
        open( $chldOut, "$self->{listProcCmdByPid} $pid |" );
        if ( defined($chldOut) ) {

            my $headLine = <$chldOut>;
            $headLine =~ s/^\s*|\s*$//g;
            $headLine =~ s/^.*?PID/PID/g;
            my $cmdPos      = rindex( $headLine, ' ' );
            my @fields      = split( /\s+/, substr( $headLine, 0, $cmdPos ) );
            my $fieldsCount = scalar(@fields);

            my $line;
            while ( $line = <$chldOut> ) {
                $line =~ s/^\s*|\s*$//g;
                my @vars = split( /\s+/, $line );

                for ( my $i = 0 ; $i < $fieldsCount ; $i++ ) {
                    if ( $fields[$i] eq 'COMMAND' ) {
                        $procInfo->{COMM} = shift(@vars);
                    }
                    else {
                        $procInfo->{ $fields[$i] } = shift(@vars);
                    }
                }
                $procInfo->{COMMAND} = join( ' ', @vars );
            }

            close($chldOut);
            my $status = $?;

            if ( $status != 0 ) {
                print("WARN: Get Process $pid information failed.\n");
                return undef;
            }
        }
        else {
            print("ERROR: Can not launch list process command:$self->{listProcCmdByPid}\n");
            return undef;
        }
    }

    if ( defined( $procInfo->{PID} ) ) {
        if ( -e "/proc/$pid/exe" ) {
            $procInfo->{EXECUTABLE_FILE} = readlink("/proc/$pid/exe");
        }
        my $envMap = $self->getProcEnv($pid);
        $procInfo->{ENVIRONMENT} = $envMap;

        my $connGather = $self->{connGather};
        if ($parseListen) {
            my $connInfo    = $connGather->getListenInfo( $pid, 0 );
            my $portInfoMap = $self->getListenPortInfo( $connInfo->{LISTEN} );
            $connInfo->{PORT_BIND} = $portInfoMap;
            $procInfo->{CONN_INFO} = $connInfo;
        }

        if ($parseConnStat) {
            my $connInfo = $procInfo->{CONN_INFO};
            if ( defined($connInfo) ) {
                my $statInfo = $connGather->getStatInfo( $pid, $connInfo->{LISTEN}, 0 );
                map { $connInfo->{$_} = $statInfo->{$_} } keys(%$statInfo);
            }
        }

        return $procInfo;
    }
    else {
        return;
    }
}

sub getListenPortInfo {

    #根据监听地址计算出显式绑定的IP和隐式绑定的IP，IP分开IPV6和非IPV6IP
    my ( $self, $lsnAddrMap ) = @_;

    my $ipv4Addrs = $self->{ipv4Addrs};
    my $ipv6Addrs = $self->{ipv6Addrs};
    my $ipv4Map   = {};
    my $ipV6Map   = {};
    map { $ipv4Map->{ $_->{IP} } = 1 } (@$ipv4Addrs);
    map { $ipV6Map->{ $_->{IP} } = 1 } (@$ipv6Addrs);

    my $secondaryIpMap = {};
    foreach my $ipInfo ( @$ipv4Addrs, @$ipv6Addrs ) {
        if ( $ipInfo->{SECONDARY} ) {
            $secondaryIpMap->{ $ipInfo->{IP} } = 1;
        }
    }

    my $portInfoMap = {};

    foreach my $lsnAddr ( keys(%$lsnAddrMap) ) {
        my $port;
        my $portInfo;
        if ( $lsnAddr =~ /^(\d+)$/ ) {
            $port     = int($1);
            $portInfo = $portInfoMap->{$port};

            if ( not defined($portInfo) ) {
                $portInfo = {
                    EXPLICIT_IP   => {},
                    IMPLICIT_IP   => $ipv4Map,
                    EXPLICIT_IPV6 => {},
                    IMPLICIT_IPV6 => $ipV6Map,
                    SECONDARY_IP  => $secondaryIpMap
                };
                $portInfoMap->{$port} = $portInfo;
            }
        }
        elsif ( $lsnAddr =~ /^(.*):(\d+)$/ ) {
            my $ip = $1;
            $port = int($2);
            if ( $ip =~ /^127\./ or $ip eq '::1' ) {

                #去掉lookback地址
                next;
            }

            $portInfo = $portInfoMap->{$port};
            if ( not defined($portInfo) ) {
                $portInfo = {
                    EXPLICIT_IP   => {},
                    IMPLICIT_IP   => {},
                    EXPLICIT_IPV6 => {},
                    IMPLICIT_IPV6 => {},
                    SECONDARY_IP  => {}
                };
                $portInfoMap->{$port} = $portInfo;
            }

            my $explicitIpMap       = $portInfo->{EXPLICIT_IP};
            my $explicitIpV6Map     = $portInfo->{EXPLICIT_IPV6};
            my $explicitSecondIpMap = $portInfo->{SECONDARY_IP};

            if ( $ip =~ /^[\d\.]+$/ ) {
                $explicitIpMap->{$ip} = 1;
                if ( defined( $secondaryIpMap->{$ip} ) ) {
                    $explicitSecondIpMap->{$ip} = 1;
                }
            }
            else {
                $explicitIpV6Map->{$ip} = 1;
                if ( defined( $secondaryIpMap->{$ip} ) ) {
                    $explicitSecondIpMap->{$ip} = 1;
                }
            }
        }
    }

    return ($portInfoMap);
}

sub predictBizIp {
    my ( $self, $connInfo, $port ) = @_;

    my $vip;
    my $bizIp;

    my $portInfoMap = $connInfo->{PORT_BIND};
    my $mgmtIp      = $self->{mgmtIp};

    if ( not defined($portInfoMap) ) {
        return ( $mgmtIp, $mgmtIp );
    }

    my $portInfo = $portInfoMap->{"$port"};
    if ( not defined($portInfo) ) {
        return ( $mgmtIp, $mgmtIp );
    }

    my @explicitIps   = sort( keys( %{ $portInfo->{EXPLICIT_IP} } ) );
    my @explicitIpV6s = sort( keys( %{ $portInfo->{EXPLICIT_IPV6} } ) );
    my @implicitIps   = sort( keys( %{ $portInfo->{IMPLICIT_IP} } ) );
    my @implicitIpV6s = sort( keys( %{ $portInfo->{IMPLICIT_IPV6} } ) );
    my @secondaryIps  = sort( keys( %{ $portInfo->{SECONDARY_IP} } ) );

    if ( scalar(@explicitIpV6s) > 0 ) {
        $vip   = $explicitIpV6s[-1];
        $bizIp = $explicitIpV6s[0];
    }
    elsif ( scalar(@explicitIps) > 0 ) {
        $vip   = $explicitIps[-1];
        $bizIp = $explicitIps[0];
    }

    if ( not defined($bizIp) ) {
        if ( scalar(@implicitIps) == 1 ) {
            $bizIp = $implicitIps[0];
        }
        elsif ( scalar(@implicitIpV6s) == 1 ) {
            $bizIp = $implicitIpV6s[0];
        }
        else {
            $bizIp = $mgmtIp;
        }
    }

    if ( not defined($vip) ) {
        if ( scalar(@implicitIps) == 1 ) {
            $vip = $implicitIps[0];
        }
        elsif ( scalar(@implicitIpV6s) == 1 ) {
            $vip = $implicitIpV6s[0];
        }
        elsif ( scalar(@secondaryIps) >= 1 ) {
            $vip = $secondaryIps[-1];
        }
        else {
            $vip = $mgmtIp;
        }
    }

    return ( $bizIp, $vip );
}

sub getPortListenIps {
    my ( $self, $connInfo, $port ) = @_;

    my $vip;
    my $bizIp;

    my $portInfoMap = $connInfo->{PORT_BIND};

    if ( not defined($portInfoMap) ) {
        return [];
    }

    my $portInfo = $portInfoMap->{"$port"};
    if ( not defined($portInfo) ) {
        return [];
    }

    my $ipAddrsMap = {};
    map { $ipAddrsMap->{$_} = $port } ( keys( %{ $portInfo->{EXPLICIT_IP} } ) );
    map { $ipAddrsMap->{$_} = $port } ( keys( %{ $portInfo->{EXPLICIT_IPV6} } ) );
    map { $ipAddrsMap->{$_} = $port } ( keys( %{ $portInfo->{IMPLICIT_IP} } ) );
    map { $ipAddrsMap->{$_} = $port } ( keys( %{ $portInfo->{IMPLICIT_IPV6} } ) );

    return wantarray ? keys(%$ipAddrsMap) : $ipAddrsMap;
}

1;
