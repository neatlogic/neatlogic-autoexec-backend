#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package LinuxNetStat;

use strict;
use POSIX qw(uname);

use IO::File;

sub new {
    my ($type) = @_;

    #Proto Recv-Q Send-Q LocalIP localPort ForeignIP ForeignPort State PID
    my $self = {
        hasInit        => 0,
        sockInode2Pid  => {},
        allListenArray => [],
        allConnArray   => [],
        procListenMap  => {},
        procConnMap    => {},
    };

    my @connStates = (
        undef,
        qw(ESTABLISHED
            SYN_SENT
            SYN_RECV
            FIN_WAIT1
            FIN_WAIT2
            TIME_WAIT
            CLOSE
            CLOSE_WAIT
            LAST_ACK
            LISTEN
            CLOSING)
    );
    $self->{connStates} = \@connStates;

    bless( $self, $type );

    return $self;
}

sub init {
    my ($self) = @_;
    if ( $self->{hasInit} == 0 ) {
        $self->_getAllProcSockMap();
        $self->_getAllTcpStat();
        $self->_getAllUdpStat();
        $self->{hasInit} = 1;
    }
}

sub _hex2ip {
    my ( $self, $hexIp ) = @_;

    my $bin = pack( "C*" => map hex, $hexIp =~ /../g );
    my @l   = unpack( "L*", $bin );
    if ( @l == 4 ) {
        my $ipv6 = join( ':', map { sprintf "%x:%x", $_ >> 16, $_ & 0xffff } @l );
        $ipv6 =~ s/[0:]+/::/;
        return $ipv6;
    }
    elsif ( @l == 1 ) {
        return join( '.', map { $_ >> 24, ( $_ >> 16 ) & 0xff, ( $_ >> 8 ) & 0xff, $_ & 0xff } @l );
    }
}

sub _getProcSockMap {
    my ( $self, $pid ) = @_;
    my $procListenMap = $self->{procListenMap};
    my $procConnMap   = $self->{procConnMap};
    $procListenMap->{$pid} = [];
    $procConnMap->{$pid}   = [];

    my $fdDir = "/proc/$pid/fd";
    my $dh;
    opendir( $dh, $fdDir );
    if ( not defined($dh) ) {
        print("WARN: Open directory $fdDir failed:$!\n");
        return;
    }

    my $sockInode2Pid = $self->{sockInode2Pid};
    while ( my $lnk = readdir($dh) ) {
        if ( $lnk =~ /^\d+$/ ) {
            my $target = readlink("/proc/$pid/fd/$lnk");
            if ( $target =~ /^socket:\[(\d+)\]$/ ) {
                $sockInode2Pid->{$1} = $pid;
            }
        }
    }
    closedir($dh);
}

sub _getAllProcSockMap {
    my ($self) = @_;

    my $dh;
    opendir( $dh, '/proc' );
    if ( not defined($dh) ) {
        print("WARN: Open directory /proc failed:$!\n");
        return;
    }

    while ( my $pid = readdir($dh) ) {
        if ( $pid =~ /^\d+$/ ) {
            $self->_getProcSockMap($pid);
        }
    }
    closedir($dh);
}

sub _getAllTcpStat {
    my ($self)         = @_;
    my $sockInode2Pid  = $self->{sockInode2Pid};
    my $connStates     = $self->{connStates};
    my $allListenArray = $self->{allListenArray};
    my $allConnArray   = $self->{allConnArray};
    my $procListenMap  = $self->{procListenMap};
    my $procConnMap    = $self->{procConnMap};

    foreach my $protocol ( 'tcp', 'tcp6' ) {
        my $status = 0;
        my $pipe;
        open( $pipe, "cat /proc/net/$protocol |" );
        if ( defined($pipe) ) {
            my $line = <$pipe>;
            while ( $line = <$pipe> ) {
                $line =~ s/^\s+//;
                my @tblFields = split( /[\s:]+/, $line );
                my $pid       = $sockInode2Pid->{ $tblFields[13] };
                my $stateNo   = hex( $tblFields[5] );
                my $state     = $$connStates[$stateNo];

                #Proto Recv-Q Send-Q LocalIP localPort ForeignIP ForeignPort State PID
                my $fields = [ $protocol, hex( $tblFields[7] ), hex( $tblFields[6] ), $self->_hex2ip( $tblFields[1] ), hex( $tblFields[2] ), $self->_hex2ip( $tblFields[3] ), hex( $tblFields[4] ), $state, $pid ];
                if ( $stateNo == 10 ) {
                    push( @$allListenArray, $fields );
                    my $procLsnArray = $procListenMap->{$pid};
                    push( @$procLsnArray, $fields );
                }
                else {
                    push( @$allConnArray, $fields );
                    my $procConnArray = $procConnMap->{$pid};
                    push( @$procConnArray, $fields );
                }
            }
            close($pipe);
            $status = $?;
            if ( $status != 0 ) {
                print("WARN: Open file /proc/net/$protocol failed.\n");
            }
        }
    }
}

sub _getAllUdpStat {
    my ($self)         = @_;
    my $sockInode2Pid  = $self->{sockInode2Pid};
    my $connStates     = $self->{connStates};
    my $allListenArray = $self->{allListenArray};
    my $allConnArray   = $self->{allConnArray};
    my $procListenMap  = $self->{procListenMap};
    my $procConnMap    = $self->{procConnMap};

    foreach my $protocol ( 'udp', 'udp6' ) {
        my $status = 0;
        my $pipe;
        open( $pipe, "cat /proc/net/$protocol |" );
        if ( defined($pipe) ) {
            my $line = <$pipe>;
            while ( $line = <$pipe> ) {
                $line =~ s/^\s+//;
                my @tblFields = split( /[\s:]+/, $line );
                my $pid       = $sockInode2Pid->{ $tblFields[13] };
                my $stateNo   = hex( $tblFields[5] );
                my $state     = '';

                #Proto Recv-Q Send-Q LocalIP localPort ForeignIP ForeignPort State PID
                my $fields = [ $protocol, hex( $tblFields[7] ), hex( $tblFields[6] ), $self->_hex2ip( $tblFields[1] ), hex( $tblFields[2] ), $self->_hex2ip( $tblFields[3] ), hex( $tblFields[4] ), $state, $pid ];

                push( @$allListenArray, $fields );
                my $procLsnArray = $procListenMap->{$pid};
                push( @$procLsnArray, $fields );
            }
            close($pipe);
            $status = $?;
            if ( $status != 0 ) {
                print("WARN: Open file /proc/net/$protocol failed.\n");
            }
        }
    }
}

sub getListenTable {
    my ($self) = @_;
    $self->init();
    return $self->{allListenArray};
}

sub getProclistenTable {
    my ( $self, $pid ) = @_;
    $self->init();
    if ( defined($pid) and $pid ne '' ) {
        my $procLsnArray = $self->{procListenMap}->{$pid};
        if ( not defined($procLsnArray) ) {
            $procLsnArray = [];
        }
        return $procLsnArray;
    }
    else {
        return $self->{allListenArray};
    }
}

sub getConnTable {
    my ($self) = @_;
    $self->init();
    return $self->{allConnArray};
}

sub getProcConnTable {
    my ( $self, $pid ) = @_;
    $self->init();
    if ( defined($pid) and $pid ne '' ) {
        my $procConnArray = $self->{procConnMap}->{$pid};
        if ( not defined($procConnArray) ) {
            $procConnArray = [];
        }
        return $procConnArray;
    }
    else {
        return $self->{allConnArray};
    }
}

1;
