#!/usr/bin/perl
use strict;

package BuildNPM;
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
    my $nodejs      = $opt{nodejs};

    my $nodejsVer;
    if ( defined($nodejs) and $nodejs ne '' ) {
        $nodejsVer = $nodejs;
    }
    else {
        $nodejsVer = $makeToolVer;
    }

    chdir($prjPath);

    my $nodejsPath = '';

    if ( $nodejsVer ne '' ) {
        $nodejsPath = "$toolsPath/node$nodejsVer";
    }
    else {
        $nodejsPath = "$toolsPath/node";
    }

    my $ret = 0;

    if ( not -e $nodejsPath ) {
        print("ERROR: node.js path($nodejsPath) not exists.\n");
        $ret = -1;
    }
    else {
        $ENV{PATH}            = "$nodejsPath/bin:" . $ENV{PATH};
        $ENV{LD_LIBRARY_PATH} = "$nodejsPath/lib:" . $ENV{LD_LIBRARY_PATH};

        my $cmd;

        if ( not defined($args) or $args eq '' ) {
            $cmd = "npm ci && npm run build";
            print("INFO:execute->$cmd\n");
            $ret = DeployUtils->execmd($cmd);
        }
        else {
            $cmd = "npm ci && npm $args";
            print("INFO:execute->$cmd\n");
            $ret = DeployUtils->execmd($cmd);
        }
    }

    return $ret;
}

1;
