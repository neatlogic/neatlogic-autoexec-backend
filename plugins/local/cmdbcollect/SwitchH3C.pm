#!/usr/bin/perl
use strict;

package SwitchH3C;
use SwitchBase;
our @ISA = qw(SwitchBase);
use NetExpect;
use Net::OpenSSH;
use Data::Dumper;
sub before {
    my ($self) = @_;

    #SN可能要调整，如果有多个可能，就在数组里添加
    $self->addScalarOid( SN => [ '1.3.6.1.2.1.47.1.1.1.1.11.1', '1.3.6.1.2.1.47.1.1.1.1.11.2', '1.3.6.1.2.1.47.1.1.1.1.11.19' ] );
}
#针对l2vpn这种需要单独用ssh采集Mac表
sub after {
    my ($self) = @_;
    my $sshAccount = $self->{sshaccount};
    my $node = $self->{node};
    my $sshAccountInfo = {};
    if ( defined($sshAccount) and $sshAccount ne '' ) {
        if ( $sshAccount =~ /^\s*(\d+)\s*:\s*(\w+)\/(.*?)\s*$/ ) {
            my $protocolPort = int($1);
	    if ( $protocolPort == 0 ) {
	        $protocolPort = 22;
	    }
	    $sshAccountInfo->{protocolPort} = $protocolPort;
	    $sshAccountInfo->{username}     = $2;
	    $sshAccountInfo->{password}     = $3;
	}
	elsif ( $sshAccount =~ /^\s*(\w+)\/(.*?)\s*$/ ) {
	    $sshAccountInfo->{protocolPort} = 22;
	    $sshAccountInfo->{username}     = $1;
	    $sshAccountInfo->{password}     = $2;
	}
    }
    my $data = $self->{DATA};
    my $mac_table = $data->{MAC_TABLE};
    my $nodeInfo = $self->{node};
    
    my $portNoMap   = $self->{portNoMap};
    #print Dumper($portNoMap);
    my $portMacsMap = {};

    if ( defined $sshAccountInfo->{username}  and $sshAccountInfo->{protocolPort} == 22 ) {
        print("INFO:  try ssh collect mac_table data.\n");
	my $sshclient = Net::OpenSSH->new(
	$nodeInfo->{host},
	port        => $sshAccountInfo->{protocolPort},
	user        => $sshAccountInfo->{username},
	password    => $sshAccountInfo->{password},
	timeout     => $self->{timeout},
	master_opts => [ -o => "StrictHostKeyChecking=no" ]
	);

	if ( $sshclient->error ) {
	    die( "ERROR: Can not establish SSH connection: " . $sshclient->error );
	}
	my @lines = $sshclient->capture('display l2vpn mac-address dynamic');
	my @macTblData;
        foreach my $line (@lines){
            if ($line =~ /Dynamic/){

                my @splits = split(/\s+/,$line);
                my $mac = $splits[0];
                my $portName = $splits[3];
                my $formatted_mac = $mac;  
		$formatted_mac =~ s/-/:/g;  # 将'-'替换为':'  
		$formatted_mac =~ s/(..)(?!$)/$1:/g;  # 在每两个字符后添加':'，但不在末尾  
		$formatted_mac =~ s/:$//;  # 移除末尾的':'
		my $portMacInfo = { PORT => $portName, MAC => $formatted_mac };
		push @macTblData,$portMacInfo;
	    }
        }

        for ( my $i = 0 ; $i < scalar(@macTblData) ; $i++ ) {
            my $macInfo = $macTblData[$i];
            
            my $portNo        = $macInfo->{PORT};
	    my @splits = split("/",$portNo);
            my $portInfo      = $portNoMap->{$splits[2]};
            my $portDesc      = $portInfo->{NAME};
            my $neighborCount = $portInfo->{NEIGHBOR_COUNT};

            my $remoteMac = $macInfo->{MAC};
            if ( $remoteMac ne '' ) {
                my $portMacInfo = $portMacsMap->{$portDesc};
                if ( not defined($portMacInfo) ) {
                    $portMacInfo = { PORT => $portDesc, MAC_COUNT => 0, NEIGHBOR_COUNT => $neighborCount, MACS => [] };
                    $portMacsMap->{$portDesc} = $portMacInfo;
                }
                $portMacInfo->{MAC_COUNT} = 1 + $portMacInfo->{MAC_COUNT};
                my $macs = $portMacInfo->{MACS};
                push( @$macs, $remoteMac );
            }
        }

        my @macTable = values(%$portMacsMap);
        push @$mac_table,@macTable;
        $self->{DATA}->{MAC_TABLE} = $mac_table;

    }

    return $data;
}
1;

