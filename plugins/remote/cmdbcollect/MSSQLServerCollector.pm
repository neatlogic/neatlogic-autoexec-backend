#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package MSSQLServerCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjType;

use Data::Dumper;

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps  => ['\bsqlservr.exe\b'],      #正则表达是匹配ps输出
        psAttrs  => { COMM => 'sqlservr' },    #ps的属性的精确匹配
        envAttrs => {}                         #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

#可用参数：
#$self->{procInfo}， 根据config命中的进程信息
#$self->{matchedProcsInfo}，之前已经matched的进程信息
#Return：应用信息的Hash，undef:不匹配
#采集器实现需要重载这个类
#Return：如果判断当前进程不是想要的进程，返回undef，否则返回应用信息的HashMap
sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $appInfo = {};

    my $objType          = $CollectObjType::DB;
    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};
    my $user             = $procInfo->{USER};
    my $envMap           = $procInfo->{ENVIRONMENT};
    my $cmdLine          = $procInfo->{COMMAND};

    print Dumper ($procInfo);

    # c:\tmp\autoexec\cmdbcollect>"C:\Program Files\Microsoft SQL Server\MSSQL10_50.MSSQLSERVER\MSSQL\Binn\sqlservr.exe"
    # 2021-09-22 11:32:58.67 Server      Logging to event log is disabled. Startup option '-v' is supplied, either from th
    # d prompt.
    # 2021-09-22 11:32:58.67 Server      Microsoft SQL Server 2008 R2 (RTM) - 10.50.1600.1 (X64)
    #         Apr  2 2010 15:48:46
    #         Copyright (c) Microsoft Corporation
    #         Enterprise Edition (64-bit) on Windows NT 6.0 <X64> (Build 6001: Service Pack 1) (Hypervisor)

    # 2021-09-22 11:32:58.67 Server      (c) Microsoft Corporation.
    # 2021-09-22 11:32:58.67 Server      All rights reserved.
    # 2021-09-22 11:32:58.67 Server      Server process ID is 5644.
    # 2021-09-22 11:32:58.67 Server      System Manufacturer: 'VMware, Inc.', System Model: 'VMware Virtual Platform'.
    # 2021-09-22 11:32:58.67 Server      Authentication mode is MIXED.
    my $sqlServerCmd = $procInfo->{COMMAND};
    $sqlServerCmd =~ s/sqlservr.exe".*$/sqlservr.exe"/;

    my $version;
    my $authMode;
    my $verCmd       = "$sqlServerCmd -v";
    my $verInfoLines = $self->getCmdOutLines($verCmd);
    foreach my $line (@$verInfoLines) {
        if ( $line =~ /Microsoft SQL Server\s+(.*?)\s*$/ ) {
            $version = $1;
        }
        elsif ( $line =~ /Authentication mode is (\w+)/ ) {
            $authMode = $1;
        }
    }
    $appInfo->{VERSION}             = $version;
    $appInfo->{AUTHENTICATION_MODE} = $authMode;

    my $portsMap    = {};
    my @portNumbers = ();
    my $lsnPortsMap = $procInfo->{CONN_INFO}->{LISTEN};
    foreach my $lsnPort ( keys(%$lsnPortsMap) ) {
        if ( $lsnPort !~ /:\d+$/ ) {
            $portsMap->{ int($lsnPort) } = 1;
        }
        else {
            my $myPort = $lsnPort;
            $myPort =~ s/^.*://;
            $portsMap->{ int($myPort) } = 1;
        }
        @portNumbers = sort( keys(%$portsMap) );
    }
    $appInfo->{PORT}     = $portNumbers[0];
    $appInfo->{MON_PORT} = $portNumbers[0];
    $appInfo->{PORTS}    = \@portNumbers;

    return $appInfo;
}

1;
