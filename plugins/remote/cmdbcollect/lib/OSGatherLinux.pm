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
use JSON qw(to_json from_json);
use IO::File;
use File::Basename;
use XML::MyXML qw(xml_to_object);

use Distribution;

sub init {
    my ($self) = @_;
}

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

    $osInfo->{IS_VIRTUAL} = $self->isVirtualVendor($sysVendor);
    if ( $osInfo->{IS_VIRTUAL} == 0 ) {
        $osInfo->{IS_VIRTUAL} = $self->isVirtualVendor($productName);
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

sub getNFSInfo {
    my ( $self, $osInfo ) = @_;
    my $mountPoints = $osInfo->{MOUNT_POINTS};

    my @nfsMounts    = ();
    my $nfsMountCmds = '';
    my $rcLocalLines = $self->getFileLines('/etc/rc.local');
    foreach my $line (@$rcLocalLines) {
        if ( $line =~ /mount\s+-t\s+nfs\s+.*/ ) {
            $nfsMountCmds = $nfsMountCmds . $line . "\n";
        }
    }

    foreach my $mountInfo (@$mountPoints) {
        if ( $mountInfo->{FS_TYPE} =~ /^nfs/ ) {
            my $device    = $mountInfo->{DEVICE};
            my $autoMount = 0;

            #192.168.20.178:/export/share
            my ( $remoteHost, $remotePath ) = split( ':', $device );
            my $remoteIp = $remoteHost;
            if ( $remoteIp !~ /[\d\.]+/ ) {
                my $ipAddr = gethostbyname($remoteHost);
                if ( defined($ipAddr) ) {
                    $remoteIp = inet_ntoa($ipAddr);
                }
            }

            if ( $nfsMountCmds =~ /\s$device\s/s ) {
                $autoMount = 1;
            }
            my $nfsInfo = {
                _OBJ_CATEGORY => 'OS',
                _OBJ_TYPE     => 'OS-NFS',
                NFS_IP        => $remoteIp,
                NFS_HOST      => $remoteHost,
                REMOTE_PATH   => $remotePath,
                MOUNT_POINT   => $mountInfo->{NAME},
                AUTO_MOUNT    => $autoMount
            };
            push( @nfsMounts, $nfsInfo );
        }
    }
    $osInfo->{NFS_INFO} = \@nfsMounts;
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

    my @dnsServers   = ();
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
    my $objCat = CollectObjCat->get('OS');
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

                my $isSecondary = 0;
                if ( $line =~ /secondary/ ) {
                    $isSecondary = 1;
                }

                push( @ipv4, { _OBJ_CATEGORY => $objCat, _OBJ_TYPE => 'OS-IP', IP => $ip, NETMASK => $netmask, TYPE => 'IPV4', SECONDARY => $isSecondary } );
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

                my $isSecondary = 0;
                if ( $line =~ /secondary/ ) {
                    $isSecondary = 1;
                }

                push( @ipv6, { _OBJ_CATEGORY => $objCat, _OBJ_TYPE => 'OS-IP', IP => $ip, NETMASK => $netmask, TYPE => 'IPV6', SECONDARY => $isSecondary } );
            }
        }
    }
    $osInfo->{BIZ_IP}     = $self->getBizIp( \@ipv4, \@ipv6 );
    $osInfo->{IPV4_ADDRS} = \@ipv4;
    $osInfo->{IPV6_ADDRS} = \@ipv6;
    my @ipAddrs = ( @ipv4, @ipv6 );
    $osInfo->{IP_ADDRS} = \@ipAddrs;
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

            $usersMap->{_OBJ_CATEGORY} = 'OS';
            $usersMap->{_OBJ_TYPE}     = 'OS-USER';
            $usersMap->{NAME}          = $userInfo[0];
            $usersMap->{UID}           = $userInfo[2];

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
    #Model: AVAGO XF-SAS3508 (scsi)
    #Disk /dev/sda: 599GB
    #Sector size (logical/physical): 512B/512B
    #Partition Table: gpt
    #Disk Flags:
    #
    #Number  Start   End     Size    File system  Name                  Flags
    # 1      1049kB  2149MB  2147MB  fat32        EFI System Partition  boot
    # 2      2149MB  4296MB  2147MB  xfs
    # 3      4296MB  468GB   464GB                                      lvm
    #
    #
    #Model: up updisk (scsi)
    #Disk /dev/sdb: 429GB
    #Sector size (logical/physical): 512B/512B
    #Partition Table: unknown
    #Disk Flags:
    #
    #
    #
    #Model: Linux device-mapper (linear) (dm)
    #Disk /dev/mapper/rootvg-oraclelv: 215GB
    #Sector size (logical/physical): 512B/512B
    #Partition Table: loop
    #Disk Flags:
    #
    #Number  Start  End    Size   File system  Flags
    # 1      0.00B  215GB  215GB  xfs
    #
    my @diskInfos = ();
    my ( $diskStatus, $diskLines ) = $self->getCmdOutLines('LANG=C fdisk -l ');
    if ( $diskStatus ne 0 ) {
        $diskLines = $self->getCmdOutLines('LANG=C parted -l');
    }

    foreach my $line (@$diskLines) {
        if ( $line =~ /^\s*Disk\s+(\/[^:]+):\s+([\d\.]+)\s*(\w+B)/ ) {
            my $diskInfo = {
                '_OBJ_CATEGORY' => 'COLLECT_OS',
                '_OBJ_TYPE'     => 'OS-DISK'
            };

            my $name = $1;
            my $size = $2;
            my $unit = $3;

            $diskInfo->{NAME} = $name;
            ( $diskInfo->{UNIT}, $diskInfo->{CAPACITY} ) = $utils->getDiskSizeFormStr( $size . $unit );

            if ( $name =~ /\/dev\/sd/ or $name =~ /\/dev\/sr/ ) {

                #这也可能是存储阵列的磁盘，通过后续如果发现磁盘对应了WWN，则修改为remote
                $diskInfo->{TYPE} = 'local';
            }
            elsif ( $name =~ /\/dev\/mapper\// ) {
                $diskInfo->{TYPE} = 'lvm';
            }
            else {
                $diskInfo->{TYPE} = 'remote';
            }

            if ( not defined( $mountedDevicesMap->{$name} ) ) {
                $diskInfo->{NOT_MOUNTED} = 1;
            }
            else {
                $diskInfo->{NOT_MOUNTED} = 0;
            }

            push( @diskInfos, $diskInfo );

        }
    }

    #TODO: SAN磁盘的计算以及磁盘多链路聚合的计算，因没有测试环境，需要再确认
    #upadmin是华为存储的多链路管理软件？
    my ( $upadminRet, $upadminPath ) = $self->getCmdOut( 'which upadmin >/dev/null 2>&1', undef, { nowarn => 1 } );
    my $lunInfosMap   = {};
    my $arrayInfosMap = {};
    if ( $upadminRet == 0 ) {

        # [root ~]# upadmin show array
        # -----------------------------------------------------------------------------
        # Array ID    Array Name          Array SN        Vendor Name  Product Name
        # 0      Huawei.Storage  2102353TJYFSP5100006    HUAWEI        XSG1
        # 1      Huawei.Storage  2102353TJYFSP5100005    HUAWEI        XSG1
        my $arrayInfoLines = $self->getCmdOutLines('upadmin show array');
        if ( defined($arrayInfoLines) and scalar(@$arrayInfoLines) > 2 ) {
            foreach my $line ( splice( @$arrayInfoLines, 2, -1 ) ) {
                my $arrayInfo = {};
                $line =~ s/^\s*|\s*$//g;
                my @infos = split( /\s+/, $line );
                $arrayInfo->{NAME}                     = $infos[1];
                $arrayInfo->{SN}                       = $infos[2];
                $arrayInfosMap->{ $arrayInfo->{NAME} } = $arrayInfo;
            }
        }

        # [root ~]# upadmin show vlun
        # ----------------------------------------------------------------------------------------------------------------------------------------------------------------------
        # Vlun ID  Disk        Name                    Lun WWN               Status  Capacity  Ctrl(Own/Work)    Array Name    Dev Lun ID  No. of Paths(Available/Total)
        #    0     sdb   xgm_data_0000000  65856c21008355422fa8739d000000aa  Normal  400.00GB      --/--       Huawei.Storage     170                   4/4
        #    1     sdc   xgm_data_0000001  65856c21008355422fa8739d000000ab  Normal  400.00GB      --/--       Huawei.Storage     171                   4/4
        #    2     sdd   xgm_data_0000002  65856c21008355422fa8739d000000ac  Normal  400.00GB      --/--       Huawei.Storage     172                   4/4
        my $hwLunInfoLines = $self->getCmdOutLines('upadmin show vlun');
        if ( defined($hwLunInfoLines) and @$hwLunInfoLines > 0 ) {
            foreach my $line ( splice( @$hwLunInfoLines, 2, -1 ) ) {
                my $lunInfo = {};
                $line =~ s/^\s+|\s*$//g;
                my @infos = split( /\s+/, $line );
                $lunInfo->{NAME} = '/dev/' . $infos[1];
                $lunInfo->{WWN}  = $infos[3];
                ( $lunInfo->{UNIT}, $lunInfo->{CAPACITY} ) = $utils->getDiskSizeFormStr( $infos[5] );
                $lunInfo->{ARRAY} = $infos[7];
                my $arrayInfo = $arrayInfosMap->{ $lunInfo->{ARRAY} };

                if ( defined($arrayInfo) ) {
                    $lunInfo->{SN} = $arrayInfo->{SN};
                }
                $lunInfosMap->{ $lunInfo->{NAME} } = $lunInfo;
            }
        }
    }

    #日立存储多链路管理软件
    # Product       : HUS100
    # SerialNumber  : 92212433
    # LUs           : 1
    # iLU  HDevName Device   PathID Status
    # 0011 sddlmca  /dev/sdb 000000 Online
    #               /dev/sdq 000001 Online
    # Product       : VSP_Gx00
    # SerialNumber  : 412905
    # LUs           : 7
    # iLU    HDevName Device   PathID Status
    # 000800 sddlmaa  /dev/sdc 000002 Online
    #                 /dev/sdr 000003 Online
    # 000801 sddlmab  /dev/sdd 000006 Online
    my $dlnkmgrDir = "/opt/DynamicLinkManager/bin";
    if ( -e $dlnkmgrDir ) {
        my $lunInfoLines = $self->getCmdOutLines(qq{ $dlnkmgrDir/dlnkmgr view -lu});
        if ( defined($lunInfoLines) ) {
            my ( $storageSN, $name, $iLU );
            foreach my $line (@$lunInfoLines) {
                $line =~ s/^\s*|\s*$//g;
                if ( $line =~ /SerialNumber\s+:\s+(\w+)/ ) {
                    $storageSN = $1;
                }
                elsif ( $line =~ /^(\w+)\s+(sdd\w+)/ ) {
                    $iLU  = $1;
                    $name = $2;

                    #$iLU =~ s/(\w{2})(\w{2})(\w{2})/$1:$2:$3/;
                    $iLU  = ~s/..(?=.)/$&:/g;
                    $name = '/dev/' . $name;
                    if ( defined($name) and defined($storageSN) ) {
                        $lunInfosMap->{$name} = {
                            NAME => $name,
                            SN   => $storageSN,

                            #wwn用sn+uuid
                            WWN => $storageSN . ":" . $iLU
                        };

                        #undef($storageSN);
                        undef($name);
                        undef($iLU);
                    }
                }
            }
        }
    }

    #最后读取/dev/disk/by-id，获取WWN，这是最通用的方法了
    my $dh;
    opendir( $dh, "/dev/disk/by-id" );
    if ( defined($dh) ) {
        my $currentDir = getcwd();
        chdir("/dev/disk/by-id");
        while ( my $linkName = readdir($dh) ) {
            if ( $linkName =~ /^wwn-0x(\S+)/ ) {
                my $wwn      = $1;
                my $diskName = Cwd::realpath( readlink($linkName) );
                my $lunInfo  = $lunInfosMap->{$diskName};
                if ( defined($lunInfo) and not defined( $lunInfo->{WWN} ) ) {

                    #如果多链路软件采集了相关信息，则只补充WWN
                    $lunInfo->{WWN} = $wwn;
                }
                else {
                    #如多链路软件没有采集到添加设备
                    $lunInfosMap->{$diskName} = { NAME => $diskName, WWN => $wwn };
                }
            }
        }
        closedir($dh);
        chdir($currentDir);
    }
    else {
        print("WARN: Open directory /dev/disk/by-id failed: $!\n");
    }

    #Linux通用多链路管理软件multipath
    # mpath0 (3600508b400105e210000900000490000) dm-0 IBM     ,2810XIV
    # size=100G features='1 queue_if_no_path' hwhandler='0' wp=rw
    # `-+- policy='round-robin 0' prio=1 status=active
    # |- 7:0:0:1 sdc 8:32  active ready running
    # `- 8:0:0:1 sdd 8:48  active ready running
    my ( $multiPathRet, $multiPathLines ) = $self->getCmdOutLines(qq{multipath -l});
    if ( $multiPathRet == 0 ) {
        foreach my $line (@$multiPathLines) {
            if ( $line =~ /^\w+/ ) {
                my @infos    = split( /\s+/, $line );
                my $diskName = '/dev/mapper/' . $infos[0];
                my $wwn      = substr( $infos[1], 2, 32 );

                my $lunInfo = $lunInfosMap->{$diskName};
                if ( defined($lunInfo) and not defined( $lunInfo->{WWN} ) ) {

                    #如果多链路软件采集了相关信息，则只补充WWN
                    $lunInfo->{WWN} = $wwn;
                }
                else {
                    #如多链路软件没有采集到添加设备
                    $lunInfosMap->{$diskName} = { NAME => $diskName, WWN => $wwn };
                }
            }
        }
    }

    foreach my $diskInfo (@diskInfos) {
        my $diskName = $diskInfo->{NAME};
        my $lunInfo  = $lunInfosMap->{$diskName};
        if ( defined($lunInfo) ) {
            $diskInfo->{TYPE} = 'remote';

            #TODO: WWID是从老平台的采集脚本中看到的，不知懂做何用途
            $diskInfo->{WWID} = $lunInfo->{SN} . ':' . $lunInfo->{WWN};
            $diskInfo->{SN}   = $lunInfo->{SN};
            $diskInfo->{WWN}  = $lunInfo->{WWN};
        }

    }

    $osInfo->{DISKS} = \@diskInfos;
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

    my $nproc;
    my $limitLines = $self->getFileLines('/etc/security/limits.conf');
    foreach my $line (@$limitLines) {
        if ( $line =~ /^\s*\*\s+soft\s+nproc\s+(\d+)\s*$/ ) {
            $nproc = int($1);
            last;
        }
    }
    $osInfo->{MAX_USER_PROCESS_COUNT} = $nproc;

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

    my $osInfo = { IS_VIRTUAL => 0 };
    if ( $self->{justBaseInfo} == 0 ) {
        $self->getUpTime($osInfo);
        $self->getMiscInfo($osInfo);
        $self->getOsVersion($osInfo);
        $self->getVendorInfo($osInfo);

        my $mountedDevicesMap = $self->getMountPointInfo($osInfo);
        $self->getDiskInfo( $osInfo, $mountedDevicesMap );
        $self->getNFSInfo($osInfo);

        $self->getSSHInfo($osInfo);
        $self->getBondInfo($osInfo);
        $self->getMemInfo($osInfo);
        $self->getDNSInfo($osInfo);

        $self->getServiceInfo($osInfo);
        $self->getIpAddrs($osInfo);
        $self->getUserInfo($osInfo);
    }
    else {
        $self->getOsVersion($osInfo);
        $self->getUpTime($osInfo);
        $self->getMemInfo($osInfo);
        $self->getIpAddrs($osInfo);
        $self->getOsServices($osInfo);
        $self->getVendorInfo($osInfo);
    }

    return $osInfo;
}

sub collectOsPerfInfo {
    my ( $self, $osInfo ) = @_;
    if ( $self->{inspect} == 1 ) {
        if ( not defined( $osInfo->{CPU_LOGIC_CORES} ) or $osInfo->{CPU_LOGIC_CORES} == 0 ) {
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

    #$hostInfo->{IS_VIRTUAL} = 0;

    if ($dmidecodeInstalled) {
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
        my $sn = $chassisInfo->{'Serial Number'};
        if ( $sn ne 'None' ) {
            $hostInfo->{CHASSIS_SERIAL} = $sn;
        }
        else {
            $hostInfo->{CHASSIS_SERIAL} = undef;
        }

        my $sysInfoLines = $self->getCmdOutLines('dmidecode -t system');
        my $sysInfo      = {};
        foreach my $line (@$sysInfoLines) {
            $line =~ s/^\s*|\s*$//g;
            if ( $line ne '' and $line !~ /^#/ ) {
                my @info = split( /\s*:\s*/, $line );
                $sysInfo->{ $info[0] } = $info[1];
            }
        }

        my $productName = $sysInfo->{'Product Name'};
        if ( defined($productName) and $productName ne 'None' ) {
            $hostInfo->{MODEL}      = $productName;
            $hostInfo->{IS_VIRTUAL} = $self->isVirtualVendor($productName);
        }
        my $manufacturer = $sysInfo->{'Manufacturer'};
        $hostInfo->{MANUFACTURER} = $manufacturer;
        if ( defined($manufacturer) and $manufacturer ne 'None' ) {
            if ( $hostInfo->{IS_VIRTUAL} == 0 ) {
                $hostInfo->{IS_VIRTUAL} = $self->isVirtualVendor($manufacturer);
            }
        }

        my $biosVersion = $self->getCmdOut('dmidecode -s bios-version');
        $biosVersion =~ s/^\s*|\s*$//g;
        $hostInfo->{BIOS_VERSION} = $biosVersion;

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
    }
    else {
        my $sn = $self->getFileContent('/sys/class/dmi/id/board_serial');
        $sn =~ s/^\s*|\s*$//g;
        if ( $sn eq '' or $sn eq 'None' ) {
            undef($sn);
        }
        $hostInfo->{BOARD_SERIAL}   = $sn;
        #$hostInfo->{CHASSIS_SERIAL} = undef;

        my $productName = $self->getFileContent('/sys/class/dmi/id/product_name');
        $productName =~ s/^\*|\s$//g;
        $hostInfo->{PRODUCT_NAME} = $productName;

        my $vendorName = $self->getFileContent('/sys/class/dmi/id/sys_vendor');
        $vendorName =~ s/^\*|\s$//g;
        $hostInfo->{MANUFACTURER} = $vendorName;

        my $biosVersion;
        my $biosVersion = $self->getFileContent('/sys/class/dmi/id/bios_version');
        $biosVersion =~ s/^\*|\s$//g;
        $hostInfo->{BIOS_VERSION} = $biosVersion;

        if ( defined($productName) and $productName ne 'None' ) {
            $hostInfo->{MODEL}      = $productName;
            $hostInfo->{IS_VIRTUAL} = $self->isVirtualVendor($productName);
        }
        if ( defined($vendorName) and $vendorName ne 'None' ) {
            if ( $hostInfo->{IS_VIRTUAL} == 0 ) {
                $hostInfo->{IS_VIRTUAL} = $self->isVirtualVendor($vendorName);
            }
        }
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
    $hostInfo->{CPU_MODEL} = $modelInfo[0];
    my $cpuFrequency = $cpuInfo->{'cpu MHz'};
    $hostInfo->{CPU_FREQUENCY} = sprintf( '%.2f', $cpuFrequency / 1000 ) . 'GHz';
    my $cpuArch = ( POSIX::uname() )[4];
    $hostInfo->{CPU_ARCH} = $cpuArch;
}

sub isIgnoreNetIf {
    my ( $self, $ifName ) = @_;

    my $ignore = 0;

    my $ifTypeNum = int( $self->getFileContent("/sys/class/net/$ifName/type") );
    if ( $ifTypeNum == 1 ) {
        if ( -e "/sys/class/net/$ifName/bridge" or -e "/sys/class/net/$ifName/brport/bridge" ) {

            #bridge or bridge port
            $ignore = 1;
        }
        elsif ( -e "/sys/class/net/$ifName/tun_flags" ) {

            #tun tap
            $ignore = 1;
        }
        elsif ( -e "/proc/net/vlan/$ifName" ) {

            #vlan
            $ignore = 1;
        }
        elsif ( $ifName =~ /^dummy/ and -e "/sys/devices/virtual/net/$ifName" ) {

            #dummy
            $ignore = 1;
        }
        elsif ( -f "/sys/class/net/$ifName/address" ) {
            my $macAddr = $self->getFileContent("/sys/class/net/$ifName/address");
            if ( $macAddr eq '00:00:00:00:00:00' ) {
                $ignore = 1;
            }
        }
    }
    else {
        $ignore = 1;
    }

    return $ignore;
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
        $nicInfo->{_OBJ_CATEGORY} = 'HOST';
        $nicInfo->{_OBJ_TYPE}     = 'HOST-ETH';
        my ( $ethName, $macAddr, $ipAddr, $speed, $linkState );
        if ( $line =~ /^\d+:\s+(\S+):/ ) {
            $ethName = $1;
            if ( $ethName =~ /@/ ) {
                $ethName = substr( $ethName, 0, index( $ethName, '@' ) );
            }
            if ( $self->isIgnoreNetIf($ethName) ) {

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
            $i = $i - 1;

            if ( $ethName =~ /^lo/i or $ipAddr =~ /^127/ or $ipAddr =~ '^::1' ) {

                #忽略loopback网卡
                next;
            }

            if ( defined($macAddr) and $macAddr ne '' ) {
                $nicInfo->{NAME} = $ethName;
                $nicInfo->{MAC}  = $macAddr;

                if ( not defined( $macsMap->{$macAddr} ) ) {
                    $macsMap->{$macAddr} = 1;
                    if ( defined($speed) and $speed ne '' ) {
                        ( $nicInfo->{UNIT}, $nicInfo->{SPEED} ) = $utils->getNicSpeedFromStr($speed);
                    }
                    $nicInfo->{STATUS} = 'down';
                    if ( $linkState eq 'yes' ) {
                        $nicInfo->{STATUS} = 'up';
                    }
                    push( @nicInfos, $nicInfo );
                }
            }
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

    my @hbaPorts = ();
    foreach my $hbaInfo (@hbaInfos) {
        foreach my $portInfo ( @{ $hbaInfo->{PORTS} } ) {
            push(
                @hbaPorts,
                {
                    _OBJ_CATEGORY => 'HOST',
                    _OBJ_TYPE     => 'HOST-HBA',
                    NAME          => $hbaInfo->{NAME},
                    IS_VIRTUAL    => $hbaInfo->{IS_VIRTUAL},
                    WWNN          => $hbaInfo->{WWNN},
                    SPEED         => $hbaInfo->{SPEED},
                    WWPN          => $portInfo->{WWPN},
                    STATUS        => $portInfo->{STATUS}
                }
            );
        }
    }
    $hostInfo->{HBA_INTERFACES} = \@hbaPorts;
}

sub getKVMGuestOSUUIDs {
    my ( $self, $hostInfo ) = @_;
    my @uuids    = ();
    my $kvmLines = $self->getCmdOutLines("ps -efww |grep qemu-kvm");
    foreach my $line (@$kvmLines) {
        if ( $line =~ /-uuid\s(\S+)/ ) {
            push( @uuids, $1 );
        }
    }
    $hostInfo->{GUESTOS_UUIDS} = \@uuids;
}

sub getKVMAllocateInfo {
    my ( $self, $hostInfo ) = @_;
    my $memAllocatedSize  = 0;
    my $currentMemorySize = 0;
    my $vcpuAllocated     = 0;
    my $diskAllocatedSize = 0;
    my $diskUsedSize      = 0;

    my @kvmMachines = ();
    foreach my $confFile ( glob("/etc/libvirt/qemu/*.xml") ) {
        my $domain = xml_to_object( $confFile, { file => 1 } );
        if ( not defined($domain) or $domain->attr('type') ne 'kvm' ) {
            next;
        }

        my ( $name, $uuid, $osType, $arch, $on_poweroff, $on_reboot, $on_crash );
        my $childDom = undef;
        $childDom = $domain->path('name');
        if ( defined($childDom) ) {
            $name = $childDom->value();
        }
        $childDom = $domain->path('uuid');
        if ( defined($childDom) ) {
            $uuid = $childDom->value();
        }
        $childDom = $domain->path('os/type');
        if ( defined($childDom) ) {
            $osType = $childDom->value();
            $arch   = $childDom->attr('arch');
        }
        $childDom = $domain->path('on_poweroff');
        if ( defined($childDom) ) {
            $on_poweroff = $childDom->value();
        }
        $childDom = $domain->path('on_reboot');
        if ( defined($childDom) ) {
            $on_reboot = $childDom->value();
        }
        $childDom = $domain->path('on_crash');
        if ( defined($childDom) ) {
            $on_crash = $childDom->value();
        }

        my $allocatedMem;
        my $memory = $domain->path('memory');
        if ( defined($memory) ) {
            my $memSize = int( $memory->value() );
            my $memUnit = $memory->attr('unit');
            if ( $memUnit =~ /^K/ ) {
                $memSize = $memSize / 1024;
            }
            elsif ( $memUnit =~ /^G/ ) {
                $memSize = $memSize * 1024;
            }
            elsif ( $memUnit =~ /^T/ ) {
                $memSize = $memSize * 1024 * 1024;
            }
            $allocatedMem     = $memSize;
            $memAllocatedSize = $memAllocatedSize + $memSize;
        }

        my $currentMemory;
        my $currMemory = $domain->path('currentMemory');
        if ( defined($currMemory) ) {
            my $memSize = int( $currMemory->value() );
            my $memUnit = $currMemory->attr('unit');
            if ( $memUnit =~ /^K/ ) {
                $memSize = $memSize / 1024;
            }
            elsif ( $memUnit =~ /^G/ ) {
                $memSize = $memSize * 1024;
            }
            elsif ( $memUnit =~ /^T/ ) {
                $memSize = $memSize * 1024 * 1024;
            }
            $currentMemory     = $memSize;
            $currentMemorySize = $currentMemorySize + $memSize;
        }

        my $vcpuCount;
        my $vcpu = $domain->path('vcpu');
        if ( defined($vcpu) ) {
            $vcpuCount     = int( $vcpu->value() );
            $vcpuAllocated = $vcpuAllocated + $vcpuCount;
        }

        my @diskList     = ();
        my @diskInfoList = $domain->path('devices/disk');
        foreach my $disk (@diskInfoList) {
            my $diskType = $disk->attr('type');
            my $diskDev  = $disk->attr('device');

            my $targetDom = $disk->path('target');
            my $targetDev;
            if ( defined($targetDom) ) {
                $targetDev = $targetDom->attr('dev');
            }

            my ( $format, $virtualSize, $actualSize );
            my $imgFile;
            if ( $diskType eq 'file' ) {
                my $sourceDom = $disk->path('source');
                if ( defined($sourceDom) ) {
                    $imgFile = $sourceDom->attr('file');
                    if ( -f $imgFile ) {
                        my $jsonTxt     = $self->getCmdOut(qq{qemu-img info --output=json '$imgFile'});
                        my $imgFileJson = from_json($jsonTxt);
                        $format      = $imgFileJson->{'format'};
                        $virtualSize = springf( '%.2f', $imgFileJson->{'virtual-size'} / 1024 / 1024 / 1024 );
                        $actualSize  = sprintf( '%.2f', $imgFileJson->{'actual-size'} / 1024 / 1024 / 1024 );

                        $diskAllocatedSize = $diskAllocatedSize + $virtualSize;
                        $diskUsedSize      = $diskUsedSize + $actualSize;
                    }
                }
            }
            push(
                @diskList,
                {
                    _OBJ_CATEGORY => 'HOST',
                    _OBJ_TYPE     => 'DISK',
                    TYPE          => $diskType,
                    FORMAT        => $format,
                    VIRTUAL_SIZE  => $virtualSize,
                    ACTUAL_SIZE   => $actualSize,
                    DEVICE        => $diskDev,
                    TARGET_DEV    => $targetDev,
                    FILE          => $imgFile
                }
            );
        }

        push(
            @kvmMachines,
            {
                _OBJ_CATEGORY => 'HOST',
                _OBJ_TYPE     => 'KVM-MACHINE',
                NAME          => $name,
                UUID          => $uuid,
                ARCH          => $arch,
                OS_TYPE       => $osType,
                ON_POWEROFF   => $on_poweroff,
                ON_REBOOT     => $on_reboot,
                ON_CRASH      => $on_crash,
                MEMORY        => $allocatedMem,
                USED_MEMORY   => $currentMemory,
                VCPU          => $vcpuCount,
                DISKS         => \@diskList
            }
        );
    }

    $hostInfo->{KVM_MEM_ALLOCATE}  = $memAllocatedSize;
    $hostInfo->{KVM_MEM_USED}      = $currentMemorySize;
    $hostInfo->{KVM_VCPU_ALLOCATE} = $vcpuAllocated;
    $hostInfo->{KVM_DISK_ALLOCATE} = $diskAllocatedSize;
    $hostInfo->{KVM_DISK_USED}     = $diskUsedSize;

    $hostInfo->{KVM_MACHINES} = \@kvmMachines;
}

sub getOsServices {
    my ( $self, $osInfo ) = @_;
    my $connGather = ConnGather->new( $self->{inspect} );
    my $connInfo   = $connGather->getListenInfo();
    my $listenMap  = $connInfo->{LISTEN};

    my $svcPortsMap = {};
    if ( defined($listenMap) ) {
        foreach my $lsnAddr ( keys(%$listenMap) ) {
            if ( $lsnAddr =~ /(\d+)/ ) {
                my $lsnPort = int($1);
                if ( $lsnPort < 1024 and $lsnPort > 1 ) {
                    $svcPortsMap->{$lsnPort} = 1;
                }
            }
        }
    }

    my @services    = ();
    my $servicesTxt = $self->getFileContent("/etc/services");
    foreach my $line ( split( /\n+/, $servicesTxt ) ) {
        if ( $line =~ /^\s*(\w+)\s+(\d+)\/(\w+)/ ) {
            my $svcName  = $1;
            my $port     = int($2);
            my $protocol = $3;
            if ( $svcPortsMap->{$port} ) {
                my $svcInfo = {
                    NAME     => $svcName,
                    PORT     => $port,
                    PROTOCOL => $protocol
                };
                push( @services, $svcInfo );
            }
        }
    }
    $osInfo->{SERVICES} = \@services;
}

sub collectHostInfo {
    my ( $self, $osInfo ) = @_;

    my $hostInfo = {};
    $hostInfo->{IS_VIRTUAL} = $osInfo->{IS_VIRTUAL};
    $hostInfo->{DISKS}      = $osInfo->{DISKS};
    $hostInfo->{MEM_TOTAL}  = $osInfo->{MEM_TOTAL};

    if ( $self->{justBaseInfo} == 0 ) {
        $self->getMainBoardInfo($hostInfo);
        $self->getCPUInfo($hostInfo);
        $self->getNicInfo($hostInfo);
        $self->getHBAInfo($hostInfo);
        $self->getKVMGuestOSUUIDs($hostInfo);
        $self->getKVMAllocateInfo($hostInfo);
    }
    else{
        $self->getMainBoardInfo($hostInfo);
        $self->getCPUInfo($hostInfo);
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
    $osInfo->{IS_VIRTUAL}      = $hostInfo->{IS_VIRTUAL};

    my @os_eths;
    foreach my $item ( @{ $hostInfo->{ETH_INTERFACES} } ) {
        my %tmp = %$item;
        $tmp{_OBJ_CATEGORY} = 'OS';
        $tmp{_OBJ_TYPE}     = 'OS-ETH';

        push @os_eths, \%tmp;
    }
    $osInfo->{ETH_INTERFACES} = \@os_eths;
    my @os_hbas;
    foreach my $item ( @{ $hostInfo->{HBA_INTERFACES} } ) {
        my %tmp = %$item;
        $tmp{_OBJ_CATEGORY} = 'OS';
        $tmp{_OBJ_TYPE}     = 'OS-HBA';

        push @os_hbas, \%tmp;
    }
    $osInfo->{HBA_INTERFACES} = \@os_hbas;

    $self->collectOsPerfInfo($osInfo);

    if ( $osInfo->{IS_VIRTUAL} == 0 ) {
        return ( $hostInfo, $osInfo );
    }
    else {
        return ( undef, $osInfo );
    }
}

1;
