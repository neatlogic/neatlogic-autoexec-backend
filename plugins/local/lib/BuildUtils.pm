#!/usr/bin/perl
use strict;

package BuildUtils;
use Cwd;
use File::Path;
use File::Basename;

use ServerAdapter;
use DeployUtils;

sub new {
    my ( $pkg, %args ) = @_;

    my $self = \%args;
    bless( $self, $pkg );

    $self->{serverAdapter} = ServerAdapter->new();
    return $self;
}

sub getPrjRoots {
    my ( $self, $prjSrc ) = @_;
    my @prjRoots;

    if ( -f "$prjSrc/pom.xml" or -f "$prjSrc/build.xml" or -f "$prjSrc/build.gradle" ) {
        push( @prjRoots, $prjSrc );
    }
    else {
        my @subPoms = bsd_glob("$prjSrc/*");

        for my $subDir (@subPoms) {
            if ( -f "$subDir/pom.xml" or -f "$subDir/build.xml" or -f "$subDir/build.gradle" ) {
                push( @prjRoots, $subDir );
            }
        }
    }

    push( @prjRoots, $prjSrc ) if ( scalar(@prjRoots) == 0 );

    return @prjRoots;
}

sub compile {
    my ( $self, $opts ) = @_;

    my $buildEnv    = $opts->{buildEnv};
    my $version     = $opts->{version};
    my $lang        = $opts->{lang};
    my $startPath   = $opts->{startPath};
    my $buildType   = $opts->{buildType};
    my $codePath    = $opts->{codePath};
    my $args        = $opts->{args};
    my $isVerbose   = $opts->{isVerbose};
    my $jdk         = $opts->{jdk};
    my $prjPath     = $opts->{prjPath};
    my $makeToolVer = $opts->{makeToolVer};

    if ( defined($lang) ) {
        $ENV{LANG}   = $lang;
        $ENV{LC_ALL} = $lang;
    }
    $ENV{CLASSPATH} = '';

    my $namePath  = $buildEnv->{NAME_PATH};
    my $toolsPath = $buildEnv->{TOOLS_PATH};

    if ( defined $jdk ) {
        if ( -d "$toolsPath/jdk$jdk" ) {
            $jdk = "$toolsPath/jdk$jdk";
        }
        elsif ( -d "$toolsPath/$jdk" ) {
            $jdk = "$toolsPath/$jdk";
        }
        else {
            print("ERROR: jdk $jdk not exists.\n");
            exit(-1);
        }
    }
    else {
        $jdk = "$toolsPath/jdk";
    }

    my $prjPath  = $buildEnv->{PRJ_PATH};
    my $codePath = $prjPath;

    if ( defined($startPath) and $startPath ne '' ) {
        $codePath = "$codePath/$startPath";
        if ( not -d $codePath ) {
            print("ERROR: start path:$startPath($codePath) not exists.\n");
            exit(-1);
        }
    }

    my $isFail = 0;

    if ( $isFail eq 0 ) {
        my $ret;
        my @codePaths;

        if ( defined($startPath) and $startPath ne '' and defined($buildType) and $buildType ne '' ) {
            print("INFO: start path and build type defined, use $buildType to build $startPath under $prjPath.\n");
            @codePaths = ($codePath);
        }
        else {
            @codePaths = $self->getPrjRoots($codePath);
        }

        my $aCodePath;
        foreach $aCodePath (@codePaths) {
            if ( not defined($buildType) ) {
                if ( -e "$aCodePath/build.xml" ) {
                    $buildType = 'ant';
                }
                elsif ( -e "$aCodePath/pom.xml" ) {
                    $buildType = 'maven';
                }
                elsif ( -e "$aCodePath/build.gradle" ) {
                    $buildType = 'gradle';
                }
                elsif ( -e "$aCodePath/package.json" ) {
                    $buildType = 'npm';
                }
            }
            else {
                if ( $buildType =~ /^(.*?)([\d\.\-\_]+)$/ ) {
                    $buildType   = $1;
                    $makeToolVer = $2;
                }
                if ( $buildType eq 'maven' ) {
                    $buildType = 'maven';
                }
                elsif ( $buildType eq 'nodejs' ) {
                    $buildType = 'npm';
                }
            }

            my %opt = (
                prjPath     => $aCodePath,
                toolsPath   => $buildEnv->{TOOLS_PATH},
                version     => $version,
                jdk         => $jdk,
                args        => $args,
                isVerbose   => $isVerbose,
                makeToolVer => $makeToolVer
            );

            if ( defined $makeToolVer and $makeToolVer ne '' ) {
                print("INFO: Build type is $buildType, build tool version is $makeToolVer\n");
            }

            if ( defined($buildType) or $buildType eq '' ) {
                my $builder;
                my $buildClass = 'Build' . uc($buildType);
                eval {
                    require "$buildClass.pm";
                    our @ISA = ($buildClass);
                    $builder = $buildClass->new();
                    $ret     = $builder->build(%opt);
                };
                if ($@) {
                    $ret = 2;
                    print("ERROR: Load $buildClass.pm failed, $@\n");
                }
            }
            else {
                print("ERROR: BuildType:$buildType not supported.\n");
                $ret = 3;
            }

            $isFail = $ret;
        }
    }

    if ( $isFail eq 0 ) {
        print("FINEST: Build $namePath version:$version success.\n");
    }
    else {
        print("ERROR: Build $namePath version:$version failed.\n");
    }

    return $isFail;
}

sub release {
    my ( $self, $buildEnv ) = @_;

    my $dataPath = $buildEnv->{DATA_PATH};
    my $envName  = $buildEnv->{ENV_NAME};

    my $myRunnerId  = $buildEnv->{RUNNER_ID};
    my $runnerGroup = $buildEnv->{RUNNER_GROUP};

    my $cwd = getcwd();
    chdir($dataPath);

    my $outerCompileRoot = "workspace";
    my $dirInfo          = DeployUtils->getDataDirStruct( $buildEnv, 1 );
    my $buildRoot        = $dirInfo->{releaseRoot};
    my $buildPath        = $dirInfo->{release};
    my $envBuildRoot     = $dirInfo->{distribute};
    my $buildLnk         = "$envBuildRoot/build";

    my $buildNo = $buildEnv->{BUILD_NO};

    if ( defined($envName) and $envName ne '' ) {
        if ( -l $buildLnk ) {
            unlink($buildLnk);
        }
        symlink( "../../build/$buildNo", $buildLnk );
    }

    my $ret = 0;
    $ENV{RSYNC_RSH} = 'ssh -T -c aes128-ctr -o Compression = no -x';
    while ( my ( $runnerId, $runnerIp ) = each(%$runnerGroup) ) {
        if ( $runnerId eq $myRunnerId ) {
            next;
        }

        print("INFO: Sync '$buildPath' to $runnerIp::'$buildRoot/'.\n");
        $ret = system("rsync -avrR --delete '$buildPath' $runnerIp::'$buildRoot/'");
        if ( $ret != 0 ) {
            print("ERROR: Sync '$buildPath' to $runnerIp::'$buildRoot/' failed.\n");
            last;
        }

        if ( -d "$outerCompileRoot/build" ) {
            print("INFO: Sync '$outerCompileRoot/build' to $runnerIp::'$outerCompileRoot/'\n");
            $ret = system("rsync -avrR --delete '$outerCompileRoot/build' $runnerIp::'$outerCompileRoot/'");
            if ( $ret != 0 ) {
                print("ERROR: Sync '$outerCompileRoot/build' to $runnerIp::'$outerCompileRoot/' failed.\n");
                last;
            }
        }

        if ( defined($envName) and $envName ne '' and -l $buildLnk ) {
            print("ERROR: Copy '$buildLnk' to $runnerIp::'$envBuildRoot/'.\n");
            $ret = system("rsync -avR '$buildLnk' $runnerIp::'$envBuildRoot/'");
            if ( $ret != 0 ) {
                print("ERROR: Copy '$buildLnk' to $runnerIp::'$envBuildRoot/' failed.\n");
                last;
            }
        }
    }
    chdir($cwd);

    return $ret;
}

sub release2Env {
    my ( $self, $buildEnv ) = @_;

    my $dataPath = $buildEnv->{DATA_PATH};
    my $envName  = $buildEnv->{ENV_NAME};

    my $myRunnerId  = $buildEnv->{RUNNER_ID};
    my $runnerGroup = $buildEnv->{RUNNER_GROUP};

    my $cwd = getcwd();
    chdir($dataPath);

    my $dirInfo      = DeployUtils->getDataDirStruct( $buildEnv, 1 );
    my $envBuildRoot = $dirInfo->{distribute};

    my $ret = 0;
    $ENV{RSYNC_RSH} = 'ssh -T -c aes128-ctr -o Compression = no -x';
    while ( my ( $runnerId, $runnerIp ) = each(%$runnerGroup) ) {
        if ( $runnerId eq $myRunnerId ) {
            next;
        }

        if ( defined($envName) and $envName ne '' and -d $envBuildRoot ) {
            print("ERROR: Sync '$envBuildRoot/' to $runnerIp::'$envBuildRoot/'.\n");
            $ret = system("rsync -avrR --delete '$envBuildRoot/' $runnerIp::'$envBuildRoot/'");
            if ( $ret != 0 ) {
                print("ERROR: Sync '$envBuildRoot/' to $runnerIp::'$envBuildRoot/' failed.\n");
                last;
            }
        }
    }

    chdir($cwd);

    return $ret;
}

sub cleanExpiredBuild {
    my ( $self, $buildEnv, $maxBuildCount ) = @_;

    my $dirInfo = DeployUtils->getDataDirStruct($buildEnv);
    my $relRoot = $dirInfo->{releaseRoot};

    my @buildDirs       = glob("$relRoot/*/app");
    my @sortedBuildDirs = sort { ( stat($a) )[9] <=> ( stat($b) )[9] } @buildDirs;

    my $buildCount = scalar(@sortedBuildDirs);
    my $maxIdx     = $buildCount - $maxBuildCount;

    my $serverAdapter = $self->{serverAdapter};

    my $version = $buildEnv->{VERSION};

    for ( my $i = 0 ; $i < $maxIdx ; $i++ ) {
        my $buildDir = dirname( $sortedBuildDirs[$i] );
        my $buildNo  = basename($buildDir);
        eval {
            $serverAdapter->delBuild( $buildEnv, $version, $buildNo );
            rmtree($buildDir);
            print("INFO: Remove expired build $version\_build$buildNo success.\n");
        };
        if ($@) {
            my $errMsg = $@;
            $errMsg =~ s/ at\s*.*$//;
            print("WARN: Remove expired build artifact:$buildDir, failed, $errMsg\n");
        }
    }
}

sub cleanExpiredVersion {
    my ( $self, $buildEnv, $minVersionCount, $minLastDays ) = @_;

    my $artifactDir = $buildEnv->{DATA_PATH} . '/artifact';
    my @verDirs     = ();
    foreach my $verDir ( glob("$artifactDir/*") ) {
        if ( $verDir ne 'mirror' and -e "$verDir/build" ) {
            push( @verDirs, $verDir );
        }
    }

    my $sortVerByVerNumber = sub {
        my $leftVer  = $a;
        my $rightVer = $b;

        $leftVer  =~ s/[^\d]+/\./g;
        $rightVer =~ s/[^\d]+/\./g;
        $leftVer  =~ s/^\.//;
        $rightVer =~ s/^\.//;

        my @leftNums =
            split( /[^\d]+/, $leftVer );
        my @rightNums =
            split( /[^\d]+/, $rightVer );
        my $leftLen  = scalar(@leftNums);
        my $rightLen = scalar(@rightNums);

        my $ret = 0;
        my $i   = 0;

        for ( $i = 0 ; $i < $leftLen && $i < $rightLen ; $i++ ) {
            $ret = $leftNums[$i] <=> $rightNums[$i];

            last
                if ( $ret ne 0 );
        }

        $ret = $leftLen <=> $rightLen
            if ( $ret eq 0 );

        return $ret;
    };
    my @sortedVerDirsTmp = sort $sortVerByVerNumber @verDirs;
    my @sortedVerDirs    = sort { ( stat("$a/build") )[9] <=> ( stat("$b/build") )[9] } @sortedVerDirsTmp;

    my $verCount = scalar(@sortedVerDirs);
    my $maxIdx   = $verCount - $minVersionCount;

    my $serverAdapter = $self->{serverAdapter};

    my $minLastSecs = $minLastDays * 86400;
    my $nowTime     = time();
    for ( my $i = 0 ; $i < $maxIdx ; $i++ ) {
        my $verDir   = $sortedVerDirs[$i];
        my $verMtime = ( stat($verDir) )[9];
        my $version  = basename($verDir);

        if ( $nowTime - $verMtime > $minLastSecs ) {
            eval {
                $serverAdapter->delVer( $buildEnv, $version );
                rmtree($verDir);
                print("INFO: Remove expired version $version success.\n");
            };
            if ($@) {
                my $errMsg = $@;
                $errMsg =~ s/ at\s*.*$//;
                print("WARN: Remove expired version artifact:$verDir, failed, $errMsg\n");
            }
        }
        else {
            last;
        }
    }
}

1;
