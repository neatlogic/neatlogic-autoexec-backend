#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";
#use Data::Dumper;
use Utils;
use POSIX qw(uname);

my @uname    = uname();
my $ostype   = $uname[0];
my $shellExt = 'sh';
my $nullDev  = '/dev/null';

if ( $ostype =~ /Windows/i ) {
    $ostype   = 'windows';
    $shellExt = 'bat';
    $nullDev  = 'NUL';
}
else {
    $ostype   = 'unix';
    $shellExt = 'sh';
    $nullDev  = '/dev/null';
}

use CommonConfig;
use Cwd 'abs_path';
my $homePath = $FindBin::Bin;
$homePath = abs_path("$homePath/..");
#$ENV{LANG} = 'utf-8';

if ( scalar(@ARGV) < 2 ) {
    my $progName = $FindBin::Script;
    print("ERROR: Use as $progName config-name\n");
    exit(1);
}

chdir($homePath);
my $configName = $ARGV[0];
my $insName    = $ARGV[1];

if ( scalar(@ARGV) > 2 ) {
    my $argsLen = scalar(@ARGV);
    my $i;
    for ( $i = 2 ; $i < $argsLen ; $i++ ) {
        my $envLine = $ARGV[$i];
        if ( $envLine =~ /\s*(\w+)\s*=\s*(.*)\s*$/ ) {
            $ENV{$1} = $2;
        }
    }
}

my $insPrefix = $insName;
$insPrefix =~ s/\d*$//;

my $sectionConfig;
my $config = CommonConfig->new( "$homePath/conf", "wastool.ini" );
$sectionConfig = $config->getConfig("$configName.$insName");
my $confName = "$configName.$insName";
if ( not defined($sectionConfig) ) {
    $sectionConfig = $config->getConfig("$configName.$insPrefix");
    $confName      = "$configName.$insPrefix";
}
if ( not defined($sectionConfig) ) {
    $confName      = $configName;
    $sectionConfig = $config->getConfig("$configName");
}
my $dmgrprofile = $sectionConfig->{"dmgr_profile"};
my $wasUser     = $sectionConfig->{"was_user"};
my $wasPwd      = $sectionConfig->{"was_pwd"};

my $umask = $sectionConfig->{"umask"};
if ( defined($umask) and $umask ne '' ) {
    umask($umask);
}

if ( defined($dmgrprofile) and $dmgrprofile ne '' and -d $dmgrprofile ) {
    my $cmd;
    if ( $ostype eq 'windows' ) {
        $cmd = "\"$dmgrprofile/bin/startManager.$shellExt\"";
    }
    else {
        $cmd = "$dmgrprofile/bin/startManager.$shellExt";
    }

    #my $cmd = "$dmgrprofile/bin/startManager.$shellExt";
    #system($cmd);
    Utils::execCmd($cmd);
}
else {
    print('WARN: Dmgr not defined on this server.\n');
}

