#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;

package BuildMVN;

sub build {
    my (%opt) = @_;

    #my ( $prjDir, $versDir, $version, $jdk, $args, $isVerbose, $isUpdate ) = @_;

    my $prjDir      = $opt{prjDir};
    my $versDir     = $opt{versDir};
    my $version     = $opt{version};
    my $jdk         = $opt{jdk};
    my $args        = $opt{args};
    my $isVerbose   = $opt{isVerbose};
    my $makeToolVer = $opt{makeToolVer};
    my $isUpdate    = $opt{isUpdate};

    my $verDir = "$versDir/$version";
    chdir($prjDir);

    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );
    my $updateOpt = '';
    $updateOpt = '-U' if ( defined($isUpdate) );

    my $techsureHome = $ENV{TECHSURE_HOME};
    if ( not defined($techsureHome) or $techsureHome eq '' ) {
        $techsureHome = Cwd::abs_path("$FindBin::Bin/../..");
    }

    #$ENV{CLASSPATH} = '';
    my $m2Home = "$techsureHome/serverware/maven$makeToolVer";
    if ( not -e $m2Home ) {
        print("ERROR: maven not found in dir:$m2Home, check if maven version $makeToolVer is installed.\n");
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

    #my $cmd = "mvn $silentOpt clean";
    #print("INFO:execute->$cmd\n");
    #my $ret = Utils::execmd($cmd);

    my $ret = 0;
    my $cmd;

    if ( not defined($args) or $args eq '' ) {
        $cmd = "mvn $silentOpt $updateOpt clean install";
        print("INFO:execute->$cmd\n");
        $ret = Utils::execmd($cmd);
    }
    else {
        #if ( $args !~ /\sclean\s/ ){
        #    $cmd = "mvn $silentOpt clean";
        #    print("INFO:execute->$cmd\n");
        #    $ret = Utils::execmd($cmd);
        #}

        $cmd = "mvn $silentOpt $updateOpt clean $args";
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
