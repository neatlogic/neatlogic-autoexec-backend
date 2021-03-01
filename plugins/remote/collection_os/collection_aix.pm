package collection_aix;

#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use utf8;

sub collect {
    my ($nodeIp) = @_;
    my %data = ();

    system("prtconf > prtconf.txt");
    my $sn = `grep Machine\\ Serial prtconf.txt|cut -d ':' -f 2`;
    chomp($sn);
    $sn =~ s/^\s+|\s+$//g;
    $data{'服务器或CLUSTER'} = $sn;

    my $hostname = `hostname`;
    chomp($hostname);
    $data{'主机名称'} = $hostname;

    my $ip;
    my @lines = `cat /etc/hosts`;
    foreach (@lines) {
        if (/(^[^\#]\d+\.\d+\.\d+\.\d+)\s+\Q$hostname/) {
            $ip = $1;
            last;
        }
    }
    $data{'ip'} = $ip;
    $data{'agentIP'} = $nodeIp;

    my $os_ver = `oslevel -s`;
    chomp($os_ver);
    $data{'OS版本'} = 'AIX ' . $os_ver;

    my $bits = `bootinfo -y`;
    chomp($bits);
    $data{'位长'} = $bits;

    $data{'内核版本'} = "none";

    my $logicCPU = `grep Of\\ Processors prtconf.txt|cut -d ':' -f 2`;
    $logicCPU =~ s/^\s+|\s+$//g;
    $data{'CPU核数'} = $logicCPU;

    my $mem_info = `vmstat`;
    my $totalMemory;
    if ( $mem_info =~ /(?<=mem=)\d+MB/ ) {
        $totalMemory = $&;
    }
    chomp($totalMemory);
    $data{'内存'} = $totalMemory;

    my $ssh_ver = `ssh -V 2>&1 /dev/null | cut -d , -f 1`;
    chomp($ssh_ver);
    $data{'ssh版本'} = $ssh_ver;

    my $is_bond = `lsdev -Cc adapter|grep EtherChannel`;
    if ($is_bond) {
        $data{'bond'} = '是';
    }
    else {
        $data{'bond'} = '否';
    }

    my $df_output = `df -g`;
    if ( $df_output =~ /(\S+:\/\S+)/ ) {
        my @arr = $df_output =~ /\S+:\/\S+/g;
        my $tmp = join( ',', @arr );
        $data{'挂载NFS'} = $tmp;
    }
    else {
        $data{'挂载NFS'} = '否';
    }

    my $swap = `lsps -s|tail -n1|awk '{print \$1}'`;
    $swap =~ s/^\s+|\s+$//g;
    $data{'内存swap'} = $swap;

    my @patchs;
    foreach my $patch (`instfix -i|grep ML|awk \'{print \$4}\'`) {
        chomp($patch);
        push @patchs, $patch;
    }
    $data{'补丁情况'} = \@patchs;

    my @dns;
    if ( -e "/etc/resolv.conf" && -s "/etc/resolv.conf" ) {
        my @dns_info = `cat /etc/resolv.conf|grep nameserver\\ |awk \'{print \$2}\'` or die "cat /etc/resolv.coonf failed ";
        foreach (@dns_info) {
            chomp($_);
            push @dns, $_;
        }
    }
    else {
        @dns = '';
    }
    $data{'DNS服务'} = \@dns;

    my $ntpd_text = `lssrc -s xntpd`;
    if ( $ntpd_text =~ /active/i ) {
        $data{'是否启用NTP'} = 'running';
    }
    else {
        $data{'是否启用NTP'} = 'not running';
    }
    my $ntp_autostart = `cat /etc/rc.tcpip|grep xntp`;
    if ( $ntp_autostart =~ /^#/ ) {
        $data{'ntpd自启'} = '否';
    }
    else {
        $data{'ntpd自启'} = '是';
    }

    my @ntp;
    if ( -e "/etc/ntp.conf" && -s "/etc/ntp.conf" ) {
        my @ntp_info = `cat /etc/ntp.conf`;
        foreach my $line (@ntp_info) {
            if ( $line =~ /^(server)\s+(\d+\.\d+\.\d+\.\d+)/ ) {
                push @ntp, $2;
            }
        }
    }
    else {
        @ntp = '';
    }
    $data{'NTP服务器'} = \@ntp;

    my $mfo = `cat /etc/security/limits|grep ^[^#]`;
    $data{'最大打开文件数'} = $mfo;

    my $mpo = `lsattr -E -l sys0|grep maxuproc|awk '{print \$2}'`;
    $mpo =~ s/^\s+|\s+$//g;
    $data{'最大进程数'} = $mpo;

    my @arr_disks;

    my @name_sas = `lsdev -Cc disk|grep SAS|awk '{print \$1}'`;
    chomp(@name_sas);
    my @name_lun = `lsdev -Cc disk|grep MPIO|awk '{print \$1}'`;
    chomp(@name_lun);
    my %disk = ();
    foreach my $name (@name_sas) {

        $disk{'盘名称'} = $name;
        my $size = `bootinfo -s $name`;
        chomp($size);
        my $size_gb = int( $size / 1024 );

        $disk{'容量'} = $size_gb;

        $disk{'盘源'} = 'local';
        my %tmp_disk = %disk;

        push @arr_disks, \%tmp_disk;
    }
    foreach my $name (@name_lun) {
        $disk{'盘名称'} = $name;
        my $size = `bootinfo -s $name`;
        chomp($size);
        my $size_gb = int( $size / 1024 );

        $disk{'容量'} = $size_gb;
        $disk{'盘源'} = 'remote';

        my $lun_info = `lscfg -vpl $name`;

        my $sn;
        my $id;
        if ( $lun_info =~ /FlashSystem/ ) {
            my $output = `lsattr -El $name`;
            my $id_info;
            if ( $output =~ /unique_id\s+\S+\s+(\S+)/ ) {
                $id_info = $1;
            }
            if ( $id_info =~ /(?<=FlashSystem-9840)\w{8}/ ) {
                $sn = $&;
            }
            if ( $id_info =~ /\w{4}(?=10FlashSystem)/ ) {
                $id = $&;
            }
        }
        elsif ( $lun_info =~ /hitachi/i ) {
            if ( $lun_info =~ /Serial\sNumber\.+(\w+)/ ) {
                $sn = $1;
                if ( $sn eq '50403269' ) {
                    $sn = '412905';
                }
                elsif ( $sn eq '5040326B' ) {
                    $sn = '412907';
                }
            }
            if ( $lun_info =~ /\(Z1\)\.+(\w+)\s+/ ) {
                $id = $1;
                $id = '00' . $id;
                substr( $id, 2, 0 ) = ':';
                substr( $id, 5, 0 ) = ':';
            }

        }
        else {

            if ( $lun_info =~ /Serial\sNumber\.+(\w+)/ ) {
                my $sn_id = $1;
                $id = substr( $sn_id, -4 );
                $sn = substr( $sn_id, 0, -4 );
            }
        }
        $disk{'关联LUN'} = $sn . ':' . $id;
        $disk{'唯一标识'}  = $sn . ':' . $id;

        my %tmp_disk = %disk;

        push @arr_disks, \%tmp_disk;
    }

    #print Dumper(@arr_disks);
    $data{'逻辑磁盘'} = \@arr_disks;

    my @ips;

    my $ip_info = `ifconfig -a`;
    my @arr_ips = $ip_info =~ /(?<=inet\s)\d+\.\d+\.\d+\.\d+(?=\snetmask)/g;
    foreach (@arr_ips) {
        if ( $_ ne '127.0.0.1' ) {
            push @ips, $_;
        }
    }
    $data{'IP列表'} = \@ips;

    my @users;
    my %user_hash = ();
    open( FILE, "</etc/passwd" ) or die "can not open file: $!";
    while ( my $read_line = <FILE> ) {
        chomp($read_line);

        next if ( $read_line =~ /^#/ );
        my @list = split( /:/, $read_line );
        $user_hash{'用户名'} = $list[0];
        $user_hash{'uid'} = $list[2];
        next if ( $user_hash{'uid'} < 200 and $user_hash{'uid'} != 0 );
        $user_hash{'gid'}   = $list[3];
        $user_hash{'主目录'}   = $list[5];
        $user_hash{'命令解释器'} = $list[6];

        my %tmp_user = %user_hash;
        push @users, \%tmp_user;
    }
    close(FILE);
    $data{'用户列表'} = \@users;
    return \%data;
}

1;
