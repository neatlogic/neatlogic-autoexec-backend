#!/usr/bin/perl
use strict;

package BuildLock;

our $SHARE   = 0;
our $EXCLUDE = 1;

#调用autoexec的ListenThread，进行作业层次的Lock和unLock
#参数，jobId，lockTarget

sub new {
    my ($pkg) = @_;
    my $self = {};
    bless( $self, $pkg );

    return $self;
}

sub _lock {
    my ( $self, $lockTarget, $lockLevel ) = @_;
}

sub _unlock {
    my ( $self, $lockTarget, $lockLevel ) = @_;
}

sub lockWorkspace {
    my ( $self, $lockLevel ) = @_;
    $self->_lock( 'workspace', $lockLevel );
}

sub unLockWorkspace {
    my ( $self, $lockLevel ) = @_;
    $self->_unlock( 'workspace', $lockLevel );
}

sub lockMirror {
    my ( $self, $lockLevel ) = @_;
    $self->_lock( 'mirror', $lockLevel );
}

sub unlockMirror {
    my ( $self, $lockLevel ) = @_;
    $self->_unlock( 'mirror', $lockLevel );
}

sub lockBuild {
    my ( $self, $lockLevel ) = @_;
    $self->_lock( 'build', $lockLevel );
}

sub unlockBuild {
    my ( $self, $lockLevel ) = @_;
    $self->_unlock( 'build', $lockLevel );
}

sub lockEnvApp {
    my ( $self, $lockLevel ) = @_;
    $self->_lock( 'env/app', $lockLevel );
}

sub unlockEnvApp {
    my ( $self, $lockLevel ) = @_;
    $self->_unlock( 'env/app', $lockLevel );
}

sub lockEnvSql {
    my ( $self, $lockLevel ) = @_;
    $self->_lock( 'env/sql', $lockLevel );
}

sub unlockEnvSql {
    my ( $self, $lockLevel ) = @_;
    $self->_unlock( 'env/sql', $lockLevel );
}

1;