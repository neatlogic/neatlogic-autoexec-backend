#!/usr/bin/perl
use strict;

package BuildANT;

use FindBin;
use DeployUtils;

#use File::Glob qw(bsd_glob);

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

    my $antHome = "$toolsPath/ant$makeToolVer";

    if ( not -e $antHome ) {
        print("ERROR: Ant not found in dir:$antHome, check if ant version $makeToolVer is installed.\n");
    }

    $ENV{ANT_HOME}  = $antHome;
    $ENV{JAVA_HOME} = $jdk;
    $ENV{PATH}      = "$jdk/bin:$antHome/bin:" . $ENV{PATH};

    if ( defined( $ENV{CLASSPATH} ) or $ENV{CLASSPATH} ne '' ) {
        my $antJarPaths = '';
        foreach my $aPath ( glob("$antHome/lib/*.jar") ) {
            $antJarPaths = "$antJarPaths:$aPath";
        }
        $antJarPaths = substr( $antJarPaths, 1 );
        $ENV{CLASSPATH} = $antJarPaths . ':' . $ENV{CLASSPATH};
    }

    my $cmd = "ant $silentOpt $args";
    print("INFO: Execute->$cmd\n");
    my $ret = DeployUtils->execmd($cmd);

    return $ret;
}

1;
