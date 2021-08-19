#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

use strict;

package OSGatherAIX;

use POSIX qw(uname);
use OSGatherBase;
our @ISA = qw(OSGatherBase);

sub collectOsInfo {
    my ($self) = @_;

    my $utils  = $self->{collectUtils};
    my $osInfo = {};

    my @unameInfo = uname();
    my $hostName  = $unameInfo[1];
    $osInfo->{SYS_VENDOR}     = 'IBM';
    $osInfo->{OS_TYPE}        = $self->{ostype};
    $osInfo->{HOSTNAME}       = $hostName;
    $osInfo->{KERNEL_VERSION} = $unameInfo[2];

    my $osVer = $self->getCmdOut('oslevel -s');
    $osVer =~ s/^\s*|\s*$//g;
    $osInfo->{VERSION} = $osVer;

    my $machineId = $self->getCmdOut('uname -m');
    $machineId =~ s/^\s*|\s*$//g;
    $osInfo->{MACHINE_ID} = $machineId;

    my $prtConfLines = $self->getCmdOutLines('prtconf');
    my $prtConfInfo  = {};
    foreach my $line (@$prtConfLines) {
        if ( $line =~ /^\s*(.*?):\s*(.*)\s*$/ ) {
            $prtConfInfo->{$1} = $2;
        }
    }

    $osInfo->{BOARD_SERIAL}         = $prtConfInfo->{'Machine Serial Number'};
    $osInfo->{CPU_MODEL_NAME}       = $prtConfInfo->{'System Model'};
    $osInfo->{CPU_CORES}            = $prtConfInfo->{'Number Of Processors'};
    $osInfo->{CPU_BITS}             = int( $prtConfInfo->{'CPU Type'} );
    $osInfo->{CPU_ARCH}             = $prtConfInfo->{'Processor Type'};
    $osInfo->{CPU_VERSION}          = $prtConfInfo->{'Processor Version'};
    $osInfo->{CPU_MODE}             = $prtConfInfo->{'Processor Implementation Mode'};
    $osInfo->{CPU_FREQUENCY}        = $prtConfInfo->{'Processor Clock Speed'};
    $osInfo->{CPU_FIRMWARE_VERSION} = $prtConfInfo->{'Firmware Version'};
    $osInfo->{CPU_MICROCODE}        = $prtConfInfo->{'Platform Firmware level'};
    $osInfo->{AUTO_RESTART}         = $prtConfInfo->{'Auto Restart'};

    $osInfo->{MEM_TOTAL} = $utils->getMemSizeFromStr( $prtConfInfo->{'Memory Size'} );

    #TODO：detect if os is vios or vioc or lpart
    #$osInfo->{IS_VIRTUAL} = 0;

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

    #   node       mounted        mounted over    vfs       date        options
    # -------- ---------------  ---------------  ------ ------------ ---------------
    #          /dev/hd4         /                jfs2   Jul 20 04:37 rw,log=/dev/hd8
    #          /dev/hd2         /usr             jfs2   Jul 20 04:37 rw,log=/dev/hd8
    #          /dev/hd9var      /var             jfs2   Jul 20 04:37 rw,log=/dev/hd8
    #          /dev/hd3         /tmp             jfs2   Jul 20 04:37 rw,log=/dev/hd8
    my $mountLines = $self->getCmdOutLines('LANG=C mount');
    for ( my $i = 2 ; $i < scalar(@$mountLines) ; $i++ ) {
        my $line = $$mountLines[$i];
        $line =~ s/[a-zA-Z]{3}\s\d\d\s\d\d:\d\d.*$//;

        # The 1st column specifies the device that is mounted.
        # The 2nd column reveals the mount point.
        # The 3rd column tells the file-system type.
        # The 4th column tells you if it is mounted read-only (ro) or read-write (rw).
        # The 5th and 6th columns are dummy values designed to match the format used in /etc/mtab.
        my @mountInfos = split( /\s+/, $line );
        my $node       = shift(@mountInfos);
        my $device     = shift(@mountInfos);
        my $fsType     = pop(@mountInfos);
        my $mountPoint;
        if ( $line =~ /^\s*\Q$node\E\s+\Q$device\E\s+(.*?)\s+\Q$fsType\E/ ) {
            $mountPoint = $1;
        }

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

    # # df -m /usr /var
    # Filesystem    MB blocks      Free %Used    Iused %Iused Mounted on
    # /dev/hd2        5120.00   2757.21   47%    43971     7% /usr
    # /dev/hd9var     1024.00    594.10   42%     4437     4% /var
    my @diskMountPoints = keys(%$diskMountMap);
    if ( scalar(@diskMountPoints) > 0 ) {
        my $dfLines = $self->getCmdOutLines( "LANG=C df -m '" . join( "' '", @diskMountPoints ) . "'" );
        foreach my $line (@$dfLines) {
            if ( $line =~ /([\d\.]+)\s+([\d\.]+)\s+(\d+%)\s+(\d+)\s+(\d+%)\s+(.*)\s*$/ ) {
                my $totalSize    = int($1);
                my $availSize    = int($2);
                my $usedSize     = $totalSize - $availSize;
                my $utility      = $3;
                my $inodeUsed    = $4;
                my $inodeUtility = $5;
                my $mountPoint   = $6;
                chomp($mountPoint);
                my $mountInfo = $diskMountMap->{$mountPoint};

                if ( defined($mountInfo) ) {
                    $mountInfo->{CAPACITY}      = int( $totalSize * 1000 / 1024 + 0.5 ) / 1000;
                    $mountInfo->{USED}          = int( $usedSize * 1000 / 1024 + 0.5 ) / 1000;
                    $mountInfo->{AVAILABLE}     = int( $availSize * 1000 / 1024 + 0.5 ) / 1000;
                    $mountInfo->{UNIT}          = 'GB';
                    $mountInfo->{'INODE_USED%'} = $inodeUtility + 0.0;
                    $mountInfo->{'USED%'}       = $utility + 0.0;
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

    my $bondInfoLine = $self->getCmdOut('lsdev -Cc adapter|grep EtherChannel');
    if ($bondInfoLine) {
        $osInfo->{NIC_BOND} = 1;
    }
    else {
        $osInfo->{NIC_BOND} = 0;
    }

    # # svmon -G -O pgsz=off,unit=MB
    # Unit: MB
    # --------------------------------------------------------------------------------------
    #                size       inuse        free         pin     virtual  available   mmode
    # memory      6144.00     1780.05     4363.95     1130.36     1229.83    4701.70     Ded
    # pg space     512.00        7.46
    my $memInfoLines = $self->getCmdOutLines('svmon -G -O pgsz=off,unit=MB');
    foreach my $line (@$memInfoLines) {
        if ( $line =~ /^memory\s+(\d\.)+\s+(\d\.)+\s+(\d\.)+\s+(\d\.)+\s+(\d\.)+\s+(\d\.)+\s+/ ) {
            $osInfo->{MEM_TOTAL}     = int($1);
            $osInfo->{MEM_FREE}      = int($3);
            $osInfo->{MEM_AVAILABLE} = int($6);
        }
    }

    $memInfoLines = $self->getCmdOutLines('lsps -s');
    foreach my $line (@$memInfoLines) {
        if ( $line =~ /^\s+(\d+\S+)\s+(\d+)%/ ) {
            my $swapSize = $utils->getMemSizeFromStr($1);
            my $used     = int($2);
            $osInfo->{SWAP_TOTAL} = $utils->getMemSizeFromStr($1);
            $osInfo->{SWAP_FREE}  = $swapSize * $used / 100;
        }
    }

    my @dnsServers;
    my $dnsInfoLines = $self->getFileLines('/etc/resolv.conf');
    foreach my $line (@$dnsInfoLines) {
        if ( $line =~ /\s*nameserver\s+(.*)\s*$/i ) {
            my $dns = {};
            $dns->{NAME} = $1;
            push( @dnsServers, $dns );
        }
    }
    $osInfo->{DNS_SERVERS} = \@dnsServers;

    $osInfo->{NTP_ENABLE} = 0;
    my $ntpInfo = $self->getCmdOut('lssrc -s xntpd');
    if ( $ntpInfo =~ /active/i ) {
        $osInfo->{NTP_ENABLE} = 1;
    }

    my $ntpConfFile  = '/etc/ntp.conf';
    my $ntpInfoLines = $self->getFileLines($ntpConfFile);
    my @ntpServers   = ();
    foreach my $line (@$ntpInfoLines) {
        if ( $line =~ /^server\s+(\d+\.\d+\.\d+\.\d+)/i ) {
            my $ntp = {};
            $ntp->{NAME} = $1;
            push( @ntpServers, $ntp );
        }
    }
    $osInfo->{NTP_SERVERS} = \@ntpServers;

    my $maxOpenFilesCount;
    my $limitInfoLines = $self->getFileLines('/etc/security/limits');
    for ( my $i = 0 ; $i < scalar(@$limitInfoLines) ; $i++ ) {
        my $line = $$limitInfoLines[$i];
        if ( $line =~ /^\s*default:\s*$/ ) {
            for ( my $j = 0 ; $j < scalar(@$limitInfoLines) ; $j++ ) {
                $line = $$limitInfoLines[$j];
                if ( $line =~ /^\s*nofiles\s*=\s*(\d+)/ ) {
                    $maxOpenFilesCount = int($1);
                    last;
                }
            }
            if ( defined($maxOpenFilesCount) ) {
                last;
            }
        }
    }
    $osInfo->{MAX_OPEN_FILES} = $maxOpenFilesCount;

    my $maxUserProcCount = $self->getCmdOut(q{lsattr -E -l sys0|grep maxuproc |awk '{print $2}'});
    $osInfo->{MAX_USER_PROCESS_COUNT} = int($maxUserProcCount);

    my @ipv4;
    my @ipv6;
    my $ipInfoLines = $self->getCmdOutLines('ifconfig -a');
    foreach my $line (@$ipInfoLines) {
        my $ip;
        if ( $line =~ /^\s*inet\s+([\d\.]+)\s+netmask\s+/ ) {
            $ip = $1;
            if ( $ip !~ /^127\./ ) {
                my $nip = {};
                $nip->{NAME} = $ip;
                push( @ipv4, $nip );
            }
        }
        elsif ( $line =~ /^\s*inet6\s+(.*?)\%\d+\/\d+/ ) {
            $ip = $1;
            if ( $ip ne '::1' ) {    #TODO: ipv6 loop back addr range
                my $nip = {};
                $nip->{NAME} = $ip;
                push( @ipv6, $nip );
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

    #打过的补丁
    my @patchs         = ();
    my $patchInfoLines = $self->getCmdOutLines(q{instfix -i|grep ML | awk '{print $4}'});
    foreach my $patch (@$patchInfoLines) {
        $patch =~ s/^\s*|\s*$//g;
        my $patchObj = {};
        $patchObj->{NAME} = $patch;
        push( @patchs, $patchObj );
    }
    $osInfo->{PATCHES_APPLIED} = \@patchs;

    #TODO: SAN磁盘的计算以及磁盘多链路聚合的计算，因没有测试环境，需要再确认
    # lsdev -Cc disk
    #hdisk0 Available  Virtual SCSI Disk Drive
    #hdisk1 Available 02-08-00 SAS Disk Drive
    my @diskInfos;
    my $diskLines = $self->getCmdOutLines('LANG=C lsdev -Cc disk');

    foreach my $line (@$diskLines) {
        my $diskInfo = {};
        my @diskSegs = split( /\s+/, $line );
        my $name     = $diskSegs[1];
        $diskInfo->{NAME}     = $name;
        $diskInfo->{CAPACITY} = int( $self->getCmdOut("bootinfo -s '$name'") ) / 1000;
        $diskInfo->{UNIT}     = 'GB';

        if ( not $line =~ /\bMPIO\b/ ) {
            $diskInfo->{TYPE} = 'local';
        }
        else {
            $diskInfo->{TYPE} = 'remote';
            my $lunInfo = $self->getCmdOut("lscfg -vpl '$name'");

            my $sn;
            my $id;
            if ( $lunInfo =~ /FlashSystem/ ) {
                my $output = $self->getCmdOut("lsattr -El $name");
                my $idInfo;
                if ( $output =~ /unique_id\s+\S+\s+(\S+)/ ) {
                    $idInfo = $1;
                }
                if ( $idInfo =~ /(?<=FlashSystem-9840)\w{8}/ ) {
                    $sn = $&;
                }
                if ( $idInfo =~ /\w{4}(?=10FlashSystem)/ ) {
                    $id = $&;
                }
            }
            elsif ( $lunInfo =~ /hitachi/i ) {
                if ( $lunInfo =~ /Serial\sNumber\.+(\w+)/ ) {
                    $sn = $1;
                    if ( $sn eq '50403269' ) {
                        $sn = '412905';
                    }
                    elsif ( $sn eq '5040326B' ) {
                        $sn = '412907';
                    }
                }
                if ( $lunInfo =~ /\(Z1\)\.+(\w+)\s+/ ) {
                    $id = $1;
                    $id = '00' . $id;
                    substr( $id, 2, 0 ) = ':';
                    substr( $id, 5, 0 ) = ':';
                }
            }
            else {

                if ( $lunInfo =~ /Serial\sNumber\.+(\w+)/ ) {
                    my $sn_id = $1;
                    $id = substr( $sn_id, -4 );
                    $sn = substr( $sn_id, 0, -4 );
                }
            }

            $diskInfo->{LUN} = $sn . ':' . $id;
            $diskInfo->{ID}  = $sn . ':' . $id;
        }

        push( @diskInfos, $diskInfo );
    }
    $osInfo->{DISKS} = \@diskInfos;

    return $osInfo;
}

sub collectHostInfo {
    my ($self) = @_;

    my $utils    = $self->{collectUtils};
    my $hostInfo = {};

    my @unameInfo = uname();
    my $hostName  = $unameInfo[1];
    $hostInfo->{SYS_VENDOR} = 'IBM';

    my $machineId = $self->getCmdOut('uname -m');
    $machineId =~ s/^\s*|\s*$//g;
    $hostInfo->{MACHINE_ID} = $machineId;

    my $maxMemInfo = $self->getCmdOut("lparstat -i|grep 'Maximum Memory'");
    if ( $maxMemInfo =~ /(\d+.*)\s*$/ ) {
        $hostInfo->{MEM_TOTAL} = $utils->getMemSizeFromStr($1);
    }
    my $memSlotInfo = $self->getCmdOut('lscfg -vp |grep -i dimm|wc -l');
    $hostInfo->{MEM_SLOTS} = int($memSlotInfo);

    # Name  Mtu   Network     Address            Ipkts Ierrs    Opkts Oerrs  Coll
    # en0   1500  link#2      9a.91.23.c6.58.b  9810797     0   350193     0     0
    # en0   1500  192.168.0   192.168.1.21      9810797     0   350193     0     0
    # lo0   16896 link#1                         248105     0   248105     0     0
    # lo0   16896 127         127.0.0.1          248105     0   248105     0     0
    # lo0   16896 ::1%1                          248105     0   248105     0     0

    my $nicInfoLines     = $self->getCmdOutLines('netstat -ni');
    my $nicInfoLineCount = scalar(@$nicInfoLines);

    my $nicInfosMap = {};
    for ( my $i = 1 ; $i < $nicInfoLineCount ; $i++ ) {
        my $line    = $$nicInfoLines[$i];
        my @nicSegs = split( /\s+/, $line );

        my $ethName = $nicSegs[0];
        if ( $ethName =~ /^lo/i or $nicSegs[2] eq '127' or $nicSegs[2] eq '::1%1' ) {
            next;
        }

        my $nicInfo = $nicInfosMap->{$ethName};
        if ( not defined($nicInfo) ) {
            $nicInfo                 = {};
            $nicInfo->{NAME}         = $ethName;
            $nicInfosMap->{$ethName} = $nicInfo;

            #TODO: 网卡速率和接线状态确认，在高版本AIX是有问题的
            my $status = $self->getCmdOut("entstat -d $ethName | grep 'Link Status' | cut -d : -f 2");
            $nicInfo->{STATUS} = $status;
            my $speed = $self->getCmdOut("entstat -d $ethName |grep  'Speed Running' | cut -d : -f 2");
            $nicInfo->{SPEED} = $speed;
        }

        if ( $nicSegs[3] =~ /[a-f0-9]+(\.[a-f0-9]+){5}/ ) {
            my $macAddr = $nicSegs[3];
            $macAddr =~ s/\./:/g;
            $nicInfo->{MAC} = $macAddr;
        }
    }
    my @nicInfos = values(%$nicInfosMap);
    $hostInfo->{NET_INTERFACES} = \@nicInfos;

    #TODO: 需要确认HBA卡信息采集的正确性
    my @hbaInfos    = ();
    my @hbaInfosMap = {};
    my $fcNames     = $self->getCmdOutLines(q{lsdev -Cc adapter | grep 'FC Adapter' | awk '{print $1}'});
    foreach my $fcName (@$fcNames) {
        my $hbaInfo = {};
        $fcName =~ s/^\s+|\s+$//g;
        $hbaInfo->{'NAME'} = $fcName;
        my $wwn = $self->getCmdOut(qq{fcstat $fcName | grep 'Port Name' | cut -d : -f 2});
        $wwn =~ s/^\s+|\s+$//g;
        my @wwnSegments = ( $wwn =~ m/../g );    #切分为两个字符的数组
        $hbaInfo->{WWN} = join( ':', @wwnSegments );

        my $speed = $self->getCmdOut(qq{fcstat $fcName| grep running | cut -d : -f 2});
        $speed =~ s/^\s+|\s+$//g;
        $hbaInfo->{SPEED} = $speed;
        my $portState;
        my $portStateInfo = $self->getCmdOut(qq{fcstat $fcName | grep 'Attention Type' | cut -d : -f 2});

        if ( $portStateInfo =~ /up/i ) {
            $portState = 'up';
        }
        else {
            $portState = 'down';
        }
        $hbaInfo->{STATE} = $portState;

        push( @hbaInfos, $hbaInfo );
    }
    $hostInfo->{HBA_INTERFACES} = \@hbaInfos;

    return $hostInfo;
}

sub collect {
    my ($self) = @_;
    my $osInfo = $self->collectOsInfo();

    my $hostInfo = $self->collectHostInfo();

    $osInfo->{NET_INTERFACES} = $hostInfo->{NET_INTERFACES};

    $hostInfo->{IS_VIRTUAL}           = $osInfo->{IS_VIRTUAL};
    $hostInfo->{DISKS}                = $osInfo->{DISKS};
    $hostInfo->{BOARD_SERIAL}         = $osInfo->{BOARD_SERIAL};
    $hostInfo->{CPU_MODEL_NAME}       = $osInfo->{CPU_MODEL_NAME};
    $hostInfo->{CPU_CORES}            = $osInfo->{CPU_CORES};
    $hostInfo->{CPU_BITS}             = $osInfo->{CPU_BITS};
    $hostInfo->{CPU_ARCH}             = $osInfo->{CPU_ARCH};
    $hostInfo->{CPU_VERSION}          = $osInfo->{CPU_VERSION};
    $hostInfo->{CPU_MODE}             = $osInfo->{CPU_MODE};
    $hostInfo->{CPU_FREQUENCY}        = $osInfo->{CPU_FREQUENCY};
    $hostInfo->{CPU_FIRMWARE_VERSION} = $osInfo->{CPU_FIRMWARE_VERSION};
    $hostInfo->{CPU_MICROCODE}        = $osInfo->{CPU_MICROCODE};
    $hostInfo->{AUTO_RESTART}         = $osInfo->{AUTO_RESTART};

    if ( $osInfo->{IS_VIRTUAL} == 0 ) {
        return ( $hostInfo, $osInfo );
    }
    else {
        return ( undef, $osInfo );
    }
}

1;
