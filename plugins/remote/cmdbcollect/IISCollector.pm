#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package IISCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps => ['\System\s'],           #正则表达是匹配ps输出
        psAttrs => { COMM => 'System' },    #ps的属性的精确匹配
                                            #envAttrs => {}                       #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
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
    my $utils = $self->{collectUtils};
    $self->{codepage} = $self->getCodePage();

    if ( $self->{ostype} ne 'Windows' ) {
        return;
    }

    # VersionString
    # -------------
    # Version 10.0
    my $version;
    my ( $status, $verInfo ) = $utils->getWinPSCmdOut( 'get-itemproperty HKLM:\SOFTWARE\Microsoft\InetStp\  | select versionstring', { charset => $self->{codepage} } );
    if ( $verInfo =~ /([\d\.]+)\s*$/ ) {
        $version = $1;
    }
    if ( $status ne 0 or not defined($version) ) {
        print("WARN: IIS not installed.\n");
        return;
    }

    # #如果不是主进程，则不match，则返回null
    # if ( not $self->isMainProcess() ) {
    #     return undef;
    # }

    my $procInfo = $self->{procInfo};
    $procInfo->{COMM} = 'System';
    $procInfo->{USER} = 'System';

    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');
    $appInfo->{VERSION}       = $version;

    if ( $version =~ /(\d+)/ ) {
        $appInfo->{MAJOR_VERSION} = "IIS$1";
    }

    # Name             ID   State      Physical Path                  Bindings
    # ----             --   -----      -------------                  --------
    # Default Web Site 1    Started    %SystemDrive%\inetpub\wwwroot  http *:80:
    my @sites = ();
    my ( $status, $siteInfoLines ) = $utils->getWinPSCmdOutLines( 'Get-IISSite', { charset => $self->{codepage} } );
    if ( $status ne 0 ) {
        print("ERROR: Powershell module IISAdministration not install.\n");
        print("WARN: Please install by powershell command:Install-Module -Name IISAdministration -force -Scope AllUsers -AllowClobber\n");
        return;
    }

    my $siteLineCount = scalar(@$siteInfoLines);
    foreach ( my $i = 3 ; $i < $siteLineCount ; $i++ ) {
        my $line = $$siteInfoLines[$i];

        if ( $line =~ /^\s*(.*?)\s+(\d+)\s+(Started|Stopped)\s+(.*?)\s+(https|http|ftp)\s(.?)\s*$/ ) {
            my $siteInfo = {};
            $siteInfo->{NAME}     = $1;
            $siteInfo->{ID}       = $2;
            $siteInfo->{STATE}    = $3;
            $siteInfo->{PATH}     = $4;
            $siteInfo->{PROTOCOL} = $5;
            $siteInfo->{LISTEN}   = $6;
            push( @sites, $siteInfo );
        }
    }
    $appInfo->{SITES} = \@sites;

    my $lsnMap = {};
    my ( $port, $sslPort );
    foreach my $oneSite (@sites) {
        my $protocol = $oneSite->{PROTOCOL};
        my $lsnInfo  = $oneSite->{LISTEN};
        if ( $protocol eq 'http' and $lsnInfo =~ /:80:/ ) {
            $port = 80;
        }
        if ( $protocol eq 'https' and $lsnInfo =~ /:443:/ ) {
            $sslPort = 443;
        }

        while ( $lsnInfo =~ /([^:]+):(\d+)/g ) {
            my $lsnAddr = $1;
            my $lsnPort = $2;
            if ( $lsnAddr eq '*' ) {
                $lsnMap->{$lsnPort} = 1;
            }
            else {
                $lsnMap->{"$lsnAddr:$lsnPort"} = 1;
            }
        }
    }

    if ( not defined($port) ) {
        foreach my $oneSite (@sites) {
            my $protocol = $oneSite->{PROTOCOL};
            my $lsnInfo  = $oneSite->{LISTEN};
            if ( $protocol eq 'http' and $lsnInfo =~ /:(\d+):/ ) {
                $port = $1;
                last;
            }
        }
    }

    if ( not defined($sslPort) ) {
        foreach my $oneSite (@sites) {
            my $protocol = $oneSite->{PROTOCOL};
            my $lsnInfo  = $oneSite->{LISTEN};
            if ( $protocol eq 'https' and $lsnInfo =~ /:(\d+):/ ) {
                $sslPort = $1;
                last;
            }
        }
    }
    $appInfo->{PORT}     = $port;
    $appInfo->{SSL_PORT} = $sslPort;
    $appInfo->{MON_PORT} = $port;

    # Name                 Status       CLR Ver  Pipeline Mode  Start Mode
    # ----                 ------       -------  -------------  ----------
    # DefaultAppPool       Started      v4.0     Integrated     OnDemand
    my @appPools         = ();
    my $appPoolInfoLines = $utils->getWinPSCmdOutLines( 'Get-IISAppPool', { charset => $self->{codepage} } );
    my $poolLineCount    = scalar(@$appPoolInfoLines);
    foreach ( my $i = 3 ; $i < $poolLineCount ; $i++ ) {
        my $line = $$appPoolInfoLines[$i];
        print("DEBUG: line:$line\n");

        if ( $line =~ /^\s*(.*?)\s+(Started|Stopped)\s+(\S+)\s+(\S+)\s+(\S+)\s*$/ ) {
            my $poolInfo = {};
            $poolInfo->{NAME}          = $1;
            $poolInfo->{STATE}         = $2;
            $poolInfo->{CLR_VER}       = $3;
            $poolInfo->{PIPELINE_MODE} = $4;
            $poolInfo->{START_MODE}    = $5;
            push( @appPools, $poolInfo );
        }
    }
    $appInfo->{APPPOOLS} = \@appPools;

    #!!!下面的是标准属性，必须采集并转换提供出来
    #服务名, 要根据实际来设置
    $appInfo->{SERVER_NAME}    = $procInfo->{HOST_NAME};
    $appInfo->{INSTALL_PATH}   = "c:\\Windows\\System32\\inetsrv";
    $appInfo->{CONFIG_PATH}    = undef;
    $appInfo->{ADMIN_PORT}     = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;

    #因为IIS的监听是由System内核来完成的，所以连接信息基本没用
    $procInfo->{CONN_INFO}->{PEER}   = {};
    $procInfo->{CONN_INFO}->{LISTEN} = $lsnMap;

    return $appInfo;

    #如果返回多个应用信息，则：return ($appInfo1, $appInfo2);
}

1;
