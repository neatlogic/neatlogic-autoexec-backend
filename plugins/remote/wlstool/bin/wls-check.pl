#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";

#use Data::Dumper;
use Utils;
use CommonConfig;
use Cwd 'abs_path';
use WlsDeployer;

my $rc = 0;

if ( scalar(@ARGV) < 1 ) {
    my $progName = $FindBin::Script;
    print("ERROR: Use as $progName config-name instance-name\n");
    exit(1);
}

my $configName = $ARGV[0];
my $insName    = $ARGV[1];

my $wlsDeployer = WlsDeployer->new( $configName, $insName );

chdir( $wlsDeployer->getHomePath() );

my $config = $wlsDeployer->getConf();

my $javaHome   = $config->{java_home};
my $wlsHome    = $config->{wls_home};
my $domainHome = $config->{domain_home};
my $appname    = $config->{appname};
my $wls_user   = $config->{wls_user};
my $wls_pwd    = $config->{wls_pwd};

my @appnames;
if ( defined($appname) and $appname ne '' ) {
    @appnames = split( /\s*,\s*/, $appname );
}

if ( not -f "$javaHome/bin/java" and not -f "$javaHome/bin/java.exe" ) {
    print("ERROR: $javaHome is not a JAVA HOME:java_home=$javaHome\n");
    $rc = 1;
}

if ( not -f "$wlsHome/wlserver/server/lib/weblogic.jar" ) {
    print("ERROR: $wlsHome is not a weblogic HOME, can not find file wlserver/server/lib/weblogic.jar in weblogic HOME:wls_home=$wlsHome\n");
    $rc = 2;
}

if ( not -f "$domainHome/config/config.xml" ) {
    print("ERROR: $domainHome is not a weblogic Doamain, can not find file config/config.xml in domain dir:domain_home=$domainHome\n");
    $rc = 3;
}

if ( not defined($wls_user) or $wls_user eq '' ) {
    print("ERROR: Wls_user not defined:wls_user=$wls_user\n");
    $rc = 4;
}

if ( defined($appname) ) {
    foreach $appname (@appnames) {
        my $appfile = $config->{"$appname.source-path"};
        if ( not defined($appfile) or $appfile eq '' ) {
            print("ERROR: $appname not config source-path property: $appname.source-path\n");
            $rc = 5;
        }

        my $target = $config->{"$appname.target"};
        if ( not defined($target) or $target eq '' ) {
            print("ERROR: $appname not config target property: $appname.target\n");
            $rc = 6;
        }

        my $targetDir = $appfile;
        if ( $appfile !~ /^\w:|^\// ) {
            $targetDir = "$domainHome/$appfile";
        }
        if ( -e $targetDir ) {
            print("SUCCESS: app dir check OK, $targetDir exists.\n");
        }
        else {
            print("INFO: App dir:$targetDir not exists, maybe app $appname not deploy yet.\n");
        }
    }
}

exit($rc);

