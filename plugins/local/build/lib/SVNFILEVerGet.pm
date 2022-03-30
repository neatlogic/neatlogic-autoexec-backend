#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

package SVNFILEVerGet;

use strict;
use DeployUtils;
use File::Path;
use ServerAdapter;
use Cwd;

sub new {
    my ( $pkg, %args ) = @_;

    my $self = \%args;
    bless( $self, $pkg );

    my $buildEnv  = $args{buildEnv};
    my $verInfo   = $args{verInfo};
    my $isVerbose = $args{isVerbose};

    my $prjPath = $buildEnv->{PRJ_PATH};
    my $version = $verInfo->{version};

    my $autoexecHome = $buildEnv->{AUTOEXEC_HOME};

    my $success = 1;

    my $repo     = $verInfo->{repo};
    my $confRepo = $repo;

    $repo =~ s/\/+$//;
    my $confRepo = $repo;
    my $svnRepo  = $confRepo;
    if ( defined($svnRepo) and $svnRepo ne '' ) {
        $svnRepo =~ s/\{\{version\}\}/$version/g;
        $self->{repo} = $svnRepo;
        my $prjRepo = $confRepo;
        $prjRepo =~ s/\{\{version\}\}.*?$/$version/g;
        $self->{prjRepo} = $prjRepo;
    }
    if ( $confRepo eq $svnRepo ) {
        $self->{isStatic} = 1;
    }
    else {
        $self->{isStatic} = 0;
    }

    $self->{checkoutByTag} = 0;
    my $confSvnTag = $verInfo->{tag};
    $confSvnTag =~ s/\/+$//;
    my $svnTag = $confSvnTag;
    if ( defined($svnTag) and $svnTag ne '' ) {
        $svnTag =~ s/\{\{version\}\}/$version/g;
        $self->{checkoutByTag} = 1;
        $self->{svnTag}        = $svnTag;

        my $prjRepo = $confSvnTag;
        $prjRepo =~ s/\{\{version\}\}.*?$/$version/g;
        $self->{prjRepo} = $prjRepo;
    }
    if ( $confSvnTag eq $svnTag ) {
        $self->{isStatic} = 1;
    }
    else {
        $self->{isStatic} = 0;
    }

    my $tagsDir = $verInfo->{tagsDir};
    $tagsDir =~ s/\/+$//;

    my $trunkRepo = $verInfo->{trunk};
    if ( not defined($trunkRepo) or $trunkRepo eq '' ) {
        $trunkRepo =~ s/\/+$//;
    }

    my $svnUser = $verInfo->{username};
    my $svnPass = $verInfo->{password};
    $svnPass = quotemeta($svnPass);

    my $localSvnInfo = {};
    if ( -e $prjPath ) {
        $localSvnInfo = $self->getLocalSvnInfo($prjPath);
    }

    $self->{autoexecHome} = $autoexecHome;
    $self->{prjPath}      = $prjPath;
    $self->{svnUser}      = $svnUser;
    $self->{svnPass}      = $svnPass;
    $self->{repo}         = $repo;
    $self->{trunkRepo}    = $trunkRepo;
    $self->{tagsDir}      = $tagsDir;
    $self->{localSvnInfo} = $localSvnInfo;

    return $self;
}

sub get {
    my ($self) = @_;

    my $repo      = $self->{repo};
    my $version   = $self->{version};
    my $isVerbose = $self->{isVerbose};
    my $svnUser   = $self->{svnUser};
    my $svnPass   = $self->{svnPass};

    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    my $prjPath = $self->{prjPath};

    my $successed    = 1;
    my $autoexecHome = $self->{autoexecHome};

    my $checkoutRepo = $self->{repo};
    if ( $self->{checkoutByTag} ) {
        $checkoutRepo = $self->{svnTag};
    }

    print("INFO: Export $checkoutRepo, it will take a few minutes, pleas wait...\n");
    rmtree($prjPath);
    mkdir($prjPath);

    #print("svn --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser --password $svnPass co $repo $prjPath\n");
    my $ret = 0;
    $ret = Utils::execmd("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser --password $svnPass export --force $checkoutRepo $prjPath/");

    if ( $ret ne 0 ) {
        $successed = 0;
    }

    return $successed;
}

1;
