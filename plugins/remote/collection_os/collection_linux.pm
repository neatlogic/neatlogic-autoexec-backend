package collection_linux;

#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use utf8;

sub collect {
    my ($nodeIp) = @_;
    my @collect_data =();
    my %data     = ();
    my $hostname = `hostname`;
    chomp($hostname);
    $data{'主机名称'} = $hostname;

    my $ip = `hostname -i`;
    chomp($ip);
    if ( defined($ip) or $ip eq '' ) {
        $ip = $nodeIp;
    }
    $data{'IP'} = $ip;
    $data{'agentIP'} = $nodeIp;
    
    my $os_ver;
    if ( -e '/etc/redhat-release' ) {
        $os_ver = `cat /etc/redhat-release`;
        chomp($os_ver);
        $data{'OS版本'} = $os_ver;
    }
    elsif ( -e '/etc/SuSE-release' ) {
        $os_ver = `cat /etc/SuSE-release|grep Enterprise`;
        chomp($os_ver);
        $data{'OS版本'} = $os_ver;
    }

    $data{'虚拟机'} = '否';
    my $sn = `dmidecode -t 1|grep Serial\\ Number|cut -d : -f 2`;
    chomp($sn);
    $sn =~ s/^\s+|\s+$//g;
    if ( $sn =~ /vmware/i ) {
        $sn = '';
        $data{'虚拟机'} = '是';
    }
    $data{'服务器或CLUSTER'} = $sn;

    my $df_output = `df -h`;
    if ( $df_output =~ /(\S+:\/\S+)/ ) {
        my @arr = $df_output =~ /\S+:\/\S+/g;
        my $tmp = join( ',', @arr );
        $data{'挂载NFS'} = $tmp;
    }
    else {
        $data{'挂载NFS'} = '';
    }

    my $ssh_ver = `ssh -V 2>&1 > /dev/null |cut -d , -f 1`;
    chomp($ssh_ver);
    $data{'ssh版本'} = $ssh_ver;

    my $is_bond = `cat /proc/net/dev|grep bond`;
    if ($is_bond) {
        $data{'bond'} = '是';
    }
    else {
        $data{'bond'} = '否';
    }

    my $swap = `free -m|grep Swap|awk '{print \$2}'`;
    chomp($swap);
    $data{'内存swap'} = $swap . 'MB';

    my $bits = `getconf LONG_BIT`;
    chomp($bits);
    $data{'位长'} = $bits;

    my $kernel = `uname -a|awk \'{print \$3}\'`;
    chomp($kernel);
    $data{'内核版本'} = $kernel;

    my $logicCPU = `cat /proc/cpuinfo |grep processor |wc -l`;
    chomp($logicCPU);
    $data{'CPU核数'} = $logicCPU;

    my $totalMemory = `cat /proc/meminfo |grep MemTotal|awk '{print \$2}'`;
    $totalMemory = ( int( $totalMemory / 1024 ) ) . "MB";
    chomp($totalMemory);
    $data{'内存'} = $totalMemory;

    $data{'补丁情况'} = '';
    my @dns;
    if ( -e "/etc/resolv.conf" && -s "/etc/resolv.conf" ) {
        my @dns_info = `cat /etc/resolv.conf|grep nameserver\\ |awk \'{print \$2}\'`;
        if ( @dns_info == 0 ) {
            @dns = '';
        }
        else {
            foreach (@dns_info) {
                chomp($_);
                push @dns, $_;
            }
        }
    }
    else {
        @dns = '';
    }
    $data{'DNS服务'} = \@dns;

    if ( $data{'OS版本'} =~ /6\.\d+|5\.\d+/ ) {
        my $selinux_autostart = `cat /etc/selinux/config|grep ^[^#]`;
        if ( $selinux_autostart =~ /disabled/ ) {
            $data{'selinux自启'} = '否';
        }
        elsif ( $selinux_autostart =~ /enforcing/ ) {
            $data{'selinux自启'} = '是';
        }
        my $selinux_text = `getenforce`;
        if ( $selinux_text =~ /disabled/i ) {
            $data{'启用SELinux'} = '否';
        }
        else {
            $data{'启用SELinux'} = '是';
        }

        my $iptables_autostart = `chkconfig --list iptables`;
        chomp($iptables_autostart);
        if ( $iptables_autostart =~ /2:off\s+3:off\s+4:off\s+5:off/ or $iptables_autostart =~ /2:关闭\s+3:关闭\s+4:关闭\s+5:关闭/ ) {
            $data{'iptables自启'} = '否';
        }
        elsif ( $iptables_autostart =~ /2:on\s+3:on\s+4:on\s+5:on/ or $iptables_autostart =~ /2:启用\s+3:启用\s+4:启用\s+5:启用/ ) {
            $data{'iptables自启'} = '是';
        }
        else {
            $data{'iptables自启'} = '否';
        }
        my $iptables_text = `service iptables status`;

        if ( $iptables_text =~ /not\s+running/ or $iptables_text =~ /未运行|已停/ ) {
            $data{'启用iptables'} = '否';
        }
        elsif ( $iptables_text =~ /Table:\s+filter/ ) {
            $data{'启用iptables'} = '是';
        }
        else {
            $data{'启用iptables'} = '否';
        }

        my $ntpd_autostart = `chkconfig --list ntpd`;
        if ( $ntpd_autostart =~ /2:off\s+3:off\s+4:off\s+5:off/ or $ntpd_autostart =~ /2:关闭\s+3:关闭\s+4:关闭\s+5:关闭/ ) {
            $data{'ntpd自启'} = '否';
        }
        elsif ( $ntpd_autostart =~ /2:on\s+3:on\s+4:on\s+5:on/ or $ntpd_autostart =~ /2:启用\s+3:启用\s+4:启用\s+5:启用/ ) {
            $data{'ntpd自启'} = '是';
        }
        else {
            $data{'ntpd自启'} = '否';
        }
        my $ntpd_text = `service ntpd status`;
        if ( $ntpd_text =~ /stop/i or $ntpd_text =~ /未运行|已停|已死/ ) {
            $data{'启用NTP'} = '否';
        }
        elsif ( $ntpd_text =~ /running/ or $ntpd_text =~ /正在/ ) {
            $data{'启用NTP'} = '是';
        }
        else {
            $data{'启用NTP'} = '否';
        }

        my $netmanager_autostart = `chkconfig --list NetworkManager`;
        if ( $netmanager_autostart =~ /2:off\s+3:off\s+4:off\s+5:off/ or $netmanager_autostart =~ /2:关闭\s+3:关闭\s+4:关闭\s+5:关闭/ ) {
            $data{'NetworkManager自启'} = '否';
        }
        elsif ( $netmanager_autostart =~ /2:on\s+3:on\s+4:on\s+5:on/ or $netmanager_autostart =~ /2:启用\s+3:启用\s+4:启用\s+5:启用/ ) {
            $data{'NetworkManager自启'} = '是';
        }
        else {
            $data{'NetworkManager自启'} = '否';
        }

        my $networkman_text = `service NetworkManager status`;
        if ( $networkman_text =~ /stop/ or $networkman_text =~ /未运行|已停/ ) {
            $data{'启用NetworkManager'} = '否';
        }
        elsif ( $networkman_text =~ /running/ or $networkman_text =~ /正在/ ) {
            $data{'启用NetworkManager'} = '是';
        }
        else {
            $data{'启用NetworkManager'} = '否';
        }

        my @ntp;

        if ( -e "/etc/ntp.conf" && -s "/etc/ntp.conf" ) {
            my @ntp_info = `cat /etc/ntp.conf`;
            foreach my $line (@ntp_info) {
                if ( $line =~ /^(server)\s+(\d+\.\d+\.\d+\.\d+)\s+/ ) {
                    push @ntp, $2;
                }
            }
        }
        else {
            @ntp = '';
        }
        $data{'NTP服务器'} = \@ntp;
    }
    elsif ( $data{'OS版本'} =~ /7\.\d+/ ) {
        my $selinux_autostart = `cat /etc/selinux/config|grep ^[^#]`;
        if ( $selinux_autostart =~ /disabled/ ) {
            $data{'selinux自启'} = '否';
        }
        elsif ( $selinux_autostart =~ /enforcing/ ) {
            $data{'selinux自启'} = '是';
        }
        my $selinux_text = `getenforce`;
        if ( $selinux_text =~ /disabled/i ) {
            $data{'启用SELinux'} = '否';
        }
        else {
            $data{'启用SELinux'} = '是';
        }

        my $firewalld_status = `systemctl status firewalld`;
        if ( $firewalld_status =~ /(?<=Active:\s)active/ ) {
            $data{'启用iptables'} = '是';
        }
        elsif ( $firewalld_status =~ /(?<=Active:\s)inactive/ ) {
            $data{'启用iptables'} = '否';
        }

        if ( $firewalld_status =~ /firewalld\.service;\s+enabled/ ) {
            $data{'iptables自启'} = '是';
        }
        elsif ( $firewalld_status =~ /firewalld\.service;\s+disabled/ ) {
            $data{'iptables自启'} = '否';
        }

        my $chronyd_status = `systemctl status chronyd`;
        if ( $chronyd_status =~ /(?<=Active:\s)active/ ) {
            $data{'启用NTP'} = '是';
        }
        elsif ( $chronyd_status =~ /(?<=Active:\s)inactive/ ) {
            $data{'启用NTP'} = '否';
        }
        if ( $chronyd_status =~ /chronyd\.service;\s+enabled/ ) {
            $data{'ntpd自启'} = '是';
        }
        elsif ( $chronyd_status =~ /chronyd\.service;\s+disabled/ ) {
            $data{'ntpd自启'} = '否';
        }

        my $networkmanager_status = `systemctl status NetworkManager`;
        if ( $networkmanager_status =~ /(?<=Active:\s)active/ ) {
            $data{'启用NetworkManager'} = '是';
        }
        elsif ( $networkmanager_status =~ /(?<=Active:\s)inactive/ ) {
            $data{'启用NetworkManager'} = '否';
        }
        if ( $networkmanager_status =~ /NetworkManager\.service;\s+enabled/ ) {
            $data{'NetworkManager自启'} = '是';
        }
        elsif ( $networkmanager_status =~ /NetworkManager\.service;\s+disabled/ ) {
            $data{'NetworkManager自启'} = '否';
        }

        my @ntp;

        if ( -e "/etc/chrony.conf" && -s "/etc/chrony.conf" ) {
            my @ntp_info = `cat /etc/chrony.conf`;
            foreach my $line (@ntp_info) {
                if ( $line =~ /^(server)\s+(\d+\.\d+\.\d+\.\d+)\s+/ ) {
                    push @ntp, $2;
                }
            }
        }
        else {
            @ntp = '';
        }
        $data{'NTP服务器'} = \@ntp;
    }
    elsif ( $data{'OS版本'} =~ /suse/i ) {
        my $ntpd_autostart = `chkconfig --list ntp`;
        if ( $ntpd_autostart =~ /2:off\s+3:off\s+4:off\s+5:off/ or $ntpd_autostart =~ /2:关闭\s+3:关闭\s+4:关闭\s+5:关闭/ ) {
            $data{'ntpd自启'} = '否';
        }
        elsif ( $ntpd_autostart =~ /2:on\s+3:on\s+4:on\s+5:on/ or $ntpd_autostart =~ /2:启用\s+3:启用\s+4:启用\s+5:启用/ ) {
            $data{'ntpd自启'} = '是';
        }
        else {
            $data{'ntpd自启'} = '否';
        }
        my $ntpd_text = `service ntp status`;
        if ( $ntpd_text =~ /stop|unused/i or $ntpd_text =~ /未运行|已停|已死/ ) {
            $data{'启用NTP'} = '否';
        }
        elsif ( $ntpd_text =~ /running/ or $ntpd_text =~ /正在/ ) {
            $data{'启用NTP'} = '是';
        }
        else {
            $data{'启用NTP'} = '否';
        }

        my $iptables_autostart = `service SuSEfirewall2_setup status`;
        chomp($iptables_autostart);
        if ( $iptables_autostart =~ /2:off\s+3:off\s+4:off\s+5:off/ or $iptables_autostart =~ /2:关闭\s+3:关闭\s+4:关闭\s+5:关闭/ ) {
            $data{'iptables自启'} = '否';
        }
        elsif ( $iptables_autostart =~ /2:on\s+3:on\s+4:on\s+5:on/ or $iptables_autostart =~ /2:启用\s+3:启用\s+4:启用\s+5:启用/ ) {
            $data{'iptables自启'} = '是';
        }
        else {
            $data{'iptables自启'} = '否';
        }
        my $iptables_text = `rcSuSEfirewall2 status`;

        if ( $iptables_text =~ /unused/ or $iptables_text =~ /未运行|已停/ ) {
            $data{'启用iptables'} = '否';
        }
        elsif ( $iptables_text =~ /running/ ) {
            $data{'启用iptables'} = '是';
        }
        else {
            $data{'启用iptables'} = '否';
        }

        $data{'selinux自启'} = '否';
        $data{'启用SELinux'} = '否';

        my $netmanager_autostart = `chkconfig --list NetworkManager`;
        if ( $netmanager_autostart =~ /2:off\s+3:off\s+4:off\s+5:off/ or $netmanager_autostart =~ /2:关闭\s+3:关闭\s+4:关闭\s+5:关闭/ ) {
            $data{'NetworkManager自启'} = '否';
        }
        elsif ( $netmanager_autostart =~ /2:on\s+3:on\s+4:on\s+5:on/ or $netmanager_autostart =~ /2:启用\s+3:启用\s+4:启用\s+5:启用/ ) {
            $data{'NetworkManager自启'} = '是';
        }
        else {
            $data{'NetworkManager自启'} = '否';
        }

        my $networkman_text = `service NetworkManager status`;
        if ( $networkman_text =~ /stop|unused/ or $networkman_text =~ /未运行|已停/ ) {
            $data{'启用NetworkManager'} = '否';
        }
        elsif ( $networkman_text =~ /running/ or $networkman_text =~ /正在/ ) {
            $data{'启用NetworkManager'} = '是';
        }
        else {
            $data{'启用NetworkManager'} = '否';
        }
    }

    my $mfo;
    if ( -e "/etc/security/limits.conf" ) {
        $mfo = `cat /etc/security/limits.conf|grep ^[^#]`;
    }
    chomp($mfo);
    $data{'最大打开文件数'} = $mfo;

    my $mpo;
    if ( -e "/etc/security/limits.d" ) {
        my $file = `ls /etc/security/limits.d/`;
        chomp($file);
        if ($file) {
            my $abs_file = '/etc/security/limits.d/' . $file;
            $mpo = `cat $abs_file|grep ^[^#]`;
        }
    }
    chomp($mpo);
    $data{'最大进程数'} = $mpo;

    my @arr_disk;
    my @disk_output = `fdisk -l|grep Disk|grep sd`;

    foreach my $disk (@disk_output) {
        my %l_disk = ();
        my @splits = split /\s+/, $disk;
        my $d_name = $splits[1];
        $d_name =~ s/://g;
        $l_disk{'盘名称'} = $d_name;
        my $d_size = $splits[2];
        $l_disk{'容量'} = $d_size + "GB";
        $l_disk{'盘源'} = 'local';
        push @arr_disk, \%l_disk;
    }

    my @arr_lun;

    my @list_sn;
    my @array_sn = `upadmin show array`;
    if ( @array_sn != 0 ) {
        @array_sn = splice @array_sn, 2, -1;
        foreach (@array_sn) {
            my %sn;
            my @splits = split /\s+/, $_;
            $sn{'name'} = $splits[2];
            $sn{'sn'}   = $splits[3];
            push @list_sn, \%sn;
        }
    }

    my @hw_lun = `upadmin show vlun`;
    if ( @hw_lun != 0 ) {
        @hw_lun = splice @hw_lun, 2, -1;
        foreach (@hw_lun) {
            my %lun;
            my @splits = split /\s+/, $_;
            $lun{'name'}  = '/dev/' . $splits[2];
            $lun{'wwn'}   = $splits[4];
            $lun{'array'} = $splits[8];
            foreach my $array_sn (@list_sn) {
                if ( $lun{'array'} eq $$array_sn{'name'} ) {
                    $lun{'sn'} = $$array_sn{'sn'};
                }
            }
            push @arr_lun, \%lun;
        }
    }

    my @fake_lun;
    if ( -e '/opt/DynamicLinkManager/bin/dlnkmgr' ) {

        chdir('/opt/DynamicLinkManager/bin');
        @fake_lun = `./dlnkmgr view -lu|grep /dev/|awk '{print \$(NF-2)}'`;
        chomp(@fake_lun);

        my $output = `./dlnkmgr view -lu`;
        my @splits = split /(?<=Online)\s+(?=Product)/, $output;
        foreach my $split (@splits) {
            my $sn;
            if ( $split =~ /SerialNumber\s+:\s+(\d+)/ ) {
                $sn = $1;
            }
            my @arr = $split =~ /(\w+\s+sdd\w+)/g;
            foreach (@arr) {
                my %lun;
                my ( $id, $name ) = split /\s+/, $_;
                substr( $id, 2, 0 ) = ':';
                substr( $id, 5, 0 ) = ':';
                $name        = '/dev/' . $name;
                $lun{'name'} = $name;
                $lun{'wwn'}  = $id;
                $lun{'sn'}   = $sn;
                push @arr_lun, \%lun;
            }
        }
    }
    foreach my $disk (@arr_disk) {
        foreach my $lun (@arr_lun) {
            if ( $$disk{'盘名称'} eq $$lun{'name'} ) {
                $$disk{'盘源'}    = 'remote';
                $$disk{'关联LUN'} = $$lun{'sn'} . ':' . $$lun{'wwn'};
                $$disk{'唯一标识'}  = $$lun{'sn'} . ':' . $$lun{'wwn'};
            }
        }
    }

    my @new_disk;
    if (@fake_lun) {
        foreach my $disk (@arr_disk) {
            my $name = $$disk{'盘名称'};
            if ( !grep /^\Q$name\E$/, @fake_lun ) {
                push @new_disk, $disk;
            }

        }
        $data{'逻辑磁盘'} = \@new_disk;
    }
    else {
        $data{'逻辑磁盘'} = \@arr_disk;
    }
    my @ips;

    my $ip_info = `ip addr`;
    my @arr_ips = $ip_info =~ /(?<=inet\s)\d+\.\d+\.\d+\.\d+(?=\/\d\d)/g;
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
        next if ( $user_hash{'uid'} < 500 and $user_hash{'uid'} != 0 );
        $user_hash{'gid'}   = $list[3];
        $user_hash{'主目录'}   = $list[5];
        $user_hash{'命令解释器'} = $list[6];

        my %tmp_user = %user_hash;
        push @users, \%tmp_user;
    }
    close(FILE);
    $data{'用户列表'} = \@users;
    
    push(@collect_data , \%data);
    return @collect_data;
}

1;
