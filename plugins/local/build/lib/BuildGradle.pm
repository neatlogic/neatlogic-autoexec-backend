#!/usr/bin/perl
use strict;

package BuildGRADLE;
use FindBin;
use DeployUtils;

sub new {
    my ( $pkg, %args ) = @_;

    my $self = \%args;
    bless( $self, $pkg );
    return $self;
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
    my $gradleHome = "$toolsPath/gradle$makeToolVer";
    if ( not -e $gradleHome ) {
        print("ERROR: Gradle not found in dir:$gradleHome, check if gradle version $makeToolVer is installed.\n");
    }

    $ENV{JAVA_HOME} = $jdk;
    $ENV{PATH}      = "$jdk/bin:$gradleHome/bin:" . $ENV{PATH};

    if ( defined( $ENV{CLASSPATH} ) or $ENV{CLASSPATH} ne '' ) {
        my $gradleJarPaths = '';
        foreach my $aPath ( glob("$gradleHome/lib/*.jar") ) {
            $gradleJarPaths = "$gradleJarPaths:$aPath";
        }
        $gradleJarPaths = substr( $gradleJarPaths, 1 );
        $ENV{CLASSPATH} = $gradleJarPaths . ':' . $ENV{CLASSPATH};
    }

    my $cmd = "gradle $silentOpt clean";
    print("INFO: Execute->$cmd\n");
    my $ret = DeployUtils->execmd($cmd);

    if ( not defined($args) or $args eq '' ) {
        $cmd = "gradle $silentOpt assemble";
        print("INFO: Execute->$cmd\n");
        $ret = DeployUtils->execmd($cmd);
    }
    else {
        $cmd = "gradle $silentOpt $args";
        print("INFO: Execute->$cmd\n");
        $ret = DeployUtils->execmd($cmd);
    }

    return $ret;
}

1;
