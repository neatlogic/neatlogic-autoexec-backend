#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package WeblogicCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use POSIX qw(uname);
use File::Spec;
use File::Basename;
use IO::File;
use Data::Dumper;
use XML::MyXML qw(xml_to_object);
use CollectObjType;

#配置进程的filter
sub getConfig {
    return {
        regExps  => ['\sweblogic.Server$'],    #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },        #ps的属性的精确匹配
        envAttrs => { WL_HOME => undef }       #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

sub getConfigInfo {
    my ( $self, $appInfo, $domainHome, $serverName, $confFile ) = @_;

    my $confObj = xml_to_object( $confFile, { file => 1 } );
    my $domainVersion = $confObj->path('domain-version')->value();
    $appInfo->{VERSION} = $domainVersion;

    #获取端口信息，其实也可以从CONN_INFO的LISTEN属性里获取
    # <server>
    #    <name>server1</name>
    #    <listen-port>7003</listen-port>
    #    <cluster>cluster1</cluster>
    #    <web-server>
    #      <web-server-log>
    #        <number-of-files-limited>false</number-of-files-limited>
    #      </web-server-log>
    #    </web-server>
    #    <listen-address>192.168.1.140</listen-address>
    #    <jta-migratable-target>
    #      <user-preferred-server>server1</user-preferred-server>
    #      <cluster>cluster1</cluster>
    #    </jta-migratable-target>
    #  </server>
    my $port    = '7001';
    my $cluster = '';
    my @servers = $confObj->path('server');
    foreach my $srv (@servers) {
        my $name = $srv->path('name')->value();
        if ( $name eq $serverName ) {
            my $item = $srv->path('listen-port');
            if ( defined($item) ) {
                $port = $item->value();
            }
            $item = $srv->path('cluster');
            if ( defined($item) ) {
                $cluster = $item->value();
            }
        }
    }
    $appInfo->{PORT}           = $port;
    $appInfo->{SSL_PORT}       = $port;
    $appInfo->{ADMIN_PORT}     = $port;
    $appInfo->{ADMIN_SSL_PORT} = $port;
    $appInfo->{MON_PORT}       = $port;
    $appInfo->{SERVER_CLUSTER} = $cluster;

    #获取部署应用信息
    #  <app-deployment>
    #    <name>EmpManager</name>
    #    <target>AdminServer</target>
    #    <module-type>war</module-type>
    #    <source-path>servers/AdminServer/upload/EmpManager.war</source-path>
    #    <security-dd-model>DDOnly</security-dd-model>
    #    <staging-mode>nostage</staging-mode>
    #    <plan-staging-mode xsi:nil="true"></plan-staging-mode>
    #    <cache-in-app-directory>false</cache-in-app-directory>
    #  </app-deployment>
    my @applications;
    my @appDeployments = $confObj->path('app-deployment');
    foreach my $appDeploy (@appDeployments) {
        my $name   = $appDeploy->path('name')->value();
        my $target = $appDeploy->path('target')->value();
        if ( $target =~ /\b$serverName\b/ or ( $cluster ne '' and $target =~ /\b$cluster\b/ ) ) {
            my $app = {};
            $app->{NAME}   = $name;
            $app->{TARGET} = $target;
            my $item;
            $item = $appDeploy->path('module-type');
            if ( defined($item) ) {
                $app->{MODULE_TYPE} = $item->value();
            }
            $item = $appDeploy->path('source-path');
            if ( defined($item) ) {
                my $srcPath = $item->value();
                if ( $srcPath =~ /^servers/ ) {
                    $srcPath = File::Spec->canonpath("$domainHome/$srcPath");
                }
                $app->{SOURCE_PATH} = $srcPath;
            }
            $item = $appDeploy->path('staging-mode');
            if ( defined($item) ) {
                my $stagingMode = $item->value();
                if ( $stagingMode eq '' ) {
                    $stagingMode = 'staging';
                }
                $app->{STAGING_MODE} = $stagingMode;
            }
            push( @applications, $app );
        }
    }
    $appInfo->{APPLICATIONS} = \@applications;
}

sub getPatchInfo {
    my ( $self, $appInfo, $installPath, $wlHome ) = @_;

    my $procInfo = $self->{procInfo};

    my @patches;
    my $osUser     = $procInfo->{USER};
    my $oPatchPath = "$installPath/OPatch/opatch";
    if ( -f $oPatchPath ) {
        my $cmdPath = File::Spec->canonpath($oPatchPath);
        my $patchInfo = $self->getCmdOut( qq{"$cmdPath" lsinventory}, $osUser );
        while ( $patchInfo =~ /Patch\s+(\d+)\s+:/g ) {
            push( @patches, { VALUE => $1 } );
        }
    }
    else {
        my $bsuPath   = "$installPath/utils/bsu/bsu.sh";
        my $cmdPath   = File::Spec->canonpath($bsuPath);
        my $patchInfo = $self->getCmdOut( qq{"$cmdPath" -prod_dir=$wlHome -status=applied -verbose -view}, $osUser );
        while ( $patchInfo =~ /Patch\s+ID:\s+(\w+)\s+/g ) {
            push( @patches, { VALUE => $1 } );
        }
    }
    $appInfo->{WL_PATCHES} = join( ',', @patches );

    return \@patches;
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

    my $appInfo = {};
    $appInfo->{OBJECT_TYPE} = CollectObjType->get('INS');

    my $envMap     = $procInfo->{ENVRIONMENT};
    my $domainHome = $envMap->{DOMAIN_HOME};
    my $confFile   = "$domainHome/config/config.xml";
    if ( not -f $confFile ) {

        #没有此配置文件，不是weblogic
        print("WARN: Weblogic config file $confFile not found.\n");
        return undef;
    }

    my $serverName  = $envMap->{SERVER_NAME};
    my $wlHome      = $envMap->{WL_HOME};
    my $installPath = dirname($wlHome);
    my $javaHome    = $envMap->{JAVA_HOME};

    $appInfo->{WL_HOME}      = $wlHome;
    $appInfo->{DOMAIN_HOME}  = $domainHome;
    $appInfo->{SERVER_NAME}  = $serverName;
    $appInfo->{DOMAIN_NAME}  = basename($domainHome);
    $appInfo->{INSTALL_PATH} = $installPath;

    $self->getJavaAttrs($appInfo);

    $self->getConfigInfo( $appInfo, $domainHome, $serverName, $confFile );
    $self->getPatchInfo( $appInfo, $installPath, $wlHome );

    #！！！下面的是标准属性，必须采集并转换提供出来
    $appInfo->{APP_TYPE}    = $procInfo->{APP_TYPE};
    $appInfo->{CONFIG_PATH} = $domainHome;

    return $appInfo;
}

1;
