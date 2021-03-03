package collection_windows;

#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use utf8;
use Socket;

sub getWinCodePage {
    my $charSet;
    eval(
        q{
            use Win32::API;
            if ( Win32::API->Import( 'kernel32','int GetACP()')){
                $charSet = 'cp'.GetACP();
            }
        }
    );
    return $charSet;
}

sub collect {
    my ($nodeIp) = @_;
    my @collect_data =();
    my %data = ();
    my $charSet;
    eval(
        q{
            use Win32::API;
            use Win32;
        }
    );
    $data{'虚拟机'} = '是';
    my @sn = `wmic bios get serialnumber`;
    my $sn = $sn[1];
    $sn =~ s/^\s+|\s+$//g;
    $sn =~ s/[\r]//;
    chomp($sn);

    if ( !defined $sn or $sn eq '' ) {
        print "get sn cmd not support";
    }
    elsif ( $sn !~ /vmware/i ) {
        $data{'服务器或CLUSTER'} = $sn;
        $data{'虚拟机'}         = '否';
    }

    my $dns = `wmic nicconfig get DNSServerSearchOrder /value|findstr "DNSServerSearchOrder={"`;
    $dns =~ s/^\s+|\s+$//g;
    my @arr = $dns =~ /\d+\.\d+\.\d+\.\d+/g;
    $data{'DNS服务'} = @arr;

    my $patchs = `wmic qfe list full`;
    $patchs =~ s/^\s+|\s+$//g;
    my @arr = $patchs =~ /KB\d+/g;
    my $p   = join( ',', @arr );
    $data{'补丁情况'} = $p;

    my $ntp_server = `w32tm /query /configuration`;
    if ( $ntp_server =~ /NtpServer:\s(\S+),/ ) {
        $data{'NTP服务器'} = $1;
    }
    else {
        $data{'NTP服务器'} = 'cmd not support';
    }

    if ( -e "C:\Windows\SysWOW64" ) {
        $data{'位长'} = '64';
    }
    else {
        $data{'位长'} = '32';
    }

    my $ver = `ver`;
    $ver =~ s/[\r\n]//;
    chomp($ver);
    $data{'内核版本'} = $ver;

    my @mem = `wmic computersystem get totalphysicalmemory`;
    my $mem = sprintf "%.2f", $mem[1] / 1024 / 1024 / 1024;
    chomp($mem);
    $mem = $mem . "GB";
    $data{'内存'} = $mem;

    my $tasklist = `tasklist`;
    if ( $tasklist =~ /ccSvcHst/ ) {
        $data{'symantec'} = 'installed';
    }
    else {
        $data{'symantec'} = 'not installed';
    }

    my $os;
    my $build;
    my $hostname;
    my $sys_info = `systeminfo`;
    if ( $sys_info =~ /OS\s\S+:\s+(Microsoft(\(R\))?\sWindows.*)\n/ ) {
        $os = $1;
    }
    if ( $sys_info =~ /OS\s\S+:\s+(\d+\.\d+\.\d+.*\d+)\n/ ) {
        $build = $1;
    }

    my $ip = $nodeIp;
    $data{'IP'}         = $ip;
    $data{'agentIP'} = $nodeIp;
    $data{'uniqueName'} = $ip;

    my $hostname = `hostname`;
    chomp($hostname);
    $data{'hostname'} = $hostname;

    $build =~ s/^\s+|\s+$//g;
    $os    =~ s/^\s+|\s+$//g;

    $data{'OS版本'}    = $os;
    $data{'build版本'} = $build;

    my $cpuCore = `echo %NUMBER_OF_PROCESSORS%`;
    $cpuCore =~ s/^\s+|\s+$//g;
    $data{'CPU核数'} = $cpuCore;

    my @dns_str = `netsh interface ip show dnsservers|findstr "[0-9]*\\.[0-9]*\\."`;
    my @dns;
    my $i = 0;
    foreach (@dns_str) {
        if ( defined $_ ) {
            $_ =~ m/((25[0-5]|2[0-4]\d|((1\d{2})|([1-9]?\d)))\.){3}(25[0-5]|2[0-4]\d|((1\d{2})|([1-9]?\d)))/;
            $dns[$i] = $&;
            $i = $i + 1;
        }
    }
    my $dns = join( ",", @dns );
    chomp($dns);
    $data{'DNS服务'} = $dns;

    my @ips;
    my $ip_info = `wmic nicconfig where 'IPEnabled = True' get ipaddress`;
    my @arr_ips = $ip_info =~ /\d+\.\d+\.\d+\.\d+/g;
    foreach (@arr_ips) {
        if ( $_ ne '127.0.0.1' ) {
            push @ips, $_;
        }
    }
    $data{'IP列表'} = \@ips;

    my @users;
    my $user_info = `wmic useraccount where disabled='false' get name`;
    $user_info =~ s/^\s+|\s+$//g;
    my @user_line = split /\s+/, $user_info;
    foreach my $u_name (@user_line) {
        if ( $u_name ne 'Name' ) {
            push @users, lc($u_name);
        }
    }
    $data{'用户列表'} = \@users;
    push(@collect_data , \%data);
    return @collect_data;
}

1;
