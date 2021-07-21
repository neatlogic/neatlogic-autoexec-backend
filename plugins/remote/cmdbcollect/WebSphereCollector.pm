#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package WebSphereCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjType;

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        seq      => 80,
        regExps  => ['\bcom.ibm.ws.runtime.WsServer\b'],    #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },                     #ps的属性的精确匹配
        envAttrs => {}                                      #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

sub getVersion {
    my ( $self, $appInfo, $installPath ) = @_;

    # [root@dev-env-140 ~]# LANG=en_US.UTF-8 /opt/IBM/WebSphere/AppServer/bin/versionInfo.sh
    # WVER0010I: Copyright (c) IBM Corporation 2002, 2012; All rights reserved.
    # WVER0012I: VersionInfo reporter version 1.15.1.49, dated 4/7/17
    # 此处省略。。。。
    # Installed Product
    # --------------------------------------------------------------------------------
    # Name                  IBM WebSphere Application Server Network Deployment
    # Version               8.5.5.13
    # 此处省略。。。。
    # Installed Product
    # --------------------------------------------------------------------------------
    # Name                  IBM WebSphere SDK Java Technology Edition (Optional)
    # Version               8.0.5.6
    my $binPath = "$installPath/bin";
    my $verCmd  = "LANG=en_US.UTF-8 $binPath/versionInfo.sh";
    if ( $self->{OS_TYPE} eq 'Windows' ) {
        $verCmd = "$binPath/versionInfo.bat";
    }

    my $verLines = $self->getCmdOutLines($verCmd);
    my $idx      = 0;
    while ( $$verLines[$idx] !~ /^Name\s+IBM WebSphere Application Server/ ) {
        $idx = $idx + 1;
    }
    $idx = $idx + 1;
    if ( $$verLines[$idx] =~ /^(Version|版本)\s+(.*)$/ ) {
        $appInfo->{VERSION} = $2;
    }
    while ( $$verLines[$idx] !~ /^Name\s+IBM WebSphere SDK Java Technology Edition/ ) {
        $idx = $idx + 1;
    }
    $idx = $idx + 1;
    if ( $$verLines[$idx] =~ /^(Version|版本)\s+(.*)$/ ) {
        $appInfo->{JAVA_VERSION} = $2;
    }

    return;
}

sub getPorts {
    my ( $self, $appInfo, $portConfPath ) = @_;

    my $portConfXml;
    if ( -e $portConfPath ) {
        my $fileSize = -s $portConfPath;
        my $fh = IO::File->new( $portConfPath, 'r' );
        if ( defined($fh) ) {
            $fh->read( $portConfXml, $fileSize );
        }
    }

    my $serverName = $appInfo->{SERVER_NAME};
    my @ports;
    my ( $port, $sslPort, $adminPort, $adminSslPort, $soapPort );
    if ( defined($portConfXml) ) {

        #<serverEntries xmi:id="ServerEntry_1183122129640" serverName="server1" serverType="APPLICATION_SERVER">
        if ( $portConfXml =~ /<\s*serverEntries\s.*?serverName="$serverName".*?<\/\s*serverEntries\s*>/s ) {
            my $subContent = $&;
            while ( $subContent =~ /<\s*specialEndpoints\s(.*?)<\/\s*specialEndpoints\s*>/sg ) {
                my $portDef = $&;
                if ( index( $portDef, '"WC_defaulthost"' ) > 0 ) {
                    if ( $portDef =~ /\sport="(\d+)"/ ) {
                        $port = $1;
                        push( @ports, $port );
                    }
                }
                elsif ( index( $portDef, '"WC_defaulthost_secure"' ) > 0 ) {
                    if ( $portDef =~ /\sport="(\d+)"/ ) {
                        $sslPort = $1;
                        push( @ports, $sslPort );
                    }
                }
                elsif ( index( $portDef, '"WC_adminhost"' ) > 0 ) {
                    if ( $portDef =~ /\sport="(\d+)"/ ) {
                        $adminPort = $1;
                        push( @ports, $adminPort );
                    }
                }
                elsif ( index( $portDef, '"WC_adminhost_secure"' ) > 0 ) {
                    if ( $portDef =~ /\sport="(\d+)"/ ) {
                        $adminSslPort = $1;
                        push( @ports, $adminSslPort );
                    }
                }

                #"SOAP_CONNECTOR_ADDRESS"
                elsif ( index( $portDef, '"SOAP_CONNECTOR_ADDRESS"' ) > 0 ) {
                    if ( $portDef =~ /\sport="(\d+)"/ ) {
                        $soapPort = $1;
                        push( @ports, $soapPort );
                    }
                }
            }
        }
    }

    $appInfo->{PORT}           = $port;
    $appInfo->{SSL_PORT}       = $sslPort;
    $appInfo->{ADMIN_PORT}     = $adminPort;
    $appInfo->{ADMIN_SSL_PORT} = $adminSslPort;
    $appInfo->{SOAP_PORT}      = $soapPort;
    $appInfo->{MON_PORT}       = $soapPort;
    $appInfo->{PORTS}          = \@ports;

    return;
}

sub getApplications {
    my ( $appInfo, $appPkgTmpDir ) = @_;

    my @applications = ();

    if ( -d $appPkgTmpDir ) {
        my @appPkgsDirs = glob("$appPkgTmpDir/*");
        foreach my $dir (@appPkgsDirs) {
            if ( $dir !~ /_extensionregistry$/ and $dir !~ /ibmasyncrsp$/ and $dir !~ /filetransferSecured$/ ) {
                push( @applications, basename($dir) );
            }
        }
    }
    $appInfo->{APPLICATIONS} = \@applications;
}

#可用参数：
#$self->{procInfo}， 根据config命中的进程信息
#$self->{matchedProcsInfo}，之前已经matched的进程信息
#Return：应用信息的Hash，undef:不匹配
sub collect {
    my ($self) = @_;
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};
    $self->{OS_TYPE} = $procInfo->{OS_TYPE};

    my $appInfo = {};
    $appInfo->{OBJECT_TYPE} = $CollectObjType::APP;

    #TODO：读取命令行输出或者读取配置文件，写入数据到hash map $appInfo
    my $appType       = $procInfo->{APP_TYPE};
    my $command       = $procInfo->{COMMAND};
    my @commandFields = split( /\s+/, $command );

    if ( $commandFields[-1] eq 'dmgr' ) {
        $appType = 'WebSphere-DMGR';
    }
    elsif ( $commandFields[-1] eq 'nodeagent' ) {
        $appType = 'WebSphere-NodeAgent';
    }

    my $serverName = $commandFields[-1];
    my $nodeName   = $commandFields[-2];
    my $cellName   = $commandFields[-3];
    my $confRoot   = $commandFields[-4];

    $appInfo->{SERVER_NAME} = $serverName;

    #$appInfo->{CONFIG_ROOT} = $envMap->{CONFIG_ROOT};
    #$appInfo->{WAS_CELL} = $envMap->{WAS_HOME};
    #$appInfo->{WAS_NODE} = $envMap->{WAS_NODE};
    $appInfo->{CONFIG_ROOT} = $confRoot;
    $appInfo->{WAS_CELL}    = $cellName;
    $appInfo->{WAS_NODE}    = $nodeName;

    my $envMap = $procInfo->{ENVRIONMENT};
    $appInfo->{JAVA_HOME}                     = $envMap->{JAVA_HOME};
    $appInfo->{OSGI_INSTALL}                  = $envMap->{OSGI_INSTALL};
    $appInfo->{CLIENT_CONNECTOR_INSTALL_ROOT} = $envMap->{CLIENT_CONNECTOR_INSTALL_ROOT};
    $appInfo->{USER_INSTALL_ROOT}             = $envMap->{USER_INSTALL_ROOT};
    $appInfo->{WAS_HOME}                      = $envMap->{WAS_HOME};

    my $serverRoot;

    #-Dwas.install.root=/opt/IBM/WebSphere/AppServer
    my $installPath;
    if ( $command =~ /-Dwas\.install\.root=(.*?)(?=\s-D)/ ) {
        $installPath = $1;
        $appInfo->{INSTALL_ROOT} = $installPath;
    }

    #-Dserver.root=/opt/IBM/WebSphere/AppServer/profiles/Dmgr01
    if ( $command =~ /-Dserver\.root=(.*?)(?=\s-D)/ ) {
        $appInfo->{SERVER_ROOT} = $1;
        $serverRoot = $1;
    }

    #获取-X的java扩展参数
    my ( $minHeapSize, $maxHeapSize );
    my @cmdOpts = split( /\s+/, $procInfo->{COMMAND} );
    foreach my $cmdOpt (@cmdOpts) {
        if ( $cmdOpt =~ /^-Xmx(\d+.*?)\b/ ) {
            $maxHeapSize = $1;
        }
        elsif ( $cmdOpt =~ /^-Xms(\d+.*?)\b/ ) {
            $minHeapSize = $1;
        }
    }
    $appInfo->{MIN_HEAP_SIZE} = $utils->getMemSizeFromStr($minHeapSize);
    $appInfo->{MAX_HEAP_SIZE} = $utils->getMemSizeFromStr($maxHeapSize);

    $self->getVersion( $appInfo, $installPath );

    my $portConfPath = File::Spec->canonpath("$confRoot/cells/$cellName/nodes/$nodeName/serverindex.xml");
    $self->getPorts( $appInfo, $portConfPath );

    my $appPkgTmpDir = File::Spec->canonpath("$serverRoot/temp/$nodeName/$serverName");
    $self->getApplications( $appInfo, $appPkgTmpDir );

    $appInfo->{APP_TYPE}     = $appType;
    $appInfo->{INSTALL_PATH} = $appInfo->{WAS_HOME};
    $appInfo->{CONFIG_PATH}  = $appInfo->{CONFIG_ROOT};
    return $appInfo;
}

1;
