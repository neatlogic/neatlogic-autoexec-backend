#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/../../lib";

use strict;

package OSGatherLinux;

use OSGatherBase;
our @ISA = qw(OSGatherBase);

use POSIX;
use Cwd;
use IO::File;

sub collect {
    my ($self)   = @_;
    my $hostInfo = {};
    my $osInfo   = {};

    my $machineId = $self->getFileContent('/etc/machine-id');
    $machineId =~ /^\s*|\s*$//g;
    $osInfo->{MACHINE_ID} = $machineId;

    my @unameInfo = uname();
    my $hostName  = $unameInfo[1];
    $osInfo->{OSTYPE}         = $unameInfo[0];
    $osInfo->{HOSTNAME}       = $hostName;
    $osInfo->{KERNEL_VERSION} = $unameInfo[2];

    my $osVer;
    if ( -e '/etc/redhat-release' ) {
        $osVer = $self->getFileContent('/etc/redhat-release');
        chomp($osVer);
    }
    elsif ( -e '/etc/SuSE-release' ) {
        my $verLines = $self->getFileLines('/etc/SuSE-release');
        $osVer = grep( 'Enterprise', @$verLines );
        chomp($osVer);
    }
    $osInfo->{VERSION} = $osVer;

    #cat /sys/class/dmi/id/sys_vendor #
    #cat cat /sys/class/dmi/id/product_name
    my $sysVendor = $self->getFileContent('/sys/class/dmi/id/sys_vendor');
    $sysVendor =~ s/^\*|\s$//g;
    my $productUUID = $self->getFileContent('/sys/class/dmi/id/product_uuid');
    $productUUID =~ s/^\*|\s$//g;
    my $productName = $self->getFileContent('/sys/class/dmi/id/product_name');
    $productName =~ s/^\*|\s$//g;
    $osInfo->{IS_VIRTUAL} = 0;
    if ( $productName eq 'KVM' or $productName eq 'VirtualBox' or $productName eq 'VMware Virtual Platform' ) {
        $osInfo->{IS_VIRTUAL} = 1;
    }
    $osInfo->{SYS_VENDOR}   = $sysVendor;
    $osInfo->{PRODUCT_NAME} = $productName;
    $osInfo->{PRODUCT_UUID} = $productUUID;

    my $boardSerial = $self->getFileContent('/sys/class/dmi/id/board_serial');
    $boardSerial =~ s/^\*|\s$//g;
    $osInfo->{BOARD_SERIAL} = $boardSerial;

    #my ($fs_type, $fs_desc, $used, $avail, $fused, $favail) = df($dir);
    #TODO: df
    my $diskMountMap = {};
    my @mountPoints  = ();
    my $mountFilter  = {
        'autofs'      => 1,
        'binfmt_misc' => 1,
        'cgroup'      => 1,
        'configfs'    => 1,
        'debugfs'     => 1,
        'devpts'      => 1,
        'devtmpfs'    => 1,
        'hugetlbfs'   => 1,
        'mqueue'      => 1,
        'proc'        => 1,
        'pstore'      => 1,
        'rootfs'      => 1,
        'rpc_pipefs'  => 1,
        'securityfs'  => 1,
        'selinuxfs'   => 1,
        'sysfs'       => 1,
        'tmpfs'       => 1
    };
    my $mountLines = $self->getFileLines('/proc/mounts');
    foreach my $line (@$mountLines) {

        # The 1st column specifies the device that is mounted.
        # The 2nd column reveals the mount point.
        # The 3rd column tells the file-system type.
        # The 4th column tells you if it is mounted read-only (ro) or read-write (rw).
        # The 5th and 6th columns are dummy values designed to match the format used in /etc/mtab.
        my @mountInfos = split( /\s+/, $line );
        my $device     = shift(@mountInfos);
        my $fsckOrder  = pop(@mountInfos);
        my $dump       = pop(@mountInfos);
        my $fsFlags    = pop(@mountInfos);
        my $fsType     = pop(@mountInfos);
        my $mountPoint = substr( $line, length($device) + 1, length($line) - length($device) - length($fsckOrder) - length($dump) - length($fsFlags) - length($fsType) - 6 );

        $osInfo->{NFS_MOUNTED} = 0;
        if ( $fsType =~ /^nfs/i ) {
            $osInfo->{NFS_MOUNTED} = 1;
        }
        if ( not defined( $mountFilter->{$fsType} ) ) {
            my $mountInfo = {};
            $mountInfo->{DEVICE}      = $device;
            $mountInfo->{MOUNT_POINT} = $mountPoint;
            $mountInfo->{FS_TYPE}     = $fsType;

            if ( $fsType !~ /^nfs/i ) {
                $diskMountMap->{$mountPoint} = $mountInfo;
            }
            push( @mountPoints, $mountInfo );
        }
    }
    my @diskMountPoints = keys(%$diskMountMap);
    if ( scalar(@diskMountPoints) > 0 ) {
        my $dfLines = $self->getCmdOutLines( "LANG=C df -m '" . join( "' '", @diskMountPoints ) . "'" );
        foreach my $line (@$dfLines) {
            if ( $line =~ /(\d+)\s+(\d+)\s+(\d+)\s+(\d+%)\s+(.*)$/ ) {
                my $totalSize  = int($1);
                my $usedSize   = int($2);
                my $availSize  = int($3);
                my $utility    = $4;
                my $mountPoint = $5;
                chomp($mountPoint);
                my $mountInfo = $diskMountMap->{$mountPoint};
                if ( defined($mountInfo) ) {
                    $mountInfo->{CAPACITY}  = $totalSize;
                    $mountInfo->{USED}      = $usedSize;
                    $mountInfo->{AVAILABLE} = $availSize;
                    $mountInfo->{'USED%'}   = $utility;
                }
            }
        }
    }
    $osInfo->{MOUNT_POINTS} = \@mountPoints;

    #OpenSSH_6.6.1p1, OpenSSL 1.0.1e-fips 11 Feb 2013
    my $sshInfoLine = $self->getCmdOut('ssh -V 2>&1');
    if ( $sshInfoLine =~ /(.*?),\s*OpenSSL\s+(.*?)\s/i ) {
        $osInfo->{SSH_VERSION}     = $1;
        $osInfo->{OPENSSL_VERSION} = $2;
    }
    else {
        $osInfo->{SSH_VERSION}     = undef;
        $osInfo->{OPENSSL_VERSION} = undef;
    }

    my $bondInfoLine = $self->getCmdOut('cat /proc/net/dev|grep bond');
    if ($bondInfoLine) {
        $osInfo->{NIC_BOND} = 1;
    }
    else {
        $osInfo->{NIC_BOND} = 0;
    }

    my $memInfoLines = $self->getCmdOutLines('free -m');
    foreach my $line (@$memInfoLines) {
        if ( $line =~ /Swap:\s+(\d+)/ ) {
            $osInfo->{SWAP_SIZE} = $1 . 'M';
        }
    }

    my $bitsInfo = $self->getCmdOut('getconf LONG_BIT');
    chomp($bitsInfo);
    $osInfo->{BITS} = $bitsInfo;

    my $logicCPUCount = $self->getCmdOut('cat /proc/cpuinfo |grep processor |wc -l');
    chomp($logicCPUCount);
    $osInfo->{CPU_CORES} = $logicCPUCount;

    my $memInfoLines = $self->getFileLines('/proc/meminfo');
    my $memInfo      = {};
    foreach my $line (@$memInfoLines) {
        my @lineInfo = split( /:\s*|\s+/, $line );
        $memInfo->{ $lineInfo[0] } = sprintf( '%.2fM', int( $lineInfo[1] ) / 1024 );
    }
    $osInfo->{MEM_TOTAL}     = $memInfo->{MemTotal};
    $osInfo->{MEM_FREE}      = $memInfo->{MemFree};
    $osInfo->{MEM_AVAILABLE} = $memInfo->{MemAvailable};
    $osInfo->{MEM_CACHED}    = $memInfo->{Cached};
    $osInfo->{MEM_BUFFERS}   = $memInfo->{Buffers};
    $osInfo->{SWAP_TOTAL}    = $memInfo->{SwapTotal};
    $osInfo->{SWAP_FREE}     = $memInfo->{SwapFree};

    my @dnsServers;
    my $dnsInfoLines = $self->getFileLines('/etc/resolv.conf');
    foreach my $line (@$dnsInfoLines) {
        if ( $line =~ /\s*nameserver\s+(.*)\s*$/i ) {
            push( @dnsServers, $1 );
        }
    }
    $osInfo->{DNS_SERVERS} = \@dnsServers;

    my $isSystemd = $self->getCmdOut('pidof systemd');
    $isSystemd =~ s/^\s*|\s*$//g;
    my $services = {};
    if ( $isSystemd eq '1' ) {
        my $serviceLines = $self->getCmdOutLines('systemctl list-units -a');
        foreach my $line (@$serviceLines) {
            if ( $line =~ /^(?:\xe2\x97\x8f)?\s*(\w+)\.service\s+(\w+)\s+(\w+)\s+\w+\s+(.*?)$/ ) {
                my $service = {};
                my $name    = $1;
                my $enable  = $2;
                my $active  = $3;
                $service->{DESC} = $4;
                $service->{NAME} = $name;
                if ( $enable eq 'loaded' ) {
                    $service->{ENABLE} = 1;
                }
                else {
                    $service->{ENABLE} = 0;
                }
                if ( $active eq 'active' ) {
                    $service->{ACTIVE} = 1;
                }
                else {
                    $service->{ACTIVE} = 0;
                }
                $services->{$name} = $service;
            }
        }
    }
    else {
        my $serviceLines = $self->getCmdOutLines('chkconfig --list');
        foreach my $line (@$serviceLines) {
            if ( $line =~ /^\s*(\w+)\s+.*?3:(\w+)/ ) {
                my $service = {};
                my $name    = $1;
                my $enable  = $2;
                my $active  = $2;
                $service->{NAME} = $1;
                if ( $enable eq 'on' ) {
                    $service->{ENABLE} = 1;
                    $service->{ACTIVE} = 1;
                }
                else {
                    $service->{ENABLE} = 0;
                    $service->{ACTIVE} = 0;
                }
                $services->{$name} = $service;
            }
        }
    }

    my $firewallService = $services->{iptables};
    if ( not defined($firewallService) ) {
        $firewallService = $services->{firewalld};
    }
    if ( not defined($firewallService) ) {
        $firewallService = $services->{SuSEfirewall2_setup};
    }
    $osInfo->{FIREWALL_ENABLE} = 0;
    if ( $firewallService->{ENABLE} ) {
        $osInfo->{FIREWALL_ENABLE} = 1;
    }

    my $ntpService = $services->{ntpd};
    if ( not defined($ntpService) ) {
        $ntpService = $services->{chronyd};
    }
    if ( not defined($ntpService) ) {
        $ntpService = $services->{ntp};
    }
    $osInfo->{NTP_ENABLE} = 0;
    if ( $ntpService->{ENABLE} ) {
        $osInfo->{NTP_ENABLE} = 1;
    }

    my $networkmanagerService = $services->{NetworkManager};
    $osInfo->{NETWORKMANAGER_ENABLE} = 0;
    if ( defined($networkmanagerService) and $networkmanagerService->{ENABLE} ) {
        $osInfo->{NETWORKMANAGER_ENABLE} = 1;
    }

    my $selinuxConfig;
    my $selinuxInfoLines = $self->getFileLines('/etc/selinux/config');
    foreach my $line (@$selinuxInfoLines) {
        if ( $line =~ /^\s*SELINUX\s*=\s*(\w+)\s*$/ ) {
            $selinuxConfig = $1;
            last;
        }
    }
    $osInfo->{SELINUX_STATUS} = $selinuxConfig;

    my $ntpConfFile = '/etc/ntp.conf';
    if ( not -f $ntpConfFile ) {
        $ntpConfFile = '/etc/chrony.conf';
    }
    my $ntpInfoLines = $self->getFileLines($ntpConfFile);
    my @ntpServers   = ();
    foreach my $line (@$ntpInfoLines) {
        if ( $line =~ /^server\s+(\d+\.\d+\.\d+\.\d+)/i ) {
            push( @ntpServers, $1 );
        }
    }
    $osInfo->{NTP_SERVERS} = \@ntpServers;

    my $maxOpenFiles = $self->getFileContent('/proc/sys/fs/file-max');
    $maxOpenFiles =~ s/^\s*|\s*$//g;
    $osInfo->{MAX_OPEN_FILES} = $maxOpenFiles;

    my @ipv4;
    my @ipv6;
    my $ipInfoLines = $self->getCmdOutLines('ip addr');
    foreach my $line (@$ipInfoLines) {
        my $ip;
        if ( $line =~ /^\s*inet\s+(.*?)\/\d+/ ) {
            $ip = $1;
            if ( $ip !~ /^127\./ ) {
                push( @ipv4, $ip );
            }
        }
        elsif ( $line =~ /^\s*inet6\s+(.*?)\/\d+/ ) {
            $ip = $1;
            if ( $ip ne '::1' ) {    #TODO: ipv6 loop back addr range
                push( @ipv6, $ip );
            }
        }
    }
    $osInfo->{IP_ADDRS}   = \@ipv4;
    $osInfo->{IPV6_ADDRS} = \@ipv6;

    my @users;

    my $passwdLines = $self->getFileLines('/etc/passwd');
    foreach my $line (@$passwdLines) {
        $line =~ s/^\s*|\s*$//g;
        if ( $line !~ /^#/ ) {
            my $usersMap = {};
            my @userInfo = split( /:/, $line );

            $usersMap->{NAME} = $userInfo[0];
            $usersMap->{UID}  = $userInfo[2];

            if ( $usersMap->{UID} < 500 and $usersMap->{UID} != 0 ) {
                next;
            }

            $usersMap->{GID}   = $userInfo[3];
            $usersMap->{HOME}  = $userInfo[5];
            $usersMap->{SHELL} = $userInfo[6];

            push( @users, $usersMap );
        }
    }
    $osInfo->{USERS} = \@users;

    #TODO: SAN磁盘的计算以及磁盘多链路聚合的计算，因没有测试环境，需要再确认
    my @diskInfos;
    my $diskLines = $self->getCmdOutLines('LANG=C fdisk -l|grep Disk|grep sd');

    foreach my $line (@$diskLines) {
        my $diskInfo = {};
        my @diskSegs = split( /\s+/, $line );
        my $name     = $diskSegs[1];
        $name =~ s/://g;
        $diskInfo->{NAME} = $name;
        my $size = $diskSegs[2];
        $diskInfo->{CAPACITY} = $size + "G";
        $diskInfo->{TYPE}     = 'local';
        push( @diskInfos, $diskInfo );
    }

    #TODO: SAN磁盘的计算以及磁盘多链路聚合的计算，因没有测试环境，需要再确认
    my $lunInfosMap    = {};
    my $arrayInfosMap  = {};
    my $arrayInfoLines = $self->getCmdOutLines('upadmin show array');
    if ( defined($arrayInfoLines) and scalar(@$arrayInfoLines) > 2 ) {
        foreach my $line ( splice( @$arrayInfoLines, 2, -1 ) ) {
            my $arrayInfo = {};
            my @infos = split( /\s+/, $line );
            $arrayInfo->{NAME}                     = $infos[2];
            $arrayInfo->{SN}                       = $infos[3];
            $arrayInfosMap->{ $arrayInfo->{NAME} } = $arrayInfo;
        }
    }

    my $hwLunInfoLines = $self->getCmdOutLines('upadmin show vlun');
    if ( defined($hwLunInfoLines) and @$hwLunInfoLines > 0 ) {
        foreach my $line ( splice( @$hwLunInfoLines, 2, -1 ) ) {
            my $lunInfo = {};
            my @infos = split( /\s+/, $line );
            $lunInfo->{NAME}  = '/dev/' . $infos[2];
            $lunInfo->{WWN}   = $infos[4];
            $lunInfo->{ARRAY} = $infos[8];
            my $arrayInfo = $arrayInfosMap->{ $lunInfo->{ARRAY} };
            if ( defined($arrayInfo) ) {
                $lunInfo->{SN} = $arrayInfo->{SN};
            }
            $lunInfosMap->{ $lunInfo->{NAME} } = $lunInfo;
        }
    }

    my $aggrLunInfoLines;
    if ( -e '/opt/DynamicLinkManager/bin/dlnkmgr' ) {
        my $currentDir = getcwd();

        chdir('/opt/DynamicLinkManager/bin');
        $aggrLunInfoLines = $self->getCmdOutLines(q{./dlnkmgr view -lu|grep /dev/|awk '{print \$(NF-2)}'});
        my $lunInfoContent = $self->getCmdOut('./dlnkmgr view -lu');
        chdir($currentDir);

        my @splits = split( /(?<=Online)\s+(?=Product)/, $lunInfoContent );
        foreach my $split (@splits) {
            my $sn;
            if ( $split =~ /SerialNumber\s+:\s+(\d+)/ ) {
                $sn = $1;
            }
            my @lunInfoLines = $split =~ /(\w+\s+sdd\w+)/g;
            foreach my $line (@lunInfoLines) {
                my $lunInfo = {};
                my ( $id, $name ) = split( /\s+/, $line );
                substr( $id, 2, 0 ) = ':';    #在index是2的字符前插入冒号
                substr( $id, 5, 0 ) = ':';
                $name                              = "/dev/$name";
                $lunInfo->{NAME}                   = $name;
                $lunInfo->{WWN}                    = $id;
                $lunInfo->{SN}                     = $sn;
                $lunInfosMap->{ $lunInfo->{NAME} } = $lunInfo;
            }
        }
    }

    foreach my $diskInfo (@diskInfos) {
        my $diskName = $diskInfo->{NAME};
        my $lunInfo  = $lunInfosMap->{$diskName};
        if ( defined($lunInfo) ) {
            $diskInfo->{TYPE} = 'remote';
            $diskInfo->{LUN}  = $lunInfo->{SN} . ':' . $lunInfo->{WWN};
            $diskInfo->{ID}   = $lunInfo->{SN} . ':' . $lunInfo->{WWN};
        }
    }

    my @singleDisks;
    if ( defined($aggrLunInfoLines) and scalar(@$aggrLunInfoLines) > 0 ) {
        foreach my $diskInfo (@diskInfos) {
            my $name = $diskInfo->{NAME};
            if ( not grep( /^\Q$name\E$/, @$aggrLunInfoLines ) ) {
                push( @singleDisks, $diskInfo );
            }

        }
        $osInfo->{DISKS} = \@singleDisks;
    }
    else {
        $osInfo->{DISKS} = \@diskInfos;
    }

    return ( $hostInfo, $osInfo );
}

1;
