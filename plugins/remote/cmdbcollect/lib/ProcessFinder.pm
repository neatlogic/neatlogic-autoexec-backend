#!/usr/bin/perl
package ProcessFinder;

use strict;
use FindBin;
use POSIX qw(uname);
use Sys::Hostname;

#use JSON qw(from_json to_json);
use Data::Dumper;

sub new {
    my ( $type, $filterMap, %args ) = @_;

    #filterMap
    #key=>'tomcat',
    #patterns=>['org.apache.catalina.startup.Bootstrap','tomcat-\d+\.\d+']
    #Callback param map:
    #key=>'tomcat',
    #pid=>3844,
    #command=>'xxxxxxxxxxxxxxxxx'

    my $self = { callback => $args{callback} };
    $self->{filterMap} = $filterMap;

    my @uname  = uname();
    my $ostype = $uname[0];
    $self->{ostype}   = $ostype;
    $self->{hostname} = hostname();

    $self->{manageIp}   = '';
    $self->{managePort} = '';
    my $AUTOEXEC_NODE = $ENV{'AUTOEXEC_NODE'};

    #if ( defined $AUTOEXEC_NODE and $AUTOEXEC_NODE ne '' ) {
    #    my $nodeInfo = from_json($AUTOEXEC_NODE);
    #    $self->{manageIp}   = $nodeInfo->{host};
    #    $self->{managePort} = $nodeInfo->{port};
    #}

    #列出某个进程的信息，要求：前面的列的值都不能有空格，args（就是命令行）放后面，因为命令行有空格
    $self->{procInfoCmd} = 'ps -o pid,ppid,user,group,ruser,rgroup,pcpu,pmem,time,etime,args -p';

    #列出所有进程的命令，包括环境变量，用于定位查找进程，命令行和环境变量放最后列，因为命令行有空格
    $self->{listProcCmd} = 'ps aeSxvww';

    if ( $ostype eq 'AIX' ) {
        $self->{listProcCmd} = 'ps aexvww';
    }
    elsif ( $ostype eq 'Windows' ) {

        #windows需要编写powershell脚本实现ps的功能，用于根据命令行和环境变量过滤进程
        $self->{listProcCmd} = "$FindBin::Bin/windowsps.ps1";

        #根据pid获取详细信息的powershell脚本，实现类似ps的功能
        $self->{procInfoCmd} = "$FindBin::Bin/windowspinfo.ps1";
    }

    bless( $self, $type );
    return $self;
}

#获取单个进程的信息
sub getProcInfo {
    my ( $self, $pid ) = @_;
    if ( not defined($pid) ) {
        print("WARN: PID is not defined, can not get process info.\n");
    }

    my $cmd     = $self->{procInfoCmd} . " $pid";
    my $procTxt = `$cmd`;
    my $status  = $?;
    if ( $status != 0 ) {
        print("WARN: Get process info for pid:$pid failed.\n");
    }

    my ( $headLine, $line ) = split( /\n/, $procTxt );
    $headLine =~ s/^\s*|\s*$//g;
    $line =~ s/^\s*|\s*$//g;
    my @fields      = split( /\s+/, $headLine );
    my $fieldsCount = scalar(@fields);
    my @vars        = split( /\s+/, $line );

    my $infoMap = {};
    for ( my $i = 0 ; $i < $fieldsCount - 1 ; $i++ ) {
        $infoMap->{ $fields[$i] } = shift(@vars);
    }
    $infoMap->{COMMAND} = join( ' ', @vars );

    return $infoMap;
}

sub getOutgoingConn {
    my ( $self, $pid ) = @_;
}

sub findProcess {
    my ($self) = @_;

    my $callback    = $self->{callback};
    my $matchedProc = {};
    my $pipe;
    my $pid = open( $pipe, "$self->{listProcCmd}|" );
    if ( defined($pipe) ) {
        my $filterMap = $self->{filterMap};
        my $line;
        my $headLine = <$pipe>;
        $headLine =~ s/^\s*|\s*$//g;
        my $cmdPos = rindex( $headLine, ' ' );
        my @fields = split( /\s+/, substr( $headLine, 0, $cmdPos ) );
        my $fieldsCount = scalar(@fields);
        while ( $line = <$pipe> ) {

            while ( my ( $key, $patterns ) = each(%$filterMap) ) {
                my $isMatched = 1;
                foreach my $pattern (@$patterns) {
                    if ( $line !~ /$pattern/ ) {
                        $isMatched = 0;
                        last;
                    }
                }

                if ( $isMatched == 1 ) {
                    $line =~ s/^\s*|\s*$//g;
                    my @vars = split( /\s+/, $line );

                    my $matchedMap = {
                        OS_TYPE     => $self->{ostype},
                        HOST_NAME   => $self->{hostname},
                        MANAGE_IP   => $self->{manageIp},
                        MANAGE_PORT => $self->{managePort}
                    };

                    $matchedMap->{APP_TYPE} = $key;
                    for ( my $i = 0 ; $i < $fieldsCount ; $i++ ) {
                        $matchedMap->{ $fields[$i] } = shift(@vars);
                    }
                    my $envs = join( ' ', @vars );

                    #获取进程详细的信息
                    my $procInfo = $self->getProcInfo( $matchedMap->{PID} );
                    while ( my ( $k, $v ) = each(%$procInfo) ) {
                        $matchedMap->{$k} = $v;
                    }
                    $matchedMap->{ENVRIONMENT} = substr( $envs, length( $matchedMap->{COMMAND} ) );

                    &$callback($matchedMap);
                }
            }
        }

        close($pipe);
        my $status = $?;
        if ( $status != 0 ) {
            print("ERROR: Get Process list failed.\n");
            exit(1);
        }
    }
}

1;
