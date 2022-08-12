#!/usr/bin/perl
use strict;

package SVNVerGet;
use FindBin;
use File::Path;
use File::Copy;
use File::Basename;
use Cwd;
use URI::Escape;

use DeployUtils;

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

    my $repo    = $verInfo->{repo};
    my $trunk   = $verInfo->{trunk};
    my $branch  = $verInfo->{branch};
    my $tag     = $verInfo->{tag};
    my $tagsDir = $verInfo->{tagsDir};

    $repo    =~ s/\/+$//;
    $repo    =~ s/\{\{version\}\}/$version/g;
    $trunk   =~ s/^\/+|\/+$//g;
    $trunk   =~ s/\{\{version\}\}/$version/g;
    $branch  =~ s/^\/+|\/+$//g;
    $branch  =~ s/\{\{version\}\}/$version/g;
    $tag     =~ s/^\/+|\/+$//g;
    $tag     =~ s/\{\{version\}\}/$version/g;
    $tagsDir =~ s/^\/+|\/+$//g;
    $tagsDir =~ s/\{\{version\}\}/$version/g;

    $self->{checkoutByTag} = 0;
    if ( defined($tag) and $tag ne '' ) {
        $self->{checkoutByTag} = 1;
    }

    my $svnUser = $verInfo->{username};
    my $svnPass = $verInfo->{password};
    if ( defined($svnUser) ) {
        $svnUser = quotemeta($svnUser);
    }
    if ( defined($svnPass) ) {
        $svnPass = quotemeta($svnPass);
    }

    my $localSvnInfo = {};
    if ( -e $prjPath ) {
        $localSvnInfo = $self->getLocalSvnInfo($prjPath);
    }

    $self->{autoexecHome} = $autoexecHome;
    $self->{prjPath}      = $prjPath;
    $self->{svnUser}      = $svnUser;
    $self->{svnPass}      = $svnPass;
    $self->{repo}         = $repo;
    $self->{trunk}        = $trunk;
    $self->{branch}       = $branch;
    $self->{tag}          = $tag;
    $self->{tagsDir}      = $tagsDir;
    $self->{localSvnInfo} = $localSvnInfo;

    return $self;
}

sub getLocalSvnInfo {
    my ( $self, $localDir ) = @_;

    my $output = DeployUtils->getPipeOut("svn info $localDir 2>/dev/null");

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

    print("INFO: Begin to clean up unversioned files in working copy.\n");
    DeployUtils->handlePipeOut( "svn status '$prjPath'", $callback );
    print("INFO: Clean up unversioned files finished.\n");
}

sub checkout {
    my ( $self, $checkoutRepo ) = @_;

    my $autoexecHome = $self->{autoexecHome};
    my $prjPath      = $self->{prjPath};
    my $tagsDir      = $self->{tagsDir};
    my $trunk        = $self->{trunk};
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

    my $localSvnInfo = $self->getLocalSvnInfo($prjPath);

    if ( not defined( $localSvnInfo->{URL} ) ) {
        print("INFO: Checkout $checkoutRepo, it will take a few minutes, pleas wait...\n");
        rmtree($prjPath);

        print("DEBUG: svn --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser --password $svnPass co $checkoutRepo $prjPath\n");
        $ret = DeployUtils->execmd("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass co '$checkoutRepo' '$prjPath'");
    }
    elsif ( $checkoutRepo ne $localSvnInfo->{URL} ) {
        $self->cleanUp();
        print("INFO: Local copy url has been changed, switch to $checkoutRepo......\n");

        #print("svn --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser--password $svnPass switch $checkoutRepo $prjPath\n");
        $ret = DeployUtils->execmd("svn cleanup '$prjPath' && svn revert -R '$prjPath' && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass switch '$checkoutRepo' '$prjPath'");

        if ( $ret ne 0 ) {
            print("INFO: Checkout failed, clean the project directory will take a few minutes, please wait...\n");
            if ( -e $prjPath and rmtree($prjPath) == 0 ) {
                $ret = 3;
                print("ERROR:Remove directory $prjPath failed.\n");
            }
            else {
                mkdir($prjPath);
                print("INFO: Checkout again, it will take a few minutes, please wait...\n");

                #print("DEBUG: svn --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser --password $svnPass co $checkoutRepo $prjPath\n");
                $ret = DeployUtils->execmd("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass co '$checkoutRepo' '$prjPath'");
            }
        }
    }
    else {
        $self->cleanUp();
        print("INFO: Update $checkoutRepo......\n");

        #print("svn --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser--password $svnPass update $checkoutRepo\n");
        #print("cd $prjPath && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser --password $svnPass update .\n");
        $ret = DeployUtils->execmd("cd '$prjPath' && svn cleanup . && svn revert -R . && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass update .");

        if ( $ret ne 0 ) {
            print("INFO:Checkout failed, clean the project directory will take a few minutes, please wait...\n");
            if ( rmtree($prjPath) == 0 ) {
                $ret = 3;
                print("ERROR:remove directory $prjPath failed.\n");
            }
            else {
                mkdir($prjPath);
                print("INFO:Checkout again, it will take a few minutes, please wait...\n");

                #print("svn --no-auth-cache --non-interactive --trust-server-cert --config-dir $autoexecHome --username $svnUser --password $svnPass co $checkoutRepo $prjPath\n");
                $ret = DeployUtils->execmd("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass co '$checkoutRepo' '$prjPath'");
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
    my ( $self, $branchName, $tagName ) = @_;

    my $autoexecHome = $self->{autoexecHome};

    my $version = $self->{version};
    my $repo    = $self->{repo};
    my $branch  = $self->{branch};
    my $tag     = $self->{tag};

    if ( not defined($tagName) or $tagName eq '' ) {
        $tagName = $tag;
    }

    my $srcRepo = "$repo/$branchName";
    my $tagRepo = "$repo/$tagName";

    if ( $srcRepo eq $tagRepo ) {
        print("WARN: $srcRepo and $tagRepo is same, tag abort.\n");
        return 0;
    }

    my $svnUser = $self->{svnUser};
    my $svnPass = $self->{svnPass};

    my $isVerbose = $self->{isVerbose};
    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    my $ret = 0;

    print("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' rm  '$tagRepo' -m 'delete for autodeploy.'\n");
    $ret = DeployUtils->execmd("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass rm  '$tagRepo' -m 'delete for autodeploy.'");
    print("INFO: Remove $tagRepo failed, maybe $tagRepo no exist.\n") if ( $ret != 0 );

    print("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' cp --parents '$srcRepo' '$tagRepo'  -m 'copy for autodeploy.'\n");
    $ret = DeployUtils->execmd("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass cp --parents '$srcRepo' '$tagRepo'  -m 'copy for autodeploy.'");
    if ( $ret != 0 ) {
        print("ERROR: Create tag:$tagName $tagRepo -> $srcRepo failed.\n");
    }
    else {
        print("FINEST: Create tag:$tagName $tagRepo -> $srcRepo success.\n");
    }

    return $ret;
}

sub tagRepoRev {
    my ( $self, $branch, $tag, $version, $tagRevision ) = @_;

    if ( $branch eq $tag ) {
        print("WARN: branch:$branch and tag:$tag is same, tag abort.\n");
        return 0;
    }

    my $autoexecHome = $self->{autoexecHome};

    my $version = $self->{version};
    my $repo    = $self->{repo};
    my $tagsDir = $self->{tagsDir};

    my $svnUser = $self->{svnUser};
    my $svnPass = $self->{svnPass};

    my $isVerbose = $self->{isVerbose};
    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    my $tagName = $tag;
    if ( not defined($tag) or $tag eq '' and defined($version) and $version ne '' ) {
        if ( defined($tagsDir) and $tagsDir ne '' ) {
            $tagName = "$tagsDir/$version";
        }
    }

    my $svnTagsDir = "$repo/$tagsDir";
    my $srcRepo    = "$repo/$branch";
    my $tagRepo    = "$repo/$tagName";

    my $ret = 0;
    if ( defined($tagName) and $tagName ne '' ) {
        my $listtags = "svn --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass ls  '$svnTagsDir' ";
        $ret = DeployUtils->execmd($listtags);
        if ( $ret != 0 ) {
            my $createtagsdir = "svn --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass mkdir '$svnTagsDir' -m 'create tags dir for autodeploy'";
            print("WARN: tags dir $svnTagsDir does not exist, creating one.\n");
            $ret = DeployUtils->execmd($createtagsdir);
            if ( $ret != 0 ) {
                print("ERROR: creat tags dir $svnTagsDir failed, exiting.\n");
                return $ret;
            }
        }

        print("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' cp '$srcRepo\@$tagRevision' '$tagRepo'  -m 'copy for autodeploy.'\n");
        $ret = DeployUtils->execmd("svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass cp '$srcRepo\@$tagRevision' '$tagRepo'  -m 'copy for autodeploy.'");
        if ( $ret == 0 ) {
            print("FINEST: Create tag:$tagName $tagRepo -> $srcRepo success.\n");
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

    my $repo       = $self->{repo};
    my $tagsDir    = $self->{tagsDir};
    my $svnTagsDir = "$repo/$tagsDir";

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
    my $repo         = $self->{repo};
    my $branch       = $self->{branch};
    my $tag          = $self->{tag};
    my $svnUser      = $self->{svnUser};
    my $svnPass      = $self->{svnPass};

    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    my $ret = 0;

    my $checkoutRepo;
    if ( $self->{checkoutByTag} == 1 ) {
        print("INFO: Try to checkout repository:$repo tag:$tag...\n");
        $checkoutRepo = "$repo/$tag";
    }
    else {
        print("INFO: Try to checkout repository:$repo branch:$branch...\n");
        $checkoutRepo = "$repo/$branch";
    }

    $ret = $self->checkout($checkoutRepo);

    return $ret;
}

sub checkBaseLineMerged {
    my ($self) = @_;

    my $version   = $self->{version};
    my $isVerbose = $self->{isVerbose};

    my $autoexecHome = $self->{autoexecHome};
    my $prjPath      = $self->{prjPath};

    my $svnUser      = $self->{svnUser};
    my $svnPass      = $self->{svnPass};
    my $localSvnInfo = $self->{localSvnInfo};

    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    my $repo      = $self->{repo};
    my $trunk     = $self->{trunk};
    my $trunkRepo = "$repo/$trunk";

    if ( not defined($trunkRepo) or $trunkRepo eq '' ) {
        print("ERROR: Config option trunk not defined.\n");
        return 0;
    }

    my $hasError = 0;

    my $ret = $self->get();

    if ( $ret != 0 ) {

        #checkout failed
        return $ret;
    }

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

        $output = DeployUtils->handlePipeOut( $mergeCmd, $checkSub, 0, $execDesc );
    };
    if ($@) {
        $hasError = 1;
        print("ERROR: Merge trunk to check if base line merged failed:$@\n");
    }

    if ( $hasError == 1 ) {
        print("ERROR: Version $version has not merged trunk modifications.\n");
        print("ERROR: 未从trunk合并最新代码，请合并至版本$version后再重新提交!\n");
    }
    else {
        print("INFO: Version $version has merged trunk modifications.\n");
    }

    my $ret = DeployUtils->execmd("cd '$prjPath' && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass revert -R .");

    return $hasError;
}

sub mergeToBaseLine {
    my ($self) = @_;

    my $version   = $self->{version};
    my $isVerbose = $self->{isVerbose};

    my $repo         = $self->{repo};
    my $trunk        = $self->{trunk};
    my $branch       = $self->{branch};
    my $tag          = $self->{tag};
    my $autoexecHome = $self->{autoexecHome};
    my $prjPath      = $self->{prjPath};
    my $svnTagsDir   = $self->{tagsDir};
    my $svnUser      = $self->{svnUser};
    my $svnPass      = $self->{svnPass};
    my $localSvnInfo = $self->{localSvnInfo};

    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    my $checkoutRepo;
    if ( $self->{checkoutByTag} == 1 ) {
        $checkoutRepo = "$repo/$tag";
    }
    else {
        $checkoutRepo = "$repo/$branch";
    }

    my $ret          = 0;
    my $svnTrunkRepo = "$repo/$trunk";
    if ( defined($trunk) and $trunk ne '' ) {
        $ret = $self->checkout($svnTrunkRepo);

        if ( $ret == 0 ) {
            print("INFO: Merge $checkoutRepo -> $svnTrunkRepo\n");
            $ret =
                DeployUtils->execmd(
"cd '$prjPath' && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass merge '$checkoutRepo' '$svnTrunkRepo' && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass commit -m 'merge $version'"
                );
        }
        else {
            print("ERROR: Checkout $svnTrunkRepo failed.\n");
        }
    }
    else {
        $ret = 3;
        print("ERROR: Config option trunk not defined, can not merge.\n");
    }

    return $ret;
}

sub mergeBaseLine {
    my ($self) = @_;

    my $version   = $self->{version};
    my $isVerbose = $self->{isVerbose};

    my $repo         = $self->{repo};
    my $trunk        = $self->{trunk};
    my $branch       = $self->{branch};
    my $tag          = $self->{tag};
    my $autoexecHome = $self->{autoexecHome};
    my $prjPath      = $self->{prjPath};
    my $svnTagsDir   = $self->{tagsDir};
    my $svnUser      = $self->{svnUser};
    my $svnPass      = $self->{svnPass};
    my $localSvnInfo = $self->{localSvnInfo};

    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    my $checkoutRepo;
    if ( $self->{checkoutByTag} == 1 ) {
        $checkoutRepo = "$repo/$tag";
    }
    else {
        $checkoutRepo = "$repo/$branch";
    }

    my $ret          = 0;
    my $svnTrunkRepo = "$repo/$trunk";
    if ( defined($trunk) and $trunk ne '' ) {
        $ret = $self->checkout($checkoutRepo);

        if ( $ret == 0 ) {
            print("INFO: Merge $svnTrunkRepo -> $checkoutRepo\n");
            $ret =
                DeployUtils->execmd(
"cd '$prjPath' && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass merge '$svnTrunkRepo' '$checkoutRepo' && svn $silentOpt --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass commit -m 'merge $version to baseline'"
                );
        }
        else {
            print("ERROR: Checkout $checkoutRepo failed.\n");
        }
    }
    else {
        $ret = 3;
        print("ERROR: Config option trunk not defined, can not merge.\n");
    }

    return $ret;
}

sub tag {
    my ( $self, $version, $tagPrefix ) = @_;

    my $repo    = $self->{repo};
    my $trunk   = $self->{trunk};
    my $branch  = $self->{branch};
    my $tag     = $self->{tag};
    my $tagsDir = $self->{tagsDir};

    my $tagName;
    if ( defined($tagPrefix) and $tagPrefix ne '' ) {
        if ( not defined($tagsDir) or $tagsDir eq '' ) {
            print("ERROR: Config option tagsDir not difined.\n");
            return 3;
        }
        elsif ( defined($version) and $version ne '' ) {
            $tagName = "$tagsDir/$tagPrefix$version";
        }
        else {
            print("ERROR: Version number not defined.\n");
            return 3;
        }
    }
    else {
        $tagName = $tag;
    }

    if ( $tagName eq $branch ) {
        print("WARN: Tag:$tagName and branch:$branch is same, can not create tag.\n");
        return 0;
    }

    print("INFO: Create or replace tag:$tagName for branch:$branch.\n");
    my $ret = $self->tagRepo( $branch, $tagName );

    return $ret;
}

sub tagRev {
    my ( $self, $version, $tagPrefix, $tagRevision ) = @_;

    my $repo    = $self->{repo};
    my $trunk   = $self->{trunk};
    my $branch  = $self->{branch};
    my $tag     = $self->{tag};
    my $tagsDir = $self->{tagsDir};

    my $ret = 0;

    if ( not defined($tagPrefix) or $tagPrefix eq '' ) {
        if ( defined($tag) and $tag ne '' ) {
            if ( $tag eq $branch ) {
                print("WARN: Tag:$tag and branch:$branch is same, can not create tag.\n");
                return 0;
            }

            $ret = $self->tagRepoRev( $branch, $tag, undef );
        }
    }
    else {
        my $tagsDir = $self->{tagsDir};
        if ( not defined($tagsDir) or $tagsDir eq '' ) {
            print("ERROR: Config option tagsDir not difined.\n");
        }
        elsif ( defined($version) and $version ne '' ) {
            $ret = $self->tagRepoRev( $branch, "$tagsDir/$tagPrefix$version", $version, $tagRevision, undef );
        }
        else {
            print("ERROR: Version number not defined.\n");
            return 3;
        }
    }

    return $ret;
}

sub checkChangedAfterCompiled {
    my ($self) = @_;

    my $verInfo = $self->{verInfo};
    my $repo    = $self->{repo};
    my $trunk   = $self->{trunk};
    my $branch  = $self->{branch};
    my $tag     = $self->{tag};
    my $version = $self->{version};

    my $isVerbose = $self->{isVerbose};

    my $autoexecHome = $self->{autoexecHome};
    my $prjPath      = $self->{prjPath};
    my $svnUser      = $self->{svnUser};
    my $svnPass      = $self->{svnPass};
    my $endRev       = $verInfo->{endRev};

    my $newRepo;
    if ( defined($branch) and $branch ne '' ) {
        $newRepo = "$repo/$branch";
    }
    else {
        $newRepo = "$repo/$trunk";
    }

    my $checkoutRepo;
    if ( $self->{checkoutByTag} == 1 ) {
        $checkoutRepo = "$repo/$tag";
    }
    else {
        $checkoutRepo = "$repo/$branch";
    }

    my $silentOpt = '-q';
    $silentOpt = '' if ( defined($isVerbose) );

    my $ret = 1;

    if ( defined($checkoutRepo) and $checkoutRepo ne '' ) {
        print("INFO: Compare $checkoutRepo\@$endRev -> $newRepo\n");
        my $lines = DeployUtils->getPipeOut("svn --summarize --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass diff --old '$checkoutRepo\@$endRev' --new '$newRepo'");
        if ( scalar(@$lines) eq '0' ) {
            $ret = 0;
            print("FINEST: Version:$version has not changed after compiled, End Revision:$endRev.\n");
        }
        elsif ( scalar(@$lines) eq '1' ) {
            my $line = $$lines[0];
            if ( $line =~ /^\s*M\s+/ and $line =~ /\s+$checkoutRepo\s*$/ ) {
                $ret = 0;
                print("WARN:$line\n");
            }
            else {
                print("WARN: Version:$version has been changed after compiled, End Revision:$endRev.\n");
                print( join( "\n", @$lines ) );
                print("\n...\n");
            }
        }
        else {
            print("WARN: Version:$version has been changed after compiled, End Revision:$endRev.\n");
            print( join( "\n", @$lines ) );
            print("\n...\n");
        }
    }
    else {
        print("ERROR: SVN repository not defined.\n");
    }

    return $ret;
}

sub getDiffByTag {
    my ( $self, $tagName, $excludeDirs, $diffSaveDir, $isVerbose ) = @_;
    return $self->_getDiff( $tagName, undef, undef, $excludeDirs, $diffSaveDir, $isVerbose );
}

sub getDiffByRev {
    my ( $self, $startRev, $endRev, $excludeDirs, $diffSaveDir, $isVerbose ) = @_;
    return $self->_getDiff( undef, $startRev, $endRev, $excludeDirs, $diffSaveDir, $isVerbose );
}

sub _getDiff {
    my ( $self, $tagName, $startRev, $endRev, $excludeDirs, $diffSaveDir, $isVerbose ) = @_;

    if ( not defined($endRev) ) {
        $endRev = 'HEAD';
    }

    my $repo    = $self->{repo};
    my $trunk   = $self->{trunk};
    my $branch  = $self->{branch};
    my $tag     = $self->{tag};
    my $tagsDir = $self->{tagsDir};

    my $autoexecHome = $self->{autoexecHome};
    my $prjPath      = $self->{prjPath};
    my $svnUser      = $self->{svnUser};
    my $svnPass      = $self->{svnPass};

    my $checkoutRepo;
    if ( $self->{checkoutByTag} == 1 ) {
        $checkoutRepo = "$repo/$tag";
    }
    else {
        $checkoutRepo = "$repo/$branch";
    }

    my $baseRepo = "$repo/$trunk";
    if ( defined($tagName) and $tagName ne '' ) {
        $baseRepo = "$repo/$tagsDir/$tagName";
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

    my $ret = 0;

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
            my $flag     = $1;
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
                        if ( not File::Copy::cp( $filePath, $savePath ) ) {
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
        $diffCmd  = "cd '$prjPath' && svn --summarize --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass diff --new '$checkoutRepo' --old '$baseRepo'";
        $execDesc = "cd '$prjPath' && svn --summarize --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password '******' diff --new '$checkoutRepo' --old '$baseRepo'\n";
    }

    eval { DeployUtils->handlePipeOut( $diffCmd, $saveSub, 0, $execDesc ); };
    if ($@) {
        $ret = 1;
        print( $@, "\n" );
    }

    if ( defined($delListFH) ) {
        $delListFH->close();
    }
    if ( defined($diffListFH) ) {
        $diffListFH->close();
    }

    return $ret;
}

sub compare {
    my ( $self, $callback, $tagName, $startRev, $endRev, $excludeDirs, $isVerbose ) = @_;

    if ( not defined($endRev) ) {
        $endRev = 'HEAD';
    }

    my $repo    = $self->{repo};
    my $trunk   = $self->{trunk};
    my $branch  = $self->{branch};
    my $tag     = $self->{tag};
    my $tagsDir = $self->{tagsDir};

    my $autoexecHome = $self->{autoexecHome};
    my $prjPath      = $self->{prjPath};
    my $svnUser      = $self->{svnUser};
    my $svnPass      = $self->{svnPass};

    my $checkoutRepo;
    if ( $self->{checkoutByTag} == 1 ) {
        $checkoutRepo = "$repo/$tag";
    }
    else {
        $checkoutRepo = "$repo/$branch";
    }

    my $baseRepo = "$repo/$trunk";
    if ( defined($tagName) and $tagName ne '' ) {
        $baseRepo = "$repo/$tagsDir/$tagName";
    }

    my $ret = 0;

    my $startPos = 0;

    if ( defined($tagName) ) {
        $startPos = length($baseRepo);
        if ( $baseRepo !~ /\/$/ ) {
            $startPos = $startPos + 1;
        }
    }

    my $saveSub = sub {
        my ($line) = @_;

        if ( $line =~ /^([MDA])\s+(.+)$/ ) {
            my $flag     = $1;
            my $filePath = substr( $2, $startPos );

            my $isExcluded = 0;
            foreach my $exdir (@$excludeDirs) {
                if ( $filePath =~ /^$exdir/ ) {
                    $isExcluded = 1;
                    last;
                }
            }

            if ( $isExcluded == 0 and defined($callback) ) {
                &$callback("$flag $filePath");
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
        $diffCmd  = "cd '$prjPath' && svn --summarize --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password $svnPass diff --new '$checkoutRepo' --old '$baseRepo'";
        $execDesc = "cd '$prjPath' && svn --summarize --no-auth-cache --non-interactive --trust-server-cert --config-dir '$autoexecHome' --username '$svnUser' --password '******' diff --new '$checkoutRepo' --old '$baseRepo'\n";
    }

    eval { DeployUtils->handlePipeOut( $diffCmd, $saveSub, 0, $execDesc ); };
    if ($@) {
        $ret = 1;
        print( $@, "\n" );
    }

    return $ret;
}

1;
