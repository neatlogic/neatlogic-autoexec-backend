#!/usr/bin/env perl
use strict;

package BuildMAVEN;
use FindBin;
use XML::MyXML qw(xml_to_object);
use DeployUtils;


sub new {
    my ( $pkg, %args ) = @_;

    my $self = \%args;
    bless( $self, $pkg );
    return $self;
}

sub syncMvnInstall {
    my ($prjPath,$m2LocalRepo) = @_;

    my $deployUtils = DeployUtils->new();
    my $buildEnv    = $deployUtils->deployInit();
    my $runnerGroup = $buildEnv->{RUNNER_GROUP};
    my @runnerIds = keys(%$runnerGroup);
    if (scalar(@runnerIds) <= 1){
        return 0;
    }

    my $hasError = 0;
    print("INFO: Begin sync mvn artifact to runner group.\n");
    my $pomFilePath = "$prjPath/pom.xml";
    if( not -f $pomFilePath){
        $hasError = 1;
        print("ERROR: Pom file: $pomFilePath not exists.\n");
    }

     my $xmlObj;
    eval{
        $xmlObj = xml_to_object( $pomFilePath, { file => 1 } );
    };
    if($@){
        $hasError = 1;
        my $errMsg = $@;
        $errMsg =~ s/\sat\s.*$//;
        print("ERROR: Invalid format xml file:$pomFilePath.\n$errMsg\n");
    }

    my ($groupId, $artifactId, $jarVersion);
    my $groupIdItem = $xmlObj->path('groupId');
    if ( defined($groupIdItem) ) {
        $groupId = $groupIdItem->value();
    }
    else{
        #如果groupId在Parent里
        my $parentItem = $xmlObj->path('parent');
        if(defined($parentItem)){
            $groupIdItem = $parentItem->path('groupId');
            if(defined($groupIdItem)){
                $groupId = $groupIdItem->value();
            }
        }
    }
    my $artifactIdItem = $xmlObj->path('artifactId');
    if ( defined($artifactIdItem)) {
        $artifactId = $artifactIdItem->value();
    }
    my $versionItem = $xmlObj->path('version');
    if ( defined($versionItem)) {
        $jarVersion = $versionItem->value();
    }

    my $homePath = $ENV{HOME};
    my $repoPath = $groupId;
    $repoPath =~ s/\./\//g;
    $repoPath = "$m2LocalRepo/$repoPath/$artifactId/$jarVersion";

    if (not defined($groupId) or $groupId eq ''){
        $hasError = 1;
        print("ERROR: Can not find groupId in pom file:$pomFilePath\n");
    }
    if (not defined($artifactId) or $artifactId eq ''){
        $hasError = 1;
        print("ERROR: Can not find artifactId in pom file:$pomFilePath\n");
    }
    if (not defined($jarVersion) or $jarVersion eq ''){
        $hasError = 1;
        print("ERROR: Can not find version in pom file:$pomFilePath\n");
    }
    
    if ( not -d $repoPath){
        $hasError = 1;
        print("ERROR: Maven artifact dir:$repoPath not exists.\n");
    }
    else{
        my $buildUtils = BuildUtils->new();
        eval { $hasError = $buildUtils->syncDirToGroup( $buildEnv, $repoPath ); };
        if ($@) {
            print("ERROR: $@\n");
        }
        if($hasError == 0) {
            print("FINE: Sync mvn repo $repoPath to group members success.\n");
        }
    }

    return $hasError == 0 ? 0 : 1;
}

sub build {
    my ( $self, %opt ) = @_;

    my $prjPath     = $opt{prjPath};
    my $toolsPath   = $opt{toolsPath};
    my $version     = $opt{version};
    my $jdk         = $opt{jdk};
    my $args        = $opt{args};
    my $isVerbose   = $opt{isVerbose};
    my $makeToolVer = $opt{makeToolVer};

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
    my $m2LocalRepo = $ENV{HOME} . '/.m2/repository';

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
        if($args =~/\Winstall\W/ ){
            $hasInstall = 1;
        }
        else{
            $hasInstall = 0;
        }
        
        if($args =~ /\-Dmaven\.repo\.local=(\S+)/ or $args =~ /\-Dmaven\.repo\.local='(.+)'/ or $args =~ /\-Dmaven\.repo\.local="(.+)"/){
            $m2LocalRepo = $1;
        }
    }

    # if ($ret eq 0 and $hasInstall == 1){
    #     $ret = syncMvnInstall($prjPath, $m2LocalRepo);
    # }

    if ( $ret > 255 ) {
        $ret = 1;
    }

    return $ret;
}

1;
