#!/usr/bin/perl
use strict;

package BuildMAVEN;
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

    if ( not defined($args) or $args eq '' ) {
        $cmd = "mvn $silentOpt -U clean install";
        print("INFO: Execute->$cmd\n");
        $ret = DeployUtils->execmd($cmd);
    }
    else {
        if ( $args !~ /\bclean\b/ ) {
            $cmd = "mvn $silentOpt clean";
            print("INFO: Execute->$cmd\n");
            $ret = DeployUtils->execmd($cmd);
        }

        if ( $ret eq 0 ) {
            $cmd = "mvn $args";
            print("INFO: Execute->$cmd\n");
            $ret = DeployUtils->execmd($cmd);
        }
    }

    if ( $ret > 255 ) {
        $ret = $ret >> 8;
    }

    return $ret;
}

1;
