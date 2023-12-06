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

use Distribution;

sub stripDMIComment {
    my ( $self, $str ) = @_;

    my $content = '';
    my @lines   = split( /\s*\n\s*/, $str );
    foreach my $line (@lines) {
        if ( $line !~ /^\s*#/ ) {
            $content = $content . $line;
        }
    }

    $content =~ s/^\s*|\s*$//g;

    return $content;
}

sub getUpTime {
    my ( $self, $osInfo ) = @_;

    my $uptimeStr = $self->getFileContent('/proc/uptime');
    my $uptime    = ( split( /\s+/, $uptimeStr ) )[0];

    $osInfo->{UPTIME} = int($uptime);
}

sub getCpuLoad {
    my ( $self, $osInfo ) = @_;
    my $procLoadAvg = IO::File->new('</proc/loadavg');
    if ( defined($procLoadAvg) ) {
        my $line = $procLoadAvg->getline();
        if ( $line =~ /^(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)/ ) {
            $osInfo->{'CPU_LOAD_AVG_1'}  = 0.0 + $1;
            $osInfo->{'CPU_LOAD_AVG_5'}  = 0.0 + $2;
            $osInfo->{'CPU_LOAD_AVG_15'} = 0.0 + $3;
        }
    }
}

sub getOsVersion {
    my ( $self, $osInfo ) = @_;
    my $osMajorVer;
    my $osVer;

    eval {
        my $dist = Distribution->new();

        my $distName = $dist->distribution_name();
        if ( defined($distName) ) {
            my $version = $dist->distribution_version();
            if ( not defined($version) ) {
                $version = '';
            }
            $osVer = "${distName}${version}";
            if ( $version =~ /(\d+)/ ) {
                $osMajorVer = "${distName}$1";
            }
        }
    };
    if ($@) {
        print("WARN: Get linux distribute info failed, $@\n");
    }

    $osInfo->{VERSION}       = $osVer;
    $osInfo->{MAJOR_VERSION} = $osMajorVer;
}

sub getVendorInfo {
    my ( $self, $osInfo ) = @_;

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
}

sub getMountPointInfo {
    my ( $self, $osInfo ) = @_;

    #my ($fs_type, $fs_desc, $used, $avail, $fused, $favail) = df($dir);
    #TODO: df
    my $mountedDevicesMap = {};
    my $diskMountMap      = {};
    my @mountPoints       = ();
    my $mountFilter       = {
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
        'tmpfs'       => 1,
        'iso9660'     => 1,
        'usbfs'       => 1,
        'nfsd'        => 1
    };

    $osInfo->{NFS_MOUNTED} = 0;
    my $mountLines = $self->getFileLines('/proc/mounts');
    foreach my $line (@$mountLines) {

        # The 1st column specifies the device that is mounted.
        # The 2nd column reveals the mount point.
        # The 3rd column tells the file-system type.
        # The 4th column tells you if it is mounted read-only (ro) or read-write (rw).
        # The 5th and 6th columns are dummy values designed to match the format used in /etc/mtab.
        my @mountInfos = split( /\s+/, $line );
        my $device     = $mountInfos[0];
        my $mountPoint = $mountInfos[1];
        my $fsType     = $mountInfos[2];

        $mountedDevicesMap->{$device} = 1;

        if ( $fsType =~ /^nfs/i ) {
            $osInfo->{NFS_MOUNTED} = 1;
        }
        if ( not defined( $mountFilter->{$fsType} ) and $fsType !~ /^fuse/ ) {
            my $mountInfo = {};
            $mountPoint =~ s/\\040/ /g;
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
                    $mountInfo->{USED_PCT}  = $utility + 0.0;
                }
            }
        }

        $dfLines = $self->getCmdOutLines( "LANG=C df -i '" . join( "' '", @diskMountPoints ) . "'" );
        foreach my $line (@$dfLines) {
            if ( $line =~ /\d+\s+\d+\s+\d+\s+(\d+%)\s+(.*)$/ ) {
                my $inodeUtility = $1;
                my $mountPoint   = $2;
                chomp($mountPoint);
                my $mountInfo = $diskMountMap->{$mountPoint};
                if ( defined($mountInfo) ) {
                    $mountInfo->{INODE_USED_PCT} = $inodeUtility + 0.0;
                }
            }
        }
    }
    $osInfo->{MOUNT_POINTS} = \@mountPoints;

    return $mountedDevicesMap;
}

sub getSSHInfo {
    my ( $self, $osInfo ) = @_;

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
}

sub getBondInfo {
    my ( $self,    $osInfo )       = @_;
    my ( $bondRet, $bondInfoLine ) = $self->getCmdOut( 'cat /proc/net/dev|grep bond', undef, { nowarn => 1 } );
    if ( $bondRet == 0 ) {
        $osInfo->{NIC_BOND} = 1;
    }
    else {
        $osInfo->{NIC_BOND} = 0;
    }
}

sub getMemInfo {
    my ( $self, $osInfo ) = @_;

    my $utils        = $self->{collectUtils};
    my $memInfoLines = $self->getFileLines('/proc/meminfo');
    my $memInfo      = {};
    foreach my $line (@$memInfoLines) {
        my @lineInfo = split( /:\s*|\s+/, $line );
        $memInfo->{ $lineInfo[0] } = $lineInfo[1] . $lineInfo[2];
    }
    $osInfo->{MEM_TOTAL}   = $utils->getMemSizeFromStr( $memInfo->{MemTotal} );
    $osInfo->{MEM_FREE}    = $utils->getMemSizeFromStr( $memInfo->{MemFree} );
    $osInfo->{MEM_CACHED}  = $utils->getMemSizeFromStr( $memInfo->{Cached} );
    $osInfo->{MEM_BUFFERS} = $utils->getMemSizeFromStr( $memInfo->{Buffers} );
    if ( defined( $memInfo->{MemAvailable} ) ) {
        $osInfo->{MEM_AVAILABLE} = $utils->getMemSizeFromStr( $memInfo->{MemAvailable} );
    }
    else {
        $osInfo->{MEM_AVAILABLE} = $osInfo->{MEM_FREE} + $osInfo->{MEM_CACHED} + $osInfo->{MEM_BUFFERS};
    }
    $osInfo->{MEM_USAGE} = int( ( $osInfo->{MEM_TOTAL} - $osInfo->{MEM_AVAILABLE} ) * 10000 / $osInfo->{MEM_TOTAL} + 0.5 ) / 100;

    $osInfo->{SWAP_TOTAL} = $utils->getMemSizeFromStr( $memInfo->{SwapTotal} );
    $osInfo->{SWAP_FREE}  = $utils->getMemSizeFromStr( $memInfo->{SwapFree} );
}

sub getDNSInfo {
    my ( $self, $osInfo ) = @_;

    my @dnsServers;
    my $dnsInfoLines = $self->getFileLines('/etc/resolv.conf');
    foreach my $line (@$dnsInfoLines) {
        if ( $line =~ /\s*nameserver\s+(\S+)\s*$/i ) {
            push( @dnsServers, { VALUE => $1 } );
        }
    }
    $osInfo->{DNS_SERVERS} = \@dnsServers;
}

sub getServiceInfo {
    my ( $self, $osInfo ) = @_;

    my ( $systemdRet, $isSystemd ) = $self->getCmdOut( 'ps -p1 |grep systemd', undef, { nowarn => 1 } );
    my $services = {};
    if ( $systemdRet == 0 ) {
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
}

sub getIpAddrs {
    my ( $self, $osInfo ) = @_;
    my @ipv4;
    my @ipv6;
    my $ipInfoLines = $self->getCmdOutLines('ip addr');
    foreach my $line (@$ipInfoLines) {
        my $ip;
        my $maskBit;
        if ( $line =~ /^\s*inet\s+(.*?)\/(\d+)/ ) {
            $ip      = $1;
            $maskBit = $2;

            #兼容tunnel，例如：10.10.10.2 peer 10.10.20.2/32
            $ip =~ s/\s*peer\s.*$//i;

            if ( $ip !~ /^127\./ ) {
                my $block = Net::Netmask->safe_new("$ip/$maskBit");
                my $netmask;
                if ( defined($block) ) {
                    $netmask = $block->mask();
                }
                else {
                    print("WARN: Invalid CIDR $ip/$maskBit\n");
                }
                push( @ipv4, { IP => $ip, NETMASK => $netmask } );
            }
        }
        elsif ( $line =~ /^\s*inet6\s+(.*?)\/(\d+)/ ) {
            $ip      = $1;
            $maskBit = $2;

            #兼容tunnel，例如：10.10.10.2 peer 10.10.20.2/32
            $ip =~ s/\s*peer\s.*$//i;

            if ( $ip ne '::1' ) {    #TODO: ipv6 loop back addr range
                my $block = Net::Netmask->safe_new("$ip/$maskBit");
                my $netmask;
                if ( defined($block) ) {
                    $netmask = $block->mask();
                }
                else {
                    print("WARN: Invalid CIDR $ip/$maskBit\n");
                }
                push( @ipv6, { IP => $ip, NETMASK => $netmask } );
            }
        }
    }
    $osInfo->{BIZ_IP}     = $self->getBizIp( \@ipv4, \@ipv6 );
    $osInfo->{IP_ADDRS}   = \@ipv4;
    $osInfo->{IPV6_ADDRS} = \@ipv6;
}

sub getUserInfo {
    my ( $self, $osInfo ) = @_;

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
}

sub getDiskInfo {
    my ( $self, $osInfo, $mountedDevicesMap ) = @_;
    my $utils = $self->{collectUtils};

    #TODO: SAN磁盘的计算以及磁盘多链路聚合的计算，因没有测试环境，需要再确认
    my @diskInfos = ();
    my ( $diskStatus, $diskLines ) = $self->getCmdOutLines('LANG=C parted -l 2>/dev/null');
    if ( $diskStatus ne 0 ) {
        $diskLines = $self->getCmdOutLines('LANG=C fdisk -l');
    }

    foreach my $line (@$diskLines) {
        if ( $line =~ /^\s*Disk\s+(\/[^:]+):\s+([\d\.]+)\s*(\wB)/ ) {
            my $diskInfo = {};

            my $name = $1;
            $diskInfo->{NAME} = $name;

            my $size = $2;
            my $unit = $3;
            ( $diskInfo->{UNIT}, $diskInfo->{CAPACITY} ) = $utils->getDiskSizeFormStr( $size . $unit );

            if ( $name =~ /\/dev\/sd/ or $name =~ /\/dev\/sr/ ) {
                $diskInfo->{TYPE} = 'local';
            }
            elsif ( $name =~ /\/dev\/mapper\// ) {
                $diskInfo->{TYPE} = 'lvm';
            }
            else {
                $diskInfo->{TYPE} = 'remote';
            }

            if ( not defined($mountedDevicesMap) ) {
                $diskInfo->{NOT_MOUNTED} = 1;
            }
            else {
                $diskInfo->{NOT_MOUNTED} = 0;
            }

            push( @diskInfos, $diskInfo );

        }
    }

    #TODO: SAN磁盘的计算以及磁盘多链路聚合的计算，因没有测试环境，需要再确认
    my ( $upadminRet, $upadminPath ) = $self->getCmdOut( 'which upadmin >/dev/null 2>&1', undef, { nowarn => 1 } );
    my $lunInfosMap   = {};
    my $arrayInfosMap = {};
    if ( $upadminRet == 0 ) {
        my $arrayInfoLines = $self->getCmdOutLines('upadmin show array');
        if ( defined($arrayInfoLines) and scalar(@$arrayInfoLines) > 2 ) {
            foreach my $line ( splice( @$arrayInfoLines, 2, -1 ) ) {
                my $arrayInfo = {};
                my @infos     = split( /\s+/, $line );
                $arrayInfo->{NAME}                     = $infos[2];
                $arrayInfo->{SN}                       = $infos[3];
                $arrayInfosMap->{ $arrayInfo->{NAME} } = $arrayInfo;
            }
        }

        my $hwLunInfoLines = $self->getCmdOutLines('upadmin show vlun');
        if ( defined($hwLunInfoLines) and @$hwLunInfoLines > 0 ) {
            foreach my $line ( splice( @$hwLunInfoLines, 2, -1 ) ) {
                my $lunInfo = {};
                my @infos   = split( /\s+/, $line );
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
}

sub getMiscInfo {
    my ( $self, $osInfo ) = @_;
    my @unameInfo = uname();
    my $hostName  = $unameInfo[1];
    $osInfo->{OS_TYPE}        = $unameInfo[0];
    $osInfo->{HOSTNAME}       = $hostName;
    $osInfo->{KERNEL_VERSION} = $unameInfo[2];

    my $machineId;
    if ( -e '/etc/machine-id' ) {
        $machineId = $self->getFileContent('/etc/machine-id');
        $machineId =~ s/^\s*|\s*$//g;
    }
    $osInfo->{MACHINE_ID} = $machineId;

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
        if ( $line =~ /^server\s+(\S+)/i ) {
            push( @ntpServers, { VALUE => $1 } );
        }
    }
    $osInfo->{NTP_SERVERS} = \@ntpServers;

    my $maxOpenFiles = $self->getFileContent('/proc/sys/fs/file-max');
    $maxOpenFiles =~ s/^\s*|\s*$//g;
    $osInfo->{MAX_OPEN_FILES} = int($maxOpenFiles);
}

sub getPerformanceInfo {
    my ( $self, $osInfo ) = @_;
    my $utils = $self->{collectUtils};

    $self->getCpuLoad($osInfo);

    my $hasCpuSum = 0;
    my $userCpu   = 0.0;
    my $sysCpu    = 0.0;
    my $iowait    = 0.0;

    my $status = 0;
    my @fieldNames;
    my $topLines  = $self->getCmdOutLines('top -bn1 | head -22');
    my $lineCount = scalar(@$topLines);
    my $k         = 0;
    for ( $k = 0 ; $k < $lineCount ; $k++ ) {
        my $line = $$topLines[$k];
        if ( $line =~ /^%?Cpu\(s\)/ ) {

            #%Cpu(s):  0.6 us,  0.6 sy,  0.0 ni, 98.7 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st
            #Cpu(s):  1.2%us,  0.5%sy,  0.0%ni, 98.3%id,  0.0%wa,  0.0%hi,  0.0%si,  0.0%st
            if ( $line =~ /([\d\.])+[\s\%]+us/ ) {
                $userCpu = $userCpu + $1;
                $hasCpuSum++;
            }

            if ( $line =~ /([\d\.])+[\s\%]+sy/ ) {
                $sysCpu = $sysCpu + $1;
                $hasCpuSum++;
            }

            if ( $line =~ /([\d\.])+[\s\%]+wa/ ) {
                $iowait = $iowait + $1;
            }
        }
        elsif ( $line =~ /^\s*PID/ ) {
            $line =~ s/^\s*|\s*$//g;
            @fieldNames = split( /\s+/, $line );
            $k++;
            last;
        }
    }

    if ( $hasCpuSum < 2 ) {
        print("WARN: Can not find os cpu usage.\n");
    }

    my @cpuTopProc = ();
    for ( my $j = $k ; $j < $k + 10 and $j < $lineCount ; $j++ ) {
        my $line = $$topLines[$j];
        $line =~ s/^\s*|\s*$//g;
        my @fields   = split( /\s+/, $line );
        my $procInfo = {};
        for ( my $i = 0 ; $i <= $#fields ; $i++ ) {
            if ( $fields[$i] =~ /^\d+$/ ) {
                $fields[$i] = int( $fields[$i] );
            }
            elsif ( $fields[$i] =~ /^[\d\.]+$/ ) {
                $fields[$i] = 0.0 + $fields[$i];
            }
            $procInfo->{ $fieldNames[$i] } = $fields[$i];
        }
        if ( $procInfo->{'%CPU'} > 10 ) {
            my $command = $self->getFileContent( '/proc/' . $procInfo->{PID} . '/cmdline' );
            $command =~ s/\x0/ /g;
            $procInfo->{COMMAND}   = $command;
            $procInfo->{VIRT}      = $utils->getMemSizeFromStr( $procInfo->{VIRT}, 'K' );
            $procInfo->{RES}       = $utils->getMemSizeFromStr( $procInfo->{VIRT}, 'K' );
            $procInfo->{SHR}       = $utils->getMemSizeFromStr( $procInfo->{VIRT}, 'K' );
            $procInfo->{CPU_USAGE} = delete( $procInfo->{'%CPU'} );
            $procInfo->{MEM_USAGE} = delete( $procInfo->{'%MEM'} );
            push( @cpuTopProc, $procInfo );
        }
    }

    ( $status, $topLines ) = $self->getCmdOutLines( 'top -bn1 -o %MEM 2>/dev/null | head -17', undef, { nowarn => 1 } );
    if ( $status != 0 ) {
        $topLines = $self->getCmdOutLines('top -bn1 -a | head -17');
    }

    for ( $k = 0 ; $k < $lineCount ; $k++ ) {
        my $line = $$topLines[$k];
        if ( $line =~ /^\s*PID/ ) {
            $k++;
            last;
        }
    }
    my @memTopProc = ();
    for ( my $j = $k ; $j < $k + 5 and $j < $lineCount ; $j++ ) {
        my $line = $$topLines[$j];
        $line =~ s/^\s*|\s*$//g;
        my @fields   = split( /\s+/, $line );
        my $procInfo = {};
        for ( my $i = 0 ; $i <= $#fields ; $i++ ) {
            if ( $fields[$i] =~ /^\d+$/ ) {
                $fields[$i] = int( $fields[$i] );
            }
            elsif ( $fields[$i] =~ /^[\d\.]+$/ ) {
                $fields[$i] = 0.0 + $fields[$i];
            }
            $procInfo->{ $fieldNames[$i] } = $fields[$i];
        }

        if ( $procInfo->{'%MEM'} > 10 ) {
            my $command = $self->getFileContent( '/proc/' . $procInfo->{PID} . '/cmdline' );
            $command =~ s/\x0/ /g;
            $procInfo->{COMMAND}   = $command;
            $procInfo->{VIRT}      = $utils->getMemSizeFromStr( $procInfo->{VIRT}, 'K' );
            $procInfo->{RES}       = $utils->getMemSizeFromStr( $procInfo->{VIRT}, 'K' );
            $procInfo->{SHR}       = $utils->getMemSizeFromStr( $procInfo->{VIRT}, 'K' );
            $procInfo->{CPU_USAGE} = delete( $procInfo->{'%CPU'} );

            if ( not defined( $osInfo->{CPU_LOGIC_CORES} or $osInfo->{CPU_LOGIC_CORES} == 0 ) ) {
                $osInfo->{CPU_LOGIC_CORES} = 1;
            }
            $procInfo->{CPU_USAGE_PERCORE} = $procInfo->{CPU_USAGE} / $osInfo->{CPU_LOGIC_CORES};
            $procInfo->{MEM_USAGE}         = delete( $procInfo->{'%MEM'} );
            push( @memTopProc, $procInfo );
        }
    }

    $osInfo->{TOP_CPU_RPOCESSES} = \@cpuTopProc;
    $osInfo->{TOP_MEM_PROCESSES} = \@memTopProc;
    $osInfo->{CPU_USAGE}         = $userCpu + $sysCpu;
    $osInfo->{CPU_USAGE_PERCORE} = $osInfo->{CPU_USAGE} / $osInfo->{CPU_LOGIC_CORES};
    $osInfo->{IOWAIT_PCT}        = $iowait;
}

sub getInspectMisc {
    my ( $self, $osInfo ) = @_;
    my $defuncStr = $self->getCmdOut('ps -ef | grep defunct | grep -v grep | wc -l');
    $osInfo->{DEFUNC_PROCESSES_COUNT} = int($defuncStr);

    my $ntpOffset = 0;
    my ( $ntpStatus, $ntpOffsetStr ) = $self->getCmdOut('chronyc tracking | grep "Last offset"');
    if ( $ntpStatus == 0 and $ntpOffset =~ /([\d\.]+)/ ) {
        $ntpOffset = 0.0 + $1;
    }
    else {
        my ( $ntpStatus, $ntpOffset ) = $self->getCmdOut('ntpq -p | grep ^*');
        if ( $ntpStatus == 0 ) {
            my @ntpStatusInfo = split( /\s+/, $ntpOffset );
            $ntpOffset = 0.0 + $ntpStatusInfo[8];
        }
    }
    $osInfo->{NTP_OFFSET_SECS} = $ntpOffset;
}

sub getSecurityInfo {
    my ( $self, $osInfo ) = @_;
}

sub collectOsInfo {
    my ($self) = @_;

    my $osInfo = {};
    if ( $self->{justBaseInfo} == 0 ) {
        $self->getMiscInfo($osInfo);
        $self->getOsVersion($osInfo);
        $self->getVendorInfo($osInfo);

        my $mountedDevicesMap = $self->getMountPointInfo($osInfo);
        $self->getDiskInfo( $osInfo, $mountedDevicesMap );

        $self->getSSHInfo($osInfo);
        $self->getBondInfo($osInfo);
        $self->getMemInfo($osInfo);
        $self->getDNSInfo($osInfo);
        $self->getServiceInfo($osInfo);
        $self->getIpAddrs($osInfo);
        $self->getUserInfo($osInfo);
    }
    else {
        $self->getMemInfo($osInfo);
        $self->getIpAddrs($osInfo);
    }

    return $osInfo;
}

sub collectOsPerfInfo {
    my ( $self, $osInfo ) = @_;
    if ( $self->{inspect} == 1 ) {
        if ( not defined( $osInfo->{CPU_LOGIC_CORES} or $osInfo->{CPU_LOGIC_CORES} == 0 ) ) {
            $osInfo->{CPU_LOGIC_CORES} = 1;
        }

        $self->getPerformanceInfo($osInfo);
        $self->getInspectMisc($osInfo);
        $self->getSecurityInfo($osInfo);
    }
}

sub getMainBoardInfo {
    my ( $self, $hostInfo ) = @_;

    my $utils              = $self->{collectUtils};
    my $dmidecodeInstalled = 1;
    my ($whichDmiRet)      = $self->getCmdOut( 'which dmidecode >/dev/null 2>&1', undef, { nowarn => 1 } );
    if ( $whichDmiRet != 0 ) {
        $dmidecodeInstalled = 0;
        print("WARN: Tools dmidecode not install, we use it to collect hardware information, please install it first.\n");
    }
    $hostInfo->{DMIDECODE_INSTALLED} = $dmidecodeInstalled;

    my $sn = $self->getFileContent('/sys/class/dmi/id/board_serial');
    $sn =~ s/^\s*|\s*$//g;
    if ( $sn eq '' or $sn eq 'None' ) {
        undef($sn);
        if ($dmidecodeInstalled) {
            my $snRet;
            ( $snRet, $sn ) = $self->getCmdOut('dmidecode -s system-serial-number');
            if ( $snRet == 0 ) {
                $sn = $self->stripDMIComment($sn);
                $sn =~ s/^\s*|\s*$//g;
                if ( $sn eq '' ) {
                    undef($sn);
                }
            }
            else {
                undef($sn);
            }
        }
    }
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

    if ($dmidecodeInstalled) {
        my $memInfoLines = $self->getCmdOutLines('dmidecode -t memory');
        my $usedSlots    = 0;
        my $memInfo      = {};
        for ( my $i = 0 ; $i < scalar(@$memInfoLines) ; $i++ ) {
            my $line = $$memInfoLines[$i];
            $line =~ s/^\s*|\s*$//g;
            if ( $line ne '' and $line !~ /^#/ ) {
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
            if ( $line ne '' and $line !~ /^#/ ) {
                my @info = split( /\s*:\s*/, $line );
                $chassisInfo->{ $info[0] } = $info[1];
            }
        }
        $hostInfo->{POWER_CORDS_COUNT} = $chassisInfo->{'Number Of Power Cords'};
    }
}

sub getCPUInfo {
    my ( $self, $hostInfo ) = @_;

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
    $hostInfo->{CPU_COUNT}       = scalar( keys(%$pCpuMap) );
    $hostInfo->{CPU_CORES}       = int( $cpuInfo->{processor} ) + 1;
    $hostInfo->{CPU_LOGIC_CORES} = $hostInfo->{CPU_COUNT} * $cpuInfo->{siblings};
    $hostInfo->{CPU_MICROCODE}   = $cpuInfo->{microcode};
    my @modelInfo = split( /\s*\@\s*/, $cpuInfo->{'model name'} );
    $hostInfo->{CPU_MODEL}     = $modelInfo[0];
    $hostInfo->{CPU_FREQUENCY} = $modelInfo[1];
    my $cpuArch = ( POSIX::uname() )[4];
    $hostInfo->{CPU_ARCH} = $cpuArch;
}

sub getNicInfo {
    my ( $self, $hostInfo ) = @_;

    my $utils            = $self->{collectUtils};
    my @nicInfos         = ();
    my $macsMap          = {};
    my $nicInfoLines     = $self->getCmdOutLines('ip addr');
    my $nicInfoLineCount = scalar(@$nicInfoLines);
    for ( my $i = 0 ; $i < $nicInfoLineCount ; $i++ ) {
        my $line    = $$nicInfoLines[$i];
        my $nicInfo = {};
        my ( $ethName, $macAddr, $ipAddr, $speed, $linkState );
        if ( $line =~ /^\d+:\s+(\S+):/ ) {
            $ethName = $1;
            if ( $ethName =~ /@/ ) {
                $ethName = substr( $ethName, 0, index( $ethName, '@' ) );
            }
            if ( -e "/sys/class/net/$ethName" and not -e "/sys/class/net/$ethName/device" ) {

                #不是物理网卡
                $nicInfo->{IS_VIRTUAL} = 1;
            }
            else {
                $nicInfo->{IS_VIRTUAL} = 0;
            }

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
                    $macAddr = lc($1);
                }
                elsif ( $line =~ /^\s*inet\s(\d+\.\d+\.\d+\.\d+)/ ) {
                    $ipAddr = $1;
                }
                $i    = $i + 1;
                $line = $$nicInfoLines[$i];
            }

            if ( $ethName =~ /^lo/i or $ipAddr =~ /^127/ or $ipAddr =~ '^::1' ) {

                #忽略loopback网卡
                next;
            }

            if ( defined($speed) and $speed ne '' and defined($macAddr) and $macAddr ne '' ) {
                $nicInfo->{NAME} = $ethName;
                $nicInfo->{MAC}  = $macAddr;

                if ( not defined( $macsMap->{$macAddr} ) ) {
                    $macsMap->{$macAddr} = 1;
                    ( $nicInfo->{UNIT}, $nicInfo->{SPEED} ) = $utils->getNicSpeedFromStr($speed);
                    $nicInfo->{STATUS} = 'down';
                    if ( $linkState eq 'yes' ) {
                        $nicInfo->{STATUS} = 'up';
                    }

                    push( @nicInfos, $nicInfo );
                }
            }

            $i = $i - 1;
        }
    }
    @nicInfos = sort { $a->{NAME} <=> $b->{NAME} } @nicInfos;
    $hostInfo->{ETH_INTERFACES} = \@nicInfos;

    if ( not defined( $hostInfo->{BOARD_SERIAL} ) and scalar(@nicInfos) > 0 ) {
        my $firstMac = $nicInfos[0]->{MAC};
        $hostInfo->{BOARD_SERIAL} = $firstMac;
    }
}

sub getHBAInfo {
    my ( $self, $hostInfo ) = @_;

    my @hbaInfos = ();
    foreach my $fcHostPath ( glob('/sys/class/fc_host/*') ) {

        #低版本linux可能通过/proc/scsi/qla2*/来获取，需验证
        my $hbaInfo = {};
        $hbaInfo->{NAME} = basename($fcHostPath);

        my $wwnn = $self->getFileContent("$fcHostPath/node_name");
        $wwnn =~ s/^\s*|\s*$//g;
        $wwnn =~ s/^0x//i;
        $wwnn = lc($wwnn);
        my @wwnnSegments = ( $wwnn =~ m/../g );    #切分为两个字符的数组
                                                   #WWNN是HBA卡的地址编号，在存储端是通过这个WWNN来控制访问权限
        $hbaInfo->{WWNN} = join( ':', @wwnnSegments );

        my @ports      = ();
        my @wwpnLines  = split( /\n/, $self->getFileContent("$fcHostPath/port_name") );
        my @wwpnStates = split( /\n/, $self->getFileContent("$fcHostPath/port_state") );
        for ( my $i = 0 ; $i <= $#wwpnLines ; $i++ ) {
            my $wwpn = $wwpnLines[$i];
            $wwpn =~ s/^\s*|\s*$//g;
            $wwpn =~ s/^0x//i;
            $wwpn = lc($wwpn);
            my @wwpnSegments = ( $wwpn =~ m/../g );    #切分为两个字符的数组
            $wwpn = join( ':', @wwpnSegments );

            my $state = $wwpnStates[$i];
            if ( $state =~ /online/i ) {
                $state = 'up';
            }
            else {
                $state = 'down';
            }

            my $portInfo = {};

            #WWPN是端口的地址编号
            $portInfo->{WWPN}   = $wwpn;
            $portInfo->{STATUS} = $state;
            push( @ports, $portInfo );
        }
        $hbaInfo->{PORTS} = \@ports;

        my $speed = $self->getFileContent("$fcHostPath/speed");
        $speed =~ s/^\s*|\s*$//g;
        $hbaInfo->{SPEED} = $speed;

        my $state = 'up';
        if ( $speed eq 'unknown' ) {
            $state = 'down';
        }
        $hbaInfo->{STATUS}     = $state;
        $hbaInfo->{IS_VIRTUAL} = $hostInfo->{IS_VIRTUAL};

        push( @hbaInfos, $hbaInfo );
    }

    $hostInfo->{HBA_INTERFACES} = \@hbaInfos;
}

sub collectHostInfo {
    my ( $self, $osInfo ) = @_;

    my $hostInfo = {};
    $hostInfo->{IS_VIRTUAL} = $osInfo->{IS_VIRTUAL};
    $hostInfo->{DISKS}      = $osInfo->{DISKS};

    if ( $self->{justBaseInfo} == 0 ) {
        $self->getMainBoardInfo($hostInfo);
        $self->getCPUInfo($hostInfo);
        $self->getNicInfo($hostInfo);
        $self->getHBAInfo($hostInfo);
    }

    return $hostInfo;
}

sub collect {
    my ($self)   = @_;
    my $osInfo   = $self->collectOsInfo();
    my $hostInfo = $self->collectHostInfo($osInfo);

    if ( not defined( $osInfo->{MACHINE_ID} ) ) {
        $osInfo->{MACHINE_ID} = $hostInfo->{BOARD_SERIAL};
    }

    $osInfo->{CPU_ARCH}        = $hostInfo->{CPU_ARCH};
    $osInfo->{CPU_COUNT}       = $hostInfo->{CPU_COUNT};
    $osInfo->{CPU_CORES}       = $hostInfo->{CPU_CORES};
    $osInfo->{CPU_LOGIC_CORES} = $hostInfo->{CPU_LOGIC_CORES};
    $osInfo->{CPU_MICROCODE}   = $hostInfo->{CPU_MICROCODE};
    $osInfo->{CPU_MODEL}       = $hostInfo->{CPU_MODEL};
    $osInfo->{CPU_FREQUENCY}   = $hostInfo->{CPU_FREQUENCY};

    $osInfo->{ETH_INTERFACES} = $hostInfo->{ETH_INTERFACES};

    $self->collectOsPerfInfo($osInfo);

    if ( $osInfo->{IS_VIRTUAL} == 0 ) {
        return ( $hostInfo, $osInfo );
    }
    else {
        return ( undef, $osInfo );
    }
}

1;
