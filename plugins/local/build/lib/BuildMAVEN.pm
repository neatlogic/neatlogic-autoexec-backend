#!/usr/bin/env perl
use strict;

package BuildMAVEN;
use FindBin;
use XML::MyXML qw(xml_to_object);
use DeployUtils;
use File::Spec;

sub new {
    my ( $pkg, %args ) = @_;

    my $self = \%args;
    bless( $self, $pkg );
    return $self;
}

sub syncMvnDependency {
    my ( $prjPath, $m2LocalRepo, $settingXml, $profiles, $isVerbose ) = @_;

    my $deployUtils = DeployUtils->new();
    my $buildEnv    = $deployUtils->deployInit();
    my $runnerGroup = $buildEnv->{RUNNER_GROUP};
    my @runnerIds   = keys(%$runnerGroup);
    if ( scalar(@runnerIds) <= 1 ) {
        return 0;
    }

    my $hasError = 0;
    print("INFO: Begin sync mvn dependency to runner group.\n");
    my $pomFilePath = "$prjPath/pom.xml";
    if ( not -f $pomFilePath ) {
        $hasError = 1;
        print("ERROR: Pom file: $pomFilePath not exists.\n");
    }

    my $cmd = "mvn dependency:tree -s $settingXml";
    if ( defined($profiles) and $profiles ne '' ) {
        $cmd = "$cmd -P$profiles";
    }
    print("INFO: Execute->$cmd\n");
    my $result     = DeployUtils->getPipeOut( $cmd, $isVerbose );
    my $buildUtils = BuildUtils->new();
    foreach my $line (@$result) {
        chomp($line);
        if ( $line !~ /^\[INFO\]\s+(.*)$/ ) {
            next;
        }
        my $depLine = $1;

        # 过滤掉非依赖行
        if ( $depLine !~ /:/ ) {
            next;
        }
        $depLine =~ s/^[|\\+\-\s]+//;

        # 拆分 groupId:artifactId:type:version[:scope]
        my ( $groupId, $artifactId, $type, $version, $scope ) = split( /:/, $depLine );

        #只处理jar和pom
        if ( not defined($type) or $type eq '' or ( $type ne 'jar' and $type ne 'pom' ) ) {
            next;
        }

        # 构建文件路径
        my $depPath = File::Spec->catfile( $m2LocalRepo, split( /\./, $groupId ), $artifactId, $version );

        if ( -e $depPath ) {
            eval { $hasError = $buildUtils->syncDirToGroup( $buildEnv, $depPath ); };
            if ($@) {
                print("ERROR: $@\n");
            }
        }
    }

    print("FINE: Sync mvn dependency to runner group members success.\n");
    return $hasError;
}

sub build {
    my ( $self, %opt ) = @_;

    my $prjPath          = $opt{prjPath};
    my $toolsPath        = $opt{toolsPath};
    my $version          = $opt{version};
    my $jdk              = $opt{jdk};
    my $args             = $opt{args};
    my $isVerbose        = $opt{isVerbose};
    my $makeToolVer      = $opt{makeToolVer};
    my $isSyncDependency = $opt{isSyncDependency};

    chdir($prjPath);

    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    #$ENV{CLASSPATH} = '';
    my $m2Home = "$toolsPath/maven$makeToolVer";
    if ( not -e $m2Home ) {
        print("ERROR: Maven not found in dir:$m2Home, check if maven version $makeToolVer is installed.\n");
    }

    my $jdkPath = $jdk;
    my $jdkVer  = 1.5;
    if ( -l $jdk ) {
        $jdkPath = readlink($jdk);
    }
    if ( $jdkPath =~ /([\d\.]+)$/ ) {
        $jdkVer = 0.0 + $1;
    }

    if ( $jdkVer < 1.8 ) {
        $ENV{MAVEN_OPTS} = '-XX:MaxPermSize=256M';
    }

    $ENV{M2_HOME}   = $m2Home;
    $ENV{JAVA_HOME} = $jdk;
    $ENV{PATH}      = "$jdk/bin:$m2Home/bin:" . $ENV{PATH};

    if ( defined( $ENV{CLASSPATH} ) or $ENV{CLASSPATH} ne '' ) {
        my $m2JarPaths = '';
        foreach my $aPath ( glob("$m2Home/lib/*.jar") ) {
            $m2JarPaths = "$m2JarPaths:$aPath";
        }
        $m2JarPaths = substr( $m2JarPaths, 1 );
        $ENV{CLASSPATH} = $m2JarPaths . ':' . $ENV{CLASSPATH};
    }

    my $ret = 0;
    my $cmd;
    my $hasInstall = 1;

    if ( not defined($args) or $args eq '' ) {
        $cmd = "mvn $silentOpt -U clean install";
        print("INFO: Execute->$cmd\n");
        $ret = DeployUtils->execmd($cmd);
    }
    else {
        # if ( $args !~ /\bclean\b/ ) {
        #     $cmd = "mvn $silentOpt clean";
        #     print("INFO: Execute->$cmd\n");
        #     $ret = DeployUtils->execmd($cmd);
        # }

        if ( $ret eq 0 ) {
            $cmd = "mvn $args";
            print("INFO: Execute->$cmd\n");
            $ret = DeployUtils->execmd($cmd);
        }

        if ( $cmd =~ /\Winstall\W/ ) {
            $hasInstall = 1;
        }
        else {
            $hasInstall = 0;
        }
    }

    if ( $ret eq 0 and $hasInstall == 1 and $isSyncDependency == 1 ) {
        my $m2LocalRepo = $ENV{HOME} . '/.m2/repository';
        my $settingXml  = $ENV{HOME} . '/.m2/settings.xml';
        my $profiles    = '';
        if ( $args =~ /\-Dmaven\.repo\.local=(\S+)/ or $args =~ /\-Dmaven\.repo\.local='(.+)'/ or $args =~ /\-Dmaven\.repo\.local="(.+)"/ ) {
            $m2LocalRepo = $1;
        }

        if ( $args =~ /-s\s+(\S+)/ ) {
            $settingXml = $1;
            if ( defined($settingXml) and $settingXml ne '' ) {
                my $xmlObj              = xml_to_object( $1, { file => 1 } );
                my $localRepositoryItem = $xmlObj->path('localRepository');
                if ( defined($localRepositoryItem) ) {
                    $$m2LocalRepo = $localRepositoryItem->value();
                }
            }
        }

        if ( $cmd =~ /(?:^|\s)-P\s*([^\s]+)/ ) {
            $profiles = $1;
        }

        $ret = syncMvnDependency( $prjPath, $m2LocalRepo, $settingXml, $profiles, $isVerbose );
    }

    if ( $ret > 255 ) {
        $ret = 1;
    }

    return $ret;
}

1;
