#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

package SVNVerGet;

use strict;
use DeployUtils;
use File::Path;
use File::Copy;
use File::Basename;
use ServerAdapter;
use Cwd;
use URI::Escape;

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

sub getLocalSvnInfo {
    my ( $self, $localDir ) = @_;

    my $output = DeployUtils::getPipeOut("svn info $localDir 2>/dev/null");

    my $svnInfo = {};
    for my $line (@$output) {
        my @info = split( /\s*:\s*/, $line, 2 );
        $svnInfo->{ $info[0] } = uri_unescape( $info[1] );
    }

    my $svnUrl = $svnInfo->{URL};
    if ( defined($svnUrl) ) {
        $svnUrl =~ s/%(..)/pack('c',hex($1))/eg;
    }
    $svnInfo->{URL} =~ $svnUrl;

    my $rootUrl = $svnInfo->{'Repository Root'};
    if ( defined($rootUrl) ) {
        $rootUrl =~ s/%(..)/pack('c',hex($1))/eg;
    }
    $svnInfo->{'Repository Root'} = $rootUrl;

    return $svnInfo;
}

sub cleanUp {
    my ($self) = @_;
    my $prjPath = $self->{prjPath};

    my $callback = sub {
        my ($line) = @_;
        if ( $line =~ /^\?\s/ ) {
            my ( $status, $file ) = split( /\s+/, $line );
            if ( defined($file) and $file ne '' ) {
                rmtree($file);
            }
        }
    };

    print("INFO: begin to clean up unversioned files in working copy.\n");
    DeployUtils::handlePipeOut( "svn status '$prjPath'", $callback );
    print("INFO: Clean up unversioned files finished.\n");
}

sub checkout {
    my ( $self, $repo ) = @_;

    my $autoexecHome = $self->{autoexecHome};
    my $prjPath      = $self->{prjPath};
    my $tagsDir      = $self->{tagsDir};
    my $trunkRepo    = $self->{trunkRepo};
    my $version      = $self->{version};

    my $startRev = 0;
    my $verInfo  = $self->{verInfo};
    if ( defined($verInfo) ) {
        $startRev = $verInfo->{startRev};
        if ( not defined($startRev) ) {
            $startRev = 0;
        }
        $verInfo->{startRev} = $startRev;
    }

    my $svnUser = $self->{svnUser};
    my $svnPass = $self->{svnPass};

    my $isVerbose = $self->{isVerbose};
    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    my $ret = 0;

    my $checkoutRepo = $repo;

    my $localSvnInfo = $self->getLocalSvnInfo($prjPath);

    if ( not defined( $localSvnInfo->{URL} ) ) {
        print("INFO:checkout $checkoutRepo, it will take a few minutes, pleas wait...\n");
        rmtree($prjPath);

        #print("DEBUG: svn --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser --password $svnPass co $checkoutRepo $prjPath\n");
        $ret = DeployUtils::execmd("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass co '$checkoutRepo' '$prjPath'");
    }
    elsif ( $checkoutRepo ne $localSvnInfo->{URL} ) {
        $self->cleanUp();
        print("INFO:Repo url has been changed, switch to $checkoutRepo......\n");

        #print("svn --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser--password $svnPass switch $checkoutRepo $prjPath\n");
        $ret = DeployUtils::execmd("svn cleanup '$prjPath' && svn revert -R '$prjPath' && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass switch '$checkoutRepo' '$prjPath'");

        if ( $ret ne 0 ) {
            print("INFO:Checkout failed, clean the project directory will take a few minutes, please wait...\n");
            if ( rmtree($prjPath) == 0 ) {

                print("ERROR:Remove directory $prjPath failed.\n");
            }
            else {
                mkdir($prjPath);
                print("INFO:Checkout again, it will take a few minutes, please wait...\n");

                #print("DEBUG: svn --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser --password $svnPass co $checkoutRepo $prjPath\n");
                $ret = DeployUtils::execmd("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass co '$checkoutRepo' '$prjPath'");
            }
        }
    }
    else {
        $self->cleanUp();
        print("INFO:update $checkoutRepo......\n");

        #print("svn --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser--password $svnPass update $checkoutRepo\n");
        #print("cd $prjPath && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser --password $svnPass update .\n");
        $ret = DeployUtils::execmd("cd '$prjPath' && svn cleanup . && svn revert -R . && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass update .");

        if ( $ret ne 0 ) {
            print("INFO:Checkout failed, clean the project directory will take a few minutes, please wait...\n");
            if ( rmtree($prjPath) == 0 ) {

                print("ERROR:remove directory $prjPath failed.\n");
            }
            else {
                mkdir($prjPath);
                print("INFO:Checkout again, it will take a few minutes, please wait...\n");

                #print("svn --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser --password $svnPass co $checkoutRepo $prjPath\n");
                $ret = DeployUtils::execmd("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass co '$checkoutRepo' '$prjPath'");
            }
        }
    }

    if ( -d $prjPath ) {
        my $newSvnInfo = $self->getLocalSvnInfo($prjPath);
        my $endRev     = $newSvnInfo->{'Last Changed Rev'};
        if ( not defined($endRev) ) {
            $endRev = 0;
        }

        if ( defined($verInfo)
            and $verInfo->{endRev} ne $endRev )
        {
            $self->{needUpdateVerInfo} = 1;
            $verInfo->{endRev}         = $endRev;
        }
    }

    return $ret;
}

sub tagRepo {
    my ( $self, $repo, $tagRepo, $tagName ) = @_;

    if ( $repo eq $tagRepo ) {
        print("WARN: $repo and $tagRepo is same, tag abort.\n");
        return 0;
    }

    my $autoexecHome = $self->{autoexecHome};

    my $version    = $self->{version};
    my $svnTagsDir = $self->{tagsDir};

    my $svnUser = $self->{svnUser};
    my $svnPass = $self->{svnPass};

    my $isVerbose = $self->{isVerbose};
    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    if ( not defined($tagRepo) or $tagRepo eq '' and defined($tagName) and $tagName ne '' ) {
        if ( defined($svnTagsDir) and $svnTagsDir ne '' ) {
            $tagRepo = "$svnTagsDir/$tagName";
        }
    }

    if ( ( not defined($tagName) or $tagName eq '' ) and defined($tagRepo) and $tagRepo ne '' ) {
        $tagName = basename($tagRepo);
    }

    my $ret = 0;
    if ( defined($tagRepo) and $tagRepo ne '' ) {
        print("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' rm  '$tagRepo' -m 'delete for autodeploy.'\n");
        $ret = DeployUtils::execmd("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass rm  '$tagRepo' -m 'delete for autodeploy.'");
        print("INFO:Remove $tagRepo failed, maybe $tagRepo no exist.\n") if ( $ret != 0 );

        print("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' cp --parents '$repo' '$tagRepo'  -m 'copy for autodeploy.'\n");
        $ret = DeployUtils::execmd("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass cp --parents '$repo' '$tagRepo'  -m 'copy for autodeploy.'");
        if ( $ret != 0 ) {
            print("ERROR: Create tag $tagName $repo to $tagRepo failed.\n");
        }
        else {
            print("FINEST: Create tag $tagName $repo to $tagRepo success.\n");
        }
    }
    else {
        print("WARN: Config option tagsDir not defined, can not create tag $tagName.\n");
    }

    return $ret;
}

sub tagRepoRev {
    my ( $self, $repo, $tagRepo, $tagName, $tagRevision ) = @_;

    if ( $repo eq $tagRepo ) {
        print("WARN: $repo and $tagRepo is same, tag abort.\n");
        return 0;
    }

    my $autoexecHome = $self->{autoexecHome};

    my $version    = $self->{version};
    my $svnTagsDir = $self->{tagsDir};

    my $svnUser = $self->{svnUser};
    my $svnPass = $self->{svnPass};

    my $isVerbose = $self->{isVerbose};
    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    if ( not defined($tagRepo) or $tagRepo eq '' and defined($tagName) and $tagName ne '' ) {
        if ( defined($svnTagsDir) and $svnTagsDir ne '' ) {
            $tagRepo = "$svnTagsDir/$tagName";
        }
    }

    if ( ( not defined($tagName) or $tagName eq '' ) and defined($tagRepo) and $tagRepo ne '' ) {
        $tagName = basename($tagRepo);
    }

    my $ret = 0;
    if ( defined($tagRepo) and $tagRepo ne '' ) {
        my $listtags = "svn --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass ls  '$svnTagsDir' ";
        $ret = DeployUtils::execmd($listtags);
        if ( $ret != 0 ) {
            my $createtagsdir = "svn --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass mkdir '$svnTagsDir' -m 'create tags dir for autodeploy'";
            print("WARN: tags dir $svnTagsDir does not exist, creating one.\n");
            $ret = DeployUtils::execmd($createtagsdir);
            if ( $ret != 0 ) {
                print("ERROR: creat tags dir $svnTagsDir failed, exiting.\n");
                return $ret;
            }
        }

        print("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' cp '$repo\@$tagRevision' '$tagRepo'  -m 'copy for autodeploy.'\n");
        $ret = DeployUtils::execmd("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass cp '$repo\@$tagRevision' '$tagRepo'  -m 'copy for autodeploy.'");
        if ( $ret == 0 ) {
            print("FINEST: Create tag $tagName $repo to $tagRepo success.\n");
        }
    }
    else {
        print("WARN: Config option tagsDir not defined, can not create tag $tagName.\n");
    }

    return $ret;
}

sub getTags {
    my ( $self, $tagPrefix ) = @_;

    my $tags = {};

    my $svnTagsDir = $self->{tagsDir};

    if ( defined($svnTagsDir) and $svnTagsDir ne '' ) {
        my $autoexecHome = $self->{autoexecHome};
        my $svnUser      = $self->{svnUser};
        my $svnPass      = $self->{svnPass};

        my $isVerbose = $self->{isVerbose};
        my $silentOpt = '-q';
        $silentOpt = '' if ( defined($isVerbose) );

        my $fh;
        open( $fh, "svn --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass ls  '$svnTagsDir' |" )
            or die "ERROR:get tag list failed:$!";
        if ( defined($tagPrefix) ) {
            while ( my $line = <$fh> ) {
                $line =~ s/^\s*//;
                $line =~ s/\s*$//;
                if ( $line =~ /^$tagPrefix/ ) {
                    $line =~ s/\/$//;
                    $tags->{$line} = 1;
                }
            }
        }
        else {
            while ( my $line = <$fh> ) {
                $line =~ s/^\s*//;
                $line =~ s/\s*$//;
                $line =~ s/\/$//;
                $tags->{$line} = 1;
            }
        }

        close($fh);
    }

    return $tags;
}

sub get {
    my ($self) = @_;

    my $isVerbose = $self->{isVerbose};

    my $autoexecHome = $self->{autoexecHome};
    my $svnUser      = $self->{svnUser};
    my $svnPass      = $self->{svnPass};

    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    my $success = 1;
    my $ret     = 0;

    my $checkoutRepo = $self->{repo};
    if ( $self->{checkoutByTag} ) {
        $checkoutRepo = $self->{svnTag};
    }
    $ret = $self->checkout($checkoutRepo);

    $success = 0 if ( $ret ne 0 );

    return $success;
}

sub checkBaseLineMerged {
    my ($self) = @_;

    my $version   = $self->{version};
    my $isVerbose = $self->{isVerbose};

    my $autoexecHome = $self->{autoexecHome};
    my $prjPath      = $self->{prjPath};
    my $trunkRepo    = $self->{trunkRepo};
    my $svnUser      = $self->{svnUser};
    my $svnPass      = $self->{svnPass};
    my $localSvnInfo = $self->{localSvnInfo};

    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    if ( not defined($trunkRepo) or $trunkRepo eq '' ) {
        print("ERROR: Config option trunk not defined.\n");
        return 0;
    }

    my $hasError = 0;

    my $checkoutRepo = $self->{repo};
    if ( $self->{checkoutByTag} ) {
        $checkoutRepo = $self->{svnTag};
    }
    my $ret = $self->checkout($checkoutRepo);

    my $hasError = 0;
    my $summary  = 0;

    my $checkSub = sub {
        my ($line) = @_;
        if ( $line =~ /^\s*U/ and $line !~ /^\s*U\s*\.\s*$/ ) {
            $hasError = 1;
        }
        elsif ( $line =~ /^\s*A/ and $line !~ /^\s*A\s*\.\s*$/ ) {
            $hasError = 1;
        }
        elsif ( $line =~ /Summary of conflicts/ ) {
            $summary = 1;
        }
        elsif ( $summary eq 1 and $line =~ /file conflict/i ) {
            $hasError = 1;
        }
    };

    #print("cd $prjPath && svn --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser --password $svnPass merge $trunkRepo");
    print("INFO:cd '$prjPath' && svn --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' merge '$trunkRepo'\n");
    my $output;
    eval {
        my $mergeCmd = "cd '$prjPath' && svn --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass merge '$trunkRepo'";
        my $execDesc = "cd '$prjPath' && svn --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password '******' merge '$trunkRepo'";

        $output = DeployUtils::handlePipeOut( $mergeCmd, $checkSub, 0, $execDesc );
    };
    if ($@) {
        $hasError = 1;
        print("ERROR:merge trunk to check if base line merged failed:$@\n");
    }

    if ( $hasError == 1 ) {
        print("ERROR: Version $version has not merge trunk modifications.\n");
        print("ERROR: 未从trunk合并最新代码，请合并至版本$version后再重新提交!\n");
    }

    $ret = DeployUtils::execmd("cd '$prjPath' && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass revert -R .");

    if ( $hasError == 1 ) {
        return 0;
    }
    else {
        return 1;
    }
}

sub mergeToBaseLine {
    my ($self) = @_;

    my $version   = $self->{version};
    my $isVerbose = $self->{isVerbose};

    my $autoexecHome = $self->{autoexecHome};
    my $prjPath      = $self->{prjPath};
    my $svnTrunkRepo = $self->{trunkRepo};
    my $svnTagsDir   = $self->{tagsDir};
    my $svnUser      = $self->{svnUser};
    my $svnPass      = $self->{svnPass};
    my $localSvnInfo = $self->{localSvnInfo};

    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    my $checkoutRepo = $self->{repo};
    if ( $self->{checkoutByTag} ) {
        $checkoutRepo = $self->{svnTag};
    }

    my $success = 1;

    if ( defined($svnTrunkRepo) and $svnTrunkRepo ne '' ) {
        my $ret = 0;

        $ret = $self->checkout($svnTrunkRepo);

        if ( $ret == 0 ) {
            $ret =
                DeployUtils::execmd(
"cd '$prjPath' && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass merge '$checkoutRepo' '$svnTrunkRepo' && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass commit -m 'merge $version'"
                );

            #auto tag
            if ( $ret == 0 ) {
                $ret = $self->checkout($checkoutRepo);
            }
            else {
                print("ERROR: Checkout $checkoutRepo failed.\n");
                $success = 0;
            }
        }
        else {
            print("ERROR: Checkout $svnTrunkRepo failed.\n");
        }

        if ( $ret ne 0 ) {
            $success = 0;
        }
    }
    else {
        print("ERROR: Config option trunk not defined, can not merge.\n");
        $success = 0;
    }

    return $success;
}

sub tag {
    my ( $self, $tagName, $tagPrefix ) = @_;

    my $checkoutRepo = $self->{repo};
    if ( $self->{checkoutByTag} ) {
        $checkoutRepo = $self->{svnTag};
    }

    my $ret = 1;

    if ( not defined($tagPrefix) or $tagPrefix eq '' ) {
        my $svnTag = $self->{svnTag};
        if ( defined($svnTag) and $svnTag ne '' ) {
            $ret = $self->tagRepo( $checkoutRepo, $svnTag, undef );
        }
        else {
            $ret = 0;
        }
    }
    else {
        my $tagsDir = $self->{tagsDir};
        if ( not defined($tagsDir) or $tagsDir ne '' ) {
            print("ERROR: Config option tagsDir not difined.\n");
        }
        else {
            $ret = $self->tagRepo( $checkoutRepo, $self->{tagsDir} . "/$tagPrefix$tagName", undef );
        }
    }

    my $success = 1;

    if ( $ret ne 0 ) {
        $success = 0;
    }

    return $success;
}

sub tagRev {
    my ( $self, $tagName, $tagPrefix, $tagRevision ) = @_;

    my $checkoutRepo = $self->{repo};
    if ( $self->{checkoutByTag} ) {
        $checkoutRepo = $self->{svnTag};
    }

    my $ret = 1;

    if ( not defined($tagPrefix) or $tagPrefix eq '' ) {
        my $svnTag = $self->{svnTag};
        if ( defined($svnTag) and $svnTag ne '' ) {
            $ret = $self->tagRepoRev( $checkoutRepo, $svnTag, undef );
        }
        else {
            $ret = 0;
        }
    }
    else {
        my $tagsDir = $self->{tagsDir};
        if ( not defined($tagsDir) or $tagsDir eq '' ) {
            print("ERROR: Config option tagsDir not difined.\n");
        }
        else {
            $ret = $self->tagRepoRev( $checkoutRepo, $self->{tagsDir} . "/$tagPrefix$tagName", $tagName, $tagRevision, undef );
        }
    }

    my $success = 1;

    if ( $ret ne 0 ) {
        $success = 1;
    }

    return $success;
}

sub checkChangedAfterCompiled {
    my ($self) = @_;

    my $verInfo = $self->{verInfo};
    my $repo    = $self->{repo};
    my $version = $self->{version};

    my $isVerbose = $self->{isVerbose};

    my $autoexecHome = $self->{autoexecHome};
    my $prjPath      = $self->{prjPath};
    my $svnUser      = $self->{svnUser};
    my $svnPass      = $self->{svnPass};
    my $endRev       = $verInfo->{endRev};

    my $checkoutRepo = $self->{repo};
    if ( $self->{checkoutByTag} ) {
        $checkoutRepo = $self->{svnTag};
    }

    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    my $success = 0;

    if ( defined($checkoutRepo) and $checkoutRepo ne '' ) {
        my $ret = 0;

        my $diffCountLines = DeployUtils::getPipeOut("svn --summarize --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass diff --old '$checkoutRepo\@$endRev' --new '$checkoutRepo' | wc -l");
        if ( $$diffCountLines[0] eq '0' ) {
            $success = 1;
            print("FINEST: Version:$version has no change after compiled, End Revision:$endRev.\n");
        }
        elsif ( $$diffCountLines[0] eq '1' ) {
            my $lines = DeployUtils::getPipeOut("svn --summarize --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass diff --old '$checkoutRepo\@$endRev' --new '$checkoutRepo'");
            my $line  = $$lines[0];
            if ( $line =~ /^\s*M\s+/ and $line =~ /\s+$checkoutRepo\s*$/ ) {
                $success = 1;
                print("WARN:$line\n");
            }
            else {
                print("WARN: Version:$version has been changed after compiled, End Revision:$endRev.\n");
                print("$line\n");
            }
        }
        else {
            print("WARN: Version:$version has been changed after compiled, End Revision:$endRev.\n");
            $ret = DeployUtils::execmd("svn --summarize --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass diff --old '$checkoutRepo\@$endRev' --new '$repo' | head -1000 2>&1");
            if ( $ret != 0 ) {
                print("WARN:diff $checkoutRepo revision range:$endRev..HEAD failed.\n");
            }
        }
    }
    else {
        print("ERROR:repo not defined.\n");
    }

    return $success;
}

sub getDiffByTag {
    my ( $self, $tagName, $excludeDirs, $diffSaveDir, $isVerbose ) = @_;
    $self->_getDiff( $tagName, undef, undef, $excludeDirs, $diffSaveDir, $isVerbose );
}

sub getDiffByRev {
    my ( $self, $startRev, $endRev, $excludeDirs, $diffSaveDir, $isVerbose ) = @_;
    $self->_getDiff( undef, $startRev, $endRev, $excludeDirs, $diffSaveDir, $isVerbose );
}

sub _getDiff {
    my ( $self, $tagName, $startRev, $endRev, $excludeDirs, $diffSaveDir, $isVerbose ) = @_;

    if ( not defined($endRev) ) {
        $endRev = 'HEAD';
    }

    my $repo = $self->{repo};

    my $autoexecHome = $self->{autoexecHome};
    my $prjPath      = $self->{prjPath};
    my $svnUser      = $self->{svnUser};
    my $svnPass      = $self->{svnPass};

    my $tagsDir  = $self->{tagsDir};
    my $baseRepo = $self->{trunkRepo};
    if ( defined($tagName) and $tagName ne '' ) {
        $baseRepo = "$tagsDir/$tagName";
    }

    my $delListFile  = "$diffSaveDir/diff-del-list.txt";
    my $diffListFile = "$diffSaveDir/diff-list.txt";

    my $delListFH;
    my $diffListFH;
    if ( defined($diffSaveDir) ) {
        if ( not -e $diffSaveDir ) {
            mkdir($diffSaveDir);
        }
        $delListFH  = IO::File->new(">$delListFile");
        $diffListFH = IO::File->new(">$diffListFile");

        if ( not defined($delListFH) ) {
            die("ERROR:Create $delListFile failed.\n");
        }
        if ( not defined($diffListFH) ) {
            die("ERROR:Create $diffListFile failed.\n");
        }
    }

    my $success = 1;

    my $startPos = 0;

    if ( defined($tagName) ) {
        $startPos = length($baseRepo);
        if ( $baseRepo !~ /\/$/ ) {
            $startPos = $startPos + 1;
        }
    }

    my $saveSub = sub {
        my ($line) = @_;
        if ( defined($diffSaveDir) and $line =~ /^([MDA].*?)\s+(.*)$/ ) {
            my $flag = $1;
            my $filePath = substr( $2, $startPos );

            if ( $isVerbose == 1 ) {
                print("$flag\t$filePath\n");
            }

            my $isExcluded = 0;
            foreach my $exdir (@$excludeDirs) {
                if ( $filePath =~ /^$exdir/ ) {
                    $isExcluded = 1;
                    last;
                }
            }

            if ( $isExcluded == 0 ) {
                if ( $flag =~ /^[MA]/ ) {
                    my $savePath = "$diffSaveDir/$filePath";
                    my $saveDir  = dirname($savePath);
                    if ( not -e $saveDir ) {
                        if ( not mkpath($saveDir) ) {
                            die("ERROR: mkpath $saveDir failed:$!\n");
                        }
                    }

                    if ( -f $filePath ) {
                        if ( not copy( $filePath, $savePath ) ) {
                            die("ERROR: copy $filePath to $savePath failed:$!\n");
                        }

                        if ( defined($diffListFH) ) {
                            if ( not print $diffListFH ( $filePath, "\n" ) ) {
                                die("ERROR: write $filePath to $diffListFile failed.");
                            }
                        }
                    }
                    elsif ( -d $filePath ) {
                        if ( not -e $savePath and not mkdir($savePath) ) {
                            die("ERROR: mkdir $savePath failed:$!\n");
                        }
                    }
                    elsif ( -l $filePath ) {
                        if ( not symlink( $savePath, readlink($filePath) ) ) {
                            die("ERROR: symlink $savePath to $filePath failed:$!\n");
                        }
                    }
                    elsif ( not -e $filePath ) {
                        die("ERROR: file $filePath not exits, check if the svn work copy have been updated.\n");
                    }
                }
                elsif ( $flag =~ /^D/ ) {
                    if ( defined($delListFH) ) {
                        if ( not print $delListFH ( $filePath, "\n" ) ) {
                            die("ERROR: write $filePath to $delListFile failed.");
                        }
                    }
                }
            }
        }
    };

    chdir($prjPath);

    #[app@techsure project]$ svn --summarize --no-auth-cache --non-interactive --trust-server-cert --config-dir /app/ezdeploy --username wenhb --password xxx diff --old 'svn://192.168.0.89/commander/tags/v1.0.0' --new 'svn://192.168.0.89/co
    #mmander/branches/1.0.0'
##D       svn://192.168.0.89/commander/branches/v1.0.0/build/classes
##M       svn://192.168.0.89/commander/branches/v1.0.0/build.properties
##A       svn://192.168.0.89/commander/branches/v1.0.0/test.txt
    my $diffCmd;
    my $execDesc;
    if ( defined($startRev) and $startRev ne '' ) {
        $diffCmd  = "cd '$prjPath' && svn --summarize --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass diff -r $startRev:$endRev";
        $execDesc = "cd '$prjPath' && svn --summarize --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password '******' diff -r $startRev:$endRev\n";
    }
    else {
        $diffCmd  = "cd '$prjPath' && svn --summarize --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass diff --new '$repo' --old '$baseRepo'";
        $execDesc = "cd '$prjPath' && svn --summarize --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password '******' diff --new '$repo' --old '$baseRepo'\n";
    }

    eval { DeployUtils::handlePipeOut( $diffCmd, $saveSub, 0, $execDesc ); };
    if ($@) {
        $success = 0;
        print( $@, "\n" );
    }

    if ( defined($delListFH) ) {
        $delListFH->close();
    }
    if ( defined($diffListFH) ) {
        $diffListFH->close();
    }

    return $success;
}

1;
