#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package WebSphereCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
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
    my $verCmd  = qq{LANG=C "$binPath/versionInfo.sh"};
    if ( $self->{OS_TYPE} eq 'Windows' ) {
        $verCmd = qq{"$binPath/versionInfo.bat"};
    }

    my $verLines  = $self->getCmdOutLines($verCmd);
    my $lineCount = scalar(@$verLines);
    for ( my $i = 0 ; $i < $lineCount ; $i++ ) {
        my $line = $$verLines[$i];
        if ( $line !~ /^(Name|名称)\s+IBM WebSphere (Application|应用)/ ) {
            next;
        }
        if ( $$verLines[ $i + 1 ] =~ /^(Version|版本)\s+(\d.*)$/ ) {
            my $version = $2;
            $appInfo->{VERSION} = $version;
            if ( $version =~ /(\d+)/ ) {
                $appInfo->{MAJOR_VERSION} = "WebSphere$1";
            }

            last;
        }
    }

    return;
}

sub getPorts {
    my ( $self, $appInfo, $portConfPath ) = @_;

    my $portConfXml;
    if ( -e $portConfPath ) {
        my $fileSize = -s $portConfPath;
        my $fh       = IO::File->new( $portConfPath, 'r' );
        if ( defined($fh) ) {
            $fh->read( $portConfXml, $fileSize );
        }
    }
    else {
        print("WARN: Open file $portConfPath failed, $!\n");
    }

    my $serverName = $appInfo->{SERVER_NAME};
    my @ports;
    my ( $port, $sslPort, $adminPort, $adminSslPort, $soapPort, $bootstrapPort );
    if ( defined($portConfXml) ) {

        #<serverEntries xmi:id="ServerEntry_1183122129640" serverName="server1" serverType="APPLICATION_SERVER">
        if ( $portConfXml =~ /<\s*serverEntries\s.*?serverName="$serverName".*?<\/\s*serverEntries\s*>/s ) {
            my $subContent = $&;
            while ( $subContent =~ /<\s*specialEndpoints\s(.*?)<\/\s*specialEndpoints\s*>/sg ) {
                my $portDef = $&;
                if ( index( $portDef, '"WC_defaulthost"' ) > 0 ) {
                    if ( $portDef =~ /\sport="(\d+)"/ ) {
                        $port = int($1);
                        push( @ports, $port );
                    }
                }
                elsif ( index( $portDef, '"WC_defaulthost_secure"' ) > 0 ) {
                    if ( $portDef =~ /\sport="(\d+)"/ ) {
                        $sslPort = int($1);
                        push( @ports, $sslPort );
                    }
                }
                elsif ( index( $portDef, '"WC_adminhost"' ) > 0 ) {
                    if ( $portDef =~ /\sport="(\d+)"/ ) {
                        $adminPort = int($1);
                        push( @ports, $adminPort );
                    }
                }
                elsif ( index( $portDef, '"WC_adminhost_secure"' ) > 0 ) {
                    if ( $portDef =~ /\sport="(\d+)"/ ) {
                        $adminSslPort = int($1);
                        push( @ports, $adminSslPort );
                    }
                }

                #"SOAP_CONNECTOR_ADDRESS"
                elsif ( index( $portDef, '"SOAP_CONNECTOR_ADDRESS"' ) > 0 ) {
                    if ( $portDef =~ /\sport="(\d+)"/ ) {
                        $soapPort = int($1);
                        push( @ports, $soapPort );
                    }
                }
                elsif ( index( $portDef, '"BOOTSTRAP_ADDRESS"' ) > 0 ) {
                    if ( $portDef =~ /\sport="(\d+)"/ ) {
                        $bootstrapPort = int($1);
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

    my $wasType = $appInfo->{WAS_TYPE};
    if ( $wasType eq 'DMGR' ) {
        $appInfo->{PORT}     = $adminPort;
        $appInfo->{SSL_PORT} = $adminSslPort;
    }
    elsif ( $wasType eq 'NodeAgent' ) {
        $appInfo->{PORT} = $bootstrapPort;
    }

    return;
}

sub getApplications {
    my ( $appInfo, $appPkgTmpDir ) = @_;

    my @applications = ();

    if ( -d $appPkgTmpDir ) {
        my @appPkgsDirs = glob("$appPkgTmpDir/*");
        foreach my $dir (@appPkgsDirs) {
            if ( $dir !~ /_extensionregistry$/ and $dir !~ /ibmasyncrsp$/ and $dir !~ /filetransferSecured$/ ) {
                push( @applications, { NAME => basename($dir), SOURCE_PATH => dirname($dir) } );
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
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    #TODO：读取命令行输出或者读取配置文件，写入数据到hash map $appInfo
    my $wasType       = 'Server';
    my $command       = $procInfo->{COMMAND};
    my @commandFields = split( /\s+/, $command );

    if ( $commandFields[-1] eq 'dmgr' ) {
        $wasType = 'DMGR';
    }
    elsif ( $commandFields[-1] eq 'nodeagent' ) {
        $wasType = 'NodeAgent';
    }
    $appInfo->{WAS_TYPE} = $wasType;

    my $serverName = $commandFields[-1];
    my $nodeName   = $commandFields[-2];
    my $cellName   = $commandFields[-3];
    my $confRoot   = $commandFields[-4];

    if ( $confRoot =~ /"$/ ) {
        $confRoot = substr( $confRoot, 0, -1 );
        if ( $command =~ /"([^"]*?\Q$confRoot\E)"/ ) {
            $confRoot = $1;
        }
    }

    $appInfo->{SERVER_NAME} = $serverName;

    #$appInfo->{CONFIG_ROOT} = $envMap->{CONFIG_ROOT};
    #$appInfo->{WAS_CELL} = $envMap->{WAS_HOME};
    #$appInfo->{WAS_NODE} = $envMap->{WAS_NODE};
    $appInfo->{CONFIG_ROOT} = $confRoot;
    $appInfo->{WAS_CELL}    = $cellName;
    $appInfo->{WAS_NODE}    = $nodeName;

    my $envMap = $procInfo->{ENVIRONMENT};
    $appInfo->{OSGI_INSTALL}                  = $envMap->{OSGI_INSTALL};
    $appInfo->{CLIENT_CONNECTOR_INSTALL_ROOT} = $envMap->{CLIENT_CONNECTOR_INSTALL_ROOT};
    $appInfo->{USER_INSTALL_ROOT}             = $envMap->{USER_INSTALL_ROOT};
    $appInfo->{WAS_HOME}                      = $envMap->{WAS_HOME};

    my $serverRoot;

    #-Dwas.install.root=/opt/IBM/WebSphere/AppServer
    my $installPath;
    if ( $command =~ /-Dwas\.install\.root=(.*?)(?="?\s+"?-D)/ ) {
        $installPath = $1;
        $appInfo->{INSTALL_ROOT} = $installPath;
    }

    #-Dserver.root=/opt/IBM/WebSphere/AppServer/profiles/Dmgr01
    if ( $command =~ /-Dserver\.root=(.*?)(?="?\s+"?-D)/ ) {
        $appInfo->{SERVER_ROOT} = $1;
        $serverRoot = $1;
    }

    $self->getJavaAttrs($appInfo);

    $self->getVersion( $appInfo, $installPath );

    my $portConfPath = File::Spec->canonpath("$confRoot/cells/$cellName/nodes/$nodeName/serverindex.xml");
    $self->getPorts( $appInfo, $portConfPath );

    my $appPkgTmpDir = File::Spec->canonpath("$serverRoot/temp/$nodeName/$serverName");
    $self->getApplications( $appInfo, $appPkgTmpDir );

    if ( defined( $appInfo->{WAS_HOME} ) ) {
        $appInfo->{INSTALL_PATH} = $appInfo->{WAS_HOME};
    }
    else {
        my $wasHome = Cwd::abs_path( $appInfo->{CONFIG_ROOT} . '/../../../..' );
        $appInfo->{WAS_HOME}     = $wasHome;
        $appInfo->{INSTALL_PATH} = $wasHome;
    }

    $appInfo->{CONFIG_PATH} = $appInfo->{CONFIG_ROOT};
    return $appInfo;
}

1;
