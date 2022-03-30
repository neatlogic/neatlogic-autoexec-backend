#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;

#use File::Glob qw(bsd_glob);

package BuildANT;

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

    #    my $classPath = "";
    #    if ( -e "$prjDir/antlib" ) {
    #        foreach my $libFile ( bsd_glob("$prjDir/antlib/*.jar") ) {
    #            print "INFO:Find antlib:$libFile\n";
    #            $classPath = $libFile . ':' . $classPath;
    #        }
    #    }
    #    my $prjRoot = "$versDir/$version/project";
    #    if ( -e "$prjRoot/antlib" ) {
    #        foreach my $libFile ( bsd_glob("$prjRoot/antlib/*.jar") ) {
    #            print "INFO:Find antlib:$libFile\n";
    #            $classPath = $libFile . ':' . $classPath;
    #        }
    #    }
    #    $classPath =~ s/(\:)|(:$)//;
    #
    #    $ENV{'CLASSPATH'} = $classPath;
    my $techsureHome = $ENV{TECHSURE_HOME};
    if ( not defined($techsureHome) or $techsureHome eq '' ) {
        $techsureHome = Cwd::abs_path("$FindBin::Bin/../..");
    }

    #$ENV{CLASSPATH} = '';
    my $antHome = "$techsureHome/serverware/ant$makeToolVer";

    if ( not -e $antHome ) {
        print("ERROR: ant not found in dir:$antHome, check if ant version $makeToolVer is installed.\n");
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
    print("INFO:execute->$cmd\n");
    my $ret = Utils::execmd($cmd);

    my $isSuccess = 1;
    if ( $ret ne 0 ) {
        $isSuccess = 0;
    }

    return $isSuccess;
}

1;
