#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package NSSwitcher;

use strict;
use POSIX qw(uname);

sub new {
    my ($type) = @_;
    my $self = {
        SYS_setns => 308,           #setns系统调用号
        mnt       => 0x00020000,    #CLONE_NEWNS, Set to create new namespace.
        uts       => 0x04000000,    #CLONE_NEWUTS, New utsname group.
        ipc       => 0x08000000,    #CLONE_NEWIPC, New ipcs.
        user      => 0x10000000,    #CLONE_NEWUSER, New user namespace.
        pid       => 0x20000000,    #CLONE_NEWPID, New pid namespace.
        net       => 0x40000000     #CLONE_NEWNET, New network namespace.
    };

    my @uname  = uname();
    my $ostype = $uname[0];
    $ostype =~ s/\s.*$//;
    $self->{ostype}        = $ostype;
    $self->{orig_NsTarget} = $$;
    $self->{mnt_NsTarget}  = $$;
    $self->{uts_NsTarget}  = $$;
    $self->{ipc_NsTarget}  = $$;
    $self->{user_NsTarget} = $$;
    $self->{pid_NsTarget}  = $$;
    $self->{net_NsTarget}  = $$;

    foreach my $nsType ( 'ipc', 'uts', 'net', 'pid', 'mnt', 'user' ) {
        my $origFhKey = 'origfh_' . $nsType;
        my $origFh;
        open( $origFh, '<', "/proc/$$/ns/$nsType" );
        if ( defined($origFh) ) {
            $self->{$origFhKey} = $origFh;
        }
    }

    bless( $self, $type );
    return $self;
}

sub DESTROY {
    my $self = shift;
    foreach my $nsType ( 'ipc', 'uts', 'net', 'pid', 'mnt', 'user' ) {
        my $origFhKey = 'origfh_' . $nsType;
        $self->_restoreNS($nsType);
        my $origFh = delete( $self->{$origFhKey} );
        if ( defined($origFh) ) {
            close($origFh);
        }
    }
}

sub _joinNS {
    my ( $self, $nsTarget, $nsType ) = @_;

    my $targetKey = $nsType . '_NsTarget';
    if ( not defined($nsTarget) or $nsTarget eq $self->{$targetKey} or $self->{ostype} =~ /Windows/i ) {

        #不支持windows
        return;
    }

    my $newNsFh;
    open( $newNsFh, '<', "/proc/$nsTarget/ns/$nsType" );
    if ( defined($newNsFh) ) {
        my $result = syscall( $self->{SYS_setns}, fileno($newNsFh), $self->{$nsType} );
        if ( $result == -1 ) {
            print("WARN: Set $nsType namespace to target:$nsTarget, failed: $!\n");
        }
        else {
            $self->{$targetKey} = $nsTarget;
            #print("INFO: Set $nsType namespace to target:$nsTarget.\n");
        }
    }
}

sub _restoreNS {
    my ( $self, $nsType ) = @_;

    my $origNsTarget = $self->{orig_NsTarget};
    my $targetKey    = $nsType . '_NsTarget';
    if ( not defined($origNsTarget) or $origNsTarget eq $self->{$targetKey} or $self->{ostype} =~ /Windows/i ) {

        #不支持windows
        return;
    }

    my $origNsFh = $self->{ 'origfh_' . $nsType };
    if ( defined($origNsFh) ) {
        my $result = syscall( $self->{SYS_setns}, fileno($origNsFh), $self->{$nsType} );
        if ( $result == -1 ) {
            print("WARN: Restore $nsType namespace to target:$origNsTarget, failed: $!\n");
        }
        else {
            $self->{$targetKey} = $origNsTarget;
            #print("INFO: Restore $nsType namespace to target:$origNsTarget.\n");
        }
    }
}

sub joinNamespace {
    my ( $self, $nsTarget, $nsType ) = @_;

    if ( not defined($nsTarget) or $nsTarget eq $self->{currentNsTarget} or $self->{ostype} =~ /Windows/i ) {

        #不支持windows
        return;
    }
    else {
        print("INFO: Swtich to namespace target:$nsTarget.\n");
    }

    my @nsTypes = ();
    if ( defined($nsType) and $nsType ne '' ) {
        @nsTypes = ($nsType);
    }
    else {
        @nsTypes = ( 'ipc', 'uts', 'net', 'pid', 'mnt' );
    }

    foreach my $aNsType (@nsTypes) {
        $self->_joinNS( $nsTarget, $aNsType );
    }
}

sub restoreNamespace {
    my ( $self, $nsType ) = @_;

    my $origNsTarget = $self->{orig_NsTarget};

    if ( not defined($origNsTarget) or $origNsTarget eq $self->{currentNsTarget} or $self->{ostype} =~ /Windows/i ) {

        #不支持windows
        return;
    }
    else {
        print("INFO: Restore to namespace target:$origNsTarget.\n");
    }

    my @nsTypes = ();
    if ( defined($nsType) and $nsType ne '' ) {
        @nsTypes = ($nsType);
    }
    else {
        @nsTypes = ( 'ipc', 'uts', 'net', 'pid', 'mnt' );
    }

    foreach my $aNsType (@nsTypes) {
        $self->_restoreNS($aNsType);
    }
}

1;
