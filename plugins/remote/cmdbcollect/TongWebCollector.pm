#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package TongWebCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use XML::MyXML qw(xml_to_object);
use CollectObjCat;

sub getConfig {
    return {
        seq      => 80,
        regExps  => ['\bcom.tongweb.web.thor.startup.ThorBootstrap\sstart$'],
        psAttrs  => { COMM => 'java' },
        envAttrs => {}
    };
}

sub getConfigInfo {
    my ( $self, $appInfo ) = @_;

    my $confPath = $appInfo->{TONGWEB_BASE};
    my $confFile = "$confPath/conf/tongweb.xml";

    my $confObj = xml_to_object( $confFile, { file => 1 } );

    #找出配置的监听
    my @httpListeners;
    my $httpListenerMap  = {};
    my @httpListenersObj = $confObj->path('server/web-container/http-listener');
    foreach my $httpListener (@httpListenersObj) {
        my $name       = $httpListener->attr('name');
        my $port       = $httpListener->attr('port');
        my $status     = $httpListener->attr('status');
        my $sslEnabled = $httpListener->attr('ssl-enabled');

        my $lsn = {
            NAME        => $name,
            PORT        => int($port),
            STATUS      => $status,
            SSL_ENABLED => $sslEnabled
        };
        $httpListenerMap->{$name} = $lsn;

        push( @httpListeners, $lsn );

    }
    $appInfo->{LISTENERS} = \@httpListeners;

    #找出Web Virutal Hosts，里面的listeners可能是多个，后续估计要处理
    my @virtualHosts;
    my @servers = $confObj->path('server/web-container/virtual-host');
    foreach my $srv (@servers) {
        my $virtualHost = {};
        my $name        = $srv->attr('name');
        my $listeners   = $srv->attr('listeners');

        if ( $name eq 'admin' ) {
            foreach my $listener ( split( /\s*,\s*/, $listeners ) ) {
                my $httpListener = $httpListenerMap->{$listener};
                if ( $httpListener->{status} eq 'started' ) {
                    $appInfo->{ADMIN_PORT} = $httpListener->{port};
                }
                delete( $httpListenerMap->{$listener} );
            }
        }

        $virtualHost->{NAME}      = $name;
        $virtualHost->{LISTENERS} = $listeners;
        push( @virtualHosts, $virtualHost );

    }
    $appInfo->{VIRTUAL_HOSTS} = \@virtualHosts;

    #找出标记当前进程标记监听的端口
    my $servicePorts = $appInfo->{SERVICE_PORTS};
    if ( not defined($servicePorts) ) {
        $servicePorts = {};
        $appInfo->{SERVICE_PORTS} = $servicePorts;
    }
    while ( my ( $key, $httpListener ) = each(%$httpListenerMap) ) {
        if ( $httpListener->{STATUS} eq 'started' ) {
            if ( $httpListener->{SSL_ENABLED} eq 'false' ) {
                $appInfo->{PORT}      = $httpListener->{PORT};
                $servicePorts->{http} = $httpListener->{PORT};
            }
            else {
                $appInfo->{SSL_PORT}   = $httpListener->{PORT};
                $servicePorts->{https} = $httpListener->{PORT};
            }
            last;
        }
    }

#获取部署应用信息
#<web-app id="console" name="console" original-location="${tongweb.upload}/console" location="${tongweb.sysapp}/console" context-root="/console" vs-names="admin" is-directory="true" enabled="true" description="console" deploy-order="1" object-type="sys" jsp-compile="false" request-parameters-lost-validation="false" dtd-validate="false" is-autodeploy="false" delegate="false"/>
#                        <web-app id="neatlogic" name="neatlogic" original-location="${tongweb.upload}/neatlogic.war" location="${tongweb.app}/neatlogic" context-root="/neatlogic" vs-names="server" session-manager="" is-directory="false" enabled="true" description="neatlogic" deploy-order="100" object-type="user" jsp-compile="false" request-parameters-lost-validation="false" dtd-validate="false" is-autodeploy="false" version="" retire-state="none" retire-strategy="nature" retire-timeout="0" version-serial-number="1" delegate="false" cache-max-size="10240" app-secret-level="1" increment-update="false" deploy-timeout="600"/>
    my @applications;
    my @appDeployments = $confObj->path('apps/web-app');
    foreach my $appDeploy (@appDeployments) {
        my $name     = $appDeploy->attr('name');
        my $vsName   = $appDeploy->attr('vs-names');
        my $location = $appDeploy->attr('original-location');

        my $app = {
            NAME              => $name,
            VIRTUAL_HOST_NAME => $vsName,
            ORIGIN_LOCATION   => $location
        };

        push( @applications, $app );
    }
    $appInfo->{APPLICATIONS} = \@applications;

    return;
}

sub getPatchInfo {
    my ( $self, $appInfo ) = @_;

    my $procInfo    = $self->{procInfo};
    my $tongwebHome = $appInfo->{TONGWEB_HOME};

    my @patches;
    my $osUser    = $procInfo->{USER};
    my $PatchPath = "$tongwebHome/tools";
    if ( -d $PatchPath ) {

        my @patchFiles = glob("$PatchPath/patch*.zip");
        if ( scalar(@patchFiles) != 0 ) {
            foreach (@patchFiles) {
                my $patchName = basename($_);
                $patchName =~ s/\.zip$//;
                push( @patches, { VALUE => $patchName } );

            }
        }
    }
    $appInfo->{PATCHES} = \@patches;

    return;
}

sub getVerInfo {
    my ( $self, $appInfo ) = @_;

    # 服务器：TongWeb 7.0.4.8，构建于：2022-12-22 11:33:59
    # -----------------------------------------
    # -----------License 信息-------------------
    # consumer_name=东莞银行股份有限公司
    # project_name=东莞银行股份有限公司-中间件采购项目
    # order_number= 2021-1392
    # license_type=release
    # create_date=2021-11-19
    # end_date=-1
    # TW_Product_Name=TongWeb
    # TW_Version_Number=7.0
    # TW_Edition=Enterprise
    # TW_CPU_COUNT=10
    # bindip=
    # BindMac=

    # -----------License 信息-------------------
    # -----------------------------------------
    my $procInfo = $self->{procInfo};
    my $javaHome = $appInfo->{JAVA_HOME};
    my $confPath = $appInfo->{CONFIG_PATH};

    my $binPath = "$confPath/bin";
    my $verCmd  = qq{JAVA_HOME="$javaHome" sh "$binPath/version.sh"};
    if ( $procInfo->{OS_TYPE} eq 'Windows' ) {
        $ENV{JAVA_HOME} = $javaHome;
        $verCmd = qq{cmd /c "$binPath/version.bat"};
    }
    my $verOut = $self->getCmdOutLines($verCmd);
    foreach my $line (@$verOut) {
        if ( $line =~ /TW_Version_Number=\s*(.*?)\s*$/ ) {
            my $version = $1;
            $appInfo->{VERSION} = $version;
            if ( $version =~ /(\d+)/ ) {
                $appInfo->{MAJOR_VERSION} = "TongWeb$1";
            }
        }
        elsif ( $line =~ /order_number=\s*(.*?)\s*$/ ) {
            my $orderNumber = $1;
            $appInfo->{ORDER_NUMBER} = $orderNumber;
        }
        elsif ( $line =~ /license_type=\s*(.*?)\s*$/ ) {
            my $license_type = $1;
            $appInfo->{LICENSE_TYPE} = $license_type;
        }
        elsif ( $line =~ /create_date=\s*(.*?)\s*$/ ) {
            my $create_date = $1;
            $appInfo->{CREATE_DATE} = $create_date;
        }
        elsif ( $line =~ /end_date=\s*(.*?)\s*$/ ) {
            my $licenseEndDate = $1;
            $appInfo->{LICENSE_END_DATE} = $licenseEndDate;
        }
        elsif ( $line =~ /TW_CPU_COUNT=\s*(.*?)\s*$/ ) {
            my $twCpuCount = int($1);
            $appInfo->{TW_CPU_COUNT} = $twCpuCount;
        }
        elsif ( $line =~ /TW_CPU_COUNT=\s*(.*?)\s*$/ ) {
            my $edition = $1;
            $appInfo->{TW_EDITION} = $edition;
        }
        elsif ( $line =~ /bindip=\s*(.*?)\s*$/ ) {
            my $bindip = $1;
            $appInfo->{BINDIP} = $bindip;
        }
        elsif ( $line =~ /BindMac=\s*(.*?)\s*$/ ) {
            my $bindmac = $1;
            $appInfo->{BINDMAC} = $bindmac;
        }
    }

    return;
}

sub collect {
    my ($self) = @_;
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo = $self->{procInfo};
    my $cmdLine  = $procInfo->{COMMAND};
    my $appInfo  = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $installPath;
    if ( $cmdLine =~ /-Dtongweb.home=(\S+)\s+/ ) {
        $installPath = $1;
        $installPath =~ s/^["']|["']$//g;
        $appInfo->{TONGWEB_HOME} = $installPath;
        $appInfo->{INSTALL_PATH} = $installPath;
    }
    else {
        print("WARN: Can not fand tongweb.base in command:$cmdLine, failed.\n");
        return;
    }

    if ( $cmdLine =~ /-Dtongweb.base=(\S+)/ ) {
        my $confPath = $1;
        $confPath =~ s/^["']|["']$//g;
        $appInfo->{TONGWEB_BASE} = $confPath;
        $appInfo->{CONFIG_PATH}  = $confPath;
        $appInfo->{SERVER_NAME}  = basename($confPath);
    }
    else {
        print("WARN: Can not fand tongweb.base in command:$cmdLine, failed.\n");
        return;
    }

    $self->getJavaAttrs($appInfo);
    $self->getVerInfo($appInfo);
    $self->getConfigInfo($appInfo);
    $self->getPatchInfo($appInfo);

    return $appInfo;
}

1;
