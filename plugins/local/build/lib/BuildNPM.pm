#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;

package BuildNPM;

sub build {
    my (%opt) = @_;

    #my ( $prjDir, $versDir, $version, $nodejsVer, $args, $isVerbose ) = @_;

    my $prjDir      = $opt{prjDir};
    my $versDir     = $opt{versDir};
    my $version     = $opt{version}, my $jdk = $opt{jdk};
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

    my $verDir = "$versDir/$version";
    chdir($prjDir);

    my $techsureHome = $ENV{TECHSURE_HOME};
    if ( not defined($techsureHome) or $techsureHome eq '' ) {
        $techsureHome = Cwd::abs_path("$FindBin::Bin/../..");
    }

    my $nodejsPath = '';

    if ( $nodejsVer ne '' ) {
        $nodejsPath = "$techsureHome/serverware/node$nodejsVer";
    }
    else {
        $nodejsPath = "$techsureHome/serverware/node";
    }

    my $isSuccess = 1;
    my $ret       = 0;

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
            $ret = Utils::execmd($cmd);
        }
        else {
            $cmd = "npm ci && npm $args";
            print("INFO:execute->$cmd\n");
            $ret = Utils::execmd($cmd);
        }
    }

    if ( $ret ne 0 ) {
        $isSuccess = 0;
    }

    return $isSuccess;
}

1;
