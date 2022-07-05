#!/usr/bin/perl
use strict;

package DeployLock;
use JSON;

use ServerAdapter;

our $READ  = 'read';
our $WRITE = 'write';

#调用autoexec的ListenThread，进行作业层次的Lock和unlock
#参数，jobId，lockTarget
sub new {
    my ( $pkg, $deployEnv ) = @_;
    my $self = {};
    bless( $self, $pkg );
    $self->{deployEnv} = $deployEnv;

    my $jobId = $ENV{AUTOEXEC_JOBID};
    $self->{jobId} = $jobId;
    my $workPath = $ENV{AUTOEXEC_WORK_PATH};
    $self->{workPath} = $workPath;
    my $sockPath = $workPath . '/job.sock';
    $self->{sockPath} = $sockPath;

    my $devMode = $ENV{DEV_MODE};
    if ( not defined($devMode) ) {
        $devMode = 0;
    }
    else {
        $devMode = int($devMode);
    }

    $self->{devMode} = $devMode;

    return $self;
}

sub _getParams {
    my ($self) = @_;

    my $jobId     = $self->{jobId};
    my $deployEnv = $self->{deployEnv};

    my $sysId      = $deployEnv->{SYS_ID};
    my $moduleId   = $deployEnv->{MODULE_ID};
    my $envId      = $deployEnv->{ENV_ID};
    my $sysName    = $deployEnv->{SYS_NAME};
    my $moduleName = $deployEnv->{MODULE_NAME};
    my $version    = $deployEnv->{VERSION};
    my $buildNo    = $deployEnv->{BUILD_NO};

    my $params = {
        jobId         => $jobId,
        lockOwner     => "$sysId/$moduleId",
        lockOwnerName => "$sysName/$moduleName",
        operType      => 'deploy',
        sysId         => $sysId,
        moduleId      => $moduleId,
        envId         => $envId,
        version       => $version,
        buildNo       => $buildNo
    };

    return $params;
}

sub _doLockByJob {
    my ( $self, $params ) = @_;

    my $lockRetObj;

    if ( $self->{devMode} ) {
        return { lockId => 0 };
    }

    my $sockPath = $self->{sockPath};

    my $lockAction = $params->{action};
    my $lockTarget = $params->{lockTarget};
    my $lockMode   = $params->{lockMode};
    my $namePath   = $params->{lockOwnerName};

    if ( -e $sockPath ) {
        my $localAddr = $self->{workPath} . "/client$$.sock";

        END {
            unlink($localAddr);
        }

        eval {
            my $client = IO::Socket::UNIX->new(
                Local   => $localAddr,
                Peer    => $sockPath,
                Type    => IO::Socket::SOCK_DGRAM,
                Timeout => 10
            );

            my $request = {};
            $request->{action}     = 'golbalLock';
            $request->{lockParams} = $params;

            $client->send( to_json($request) );

            my $lockRet;
            $client->recv( $lockRet, 1024 );
            $client->close();
            $lockRetObj = from_json($lockRet);
            unlink($localAddr);
        };
        if ($@) {
            unlink($localAddr);
            print("WARN: $lockAction $namePath $lockTarget($lockMode) failed, $@\n");
        }
    }
    else {
        print("WARN: $lockAction $namePath $lockTarget($lockMode) failed:socket file $sockPath not exist.\n");
    }

    return $lockRetObj;
}

sub _lock {
    my ( $self, $params ) = @_;

    $params->{action} = 'lock';

    my $lockAction = $params->{action};
    my $lockTarget = $params->{lockTarget};
    my $lockMode   = $params->{lockMode};
    my $namePath   = $params->{lockOwnerName};

    print("INFO: Try to $lockAction $namePath $lockTarget($lockMode).\n");
    my $lockInfo = $self->_doLockByJob($params);
    my $lockId   = $lockInfo->{lockId};

    if ( not defined($lockId) ) {
        my $errMsg = $lockInfo->{message};
        die("ERROR: $lockAction $namePath $lockTarget($lockMode) failed, $errMsg.\n");
    }
    else {
        print("INFO: $lockAction $namePath $lockTarget($lockMode) success.\n");
    }

    return $lockId;
}

sub _unlock {
    my ( $self, $lockId ) = @_;

    if ( not defined($lockId) ) {
        return;
    }

    my $params = $self->_getParams();

    $params->{action} = 'unlock';

    my $lockAction = $params->{action};
    my $lockTarget = $params->{lockTarget};
    my $namePath   = $params->{lockOwnerName};

    my $lockInfo = $self->_doLockByJob($params);
    my $lockId   = $lockInfo->{lockId};

    if ( not defined($lockId) ) {
        my $errMsg = $lockInfo->{message};
        print("WARN: $lockAction $namePath failed, $errMsg.\n");
    }
    else {
        print("INFO: $lockAction $namePath success.\n");
    }
}

sub lockWorkspace {
    my ( $self, $lockMode ) = @_;

    my $deployEnv  = $self->{deployEnv};
    my $sysId      = $deployEnv->{SYS_ID};
    my $moduleId   = $deployEnv->{MODULE_ID};
    my $sysName    = $deployEnv->{SYS_NAME};
    my $moduleName = $deployEnv->{MODULE_NAME};

    my $params = $self->_getParams();

    $params->{lockOwner}     = "$sysId/$moduleId";
    $params->{lockOwnerName} = "$sysName/$moduleName";
    $params->{lockTarget}    = 'workspace';
    $params->{lockMode}      = $lockMode;

    return $self->_lock($params);
}

sub unlockWorkspace {
    my ( $self, $lockId ) = @_;
    $self->_unlock($lockId);
}

sub lockMirror {
    my ( $self, $lockMode ) = @_;

    my $deployEnv  = $self->{deployEnv};
    my $sysId      = $deployEnv->{SYS_ID};
    my $moduleId   = $deployEnv->{MODULE_ID};
    my $envId      = $deployEnv->{ENV_ID};
    my $sysName    = $deployEnv->{SYS_NAME};
    my $moduleName = $deployEnv->{MODULE_NAME};
    my $envName    = $deployEnv->{ENV_NAME};

    my $params = $self->_getParams();

    $params->{lockOwner}     = "$sysId/$moduleId/$envId";
    $params->{lockOwnerName} = "$sysName/$moduleName/$envName";
    $params->{lockTarget}    = "mirror/$envName/app";
    $params->{lockMode}      = $lockMode;

    return $self->_lock($params);
}

sub unlockMirror {
    my ( $self, $lockId ) = @_;
    $self->_unlock($lockId);
}

sub lockBuild {
    my ( $self, $lockMode ) = @_;

    my $deployEnv  = $self->{deployEnv};
    my $sysId      = $deployEnv->{SYS_ID};
    my $moduleId   = $deployEnv->{MODULE_ID};
    my $sysName    = $deployEnv->{SYS_NAME};
    my $moduleName = $deployEnv->{MODULE_NAME};
    my $version    = $deployEnv->{VERSION};
    my $buildNo    = $deployEnv->{BUILD_NO};

    my $params = $self->_getParams();

    $params->{lockOwner}     = "$sysId/$moduleId";
    $params->{lockOwnerName} = "$sysName/$moduleName";
    $params->{lockTarget}    = "artifact/$version/build/$buildNo";
    $params->{lockMode}      = $lockMode;

    return $self->_lock($params);
}

sub unlockBuild {
    my ( $self, $lockId ) = @_;
    $self->_unlock($lockId);
}

sub lockEnvApp {
    my ( $self, $lockMode ) = @_;

    my $deployEnv  = $self->{deployEnv};
    my $sysId      = $deployEnv->{SYS_ID};
    my $moduleId   = $deployEnv->{MODULE_ID};
    my $envId      = $deployEnv->{ENV_ID};
    my $sysName    = $deployEnv->{SYS_NAME};
    my $moduleName = $deployEnv->{MODULE_NAME};
    my $envName    = $deployEnv->{ENV_NAME};
    my $version    = $deployEnv->{VERSION};

    my $params = $self->_getParams();

    $params->{lockOwner}     = "$sysId/$moduleId/$envId";
    $params->{lockOwnerName} = "$sysName/$moduleName/$envName";
    $params->{lockTarget}    = "artifact/$version/env/$envName/app";
    $params->{lockMode}      = $lockMode;

    return $self->_lock($params);
}

sub unlockEnvApp {
    my ( $self, $lockId ) = @_;
    $self->_unlock($lockId);
}

sub lockEnvSql {
    my ( $self, $lockMode ) = @_;

    my $deployEnv  = $self->{deployEnv};
    my $sysId      = $deployEnv->{SYS_ID};
    my $moduleId   = $deployEnv->{MODULE_ID};
    my $envId      = $deployEnv->{ENV_ID};
    my $sysName    = $deployEnv->{SYS_NAME};
    my $moduleName = $deployEnv->{MODULE_NAME};
    my $envName    = $deployEnv->{ENV_NAME};
    my $version    = $deployEnv->{VERSION};
    my $buildNo    = $deployEnv->{BUILD_NO};

    my $params = $self->_getParams();

    $params->{lockOwner}     = "$sysId/$moduleId/$envId";
    $params->{lockOwnerName} = "$sysName/$moduleName/$envName";
    $params->{lockTarget}    = "artifact/$version/env/$envName/db";
    $params->{lockMode}      = $lockMode;

    return $self->_lock($params);
}

sub unlockEnvSql {
    my ( $self, $lockId ) = @_;
    $self->_unlock($lockId);
}

1;
