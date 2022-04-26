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

    return $self;
}

sub _getParams {
    my ( $self, $deployEnv ) = @_;

    my $params = {
        sysId      => $deployEnv->{SYS_ID},
        moduleId   => $deployEnv->{MODULE_ID},
        envId      => $deployEnv->{ENV_ID},
        sysName    => $deployEnv->{SYS_NAME},
        moduleName => $deployEnv->{MODULE_NAME},
        envName    => $deployEnv->{ENV_NAME},
        version    => $deployEnv->{VERSION},
        buildNo    => $deployEnv->{BUILD_NO}
    };

    return $params;
}

sub _doLockByJob {
    my ( $self, $params ) = @_;

    my $sockPath = $ENV{AUTOEXEC_WORK_PATH} . '/job.sock';

    my $lockAction = $params->{action};
    my $lockTarget = $params->{lockTarget};
    my $lockMode   = $params->{lockMode};
    my $namePath   = $params->{namePath};

    if ( -e $sockPath ) {
        eval {
            my $client = IO::Socket::UNIX->new(
                Peer    => $sockPath,
                Type    => IO::Socket::SOCK_DGRAM,
                Timeout => 10
            );

            my $request = {};
            $request->{action}     = 'deployLock';
            $request->{lockParams} = $params;

            $client->send( to_json($request) );

            my $lockRet;
            $client->recv( $lockRet, 1024 );
            my $lockRetObj = from_json($lockRet);

            $client->close();
            print("INFO: $namePath $lockAction $lockTarget($lockMode) success.\n");
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

    #TODO：保护workspace和制品中心制品的锁接口实现
}

sub _unlock {
    my ( $self, $lockTarget, $lockMode ) = @_;
    my $params = $self->_getParams( $self->{deployEnv} );
    $params->{lockTarget} = $lockTarget;
    $params->{lockMode}   = $lockMode;
    $params->{action}     = 'unlock';

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
    $self->_lock( 'mirror', $lockMode );
}

sub unlockMirror {
    my ( $self, $lockMode ) = @_;
    $self->_unlock('mirror');
}

sub lockBuild {
    my ( $self, $lockMode ) = @_;
    $self->_lock( 'build', $lockMode );
}

sub unlockBuild {
    my ( $self, $lockMode ) = @_;
    $self->_unlock('build');
}

sub lockEnvApp {
    my ( $self, $lockMode ) = @_;
    $self->_lock( 'env/app', $lockMode );
}

sub unlockEnvApp {
    my ( $self, $lockMode ) = @_;
    $self->_unlock('env/app');
}

sub lockEnvSql {
    my ( $self, $lockMode ) = @_;
    $self->_lock( 'env/db', $lockMode );
}

sub unlockEnvSql {
    my ( $self, $lockMode ) = @_;
    $self->_unlock('env/db');
}

1;
