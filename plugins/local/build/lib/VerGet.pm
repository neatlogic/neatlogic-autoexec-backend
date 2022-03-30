#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

package VerGet;

use strict;
use DeployUtils;
use File::Path;
use Cwd;

sub new {
    my ( $pkg, $buildEnv, $versionInfo, $isVerbose ) = @_;
    my $self = {};
    bless( $self, $pkg );

    $self->{buildEnv}  = $buildEnv;
    $self->{verInfo}   = $versionInfo;
    $self->{version}   = $versionInfo->{version};
    $self->{isVerbose} = $isVerbose;

    $self->{VERSION}     = $buildEnv->{VERSION};
    $self->{ID_PATH}     = $buildEnv->{ID_PATH};
    $self->{NAME_PATH}   = $buildEnv->{NAME_PATH};
    $self->{DATA_PATH}   = $buildEnv->{DATA_PATH};
    $self->{SYS_NAME}    = $buildEnv->{SYS_NAME};
    $self->{MODULE_NAME} = $buildEnv->{MODULE_NAME};
    $self->{ENV_NAME}    = $buildEnv->{ENV_NAME};

    return $self;
}

sub getHandler {
    my ( $self, $verInfo ) = @_;

    my $verInfo   = $self->{verInfo};
    my $buildEnv  = $self->{buildEnv};
    my $isVerbose = $self->{isVerbose};

    my $repo     = $verInfo->{repo};
    my $repoType = $verInfo->{repoType};

    my $handler;
    if ( defined($repo) and $repo ne '' ) {
        if ( defined($repoType) and $repoType ne '' ) {
            $self->{repoType} = uc($repoType);
            my $handlerName = uc($repoType) . 'VerGet';
            my $requireName = $handlerName . '.pm';

            eval {
                require $requireName;

                $handler = $handlerName->new(
                    buildEnv  => $buildEnv,
                    verInfo   => $verInfo,
                    isVerbose => $isVerbose
                );
            };
            if ($@) {
                print("ERROR: Init repository type:$repoType failed.\n");
                print($@);
            }
        }
        else {
            print("ERROR: Repository type not defined.\n");
        }
    }
    else {
        print("ERROR: Repository address not configed.\n");
    }

    return $handler;
}

sub addVerBuildInfo {
    my ( $self, $verInfo ) = @_;

    #TODO: call api to update verinformation
}

sub get {
    my ($self) = @_;

    my $verInfo = $self->{verInfo};
    my $version = $verInfo->{version};

    print("INFO: Get version, this may take a few minutes.\n");
    my $handler = $self->getHandler();

    my $ret = 0;
    if ( defined($handler) ) {
        $ret = $handler->get();
    }

    if ( $ret eq 1 ) {
        print("INFO: Checkout version $version success.\n");
    }
    else {
        print("ERROR: Checkout version $version failed.\n");
    }

    return $ret;
}

sub checkBaseLineMerged {
    my ($self) = @_;

    my $version = $self->{version};

    print("INFO:check base line merged for version, this may take a few minutes.\n");
    my $handler = $self->getHandler();
    my $success = 0;
    if ( defined($handler) ) {
        $success = $handler->checkBaseLineMerged();
    }

    if ( $success eq 1 ) {
        print("INFO: check base line merged for version $version success.\n");
    }
    else {
        print("ERROR: check base line merged for version $version failed.\n");
    }

    return $success;
}

sub mergeToBaseLine {
    my ($self) = @_;

    my $version = $self->{version};

    print("INFO:merge version to base line, this may take a few minutes.\n");
    my $handler = $self->getHandler();
    my $success = 0;
    if ( defined($handler) ) {
        $success = $handler->mergeToBaseLine();
    }

    if ( $success eq 1 ) {
        print("INFO: merge version to base line success.\n");
    }
    else {
        print("ERROR: merge version to base line failed.\n");
    }

    return $success;
}

sub tag {
    my ( $self, $tagPrefix ) = @_;

    my $version = $self->{version};

    print("INFO:Create tag $version with tag:$tagPrefix$version, this may take a few minutes.\n");

    my $handler = $self->getHandler();
    my $success = 0;
    if ( defined($handler) ) {
        $success = $handler->tag( $version, $tagPrefix );
    }

    if ( $success eq 1 ) {
        print("INFO: Create tag $version with tag:$tagPrefix$version success.\n");
    }
    else {
        print("ERROR: Create tag $version with tag:$tagPrefix$version failed.\n");
    }

    return $success;
}

sub tagRev {
    my ( $self, $tagPrefix, $tagRevision ) = @_;

    my $version = $self->{version};

    print("INFO:Create tag $version with tag:$tagPrefix$version, this may take a few minutes.\n");

    my $handler = $self->getHandler();
    my $success = 0;
    if ( defined($handler) ) {
        $success = $handler->tagRev( $version, $tagPrefix, $tagRevision );
    }
    if ( $success eq 1 ) {
        print("INFO: Create tag $version at revision $tagRevision with tag:$tagPrefix$version success.\n");
    }
    else {
        print("ERROR: Create tag $version at revision $tagRevision with tag:$tagPrefix$version failed.\n");
    }

    return $success;
}

sub checkChangedAfterCompiled {

    #需要修改为通过revision来判断，而不是tag
    my ($self) = @_;

    my $version = $self->{version};

    print("INFO: Check if there are new changes after version:$version compiled.\n");

    my $handler = $self->getHandler();
    my $success = 0;
    if ( defined($handler) ) {
        $success = $handler->checkChangedAfterCompiled($version);
    }

    if ( $success eq 1 ) {
        print("INFO: There is no changes after compiled.\n");
    }
    else {
        print("ERROR: There are changes after compiled.\n");
    }

    return $success;
}

sub getDiffByTag {
    my ( $self, $tagName, $excludeDirs, $diffSaveDir ) = @_;

    my $version   = $self->{version};
    my $isVerbose = $self->{isVerbose};

    my $cmpDestDesc;
    if ( defined($tagName) and $tagName ne '' ) {
        $cmpDestDesc = "tag:$tagName";
    }
    else {
        $cmpDestDesc = "base line";
    }

    print("INFO: Get diff files between $version and $cmpDestDesc.\n");
    print("=======================================================\n");

    my $handler = $self->getHandler();

    my $success;
    if ( defined($handler) ) {
        $success = $handler->getDiffByTag( $tagName, $excludeDirs, $diffSaveDir, $isVerbose );
    }

    print("=======================================================\n");
    if ( $success == 1 ) {
        print("INFO: Get diff files between $version and $cmpDestDesc success.\n");
    }
    else {
        print("INFO: Get diff files between $version and $cmpDestDesc failed.\n");
    }

    return $success;
}

sub getDiffByRev {
    my ( $self, $startRev, $endRev, $excludeDirs, $diffSaveDir ) = @_;

    #print("DEBUG: get diff by startRev:$startRev\n");
    my $version   = $self->{version};
    my $isVerbose = $self->{isVerbose};

    my $cmpDestDesc;
    if ( defined($startRev) and $startRev ne '' ) {
        $version = "rev:$startRev";
    }
    if ( defined($endRev) and $endRev ne '' ) {
        $cmpDestDesc = "rev:$endRev";
    }

    print("INFO: Get diff files between $version and $cmpDestDesc.\n");
    print("=======================================================\n");

    my $handler = $self->getHandler();

    my $success;
    if ( defined($handler) ) {
        $success = $handler->getDiffByRev( $startRev, $endRev, $excludeDirs, $diffSaveDir, $isVerbose );
    }

    print("=======================================================\n");
    if ( $success == 1 ) {
        print("INFO: Get diff files between $version and $cmpDestDesc success.\n");
    }
    else {
        print("INFO: Get diff files between $version and $cmpDestDesc failed.\n");
    }

    return $success;
}

sub getBuildDiff {
    my ( $self, $tag4CmpTo, $startRev, $endRev, $prjDir, $diffDir, $excludeDirs, $isVerbose ) = @_;

    if ( not -e $diffDir ) {
        mkdir($diffDir);
    }

    if ( $tag4CmpTo eq '' ) {
        undef($tag4CmpTo);
    }

    my $success = 0;
    if ( $tag4CmpTo ne '' ) {
        $success = $self->getDiffByTag( $tag4CmpTo, $excludeDirs, $diffDir, $isVerbose );
    }
    elsif ( $startRev ne '' ) {

        $success = $self->getDiffByRev( $startRev, $endRev, $excludeDirs, $diffDir, $isVerbose );
    }
    else {
        print("ERROR: Can not get diff base(tag|branch|revision).\n");
    }

    return $success;
}

1;
