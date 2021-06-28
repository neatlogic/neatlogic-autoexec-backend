#!/usr/bin/perl

package host_linux;

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
    my $sn           = `dmidecode -t 1|grep Serial\\ Number|cut -d : -f 2`;

    #if ($sn =~ /O\.E\.M/ or $sn eq '' or $sn =~ /bad/i or $sn =~ /unknow/i){
    #	print "CAN'T FIND SN OF THE SERVER\n";
    #    exit 1;
    #}
    chomp($sn);
    $sn =~ s/^\s+|\s+$//g;
    $data{'序列号'} = $sn;

    if ( $sn =~ /vmware/i ) {
        return @collect_data;
        exit 0;
    }
    my $ip = `hostname -i`;
    chomp($ip);
    $data{'IP'} = $ip;

    $data{'agentIP'} = $nodeIp;

    my $model = `dmidecode |grep Product|head -1|cut -d ":" -f 2`;
    chomp($model);
    $data{'型号'} = $model;

    my $vendor = `dmidecode -t 1|grep Manufacturer|cut -d : -f 2`;
    chomp($vendor);
    $vendor =~ s/^\s+|\s+$//g;
    if ( $vendor =~ /huawei/i ) {
        $vendor = '华为';
    }
    $data{'品牌'} = $vendor;

    my $os = `cat /etc/redhat-release`;
    chomp($os);
    $data{'os'} = $os;
    my $biosVersion = `dmidecode -t bios|grep Version|cut -d ":" -f 2`;
    chomp($biosVersion);
    $data{'BIOS版本'} = $biosVersion;

    my $microcode = `cat /proc/cpuinfo |grep mic|uniq -c|cut -d ":" -f 2`;
    chomp($microcode);
    $data{'微码版本'} = $microcode;

    my $cpuModel = `cat /proc/cpuinfo |grep name |cut -d ":" -f2 |uniq |cut -d "@" -f1`;
    chomp($cpuModel);
    $data{'CPU型号'} = $cpuModel;

    my $cpuFrequency = `cat /proc/cpuinfo |grep name |cut -d ":" -f2 |uniq |cut -d "@" -f2`;
    chomp($cpuFrequency);
    $data{'CPU主频'} = $cpuFrequency;

    my $logicCpus = `cat /proc/cpuinfo |grep processor |wc -l`;
    chomp($logicCpus);
    $data{'CPU数量'} = $logicCpus;

    my $cpuCores = `cat /proc/cpuinfo |grep physical\\ id|sort|uniq|wc -l`;
    chomp($cpuCores);
    $data{'CPU个数'} = $cpuCores;

    my $cpuBits = `cat /proc/cpuinfo|grep flags|grep lm|wc -l`;
    if ( $cpuBits > 0 ) {
        $data{'CPU位数'} = "64";
    }
    else {
        $data{'CPU位数'} = "32";
    }

    my $singleMemory = `dmidecode |grep -A5 Memory\\ Device|grep Size|grep -v Range|grep -vi no|uniq |awk '{print \$2}'`;
    chomp($singleMemory);
    if ( $singleMemory < 1024 ) {
        $singleMemory = $singleMemory * 1024;
    }
    $data{'singleMemory'} = $singleMemory / int(1024) . "GB";

    my $usedSlots = `dmidecode -t memory|grep -i size|grep -v No|wc -l`;
    chomp($usedSlots);
    my $totalMemory = $singleMemory / int(1024) * $usedSlots;
    $totalMemory = $totalMemory . "GB";
    $data{'物理内存(总数)'} = $totalMemory;

    my $memorySlots = `dmidecode |grep -A5 Memory\\ Device|grep Size|grep -v Range|wc -l`;
    chomp($memorySlots);
    $data{'内存插槽(总数)'} = $memorySlots;

    my $memorySpeed = `dmidecode |grep -A16 Memory\\ Device|grep 'Speed'|grep -vi unknow|uniq |cut -d ":" -f 2`;
    chomp($memorySpeed);
    $data{'内存速率'} = $memorySpeed;
    my $swap = `cat /proc/meminfo |grep -i swaptotal|awk '{print \$2}'`;
    chomp($swap);
    $data{'swap'} = int( ( $swap / ( 1024 * 1024 ) ) + 0.5 ) . "GB";

    my $power = `dmidecode -t chassis|grep Power\\ Cords|cut -d : -f 2`;
    chomp($power);
    $data{'电源数量'} = $power;

    my @arr_nic;
    my @ipaddr_output = `ip addr`;
    my @ifs;
    foreach my $line (@ipaddr_output) {
        if ( $line =~ /^\d+:\s+(\S+):/ ) {
            push @ifs, $1 if ( $1 ne 'lo' );
        }
    }
    foreach my $if_name (@ifs) {
        my %nic;
        $nic{'名称'} = $if_name;
        my $sin_output = `ip a show $if_name`;
        my $mac;
        if ( $sin_output =~ /link\/ether\s+(.*?)\s+/ ) {
            $mac = $1;
        }
        $nic{'MAC地址'} = lc($mac);
        my $s_ip = '';
        if ( $sin_output =~ /inet\s(\d+\.\d+\.\d+\.\d+)/ ) {
            $s_ip = $1;
        }
        $nic{'IP'} = $s_ip;

        my $speed = `ethtool $if_name|grep Speed|awk '{print \$2}'`;
        chomp($speed);
        $nic{'网卡速度'} = $speed;

        my $state = `ethtool $if_name|grep detected|awk '{print \$3}'`;
        chomp($state);
        $nic{'接线情况'} = $state;
        push @arr_nic, \%nic if ( $nic{'IP'} ne '' );
    }

    $data{'包含网卡'} = \@arr_nic;

    my @arr_hba;
    my %hba = ();

    my $dir     = '/sys/class/fc_host/';
    my @FC_host = glob '/sys/class/fc_host/*';
    if ( @FC_host != 0 ) {
        foreach my $path (@FC_host) {
            $hba{'名称'} = basename($path);
            my $wwn = `cat $path/port_name`;
            chomp($wwn);
            my @arr;
            for ( my $i = 2 ; $i <= 16 ; $i += 2 ) {
                my $fc = substr $wwn, $i, 2;
                push @arr, $fc;
            }
            $wwn = join ':', @arr;
            $hba{'WWN'}                = $wwn;
            $hba{'对接光交端口'} = $wwn;
            my $port_speed = `cat /$path/speed`;
            chomp($port_speed);
            $hba{'传输速率'} = $port_speed;
            my $port_state;

            if ( $port_speed eq 'unknown' ) {
                $port_state = 'down';
            }
            else {
                $port_state = 'up';
            }
            $hba{'端口状态'} = $port_state;
            my %hba_copy = %hba;
            push @arr_hba, \%hba_copy;
        }
    }
    $data{'光纤网卡'} = \@arr_hba;
    push( @collect_data, \%data );
    return @collect_data;
}

1;
