#!/usr/bin/perl

package host_aix;

use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use warnings;
use utf8;

sub collect {
    my ($nodeIp)     = @_;
    my @collect_data = ();
    my %data         = ();

    system("prtconf > prtconf.txt");
    $data{'agentIP'} = $nodeIp;
    my $sn = `grep Machine\\ Serial prtconf.txt|cut -d ':' -f 2`;
    chomp($sn);
    $sn =~ s/^\s+|\s+$//g;
    $data{'序列号'} = $sn;

    my $ip;
    my @ip_info = `ifconfig -a|grep inet|awk \'{print \$2}\'`;
    foreach (@ip_info) {
        if (/100\.\d+\.\d+\.\d+/) {
            chomp($_);
            $ip = $_;
        }
    }
    $data{'管理IP'} = $ip;

    my $model = `grep System\\ Model prtconf.txt|cut -d ':' -f2`;
    chomp($model);
    $data{'型号'} = $model;

    my $vendor = `grep System\\ Model prtconf.txt|awk '{print \$3}'|cut -d ',' -f1`;
    chomp($vendor);
    $data{'品牌'} = $vendor;

    my $firmwareVersion = `grep Firmware\\ Version prtconf.txt|awk '{print \$3}'`;
    chomp($firmwareVersion);
    $data{'固件版本'} = $firmwareVersion;

    my $cpuModel = `grep Processor\\ Typ prtconf.txt|cut -d ':' -f2`;
    chomp($cpuModel);
    $data{'CPU型号'} = $cpuModel;

    my $cpuFrequency = `grep Clock\\ Speed prtconf.txt|cut -d ':' -f2`;
    chomp($cpuFrequency);
    $data{'CPU主频'} = $cpuFrequency;

    my $physicalCpus = `grep Of\\ Processors prtconf.txt|cut -d ':' -f2`;
    chomp($physicalCpus);

    my $logicCpus = `pmcycles -m|wc -l`;
    chomp($logicCpus);
    $logicCpus =~ s/^\s+|\s+$//g;
    $data{'CPU数量'} = $logicCpus;

    my $logicCPU = `grep Of\\ Processors prtconf.txt|cut -d ':' -f 2`;
    $logicCPU =~ s/^\s+|\s+$//g;
    $data{'CPU个数'} = $logicCPU;

    my $cpuBits = `grep CPU\\ Type prtconf.txt|cut -d ':' -f2`;
    chomp($cpuBits);
    $data{'CPU位数'} = $cpuBits;

    my $totalMemory = `lparstat -i|grep Maximum\\ Memory|awk '{print \$4}'`;
    chomp($totalMemory);
    $data{'物理内存(总数)'} = ( int($totalMemory) / 1024 ) . "GB";

    my $memorySlots = `lscfg -vp |grep -i dimm|wc -l`;
    chomp($memorySlots);
    $memorySlots =~ s/^\s+|\s+$//g;
    $data{'内存插槽(总数)'} = $memorySlots;

    my $storageSize = 0;
    foreach my $disk (`lspv |awk '{print \$1}'`) {
        chomp($disk);
        my $size = `bootinfo -s $disk`;
        $storageSize += $size;
    }

    my @arr_nic;
    my @nic_name = `netstat -ni|grep link|grep -v lo0|awk '{print \$1}'`;
    chomp(@nic_name);

    foreach my $name (@nic_name) {
        my %nic = ();
        my $ip  = `netstat -in|grep $name|head -n2|tail -n 1|awk '{print \$4}'`;
        chomp($ip);
        my $mac = `netstat -in|grep $name |head -n1|awk '{print \$4}'`;
        chomp($mac);
        my $status = `entstat -d $name|grep Link\\ Status|cut -d : -f 2`;
        chomp($status);
        my $speed = `entstat -d $name|grep  Speed\\ Running |cut -d : -f 2`;
        chomp($speed);
        $nic{'名称'} = $name;
        $nic{'IP'}     = $ip;
        my @mac_splits = split /\./, $mac;
        my @new_mac;

        foreach my $split (@mac_splits) {
            if ( length($split) == 1 ) {
                $split = '0' . $split;
            }
            push @new_mac, $split;
        }
        $mac = join( ':', @new_mac );
        $nic{'MAC地址'}    = $mac;
        $nic{'网卡速度'} = $speed;
        $nic{'接线情况'} = $status;
        push @arr_nic, \%nic;
    }
    $data{'包含网卡'} = \@arr_nic;

    my @arr_hba;
    my %hba      = ();
    my @fc_names = `lsdev -Cc adapter|grep fcs|awk '{print \$1}'`;
    foreach my $fc_name (@fc_names) {
        chomp($fc_name);
        $fc_name =~ s/^\s+|\s+$//g;
        $hba{'名称'} = $fc_name;
        my $wwn = `fcstat $fc_name|grep Port\\ Name|cut -d : -f 2`;
        $wwn =~ s/^\s+|\s+$//g;
        my @arr;
        for ( my $i = 2 ; $i <= 16 ; $i += 2 ) {
            my $fc = substr $wwn, $i, 2;
            push @arr, $fc;
        }
        $wwn = join ':', @arr;
        $hba{'WWN'}                = $wwn;
        $hba{'对接光交端口'} = $wwn;
        my $speed = `fcstat $fc_name|grep running|cut -d : -f 2`;
        $speed =~ s/^\s+|\s+$//g;
        $hba{'传输速率'} = $speed;
        my $port_state;
        my $port_state_info = `fcstat $fc_name|grep Attention\\ Type|cut -d : -f 2`;

        if ( $port_state_info =~ /up/i ) {
            $port_state = 'up';
        }
        else {
            $port_state = 'down';
        }
        $hba{'端口状态'} = $port_state;
        my %tmp_hba = %hba;
        push @arr_hba, \%tmp_hba;
    }
    $data{'光纤网卡'} = \@arr_hba;
    push( @collect_data, \%data );
    return @collect_data;
}

1;
