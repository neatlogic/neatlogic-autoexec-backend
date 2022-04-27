#!/usr/bin/perl
use strict;

package DeployLock;

use ServerAdapter;

our $READ  = 'read';
our $WRITE = 'write';

#调用autoexec的ListenThread，进行作业层次的Lock和unLock
#参数，jobId，lockTarget
#TODO: 修改autoexec主程序，通过它进行加锁，这个类药迁移到local/lib
sub new {
    my ( $pkg, $deployEnv ) = @_;
    my $self = {};
    bless( $self, $pkg );
    $self->{deployEnv} = $deployEnv;

    my $jobId = $ENV{AUTOEXEC_JOBID};
    $self->{jobId} = $jobId;
    my $sockPath = $ENV{AUTOEXEC_WORK_PATH} . '/job.sock';
    $self->{sockPath} = $sockPath;

    return $self;
}

sub _getParams {
    my ( $self, $deployEnv ) = @_;

    my $jobId      = $self->{jobId};
    my $sysId      = $deployEnv->{SYS_ID};
    my $moduleId   = $deployEnv->{MODULE_ID};
    my $envId      = $deployEnv->{ENV_ID};
    my $sysName    = $deployEnv->{SYS_NAME};
    my $moduleName = $deployEnv->{MODULE_NAME};
    my $envName    = $deployEnv->{ENV_NAME};

    my $params = {
        jobId         => $jobId,
        lockOwner     => "$sysId/$moduleId/$envId",
        lockOwnerName => "$sysName/$moduleName/$envName"
    };

    return $params;
}

sub _doLockByJob {
    my ( $self, $params ) = @_;

    my $sockPath = $self->{sockPath};

    my $lockAction = $params->{action};
    my $lockTarget = $params->{lockTarget};
    my $lockMode   = $params->{lockMode};
    my $namePath   = $params->{lockOwnerName};

    if ( -e $sockPath ) {
        eval {
            my $client = IO::Socket::UNIX->new(
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
            my $lockRetObj = from_json($lockRet);

            $client->close();

            #print("INFO: $namePath $lockAction $lockTarget($lockMode) success.\n");
            return $lockRetObj;
        };
        if ($@) {
            print("WARN: $namePath $lockAction $lockTarget($lockMode) failed, $@\n");
        }
    }
    else {
        print("WARN: $namePath $lockAction $lockTarget($lockMode) failed:socket file $sockPath not exist.\n");
    }

    return;
}

sub _lock {
    my ( $self, $lockTarget, $lockMode ) = @_;

    my $params = $self->_getParams( $self->{deployEnv} );
    $params->{lockTarget} = $lockTarget;
    $params->{lockMode}   = $lockMode;
    $params->{action}     = 'lock';

    my $lockAction = $params->{action};
    my $lockTarget = $params->{lockTarget};
    my $lockMode   = $params->{lockMode};
    my $namePath   = $params->{lockOwnerName};

    my $lockInfo = $self->_doLockByJob($params);
    my $lockId   = $lockInfo->{lockId};

    if ( not defined($lockId) ) {
        my $errMsg = $lockInfo->{message};
        die("ERROR: $namePath $lockAction $lockTarget($lockMode) faled, $errMsg.\n");
    }
    else {
        print("INFO: $namePath $lockAction $lockTarget($lockMode) success.\n");
    }

    return $lockId;
}

sub _unlock {
    my ( $self, $lockId ) = @_;
    my $params = { $self->_getParams( $self->{deployEnv} ) };

    $params->{action} = 'unlock';

    my $lockAction = $params->{action};
    my $lockTarget = $params->{lockTarget};
    my $namePath   = $params->{lockOwnerName};

    my $lockInfo = $self->_doLockByJob($params);
    my $lockId   = $lockInfo->{lockId};

    if ( not defined($lockId) ) {
        my $errMsg = $lockInfo->{message};
        print("WARN: $namePath $lockAction $lockTarget faled, $errMsg.\n");
    }
    else {
        print("INFO: $namePath $lockAction $lockTarget success.\n");
    }
}

sub lockWorkspace {
    my ( $self, $lockMode ) = @_;
    $self->_lock( 'workspace', $lockMode );
}

sub unLockWorkspace {
    my ($self) = @_;
    $self->_unlock('workspace');
}

sub lockMirror {
    my ( $self, $lockMode ) = @_;
    my $deployEnv  = $self->{deployEnv};
    my $version    = $deployEnv->{VERSION};
    my $envName    = $deployEnv->{ENV_NAME};
    my $lockTarget = "mirror/$envName/app";

    $self->_lock( 'mirror', $lockMode );
}

sub unlockMirror {
    my ( $self, $lockId ) = @_;
    $self->_unlock($lockId);
}

sub lockBuild {
    my ( $self, $lockMode ) = @_;
    my $deployEnv  = $self->{deployEnv};
    my $version    = $deployEnv->{VERSION};
    my $buildNo    = $deployEnv->{BUILD_NO};
    my $lockTarget = "artifact/$version/build/$buildNo";
    $self->_lock( $lockTarget, $lockMode );
}

sub unlockBuild {
    my ( $self, $lockId ) = @_;
    $self->_unlock($lockId);
}

sub lockEnvApp {
    my ( $self, $lockMode ) = @_;
    my $deployEnv  = $self->{deployEnv};
    my $version    = $deployEnv->{VERSION};
    my $envName    = $deployEnv->{ENV_NAME};
    my $lockTarget = "artifact/$version/env/$envName/app";
    $self->_lock( $lockTarget, $lockMode );
}

sub unlockEnvApp {
    my ( $self, $lockId ) = @_;
    $self->_unlock($lockId);
}

sub lockEnvSql {
    my ( $self, $lockMode ) = @_;
    my $deployEnv  = $self->{deployEnv};
    my $version    = $deployEnv->{VERSION};
    my $envName    = $deployEnv->{ENV_NAME};
    my $lockTarget = "artifact/$version/env/$envName/db";
    $self->_lock( $lockTarget, $lockMode );
}

sub unlockEnvSql {
    my ( $self, $lockId ) = @_;
    $self->_unlock($lockId);
}

1;
