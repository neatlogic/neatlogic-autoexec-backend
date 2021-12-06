#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/../../lib";

package ProcessFinder;

use strict;
use FindBin;
use Cwd;
use POSIX qw(uname);
use Sys::Hostname;
use JSON qw(from_json to_json);

use CollectUtils;

#use JSON qw(from_json to_json);
#use Data::Dumper;

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

    my $self = { callback => $args{callback} };
    $self->{procFilters}      = $procFilters;
    $self->{filtersCount}     = scalar(@$procFilters);
    $self->{matchedProcsInfo} = {};

    my @uname  = uname();
    my $ostype = $uname[0];
    $ostype =~ s/\s.*$//;
    $self->{ostype}   = $ostype;
    $self->{hostname} = hostname();

    $self->{osId}     = '';
    $self->{mgmtIp}   = '';    #此主机节点Agent或ssh连接到此主机，主机节点端的IP
    $self->{mgmtPort} = '';    #此主机节点Agent或ssh连接到此主机，主机节点端的port
    my $AUTOEXEC_NODE = $ENV{'AUTOEXEC_NODE'};

    if ( defined($AUTOEXEC_NODE) and $AUTOEXEC_NODE ne '' ) {
        my $nodeInfo = from_json($AUTOEXEC_NODE);
        $self->{mgmtIp}   = $nodeInfo->{host};
        $self->{mgmtPort} = $nodeInfo->{protocolPort};
        $self->{osId}     = $nodeInfo->{resourceId};
    }

    #列出某个进程的信息，要求：前面的列的值都不能有空格，args（就是命令行）放后面，因为命令行有空格
    $self->{procEnvCmd} = 'ps eww';

    #列出所有进程的命令，包括环境变量，用于定位查找进程，命令行和环境变量放最后列，因为命令行有空格
    $self->{listProcCmd} = 'ps -eo pid,ppid,pgid,user,group,ruser,rgroup,pcpu,pmem,time,etime,comm,args';

    if ( $ostype eq 'Windows' ) {

        #windows需要编写powershell脚本实现ps的功能，用于根据命令行过滤进程
        $self->{listProcCmd} = CollectUtils->getWinPs1Cmd("$FindBin::Bin/lib/windowsps.ps1") . ' getAllProcesses';

        #根据pid获取进程环境变量的powershell脚本，实现类似ps读取进程环境变量的功能
        if ( $uname[4] =~ /64/ ) {
            $self->{procEnvCmd} = Cwd::abs_path("$FindBin::Bin/lib/windowspenv/getprocenv");
        }
        else {
            $self->{procEnvCmd} = CollectUtils->getWinPs1Cmd("$FindBin::Bin/lib/windowspenv.ps1") . ' getProcessEnv';
        }
    }

    bless( $self, $type );
    return $self;
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
        my $content = CollectUtils->getFileContent($envFilePath);
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
        my $lastEnvPos = rindex( $envLine, ' ', $lastEqualPos );
        my $lastEnvName = substr( $envLine, $lastEnvPos + 1, $lastEqualPos - $lastEnvPos - 1 );
        my $lastEnvVal = substr( $envLine, $lastEqualPos + 1 );
        chomp($lastEnvVal);
        if ( $lastEnvVal =~ /^\w+$/ ) {
            $envMap->{$lastEnvName} = $lastEnvVal;
        }
    }
    delete( $envMap->{LS_COLORS} );
    print("INFO: Get process $pid environment complete.\n");
    return $envMap;
}

sub findProcess {
    my ($self) = @_;
    print("INFO: Begin to find and match processes.\n");
    my $callback    = $self->{callback};
    my $matchedProc = {};
    my $pipe;
    my $pid = open( $pipe, "$self->{listProcCmd}|" );
    if ( defined($pipe) ) {
        my $procFilters  = $self->{procFilters};
        my $filtersCount = $self->{filtersCount};

        my $line;
        my $headLine = <$pipe>;
        $headLine =~ s/^\s*|\s*$//g;
        $headLine =~ s/^.*?PID/PID/g;
        my $cmdPos = rindex( $headLine, ' ' );
        my @fields = split( /\s+/, substr( $headLine, 0, $cmdPos ) );
        my $fieldsCount = scalar(@fields);
        while ( $line = <$pipe> ) {
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

                if ( $isMatched == 1 ) {
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
                    my $myPid = $matchedMap->{PID};

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

                    if ( $isMatched == 1 ) {
                        if ( -e "/proc/$myPid/exe" ) {
                            $matchedMap->{EXECUTABLE_FILE} = readlink("/proc/$myPid/exe");
                        }
                        if ( not defined($envMap) ) {
                            $envMap = $self->getProcEnv($myPid);
                        }
                        $matchedMap->{ENVIRONMENT} = $envMap;

                        my $matched = &$callback( $config->{className}, $matchedMap, $self->{matchedProcsInfo} );
                        if ( $matched == 1 ) {
                            $self->{matchedProcsInfo}->{$myPid} = $matchedMap;
                        }
                    }

                    last;
                }
            }
        }

        close($pipe);
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
}

1;
