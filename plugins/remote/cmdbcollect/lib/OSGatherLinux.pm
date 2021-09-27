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
use File::Basename;

sub collectOsInfo {
    my ($self) = @_;

    my $utils  = $self->{collectUtils};
    my $osInfo = {};

    my $machineId = $self->getFileContent('/etc/machine-id');
    $machineId =~ s/^\s*|\s*$//g;
    $osInfo->{MACHINE_ID} = $machineId;

    my @unameInfo = uname();
    my $hostName  = $unameInfo[1];
    $osInfo->{OS_TYPE}        = $unameInfo[0];
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
    #cat /sys/class/dmi/id/product_name
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
            $mountInfo->{DEVICE}  = $device;
            $mountInfo->{NAME}    = $mountPoint;
            $mountInfo->{FS_TYPE} = $fsType;

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
                    $mountInfo->{CAPACITY}  = int( $totalSize * 1000 / 1024 + 0.5 ) / 1000;
                    $mountInfo->{USED}      = int( $usedSize * 1000 / 1024 + 0.5 ) / 1000;
                    $mountInfo->{AVAILABLE} = int( $availSize * 1000 / 1024 + 0.5 ) / 1000;
                    $mountInfo->{UNIT}      = 'GB';
                    $mountInfo->{'USED%'}   = $utility + 0.0;
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

    # my $memInfoLines = $self->getCmdOutLines('free -m');
    # foreach my $line (@$memInfoLines) {
    #     if ( $line =~ /Swap:\s+(\d+)/ ) {
    #         $osInfo->{SWAP_SIZE} = int($1);
    #     }
    # }

    my $cpuArch = ( POSIX::uname() )[4];
    $osInfo->{CPU_ARCH} = $cpuArch;

    # my $logicCPUCount = $self->getCmdOut('cat /proc/cpuinfo |grep processor |wc -l');
    # chomp($logicCPUCount);
    # $osInfo->{CPU_CORES} = $logicCPUCount;

    my $memInfoLines = $self->getFileLines('/proc/meminfo');
    my $memInfo      = {};
    foreach my $line (@$memInfoLines) {
        my @lineInfo = split( /:\s*|\s+/, $line );
        $memInfo->{ $lineInfo[0] } = $lineInfo[1] . $lineInfo[2];
    }
    $osInfo->{MEM_TOTAL}     = $utils->getMemSizeFromStr( $memInfo->{MemTotal} );
    $osInfo->{MEM_FREE}      = $utils->getMemSizeFromStr( $memInfo->{MemFree} );
    $osInfo->{MEM_AVAILABLE} = $utils->getMemSizeFromStr( $memInfo->{MemAvailable} );
    $osInfo->{MEM_CACHED}    = $utils->getMemSizeFromStr( $memInfo->{Cached} );
    $osInfo->{MEM_BUFFERS}   = $utils->getMemSizeFromStr( $memInfo->{Buffers} );
    $osInfo->{SWAP_TOTAL}    = $utils->getMemSizeFromStr( $memInfo->{SwapTotal} );
    $osInfo->{SWAP_FREE}     = $utils->getMemSizeFromStr( $memInfo->{SwapFree} );

    my @dnsServers;
    my $dnsInfoLines = $self->getFileLines('/etc/resolv.conf');
    foreach my $line (@$dnsInfoLines) {
        if ( $line =~ /\s*nameserver\s+(.*)\s*$/i ) {
            push( @dnsServers, { VALUE => $1 } );
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
            push( @ntpServers, { VALUE => $1 } );
        }
    }
    $osInfo->{NTP_SERVERS} = \@ntpServers;

    my $maxOpenFiles = $self->getFileContent('/proc/sys/fs/file-max');
    $maxOpenFiles =~ s/^\s*|\s*$//g;
    $osInfo->{MAX_OPEN_FILES} = int($maxOpenFiles);

    my @ipv4;
    my @ipv6;
    my $ipInfoLines = $self->getCmdOutLines('ip addr');
    foreach my $line (@$ipInfoLines) {
        my $ip;
        if ( $line =~ /^\s*inet\s+(.*?)\/\d+/ ) {
            $ip = $1;
            if ( $ip !~ /^127\./ ) {
                push( @ipv4, { VALUE => $ip } );
            }
        }
        elsif ( $line =~ /^\s*inet6\s+(.*?)\/\d+/ ) {
            $ip = $1;
            if ( $ip ne '::1' ) {    #TODO: ipv6 loop back addr range
                push( @ipv6, { VALUE => $ip } );
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
            if ( $userInfo[0] eq 'nobody' ) {
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
    my $diskLines = $self->getCmdOutLines('LANG=C fdisk -l');

    foreach my $line (@$diskLines) {
        if ( $line =~ /^\s*Disk\s+\// ) {
            my $diskInfo = {};
            my @diskSegs = split( /\s+/, $line );
            my $name     = $diskSegs[1];
            $name =~ s/://g;
            $diskInfo->{NAME} = $name;
            my $size = $diskSegs[2];
            my $unit = $diskSegs[3];
            ( $diskInfo->{UNIT}, $diskInfo->{CAPACITY} ) = $utils->getDiskSizeFormStr( $size . $unit );

            if ( $diskSegs[1] =~ /\/dev\/sd/ ) {
                $diskInfo->{TYPE} = 'local';
            }
            elsif ( $diskSegs[1] =~ /\/dev\/mapper\// ) {
                $diskInfo->{TYPE} = 'lvm';
            }
            else {
                $diskInfo->{TYPE} = 'remote';
            }
            push( @diskInfos, $diskInfo );
        }
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
            $diskInfo->{WWID} = $lunInfo->{SN} . ':' . $lunInfo->{WWN};
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

    return $osInfo;
}

sub collectHostInfo {
    my ($self) = @_;

    my $utils    = $self->{collectUtils};
    my $hostInfo = {};

    my $machineId = $self->getFileContent('/etc/machine-id');
    $machineId =~ s/^\s*|\s*$//g;
    $hostInfo->{MACHINE_ID} = $machineId;

    my $sn = $self->getCmdOut('dmidecode -s system-serial-number');
    $sn =~ s/^\*|\s$//g;
    $hostInfo->{BOARD_SERIAL} = $sn;

    my $productName = $self->getFileContent('/sys/class/dmi/id/product_name');
    $productName =~ s/^\*|\s$//g;
    $hostInfo->{PRODUCT_NAME} = $productName;

    my $vendorName = $self->getFileContent('/sys/class/dmi/id/sys_vendor');
    $vendorName =~ s/^\*|\s$//g;
    $hostInfo->{MANUFACTURER} = $vendorName;

    my $biosVersion = $self->getFileContent('/sys/class/dmi/id/bios_version');
    $biosVersion =~ s/^\*|\s$//g;
    $hostInfo->{BIOS_VERSION} = $biosVersion;

    my $cpuCount     = 0;
    my $cpuInfoLines = $self->getFileLines('/proc/cpuinfo');
    my $pCpuMap      = {};
    my $cpuInfo      = {};
    for ( my $i = 0 ; $i < scalar(@$cpuInfoLines) ; $i++ ) {
        my $line = $$cpuInfoLines[$i];
        $line =~ s/^\s*|\s*$//g;
        if ( $line ne '' ) {
            my @info = split( /\s*:\s*/, $line );
            $cpuInfo->{ $info[0] } = $info[1];
            if ( $info[0] eq 'physical id' ) {
                $pCpuMap->{ $info[1] } = 1;
            }
        }
    }
    $hostInfo->{CPU_COUNT}     = scalar( keys(%$pCpuMap) );
    $hostInfo->{CPU_CORES}     = int( $cpuInfo->{processor} ) + 1;
    $hostInfo->{CPU_MICROCODE} = $cpuInfo->{microcode};
    my @modelInfo = split( /\s*\@\s*/, $cpuInfo->{'model name'} );
    $hostInfo->{CPU_MODEL_NAME} = $modelInfo[0];
    $hostInfo->{CPU_FREQUENCY}  = $modelInfo[1];
    my $cpuArch = ( POSIX::uname() )[4];
    $hostInfo->{CPU_ARCH} = $cpuArch;

    my $memInfoLines = $self->getCmdOutLines('dmidecode -t memory');
    my $usedSlots    = 0;
    my $memInfo      = {};
    for ( my $i = 0 ; $i < scalar(@$memInfoLines) ; $i++ ) {
        my $line = $$memInfoLines[$i];
        $line =~ s/^\s*|\s*$//g;
        if ( $line ne '' ) {
            my @info = split( /\s*:\s*/, $line );
            $memInfo->{ $info[0] } = $info[1];
            if ( $info[0] eq 'Size' ) {
                if ( $info[1] =~ /^(\d+)/ ) {
                    $usedSlots = $usedSlots + 1;
                }
            }
        }
    }
    $hostInfo->{MEM_SLOTS}            = int( $memInfo->{'Number Of Devices'} );
    $hostInfo->{MEM_MAXIMUM_CAPACITY} = $utils->getMemSizeFromStr( $memInfo->{'Maximum Capacity'} );
    $hostInfo->{MEM_SPEED}            = $memInfo->{Speed};

    my $chassisInfoLines = $self->getCmdOutLines('dmidecode -t chassis');
    my $chassisInfo      = {};
    foreach my $line (@$chassisInfoLines) {
        $line =~ s/^\s*|\s*$//g;
        if ( $line ne '' ) {
            my @info = split( /\s*:\s*/, $line );
            $chassisInfo->{ $info[0] } = $info[1];
        }
    }
    $hostInfo->{POWER_CORDS_COUNT} = $chassisInfo->{'Number Of Power Cords'};

    my @nicInfos         = ();
    my $nicInfoLines     = $self->getCmdOutLines('ip addr');
    my $nicInfoLineCount = scalar(@$nicInfoLines);
    for ( my $i = 0 ; $i < $nicInfoLineCount ; $i++ ) {
        my $line    = $$nicInfoLines[$i];
        my $nicInfo = {};
        my ( $ethName, $macAddr, $ipAddr, $speed, $linkState );
        if ( $line =~ /^\d+:\s+(\S+):/ ) {
            $ethName = $1;
            my ( $ethtoolState, $ethtoolLines ) = $self->getCmdOutLines("ethtool $ethName");
            if ( $ethtoolState == 0 ) {
                foreach my $ethLine (@$ethtoolLines) {
                    if ( $ethLine =~ /^\s*Speed:\s*(\S+)/ ) {
                        $speed = $1;
                    }
                    elsif ( $ethLine =~ /^\s*Link detected:\s*(\S+)/ ) {
                        $linkState = $1;
                    }
                }
            }
            $i    = $i + 1;
            $line = $$nicInfoLines[$i];
            while ( $i < $nicInfoLineCount and $line !~ /^\d+:\s+(\S+):/ ) {
                if ( $line =~ /^\s*link\/ether\s+(.*?)\s+/i ) {
                    $macAddr = $1;
                }
                elsif ( $line =~ /^\s*inet\s(\d+\.\d+\.\d+\.\d+)/ ) {
                    $ipAddr = $1;
                }
                $i    = $i + 1;
                $line = $$nicInfoLines[$i];
            }

            if ( defined($speed) and $speed ne '' ) {
                $nicInfo->{NAME} = $ethName;
                $nicInfo->{MAC}  = $macAddr;
                ( $nicInfo->{UNIT}, $nicInfo->{SPEED} ) = $utils->getNicSpeedFromStr($speed);
                $nicInfo->{LINK_STATE} = 'down';
                if ( $linkState eq 'yes' ) {
                    $nicInfo->{LINK_STATE} = 'up';
                }
                push( @nicInfos, $nicInfo );
            }

            $i = $i - 1;
        }
    }
    $hostInfo->{ETH_INTERFACES} = \@nicInfos;

    my @hbaInfos = ();
    foreach my $fcHostPath ( glob('/sys/class/fc_host/*') ) {
        my $hbaInfo = {};
        $hbaInfo->{NAME} = basename($fcHostPath);

        my $wwn = $self->getFileContent("$fcHostPath/port_name");
        $wwn =~ s/^\s*|\s*$//g;
        my @wwnSegments = ( $wwn =~ m/../g );    #切分为两个字符的数组
        $hbaInfo->{WWN} = join( ':', @wwnSegments );

        my $speed = $self->getFileContent("$fcHostPath/speed");
        $speed =~ s/^\s*|\s*$//g;
        $hbaInfo->{SPEED} = $speed;

        my $state = 'up';
        if ( $speed eq 'unknown' ) {
            $state = 'down';
        }
        $hbaInfo->{STATUS} = $state;
        push( @hbaInfos, $hbaInfo );
    }
    $hostInfo->{HBA_INTERFACES} = \@hbaInfos;

    return $hostInfo;
}

sub collect {
    my ($self) = @_;
    my $osInfo = $self->collectOsInfo();

    my $hostInfo = $self->collectHostInfo();

    $osInfo->{CPU_CORES}      = $hostInfo->{CPU_CORES};
    $osInfo->{ETH_INTERFACES} = $hostInfo->{ETH_INTERFACES};
    $hostInfo->{IS_VIRTUAL}   = $osInfo->{IS_VIRTUAL};
    $hostInfo->{DISKS}        = $osInfo->{DISKS};

    if ( $osInfo->{IS_VIRTUAL} == 0 ) {
        return ( $hostInfo, $osInfo );
    }
    else {
        return ( undef, $osInfo );
    }
}

1;
