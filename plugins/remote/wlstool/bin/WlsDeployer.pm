#!/usr/bin/perl
package WlsDeployer;
use strict;
use Data::Dumper;
use XML::MyXML qw(:all);
use IO::Socket::INET;
use File::Path;
use Cwd;

sub new {
    my ( $type, $configName, $insName ) = @_;
    my $self = {};

    my $homePath = $FindBin::Bin;
    $homePath = Cwd::fast_abs_path("$homePath/..");
    $self->{homePath} = $homePath;

    #$ENV{LANG} = 'utf-8';

    my $insPrefix = $insName;
    $insPrefix =~ s/\d*$//;

    my $sectionConfig;
    my $config;
    if ( -f "$homePath/conf/wlstool.ini" ) {
        $config = CommonConfig->new( "$homePath/conf", "wlstool.ini" );
    }
    else {
        $config = CommonConfig->new( "$homePath/conf", "wls.ini" );
    }

    $sectionConfig = $config->getConfig("$configName.$insName");
    if ( not defined($sectionConfig) ) {
        $sectionConfig = $config->getConfig("$configName.$insPrefix");
    }
    if ( not defined($sectionConfig) ) {
        $sectionConfig = $config->getConfig("$configName");
    }

    $self->{config} = $sectionConfig;

    my $lang  = $sectionConfig->{"lang"};
    my $lcAll = $sectionConfig->{"lc_all"};
    $ENV{LANG}   = $lang  if ( defined($lang)  and $lang ne '' );
    $ENV{LC_ALL} = $lcAll if ( defined($lcAll) and $lcAll ne '' );

    my $umask = $sectionConfig->{"umask"};
    if ( defined($umask) and $umask ne '' ) {
        umask($umask);
    }

    my $javaHome   = $sectionConfig->{'java_home'};
    my $wlsHome    = $sectionConfig->{'wls_home'};
    my $domainHome = $sectionConfig->{'domain_home'};

    my $hasError = 0;

    if ( not -e $javaHome ) {
        print("WARN: Java Home directory:$javaHome is not exists, check the config argument:java_home\n");
    }
    elsif ( not -e "$javaHome/bin/java" ) {
        print("WARN: Java binary file bin/java not found in java home directory:$javaHome, check the config argument:java_home\n");
    }

    if ( not -e $wlsHome ) {
        $hasError = 1;
        print("ERROR: Weblogic Home directory:$wlsHome is not exists, check the config argument:wls_home\n");
    }
    else {
        my $jarPath;
        if ( -d "$wlsHome/wlserver" ) {
            $jarPath = "\"$wlsHome/wlserver/server/lib/weblogic.jar\"";
        }
        elsif ( -d "$wlsHome/server/lib" ) {
            $jarPath = "\"$wlsHome/server/lib/weblogic.jar\"";
        }
        else {
            my @jarPaths = glob("$wlsHome/*wlserver*/server/lib/weblogic.jar");
            if ( scalar(@jarPaths) > 0 ) {
                $jarPath = '"' . $jarPaths[0] . '"';
            }
        }

        if ( $jarPath eq '' ) {
            $hasError = 1;
            print("ERROR: Can not find weblogic.jar in weblogic Home directory:$wlsHome, it is not a weblogic installation directory, check the config argument:wls_home\n");
        }
    }

    if ( not -e $domainHome ) {
        $hasError = 1;
        print("ERROR: Weblogic domain Directory $domainHome is not exists, check config argument:domain_home\n");
    }
    elsif ( not -f "$domainHome/config/config.xml" ) {
        $hasError = 1;
        print("ERROR: Directory $domainHome is not a weblogic domain directory($domainHome/config/config.xml not found), check config argument:domain_home\n");
    }

    if ( $hasError == 1 ) {
        exit(-1);
    }

    return bless( $self, $type );
}

sub getConf {
    my ($self) = @_;
    return $self->{config};
}

sub getHomePath {
    my ($self) = @_;
    return $self->{homePath};
}

sub getAdminServerName {
    my ($self) = @_;

    my $domainHome = $self->{config}->{'domain_home'};
    my $configPath = "$domainHome/config/config.xml";

    my $obj = xml_to_object( $configPath, { file => 1 } );
    my $adminServerName = $obj->path('admin-server-name')->value();

    return $adminServerName;
}

sub getAppsConfig {
    my ($self) = @_;

    my $domainHome = $self->{config}->{'domain_home'};
    my $configPath = "$domainHome/config/config.xml";

    my $obj = xml_to_object( $configPath, { file => 1 } );

    my $appsMap = {};
    my @apps    = $obj->path('app-deployment');
    foreach my $app (@apps) {
        my $appMap        = {};
        my $appName       = $app->path('name')->value();
        my $appSourcePath = $app->path('source-path')->value();
        $appSourcePath =~ s/\\/\//g;
        if ( $appSourcePath !~ /^[\/\\]/ ) {
            $appSourcePath = "$domainHome/$appSourcePath";
        }

        $appMap->{'sourcePath'} = $appSourcePath;
        my $stage = $app->path('staging-mode')->value();
        if ( not defined($stage) or $stage eq '' ) {
            $stage = 'stage';
        }
        $appMap->{'stagingMode'} = $stage;
        my $targetStr = $app->path('target')->value();
        my @targets = split( ',', $targetStr );
        $appMap->{'target'} = \@targets;

        $appsMap->{$appName} = $appMap;
    }

    return $appsMap;
}

sub isAdminServer {
    my ( $self, $serverName ) = @_;

    my $domainHome = $self->{config}->{'domain_home'};
    my $adminUrl   = $self->{config}->{'admin_url'};

    my $isAdmin = 0;

    if ( not defined($serverName) or ( $serverName eq $self->getAdminServerName() ) ) {
        my ( $adminAddr, $adminPort );
        if ( $adminUrl =~ /^\w+:\/\/([^:]+):(\d+)/ ) {
            $adminAddr = $1;
            $adminPort = $2;
        }

        if ( $adminAddr !~ /^\d+\.\d+\.\d+\.\d+$/ and $adminUrl !~ /^[\w:]+$/ ) {
            $adminAddr = gethostbyname($adminAddr);
        }

        my $socket = IO::Socket::INET->new(
            Proto    => 'udp',
            PeerAddr => $adminAddr,
            PeerPort => 53
        );
        my $localIp = $socket->sockhost;

        $isAdmin = 1 if ( $localIp eq $adminAddr );
    }

    return $isAdmin;
}

sub isAppExists {
    my ( $self, $appName ) = @_;

    my $domainHome = $self->{config}->{'domain_home'};
    my $isExists   = 0;

    my $configPath     = "$domainHome/config/config.xml";
    my $obj            = xml_to_object( $configPath, { file => 1 } );
    my @appDeployments = $obj->path('app-deployment');

    foreach my $appDeployment (@appDeployments) {
        my $appHash = $appDeployment->simplify();
        my $aApp    = $appHash->{'app-deployment'};
        my $name    = $aApp->{'name'};

        if ( $name eq $appName ) {
            $isExists = 1;
            last;
        }
    }

    return $isExists;
}

sub removeAppStage {
    my ( $self, $serverName, $appName ) = @_;

    my $domainHome   = $self->{config}->{'domain_home'};
    my $appStagePath = "$domainHome/servers/$serverName/stage/$appName";

    my $removed = 1;
    if ( -e $appStagePath ) {
        rmtree($appStagePath);
    }

    $removed = 0 if ( -e $appStagePath );
    return $removed;
}

sub removeAppTmp {
    my ( $self, $serverName, $appName ) = @_;
    my $domainHome = $self->{config}->{'domain_home'};
    my $appTmpPath = "$domainHome/servers/$serverName/tmp/_WL_user/$appName";

    my $removed = 1;
    if ( -e $appTmpPath ) {
        rmtree($appTmpPath);
    }

    $removed = 0 if ( -e $appTmpPath );
    return $removed;
}

sub removeAdminTmp {
    my ( $self, $serverName, $appName ) = @_;
    my $domainHome   = $self->{config}->{'domain_home'};
    my $adminTmpPath = "$domainHome/servers/$serverName/tmp";

    my $removed = 1;
    if ( -e $adminTmpPath ) {
        for my $dir ( glob("$adminTmpPath/.appmergegen*") ) {
            if ( not rmtree($dir) ) {
                $removed = 0;
            }
        }
    }

    return $removed;
}

sub appDeployDispatch {
    my ( $self, $appName, $action ) = @_;

    my $javaHome    = $self->{config}->{'java_home'};
    my $wlsHome     = $self->{config}->{'wls_home'};
    my $domainHome  = $self->{config}->{'domain_home'};
    my $adminUrl    = $self->{config}->{'admin_url'};
    my $sourcePath  = $self->{config}->{"$appName.source-path"};
    my $stagingMode = $self->{config}->{"$appName.staging-mode"};
    my $targets     = $self->{config}->{"$appName.target"};
    my $user        = $self->{config}->{'wls_user'};
    my $password    = $self->{config}->{'wls_pwd'};

    $ENV{DOMAIN_HOME} = $domainHome;

    $adminUrl =~ s/^http/t3/;

    my $javaCmd = "java";
    $javaCmd = "$javaHome/bin/java" if ( defined($javaHome) and $javaHome ne '' );
    my $cmd;
    ####################################################
    #修改目的：不同版本的wlserver目录名称可能不一致，当目录不匹配时自动找目录
    ####################################################
    my $classPath;
    if ( -d "$wlsHome/wlserver" ) {
        $classPath = "\"$wlsHome/wlserver/server/lib/weblogic.jar\"";
    }
    elsif ( -d "$wlsHome/server/lib" ) {
        $classPath = "\"$wlsHome/server/lib/weblogic.jar\"";
    }
    else {
        my @jarPaths = glob("$wlsHome/*wlserver*/server/lib/weblogic.jar");
        if ( scalar(@jarPaths) > 0 ) {
            $classPath = '"' . $jarPaths[0] . '"';
        }
    }

    if ( $classPath eq '' ) {
        print("ERROR: Can not find weblogic.jar\n");
    }

    $cmd = "$javaCmd -Xmx1204m -Dweblogic.security.SSL.ignoreHostnameVerification=false -cp $classPath weblogic.Deployer -$action ";

    if ( defined($user) and $user ne '' ) {
        $cmd = $cmd . "-user $user ";
    }
    if ( defined($password) and $password ne '' ) {
        $cmd = $cmd . "-password \"$password\" ";
    }
    if ( $action eq 'deploy' ) {
        $cmd = $cmd . "-targets $targets ";
    }

    $cmd = $cmd . "-adminurl $adminUrl -name $appName ";
    if ( $action eq 'deploy' ) {
        $cmd = $cmd . "-source $sourcePath -$stagingMode";
    }

    my $ret = system($cmd);

    my $isSuccess = 0;
    $isSuccess = 1 if ( $ret eq 0 );

    return $isSuccess;
}

sub stopApp {
    my ( $self, $appName ) = @_;
    return $self->appDeployDispatch( $appName, 'stop' );
}

sub startApp {
    my ( $self, $appName ) = @_;
    return $self->appDeployDispatch( $appName, 'start' );
}

sub deployApp {
    my ( $self, $appName ) = @_;
    return $self->appDeployDispatch( $appName, 'deploy' );
}

sub undeployApp {
    my ( $self, $appName ) = @_;
    return $self->appDeployDispatch( $appName, 'undeploy' );
}

sub updateApp {
    my ( $self, $appName ) = @_;
    return $self->appDeployDispatch( $appName, 'redeploy' );
}

#my $domainHome = '/app/serverware/wls/domains/tsdomain';
#print( "app exists:", isAppExists( $domainHome, 'sample' ), "\n" );
#print( "is admin:", isAdminServer( $domainHome, "t3://192.168.0.235:7001", 'myserver' ), "\n" );

1;

