#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;

package BuildGradle;

sub build {
    my (%opt) = @_;

    #my ( $prjDir, $versDir, $version, $jdk, $args, $isVerbose ) = @_;

    my $prjDir      = $opt{prjDir};
    my $versDir     = $opt{versDir};
    my $version     = $opt{version};
    my $jdk         = $opt{jdk};
    my $args        = $opt{args};
    my $isVerbose   = $opt{isVerbose};
    my $makeToolVer = $opt{makeToolVer};

    my $verDir = "$versDir/$version";
    chdir($prjDir);

    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    my $techsureHome = $ENV{TECHSURE_HOME};
    if ( not defined($techsureHome) or $techsureHome eq '' ) {
        $techsureHome = Cwd::abs_path("$FindBin::Bin/../..");
    }

    #$ENV{CLASSPATH} = '';
    my $gradleHome = "$techsureHome/serverware/gradle$makeToolVer";
    if ( not -e $gradleHome ) {
        print("ERROR: gradle not found in dir:$gradleHome, check if gradle version $makeToolVer is installed.\n");
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
    print("INFO:execute->$cmd\n");
    my $ret = Utils::execmd($cmd);

    if ( not defined($args) or $args eq '' ) {
        $cmd = "gradle $silentOpt assemble";
        print("INFO:execute->$cmd\n");
        $ret = Utils::execmd($cmd);
    }
    else {
        $cmd = "gradle $silentOpt $args";
        print("INFO:execute->$cmd\n");
        $ret = Utils::execmd($cmd);
    }

    my $isSuccess = 1;
    if ( $ret ne 0 ) {
        $isSuccess = 0;
    }

    return $isSuccess;
}

1;
