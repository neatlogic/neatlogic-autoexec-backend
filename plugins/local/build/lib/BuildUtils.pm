#!/usr/bin/perl
use strict;

package BuildUtils;
use Cwd;
use ServerAdapter;

sub new {
    my ( $pkg, %args ) = @_;

    my $self = \%args;
    bless( $self, $pkg );
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
            print("jdk $jdk is not supported\n");
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

1;
