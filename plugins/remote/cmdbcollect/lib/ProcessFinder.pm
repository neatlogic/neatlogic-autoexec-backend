#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/../../lib";

package ProcessFinder;

use strict;
use FindBin;
use IPC::Open2;
use IO::File;
use Cwd;
use POSIX qw(uname);
use JSON qw(from_json to_json);
use CollectUtils;

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
        callback    => $args{callback},
        inspect     => $args{inspect},
        connGather  => $args{connGather},
        appsMap     => {},
        appsArray   => [],
        osInfo      => $args{osInfo},
        passArgs    => $args{passArgs},
        bizIp       => $args{bizIp},
        ipAddrs     => $args{ipAddrs},
        ipv6Addrs   => $args{ipv6Addrs},
        procEnvName => $args{procEnvName},
        containner  => $args{containner}
    };

    if(not defined($procFilters)){
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
        if ( $timeStr =~ /(\d+)-(\d+):(\d+):(\d+)/ ) {
            $uptimeSeconds = 86400 * $1 + 3600 * $2 + 60 * $3 + $4;
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
    my $fh = IO::File->new("</proc/$pid/cgroup");

    my $isContainer = 0;
    my $containerType = '';

    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            if ( index( $line, 'docker' ) >= 0 ) {
                $isContainer = 1;
                $containerType = 'Docker';
                last;
            }
        }
        $fh->close();
    }

    return ($isContainer,$containerType);
}

sub findProcess {
    my ($self) = @_;
    print("INFO: Begin to find and match processes.\n");
    my $callback    = $self->{callback};
    my $matchedProc = {};
    my $chldOut;
    open( $chldOut, $self->{listProcCmd} . '|' );
    if ( defined($chldOut) ) {
        my $procFilters  = $self->{procFilters};
        my $filtersCount = $self->{filtersCount};

        my $line;
        my $headLine = <$chldOut>;
        $headLine =~ s/^\s*|\s*$//g;
        $headLine =~ s/^.*?PID/PID/g;
        my $cmdPos      = rindex( $headLine, ' ' );
        my @fields      = split( /\s+/, substr( $headLine, 0, $cmdPos ) );
        my $fieldsCount = scalar(@fields);
        while ( $line = <$chldOut> ) {
            for ( my $i = 0 ; $i < $filtersCount ; $i++ ) {
                my $config   = $$procFilters[$i];
                my $regExps  = $config->{regExps};
                my $psAttrs  = $config->{psAttrs};
                my $envAttrs = $config->{envAttrs};

                my $isMatched = 1;
                foreach my $pattern (@$regExps) {
                    if ( $line !~ /$pattern/ ) {
                        $isMatched = 0;
                        last;
                    }
                }

                if ( $isMatched == 0 ) {
                    next;
                }

                $line =~ s/^\s*|\s*$//g;
                my @vars = split( /\s+/, $line );

                my $matchedMap = {
                    OS_ID     => $self->{osId},
                    OS_TYPE   => $self->{ostype},
                    HOST_NAME => $self->{hostname},
                    MGMT_IP   => $self->{mgmtIp},
                    MGMT_PORT => $self->{mgmtPort},
                    _OBJ_TYPE => $config->{objType}
                };

                for ( my $i = 0 ; $i < $fieldsCount ; $i++ ) {
                    if ( $fields[$i] eq 'COMMAND' ) {
                        $matchedMap->{COMM} = shift(@vars);
                    }
                    else {
                        $matchedMap->{ $fields[$i] } = shift(@vars);
                    }
                }

                $matchedMap->{COMMAND} = join( ' ', @vars );
                my $envMap;
                my $myPid = $matchedMap->{PID};

                #容器进程只采集容器信息
                my ( $isContainer, $containerType ) = $self->isProcInContainer( $matchedMap->{PID} );
                if ( $isContainer ) {
                    $matchedMap->{_CONTAINERTYPE} = $containerType;
                    $config->{className} = "$containerType"."Collector";
                    if ($self->{containner} == 0 ){
                        next ;
                    }
                }else{

                    if ( defined($psAttrs) ) {
                        my $psAttrVal;
                        foreach my $attr ( keys(%$psAttrs) ) {
                            my $attrVal = $psAttrs->{$attr};
                            $psAttrVal = $matchedMap->{$attr};
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
                }

                if ( $isMatched == 0 ) {
                    next;
                }

                if ( -e "/proc/$myPid/exe" ) {
                    $matchedMap->{EXECUTABLE_FILE} = readlink("/proc/$myPid/exe");
                }
                if ( not defined($envMap) ) {
                    $envMap = $self->getProcEnv($myPid);
                }
                $matchedMap->{ENVIRONMENT} = $envMap;
                my $matched = &$callback( $config->{className}, $matchedMap, $self );
                if ( $matched == 1 ) {
                    $matchedMap->{IP_ADDRS}   = $self->{ipAddrs};
                    $matchedMap->{IPV6_ADDRS} = $self->{ipv6Addrs};
                    if ( defined( $matchedMap->{ELAPSED} ) ) {
                        $matchedMap->{ELAPSED} = $self->convertEplapsed( $matchedMap->{ELAPSED} );
                    }
                    $self->{matchedProcsInfo}->{$myPid} = $matchedMap;
                    last;
                }
            }
        }

        close($chldOut);
        my $status = $?;

        if ( $status != 0 ) {
            print("ERROR: Get Process list failed.\n");
            exit(1);
        }
        print("INFO: List all processes and find matched processes complete.\n");
    }
    else {
        print("ERROR: Can not launch list process command:$self->{listProcCmd}\n");
    }

    return $self->{appsMap};
}

sub getProcess {
    my ( $self, $pid, %args ) = @_;

    my $parseListen   = $args{parseListen};
    my $parseConnStat = $args{parseConnStat};

    my $procInfo = {
        OS_ID      => $self->{osId},
        OS_TYPE    => $self->{ostype},
        HOST_NAME  => $self->{hostname},
        MGMT_IP    => $self->{mgmtIp},
        MGMT_PORT  => $self->{mgmtPort},
        IP_ADDRS   => $self->{ipAddrs},
        IPV6_ADDRS => $self->{ipv6Addrs}
    };

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
            my $myPid = $procInfo->{PID};

            if ( -e "/proc/$myPid/exe" ) {
                $procInfo->{EXECUTABLE_FILE} = readlink("/proc/$myPid/exe");
            }

            my $envMap = $self->getProcEnv($myPid);
            $procInfo->{ENVIRONMENT} = $envMap;
        }

        close($chldOut);
        my $status = $?;

        if ( $status != 0 ) {
            print("WARN: Get Process $pid information failed.\n");
            return undef;
        }

        my $connGather = $self->{connGather};
        if ($parseListen) {
            my $connInfo    = $connGather->getListenInfo($pid , 0);
            my $portInfoMap = $self->getListenPortInfo( $connInfo->{LISTEN} );
            $connInfo->{PORT_BIND} = $portInfoMap;
            $procInfo->{CONN_INFO} = $connInfo;
        }

        if ($parseConnStat) {
            my $connInfo = $procInfo->{CONN_INFO};
            if ( defined($connInfo) ) {
                my $statInfo = $connGather->getStatInfo( $pid, $connInfo->{LISTEN} , 0);
                map { $connInfo->{$_} = $statInfo->{$_} } keys(%$statInfo);
            }
        }
    }
    else {
        print("ERROR: Can not launch list process command:$self->{listProcCmdByPid}\n");
        return undef;
    }

    return $procInfo;
}

sub getListenPortInfo {

    #根据监听地址计算出显式绑定的IP和隐式绑定的IP，IP分开IPV6和非IPV6IP
    my ( $self, $lsnAddrMap ) = @_;

    my $ipAddrs   = $self->{ipAddrs};
    my $ipv6Addrs = $self->{ipv6Addrs};

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
                    IMPLICIT_IP   => {},
                    EXPLICIT_IPV6 => {},
                    IMPLICIT_IPV6 => {}
                };
                $portInfoMap->{$port} = $portInfo;
            }
            my $implicitIpMap   = $portInfo->{IMPLICIT_IP};
            my $implicitIpV6Map = $portInfo->{IMPLICIT_IPV6};
            map { $implicitIpMap->{ $_->{IP} }   = 1 } (@$ipAddrs);
            map { $implicitIpV6Map->{ $_->{IP} } = 1 } (@$ipv6Addrs);
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
                    IMPLICIT_IPV6 => {}
                };
                $portInfoMap->{$port} = $portInfo;
            }

            my $explicitIpMap   = $portInfo->{EXPLICIT_IP};
            my $explicitIpV6Map = $portInfo->{IMPLICIT_IPV6};

            if ( $ip =~ /^[\d\.]+$/ ) {
                $explicitIpMap->{$ip} = 1;
            }
            else {
                $explicitIpV6Map->{$ip} = 1;
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
        else {
            $vip = $mgmtIp;
        }
    }

    return ( $bizIp, $vip );
}

1;
