#!/usr/bin/perl
use FindBin;

package GITVerGet;

use strict;
use DeployUtils;
use File::Path;
use File::Copy;
use File::Basename;
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

    $self->{version}    = $version;
    $self->{verInfo}    = $verInfo;
    $self->{repoType}   = 'git';
    $self->{pwdPattern} = '(?<=\/\/).+?:.*?\@';

    my $silentOpt = '-q';
    if ( defined($isVerbose) ) {
        $silentOpt = '';
    }
    $self->{silentOpt} = $silentOpt;

    my $repo     = $verInfo->{repo};
    my $repoDesc = $repo;
    $repoDesc =~ s/$self->{pwdPattern}//;
    $self->{repoDesc} = $repoDesc;

    my $gitUser = $verInfo->{username};
    my $gitPass = $verInfo->{password};

    if ( defined($gitUser) ) {
        $gitUser = quotemeta($gitUser);
    }
    if ( defined($gitPass) ) {
        $gitPass = quotemeta($gitPass);
    }

    #$repo =~ s/^https:\/\//https:\/\/$gitUser:$gitPass\@/;
    #$repo =~ s/^http:\/\//http:\/\/$gitUser:$gitPass\@/;

    my $confGitBranch = $verInfo->{branch};
    my $gitBranch     = $confGitBranch;
    if ( defined($gitBranch) and $gitBranch ne '' ) {
        $gitBranch =~ s/\{\{version\}\}/$version/g;
    }
    if ( $confGitBranch eq $gitBranch ) {
        $self->{isStatic} = 1;
    }
    else {
        $self->{isStatic} = 0;
    }

    $self->{checkoutByTag} = 0;
    my $confGitTag = $verInfo->{tag};
    my $gitTag     = $confGitTag;
    if ( defined($gitTag) and $gitTag ne '' ) {
        $gitTag =~ s/\{\{version\}\}/$version/g;
        $self->{checkoutByTag} = 1;
    }
    if ( $confGitTag eq $gitTag ) {
        $self->{isStatic} = 1;
    }
    else {
        $self->{isStatic} = 0;
    }

    my $gitMasterBranch = $verInfo->{trunk};

    $self->{prjPath}         = $prjPath;
    $self->{gitBranch}       = $gitBranch;
    $self->{gitTag}          = $gitTag;
    $self->{gitMasterBranch} = $gitMasterBranch;
    $self->{gitUser}         = $gitUser;
    $self->{gitPass}         = $gitPass;
    $self->{repo}            = $repo;

    if ( -f "$prjPath/.git/index.lock" ) {
        unlink("$prjPath/.git/index.lock");
    }

    if ( not -e $prjPath ) {
        mkpath($prjPath);
    }

    $ENV{GIT_USER}    = $gitUser;
    $ENV{GIT_PWD}     = $gitPass;
    $ENV{GIT_ASKPASS} = 'git-askpass';

    $self->setGitEnv();

    return $self;
}

sub setGitEnv {
    my ($self) = @_;

    my $toolsPath = $ENV{TOOLS_PATH};
    my $gitHome   = "$toolsPath/git";
    $ENV{LD_LIBRARY_PATH}   = "$gitHome/lib64:" . $ENV{LD_LIBRARY_PATH};
    $ENV{PATH}              = "$gitHome/bin:" . "$gitHome/libexec/git-core:" . $ENV{PATH};
    $ENV{GIT_SSL_NO_VERIFY} = 'true';

    my $gitUser = $self->{gitUser};
    my $gitPass = $self->{gitPass};
    my $repo    = $self->{repo};
}

sub tagRepo {
    my ( $self, $branchName, $tagName ) = @_;

    if ( $branchName eq $tagName ) {
        print("WARN:tag:$tagName and branch:$branchName is same, tag abort.\n");
        return 0;
    }

    my $repo    = $self->{repo};
    my $prjPath = $self->{prjPath};

    my $repoDesc = $self->{repoDesc};

    my $ret = 0;

    if ( not defined($branchName) or $branchName eq '' ) {
        print("ERROR: BranchName not defined, can not create tag:$tagName.\n");
        $ret = -1;
    }
    else {
        print("INFO: Create or replace tag $tagName for branch:$branchName\n");
        $ret = DeployUtils->execmd( "cd '$prjPath' && git checkout '$branchName' && git reset --hard 'origin/$branchName' && git pull --tags", $self->{pwdPattern} );
        if ( $ret != 0 ) {
            print("ERROR: Checkout $repoDesc branch:$branchName failed.\n");
            return $ret;
        }

        my $tags = $self->getTags($tagName);

        if ( defined( $tags->{$tagName} ) ) {
            print("INFO: Delete tag:$tagName for branch:$branchName.\n");
            $ret = DeployUtils->execmd( "cd '$prjPath' && git tag -d '$tagName' && git push origin ':refs/tags/$tagName'", $self->{pwdPattern} );
            if ( $ret != 0 ) {
                print("ERROR: Delete tag $tagName for branch:$branchName failed.\n");
                return $ret;
            }
        }

        if ( $branchName ne $tagName ) {
            $ret = DeployUtils->execmd( "cd '$prjPath' && git tag '$tagName' && git push origin --tags", $self->{pwdPattern} );
            if ( $ret != 0 ) {
                print("ERROR: Create $tagName of $repoDesc branch:$branchName failed.\n");
            }
            else {
                print("FINEST: Create tag:$tagName of $repoDesc branch:$branchName success.\n");
            }
        }
        else {
            print("WARN: Tag:$tagName and branche:$branchName is same, abort.\n");
        }
    }

    return $ret;
}

sub getTags {
    my ( $self, $tagPrefix ) = @_;
    my $prjPath = $self->{prjPath};

    my $tags = {};
    my $fh;
    open( $fh, "cd '$prjPath'&& git tag |" )
        or die "ERROR:get tag list failed:$!";
    if ( defined($tagPrefix) ) {
        while ( my $line = <$fh> ) {
            $line =~ s/%\s*//;
            $line =~ s/\s*$//;
            if ( $line =~ /^$tagPrefix/ ) {
                $tags->{$line} = 1;
            }
        }
    }
    else {
        while ( my $line = <$fh> ) {
            $line =~ s/%\s*//;
            $line =~ s/\s*$//;
            $tags->{$line} = 1;
        }
    }

    close($fh);

    return $tags;
}

sub getBranches {
    my ($self) = @_;
    my $prjPath = $self->{prjPath};

    my $branches = {};
    my $fh;
    open( $fh, "cd '$prjPath'; git branch -r |" )
        or die "ERROR:get branche list failed:$!";
    while ( my $line = <$fh> ) {
        $line =~ s/^.*origin\///;
        $line =~ s/\s+.*?$//;
        $branches->{$line} = 1;
    }
    close($fh);

    return $branches;
}

sub fetch {
    my ($self) = @_;

    my $repo     = $self->{repo};
    my $repoDesc = $self->{repoDesc};
    my $prjPath  = $self->{prjPath};
    my $gitUser  = $self->{gitUser};

    my $silentOpt = $self->{silentOpt};

    my $ret = 0;
    if ( not -e "$prjPath/.git" ) {
        $self->{newWorkingCopy} = 1;
        print("INFO: git clone $silentOpt '$repoDesc' '$prjPath'\n");
        $ret = DeployUtils->execmd( "git clone $silentOpt '$repo' $prjPath", $self->{pwdPattern} );
    }
    else {
        print("INFO: cd '$prjPath' && git remote set-url origin $repoDesc\n");
        $ret = DeployUtils->execmd("cd '$prjPath' && git remote set-url origin '$repo'");
        if ( $ret != 0 ) {
            $ret = -1;
            print("ERROR: Switch remote url for $prjPath failed.\n");
        }
        else {
            $ret = DeployUtils->execmd( "cd '$prjPath' && git reset --hard && git clean -fd && git tag | xargs git tag -d >/dev/null && git fetch -q", $self->{pwdPattern} );
        }
    }

    if ( $ret ne 0 ) {
        print("WARN: Fetch failed, clean local repo and fetch again...\n");
        if ( -e $prjPath and rmtree($prjPath) == 0 ) {
            print("ERROR: Remove directory $prjPath failed.\n");
            $ret = -1;
        }
        else {
            mkdir($prjPath);
            $self->{newWorkingCopy} = 1;
            $ret = DeployUtils->execmd( "git clone $silentOpt '$repo' '$prjPath'", $self->{pwdPattern} );
        }
    }

    if ( $ret eq 0 ) {
        DeployUtils->execmd("cd '$prjPath' && git config user.name '$gitUser'");
        DeployUtils->execmd("cd '$prjPath' && git config user.email '$gitUser\@techsure.com.cn'");
        print("FINEST: fetch $repoDesc success.\n");
    }

    return $ret;
}

sub checkout {
    my ( $self, $version, $noPull ) = @_;

    my $prjPath      = $self->{prjPath};
    my $branchName   = $self->{gitBranch};
    my $tagName      = $self->{gitTag};
    my $masterBranch = $self->{gitMasterBranch};

    my $silentOpt = $self->{silentOpt};

    my $repoDesc = $self->{repoDesc};

    my $ret = 0;
    $ret = $self->fetch();

    if ( $ret eq 0 ) {
        my $startRev = 0;
        my $verInfo  = $self->{verInfo};
        if ( defined($verInfo) ) {
            $startRev = $verInfo->{startRev};
            if ( not defined($startRev) ) {
                $startRev = 0;
            }
            $verInfo->{startRev} = $startRev;
        }

        my $tags     = $self->getTags();
        my $branches = $self->getBranches();

        my $checkoutByTag = $self->{checkoutByTag};
        if ( $checkoutByTag == 1 ) {

            #if ( $self->{isStatic} == 0 and defined($masterBranch) and $masterBranch ne '' ){
            #    my $lines = DeployUtils->getPipeOut("cd '$prjPath' && git merge-base --fork-point '$branchName' '$masterBranch'");
            #    $startRev = $$lines[0];
            #    $self->{startRev} = $startRev;
            #}
            if ( defined( $tags->{$tagName} ) ) {
                $ret = DeployUtils->execmd("cd '$prjPath' && git checkout '$tagName'");
            }
            else {
                $ret = -1;
                print("ERROR: Tag:$tagName for $repoDesc not exists, checkout failed.\n");
            }
        }
        else {
            #if ( $self->{isStatic} == 0 and defined($masterBranch) and $masterBranch ne '' ){
            #    my $lines = DeployUtils->getPipeOut("cd '$prjPath' && git merge-base --fork-point '$tagName' '$masterBranch'");
            #    $startRev = $$lines[0];
            #    $self->{startRev} = $startRev;
            #}
            if ( defined( $branches->{$branchName} ) ) {
                if ( defined($noPull) ) {
                    $ret = DeployUtils->execmd("cd '$prjPath' && git checkout '$branchName' && git reset --hard 'origin/$branchName'");
                }
                else {
                    $ret = DeployUtils->execmd( "cd '$prjPath' && git checkout '$branchName' && git reset --hard 'origin/$branchName' && git pull --tags", $self->{pwdPattern} );
                }
            }
            else {
                $ret = -1;
                print("ERROR: Branch:$branchName for $repoDesc not exists, checkout failed.\n");
            }
        }

        eval {
            my $lines  = DeployUtils->getPipeOut("cd '$prjPath' && git rev-parse HEAD");
            my $endRev = $$lines[0];
            if ( defined($verInfo)
                and $verInfo->{endRev} ne $endRev )
            {
                $self->{needUpdateVerInfo} = 1;
                $verInfo->{endRev}         = $endRev;
            }
        };
        if ($@) {
            print("ERROR: Checkout faield, $@\n");
        }
    }

    return $ret;
}

sub get {
    my ($self) = @_;

    my $version = $self->{version};

    my $autoTag = 1;
    my $ret     = $self->checkout($version);

    return $ret;
}

sub mergeToBaseLine {
    my ($self) = @_;

    my $version   = $self->{version};
    my $silentOpt = $self->{silentOpt};

    my $prjPath      = $self->{prjPath};
    my $gitBranch    = $self->{gitBranch};
    my $gitTag       = $self->{gitTag};
    my $masterBranch = $self->{gitMasterBranch};

    my $repoDesc = $self->{repoDesc};

    my $ret = $self->fetch();

    if ( $ret eq 0 ) {
        my $tags     = $self->getTags();
        my $branches = $self->getBranches();

        my $tagOrBranchToBeMerged = $gitBranch;
        if ( $self->{checkoutByTag} == 1 ) {
            $tagOrBranchToBeMerged = $gitTag;
        }

        if ( not defined($masterBranch) or $masterBranch eq '' ) {
            print("WANR: Git masterBranch not defined, can not auto merge and tag.\n");
        }
        else {
            print("INFO: Merge $tagOrBranchToBeMerged -> $masterBranch.\n");

            $ret = DeployUtils->execmd( "cd '$prjPath' && git checkout '$masterBranch' && git reset --hard 'origin/$masterBranch' && git pull --tags", $self->{pwdPattern} );
            if ( $ret != 0 ) {
                print("ERROR: Checkout $repoDesc branch $masterBranch failed.\n");
            }
            else {
                print("INFO: Try to merge $tagOrBranchToBeMerged to $masterBranch...\n");
                $ret = DeployUtils->execmd( "cd '$prjPath' && git merge '$tagOrBranchToBeMerged' && git push $silentOpt", $self->{pwdPattern} );
                if ( $ret != 0 ) {
                    DeployUtils->execmd("cd '$prjPath' && git reset --hard HEAD");
                    print("ERROR: Merge $repoDesc $tagOrBranchToBeMerged to branch $masterBranch failed.\n");
                }
            }
        }
    }

    return $ret;
}

sub mergeBaseLine {
    my ($self) = @_;

    my $version   = $self->{version};
    my $silentOpt = $self->{silentOpt};

    my $prjPath      = $self->{prjPath};
    my $gitBranch    = $self->{gitBranch};
    my $gitTag       = $self->{gitTag};
    my $masterBranch = $self->{gitMasterBranch};

    my $repoDesc = $self->{repoDesc};

    my $checkoutName = $gitBranch;
    if ( $self->{checkoutByTag} == 1 ) {
        print("WARN: Version checkout by tag:$gitTag, can not merge base line changes.\n");
        return 3;
    }

    my $ret = $self->fetch();

    if ( $ret eq 0 ) {
        my $tags     = $self->getTags();
        my $branches = $self->getBranches();

        if ( not defined($masterBranch) or $masterBranch eq '' ) {
            print("WANR: Git masterBranch not defined, can not auto merge and tag.\n");
        }
        else {
            print("INFO: Merge $masterBranch -> $checkoutName.\n");

            $ret = DeployUtils->execmd( "cd '$prjPath' && git checkout '$checkoutName' && git reset --hard 'origin/$checkoutName' && git pull --tags", $self->{pwdPattern} );
            if ( $ret != 0 ) {
                print("ERROR: Checkout $repoDesc branch $checkoutName failed.\n");
            }
            else {
                print("INFO: Try to merge masterBranch to $checkoutName...\n");
                $ret = DeployUtils->execmd( "cd '$prjPath' && git merge '$masterBranch' && git push $silentOpt", $self->{pwdPattern} );
                if ( $ret != 0 ) {
                    DeployUtils->execmd("cd '$prjPath' && git reset --hard HEAD");
                    print("ERROR: Merge $repoDesc branch:$masterBranch to branch:$checkoutName failed.\n");
                }
            }
        }
    }

    return $ret;
}

sub checkBaseLineMerged {
    my ($self) = @_;

    my $version = $self->{version};

    my $prjPath      = $self->{prjPath};
    my $masterBranch = $self->{gitMasterBranch};

    my $repoDesc = $self->{repoDesc};

    print("INFO:Check if version $version has merged the master branch:$masterBranch\'s modification.\n");
    my $ret = 0;

    if ( not defined($masterBranch) or $masterBranch eq '' ) {
        print("WANR: Git masterBranch not defined, can not check base line merged.\n");
    }
    else {
        $ret = $self->checkout($masterBranch);
        if ( $ret == 0 ) {
            my $srcBranch = $self->{gitBranch};
            if ( $self->{checkoutByTag} == 1 ) {
                $srcBranch = $self->{gitTag};
            }

            $ret = $self->checkout( $version, 1 );
            if ( $ret == 0 ) {
                print("INFO: Check merge for: $srcBranch <- $masterBranch\n");

                #print("INFO:cd $prjPath && git merge --no-commit --no-ff $masterBranch\n");
                $ret = DeployUtils->execmd("cd '$prjPath' && git merge --no-commit --no-ff '$masterBranch'");

                if ( $ret == 0 ) {

                    #print("INFO:cd $prjPath && git diff --cached | wc -l\n");
                    my $lines = DeployUtils->getPipeOut("cd '$prjPath' && git diff --stat-count 100 --cached 2>&1");

                    if ( scalar(@$lines) > 0 ) {
                        print( join( "\n", @$lines ) );
                        print("\n...\n");
                        $ret = 3;
                        DeployUtils->execmd("cd $prjPath && git diff --stat --cached");

                        #print("INFO:cd $prjPath && git merge --abort\n");
                        my $rstRet = DeployUtils->execmd("cd '$prjPath' && git merge --abort");
                        print("ERROR: Version $version has not merge master branch:$masterBranch modifications.\n");
                        print("ERROR: 未从master分支:$masterBranch合并最新代码，请合并至版本$version后再重新提交!\n");
                    }
                }
                else {
                    print("ERROR: Test merge $repoDesc $masterBranch to $version failed.\n");
                    my $rstRet = DeployUtils->execmd("cd '$prjPath' && git reset --hard");
                    if ( $rstRet ne 0 ) {
                        print("ERROR: Reset merge failed.\n");
                    }
                }
            }
        }
    }

    return $ret;
}

sub tag {
    my ( $self, $version, $tagPrefix ) = @_;

    my $branchName = $self->{gitBranch};
    my $tag        = $self->{gitTag};

    my $tagName = $tag;
    if ( defined($tagPrefix) and $tagPrefix ne '' ) {
        $tagName = "$tagPrefix$version";
    }

    if ( $tagName eq $branchName ) {
        print("WARN: Tag:$tagName and branch:$branchName is same, abort.\n");
        return 1;
    }

    print("INFO: Create or replace tag:$tagName for $branchName.\n");

    my $ret  = $self->fetch();
    my $tags = {};
    if ( $ret eq 0 ) {
        $tags = $self->getTags();
    }

    if ( $ret eq 0 and not defined( $tags->{$branchName} ) ) {
        $ret = $self->tagRepo( $branchName, $tagName );
    }
    else {
        print("WARN: Config branch:$branchName is a tag, create tag:$tagName for $branchName abort.\n");
    }

    return $ret;
}

sub checkChangedAfterCompiled {
    my ($self) = @_;

    my $version  = $self->{version};
    my $prjPath  = $self->{prjPath};
    my $repoDesc = $self->{repoDesc};

    my $verInfo = $self->{verInfo};
    my $endRev  = $verInfo->{endRev};

    my $ret  = $self->fetch();
    my $tags = $self->getTags();

    if ( $ret eq 0 ) {
        my $checkoutName;
        if ( $self->{checkoutByTag} == 1 ) {
            $checkoutName = $self->{gitTag};
            $checkoutName = "tags/$checkoutName";
        }
        else {
            $checkoutName = $self->{gitBranch};
            $checkoutName = "origin/$checkoutName";
        }

        print("INFO: Compare revision:$endRev -> $checkoutName\n");
        my $outLines = DeployUtils->getPipeOut("cd '$prjPath' && git diff --stat-count 100 --stat $endRev '$checkoutName'  2>&1");
        my $hasDiff  = 0;
        foreach my $line (@$outLines) {
            if ( $line ne '' ) {
                $hasDiff = 1;
                print( $line, "\n" );
            }
        }
        if ( scalar(@$outLines) > 0 ) {
            print("...\n");
        }

        if ( $hasDiff == 1 ) {
            print("ERROR: Version:$version has been changed after compiled at revision:$endRev.\n");
            $ret = 2;
        }
        else {
            print("INFO: Version:$version not changed after copmpiled at revision:$endRev.\n");
        }
    }

    return $ret;
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

    my $repo      = $self->{repo};
    my $version   = $self->{version};
    my $gitBranch = $self->{gitBranch};

    my $prjPath   = $self->{prjPath};
    my $silentOpt = $self->{silentOpt};

    my $repoDesc = $self->{repoDesc};

    my $gitMasterBranch = $self->{gitMasterBranch};

    my $baseName = "origin/$gitMasterBranch";
    if ( defined($tagName) and $tagName ne '' ) {
        my $tags = $self->getTags();
        if ( defined( $tags->{$tagName} ) ) {
            $baseName = "tags/$tagName";
        }
        else {
            $baseName = "origin/$tagName";
        }
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

    my $saveSub = sub {
        my ($line) = @_;

        if ( defined($diffSaveDir) and $line =~ /^([MDA].*?)\s+(.+)$/ ) {
            my $flag     = $1;
            my $filePath = $2;

            my $isExcluded = 0;
            foreach my $exdir (@$excludeDirs) {
                if ( $filePath =~ /^$exdir/ ) {
                    $isExcluded = 1;
                    last;
                }
            }

            if ( $isExcluded == 0 ) {
                if ( $isVerbose == 1 ) {
                    print("$flag\t$filePath\n");
                }

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
                        if ( not mkdir($savePath) ) {
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

    #[app@prd_demo_26 project]$ git diff --name-status origin/oldbase..origin/1.0.0
    #M       build.xml
    #D       db/master/bsm.root/1.dml.select.sql
    #D       db/master/bsm.root/2.dml.update.sql
    #D       db/master/bsm.root/pre/1.pre.dml.select.sql
    #D       db/master/bsm.root/pre/2.pre.dml.update.sql
    #M       pom.xml
    #A       test.sh
    if ( $ret eq 0 ) {
        my $diffCmd;
        if ( defined($startRev) and $startRev ne '' ) {
            $diffCmd = "cd '$prjPath' && git config core.quotepath false && git diff --name-status $startRev..$endRev";
        }
        else {
            $diffCmd = "cd '$prjPath' && git config core.quotepath false && git diff --name-status $baseName..HEAD";
        }

        if ( defined($diffCmd) ) {
            eval { DeployUtils->handlePipeOut( $diffCmd, $saveSub ); };
            if ($@) {
                $ret = 3;
                print( $@, "\n" );
            }
        }
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

    my $repo      = $self->{repo};
    my $version   = $self->{version};
    my $gitBranch = $self->{gitBranch};

    my $prjPath   = $self->{prjPath};
    my $silentOpt = $self->{silentOpt};

    my $repoDesc = $self->{repoDesc};

    my $gitMasterBranch = $self->{gitMasterBranch};

    my $baseName = "origin/$gitMasterBranch";
    if ( defined($tagName) and $tagName ne '' ) {
        my $tags = $self->getTags();
        if ( defined( $tags->{$tagName} ) ) {
            $baseName = "tags/$tagName";
        }
        else {
            $baseName = "origin/$tagName";
        }
    }

    my $ret = 0;

    my $saveSub = sub {
        my ($line) = @_;

        if ( $line =~ /^([MDA])\s+(.+)$/ ) {
            my $flag     = $1;
            my $filePath = $2;

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

    #[app@prd_demo_26 project]$ git diff --name-status origin/oldbase..origin/1.0.0
    #M       build.xml
    #D       db/master/bsm.root/1.dml.select.sql
    #D       db/master/bsm.root/2.dml.update.sql
    #D       db/master/bsm.root/pre/1.pre.dml.select.sql
    #D       db/master/bsm.root/pre/2.pre.dml.update.sql
    #M       pom.xml
    #A       test.sh
    if ( $ret eq 0 ) {
        my $diffCmd;
        if ( defined($startRev) and $startRev ne '' ) {
            $diffCmd = "cd '$prjPath' && git config core.quotepath false && git diff --name-status $startRev..$endRev";
        }
        else {
            $diffCmd = "cd '$prjPath' && git config core.quotepath false && git diff --name-status $baseName..HEAD";
        }

        if ( defined($diffCmd) ) {
            eval { DeployUtils->handlePipeOut( $diffCmd, $saveSub ); };
            if ($@) {
                $ret = 3;
                print( $@, "\n" );
            }
        }
    }

    return $ret;
}
1;

