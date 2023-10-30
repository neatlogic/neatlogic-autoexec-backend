#!/usr/bin/perl
use strict;

package VerGet;
use FindBin;
use File::Path;
use Cwd;

use DeployUtils;

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

sub get {
    my ($self) = @_;

    my $verInfo = $self->{verInfo};
    my $version = $verInfo->{version};

    print("INFO: Get version, this may take a few minutes.\n");
    my $handler = $self->getHandler();

    my $ret = 1;
    if ( defined($handler) ) {
        $ret = $handler->get();
    }

    if ( $ret > 255 ) {
        $ret = $ret >> 8;
    }

    return $ret;
}

sub checkBaseLineMerged {
    my ($self) = @_;

    my $version = $self->{version};

    print("INFO: Check base line merged for version, this may take a few minutes.\n");
    my $handler = $self->getHandler();
    my $ret     = 1;
    if ( defined($handler) ) {
        $ret = $handler->checkBaseLineMerged();
    }

    if ( $ret > 255 ) {
        $ret = $ret >> 8;
    }

    return $ret;
}

sub mergeToBaseLine {
    my ($self) = @_;

    my $version = $self->{version};

    print("INFO: Merge version to base line, this may take a few minutes.\n");
    my $handler = $self->getHandler();
    my $ret     = 1;
    if ( defined($handler) ) {
        $ret = $handler->mergeToBaseLine();
    }

    if ( $ret > 255 ) {
        $ret = $ret >> 8;
    }

    return $ret;
}

sub mergeBaseLine {
    my ($self) = @_;

    my $version = $self->{version};

    print("INFO: Merge base line changes to version, this may take a few minutes.\n");
    my $handler = $self->getHandler();
    my $ret     = 1;
    if ( defined($handler) ) {
        $ret = $handler->mergeBaseLine();
    }

    if ( $ret > 255 ) {
        $ret = $ret >> 8;
    }

    return $ret;
}

sub tag {
    my ( $self, $tagPrefix ) = @_;

    my $version = $self->{version};

    print("INFO: Create tag:$tagPrefix$version, this may take a few minutes.\n");

    my $handler = $self->getHandler();
    my $ret     = 1;
    if ( defined($handler) ) {
        $ret = $handler->tag( $version, $tagPrefix );
    }

    if ( $ret > 255 ) {
        $ret = $ret >> 8;
    }

    return $ret;
}

sub tagRev {
    my ( $self, $tagPrefix, $tagRevision ) = @_;

    my $version = $self->{version};

    print("INFO: Create tag $version with tag:$tagPrefix$version, this may take a few minutes.\n");

    my $handler = $self->getHandler();
    my $ret     = 1;
    if ( defined($handler) ) {
        $ret = $handler->tagRev( $version, $tagPrefix, $tagRevision );
    }

    if ( $ret > 255 ) {
        $ret = $ret >> 8;
    }

    return $ret;
}

sub checkChangedAfterCompiled {

    #需要修改为通过revision来判断，而不是tag
    my ($self) = @_;

    my $version = $self->{version};

    print("INFO: Check if there are new changes after version:$version compiled.\n");

    my $handler = $self->getHandler();
    my $ret     = 1;
    if ( defined($handler) ) {
        $ret = $handler->checkChangedAfterCompiled($version);
    }

    if ( $ret > 255 ) {
        $ret = $ret >> 8;
    }

    return $ret;
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

    my $ret = 1;
    if ( defined($handler) ) {
        $ret = $handler->getDiffByTag( $tagName, $excludeDirs, $diffSaveDir, $isVerbose );
    }

    print("=======================================================\n");
    if ( $ret == 0 ) {
        print("INFO: Get diff files between $version and $cmpDestDesc success.\n");
    }
    else {
        print("INFO: Get diff files between $version and $cmpDestDesc failed.\n");
    }

    if ( $ret > 255 ) {
        $ret = $ret >> 8;
    }

    return $ret;
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

    my $ret = 1;
    if ( defined($handler) ) {
        $ret = $handler->getDiffByRev( $startRev, $endRev, $excludeDirs, $diffSaveDir, $isVerbose );
    }

    print("=======================================================\n");
    if ( $ret == 0 ) {
        print("INFO: Get diff files between $version and $cmpDestDesc success.\n");
    }
    else {
        print("INFO: Get diff files between $version and $cmpDestDesc failed.\n");
    }

    if ( $ret > 255 ) {
        $ret = $ret >> 8;
    }

    return $ret;
}

sub getBuildDiff {
    my ( $self, $tag4CmpTo, $startRev, $endRev, $prjDir, $diffDir, $excludeDirs, $isVerbose ) = @_;

    if ( not -e $diffDir ) {
        mkdir($diffDir);
    }

    if ( $tag4CmpTo eq '' ) {
        undef($tag4CmpTo);
    }

    my $ret = 1;
    if ( defined($startRev) and $startRev ne '' and $startRev ne '0' ) {
        $ret = $self->getDiffByRev( $startRev, $endRev, $excludeDirs, $diffDir, $isVerbose );
    }
    else {
        $ret = $self->getDiffByTag( $tag4CmpTo, $excludeDirs, $diffDir, $isVerbose );

        #print("ERROR: Can not get diff base(tag|branch|revision).\n");
    }

    if ( $ret > 255 ) {
        $ret = $ret >> 8;
    }

    return $ret;
}

sub compare {
    my ( $self, $callback, $tagName, $startRev, $endRev, $excludeDirs, $isVerbose ) = @_;
    my $handler = $self->getHandler();

    my $ret = 1;
    if ( defined($handler) ) {
        $ret = $handler->compare( $callback, $tagName, $startRev, $endRev, $excludeDirs, $isVerbose );
    }

    if ( $ret > 255 ) {
        $ret = $ret >> 8;
    }

    return $ret;
}
1;
