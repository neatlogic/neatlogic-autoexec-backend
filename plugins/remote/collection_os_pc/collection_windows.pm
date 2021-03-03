package collection_windows;

#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use utf8;
use Socket;

sub collect {
    my ($nodeIp) = @_;
    my @collect_data =();
    my %data = ();
    eval(
        q{
            use Win32::API;
            use Win32;
        }
    );
    $data{'agentIP'} = $nodeIp;

    my @sn = `wmic bios get serialnumber`;
    my $sn = $sn[1];
    $sn =~ s/^\s+|\s+$//g;
    $sn =~ s/[\r]//;
    chomp($sn);
    $data{'序列号'} = $sn;

    my @biosVersion = `wmic bios get version`;
    my $biosVer     = $biosVersion[1];
    $biosVer =~ s/^\s+|\s+$//g;
    $biosVer =~ s/[\r]//;
    chomp($biosVer);
    $data{'BIOS版本'} = $biosVer;

    my @vendor = `wmic csproduct get vendor`;
    my $vendor = $vendor[1];
    $vendor =~ s/^\s+|\s+$//g;
    $vendor =~ s/[\r]//;
    chomp($vendor);
    if ( $vendor =~ /vmware/i or $vendor =~ /Nutanix/ ) {
        print "it's vm\n";
        return @collect_data;
        exit 0;
    }
    $data{'品牌'} = $vendor;

    my @model = `wmic computersystem get model`;
    my $model = $model[1];
    $model =~ s/^\s+|\s+$//g;
    $model =~ s/[\r]//;
    chomp($model);
    $data{'型号'} = $model;

    my @cpuModel = `wmic cpu get name`;
    my $cpuModel = $cpuModel[1];
    $cpuModel =~ s/^\s+|\s+$//g;
    $cpuModel =~ s/[\r]//;
    chomp($cpuModel);
    $data{'CPU型号'} = $cpuModel;

    if ( $cpuModel !~ /Pentium\(R\)/ ) {
        my $cpuFrequency = substr( $cpuModel, rindex( $cpuModel, "@" ) + 1 );
        chomp($cpuFrequency);
        $cpuFrequency =~ s/^\s+|\s+$//g;
        $cpuFrequency =~ s/[\r]//;
        $data{'CPU主频'} = $cpuFrequency;
    }
    else {
        $data{'CPU主频'} = '2.20GHz';
    }

    my $os;
    my $sys_info = `systeminfo`;

    if ( $sys_info =~ /OS\s\S+:\s+(Microsoft(\(R\))?\sWindows.*)\n/ ) {

        #print "$1";
        $os = $1;
    }

    if ( $os !~ /2003/ ) {
        my $cpu_gs = `wmic cpu get`;
        $cpu_gs =~ s/^\s+|\s+$//g;
        my @arr_gs = split /\n/, $cpu_gs;
        my $gs     = ( scalar @arr_gs ) - 1;
        $data{'CPU个数'} = $gs;
    }
    else {
        $data{'CPU个数'} = 'cmd not support';
    }

    my @longbits = `wmic cpu get AddressWidth`;
    my $bits     = $longbits[1];
    $bits =~ s/^\s+|\s+$//g;
    $bits =~ s/[\r\n]//;
    chomp($bits);
    $data{'CPU位数'} = $bits;

    my @Memory = `wmic computersystem get totalphysicalmemory`;
    my $Memory = sprintf "%.2f", $Memory[1] / 1024 / 1024 / 1024;

    my $totalMemory = $Memory . "GB";
    chomp($totalMemory);
    $data{'物理内存(总数)'} = $totalMemory;

    my @memSlots = `wmic memphysical get memorydevices`;
    my $memSlots = $memSlots[1];
    $memSlots =~ s/^\s+|\s+$//g;
    $memSlots =~ s/[\r\n]//;
    chomp($memSlots);
    $data{'内存插槽(总数)'} = $memSlots;

    my @memSpeed = `wmic memorychip get speed`;
    my $memSpeed = $memSpeed[1];
    $memSpeed =~ s/^\s+|\s+$//g;
    $memSpeed =~ s/[\r\n]//;
    chomp($memSpeed);
    $data{'内存速率'} = $memSpeed . "MHz";

    my @nic;
    my @nic_info = `wmic nicconfig where 'IPEnabled = True' get description,ipaddress,macaddress`;
    shift @nic_info;
    @nic_info = grep { $_ !~ /^\s+$/ } @nic_info;
    foreach (@nic_info) {
        my %nic     = ();
        my @arr_tmp = split /\{/, $_;
        my $name    = $arr_tmp[0];
        $name =~ s/^\s+|\s+$//g;
        my $ip_info = $arr_tmp[1];
        my $ip;
        my $mac;
        if ( $ip_info =~ /\d+\.\d+\.\d+\.\d+/ ) {
            $ip = $&;
        }
        if ( $ip_info =~ /(\w\w:){5}\w{2}/ ) {
            $mac = $&;
            chomp($mac);
        }

        $nic{'IP'}    = $ip;
        $nic{'名称'}    = $name;
        $nic{'MAC地址'} = $mac;
        $nic{'接线情况'}  = 'up';
        if ( $ip ne '0.0.0.0' ) {
            push @nic, \%nic;
        }
    }
    $data{'包含网卡'} = \@nic;
    push(@collect_data , \%data);
    return @collect_data;
}

1;
