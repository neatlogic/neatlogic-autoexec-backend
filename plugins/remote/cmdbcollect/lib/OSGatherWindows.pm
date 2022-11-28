#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

use strict;

package OSGatherWindows;

use POSIX qw(uname);
use Encode;

use Win32;
use Win32::API;

use OSGatherBase;
our @ISA = qw(OSGatherBase);

sub getUptime {
    my ( $self, $osInfo ) = @_;

    my $uptimeSeconds;
    my $uptimeStr = $self->getCmdOut( 'wmic path Win32_OperatingSystem get LastBootUpTime', 'Administrator', { charset => $self->{codepage} } );
    if ( $uptimeStr =~ /([\d\.]+)([\+|\-]{1}\d+)/ ) {
        my $epochSeconds = int($1);
        $uptimeSeconds = time() - $epochSeconds;
    }
    $osInfo->{UPTIME} = $uptimeSeconds;
}

sub getMiscInfo {
    my ( $self, $osInfo ) = @_;

    my @unameInfo = uname();
    my $hostName  = $unameInfo[1];
    my $osType    = $unameInfo[0];
    $osType =~ s/\s.*$//;

    $osInfo->{SYS_VENDOR} = 'IBM';
    $osInfo->{OS_TYPE}    = $osType;
    $osInfo->{HOSTNAME}   = $hostName;
    $osInfo->{CPU_ARCH}   = $unameInfo[4];

    if ( $unameInfo[4] eq 'x86' ) {
        $osInfo->{CPU_BITS} = 32;
    }
    else {
        $osInfo->{CPU_BITS} = 64;
    }

    my $biosSerialInfo = $self->getCmdOutLines( 'wmic bios get serialnumber', 'Administrator', { charset => $self->{codepage} } );
    my $machineId      = $$biosSerialInfo[1];
    $machineId =~ s/^\s+|\s+$//g;
    $osInfo->{MACHINE_ID} = $machineId;

    #是否虚拟机的判断
    $osInfo->{IS_VIRTUAL} = 0;
    if ( $machineId =~ /^vmware/i or $machineId =~ /^kvm/i or $machineId =~ /Nutanix/ ) {
        $osInfo->{IS_VIRTUAL} = 1;
    }
}

sub getDNSInfo {
    my ( $self, $osInfo ) = @_;

    my @dnsServers = ();
    my $dnsInfo    = $self->getCmdOutLines( 'wmic nicconfig get DNSServerSearchOrder /value|findstr "DNSServerSearchOrder={"', { charset => $self->{codepage} } );
    foreach my $line (@$dnsInfo) {
        while ( $line =~ /(\d+\.\d+\.\d+\.\d+)/g ) {
            push( @dnsServers, { VALUE => $1 } );
        }
    }
    $osInfo->{DNS_SERVERS} = \@dnsServers;
}

sub getNTPInfo {
    my ( $self, $osInfo ) = @_;

    my @ntpServers   = ();
    my $ntpInfoLines = $self->getCmdOutLines('w32tm /query /configuration');
    foreach my $line (@$ntpInfoLines) {
        if ( $line =~ /NtpServer:\s*(\S+),/ ) {
            push( @ntpServers, { VALUE => $1 } );
        }
    }
    $osInfo->{NTP_SERVERS} = \@ntpServers;
    $osInfo->{NTP_ENABLE}  = 0;
    if ( scalar(@ntpServers) > 0 ) {
        $osInfo->{NTP_ENABLE} = 1;
    }
}

sub getSymantecInfo {
    my ( $self, $osInfo ) = @_;

    my $symantecProc = $self->getCmdOut('tasklist | findstr "ccSvcHst"');
    $osInfo->{SYMANTEC_INSTALLED} = 0;
    if ( $symantecProc =~ /ccSvcHst/ ) {
        $osInfo->{SYMANTEC_INSTALLED} = 1;
    }
}

sub getSystemInfo {
    my ( $self, $osInfo ) = @_;

    my $utils = $self->{collectUtils};

    # Active code page: 437

    # Host Name:                 DEV-WIN2K8-35
    # OS Name:                   Microsoftr Windows Serverr 2008 Standard
    # OS Version:                6.0.6001 Service Pack 1 Build 6001
    # OS Manufacturer:           Microsoft Corporation
    # OS Configuration:          Standalone Server
    # OS Build Type:             Multiprocessor Free
    # Registered Owner:          Windows ??
    # Registered Organization:
    # Product ID:                92573-082-2500115-76360
    # Original Install Date:     2017/7/12, 2:24:58
    # System Boot Time:          2021/8/2, 14:34:41
    # System Manufacturer:       VMware, Inc.
    # System Model:              VMware Virtual Platform
    # System Type:               x64-based PC
    # Processor(s):              2 Processor(s) Installed.
    #                         [01]: Intel64 Family 6 Model 45 Stepping 7 GenuineInt
    # el ~2600 Mhz
    #                         [02]: Intel64 Family 6 Model 45 Stepping 7 GenuineInt
    # el ~2600 Mhz
    # BIOS Version:              Phoenix Technologies LTD 6.00, 2019/12/9
    # Windows Directory:         C:\Windows
    # System Directory:          C:\Windows\system32
    # Boot Device:               \Device\HarddiskVolume1
    # System Locale:             zh-cn;Chinese (China)
    # Input Locale:              zh-cn;Chinese (China)
    # Time Zone:                 (GMT+08:00) ??,??,???????,????
    # Total Physical Memory:     6,143 MB
    # Available Physical Memory: 4,666 MB
    # Page File: Max Size:       12,397 MB
    # Page File: Available:      10,750 MB
    # Page File: In Use:         1,647 MB
    # Page File Location(s):     C:\pagefile.sys
    # Domain:                    WORKGROUP
    # Logon Server:              \\DEV-WIN2K8-35
    # Hotfix(s):                 10 Hotfix(s) Installed.
    #                         [01]: KB2305420
    #                         [02]: KB2423089
    #                         [03]: KB2535512
    #                         [04]: KB942288
    #                         [05]: KB948609
    #                         [06]: KB948610
    #                         [07]: KB949246
    #                         [08]: KB949247
    #                         [09]: KB956250
    #                         [10]: KB974318
    # Network Card(s):           1 NIC(s) Installed.
    #                         [01]: Intel(R) PRO/1000 MT Network Connection
    #                                 Connection Name: ????
    #                                 DHCP Enabled:    No
    #                                 IP address(es)
    #                                 [01]: 192.168.0.35

    my $sysInfo  = {};
    my @patches  = ();
    my $cpuCount = 1;
    my $cpuModel;
    my $cpuFrequency;
    my $sysInfoLines      = $self->getCmdOutLines('chcp 65001 && systeminfo');
    my $sysInfoLinesCount = scalar(@$sysInfoLines);
    for ( my $i = 0 ; $i < $sysInfoLinesCount ; $i++ ) {
        my $line = $$sysInfoLines[$i];

        if ( $line =~ /^Processor\(s\):\s*(\d+)\s*Processor/ ) {
            $cpuCount = int($1);
            $i        = $i + 1;
            $line     = $$sysInfoLines[$i];
            if ( $line =~ /\s+\[\d+\]:\s*(.*)\s*$/ ) {
                $cpuModel = $1;
                if ( $cpuModel =~ /\~(\d+\s*Mhz)/ ) {
                    $cpuFrequency = $1;
                }
            }
        }
        elsif ( $line =~ /\[\d+\]:\s+(KB\d+)$/ ) {
            push( @patches, { VALUE => $1 } );
        }
        elsif ( $line =~ /^(\S.*?):\s*(.*?)\s*$/ ) {
            $sysInfo->{$1} = $2;
        }
    }
    $osInfo->{PATCHES_APPLIED} = \@patches;
    $osInfo->{CPU_COUNT}       = $cpuCount;
    $osInfo->{CPU_MODEL}       = $cpuModel;
    $osInfo->{CPU_FREQUENCY}   = $cpuFrequency;

    $osInfo->{VERSION}        = $sysInfo->{'OS Version'};
    $osInfo->{KERNEL_VERSION} = $sysInfo->{'OS Version'};
    $osInfo->{NAME}           = $sysInfo->{'OS Name'};
    $osInfo->{DOMAIN}         = $sysInfo->{'Domain'};
    $osInfo->{SYSTEM_LOCALE}  = $sysInfo->{'System Locale'};
    $osInfo->{INPUT_LOCALE}   = $sysInfo->{'Input Locale'};

    $osInfo->{TIME_ZONE}    = $sysInfo->{'Time Zone'};
    $osInfo->{SYS_VENDOR}   = $sysInfo->{'System Manufacturer'};
    $osInfo->{PRODUCT_NAME} = $sysInfo->{'System Model'};
    $osInfo->{BIOS_VERSION} = $sysInfo->{'BIOS Version'};
    $osInfo->{PRODUCT_UUID} = $sysInfo->{'Product ID'};

    $osInfo->{MEM_TOTAL}     = $utils->getMemSizeFromStr( $sysInfo->{'Total Physical Memory'} );
    $osInfo->{MEM_AVAILABLE} = $utils->getMemSizeFromStr( $sysInfo->{'Available Physical Memory'} );
    if( defined($osInfo->{MEM_TOTAL}) and $osInfo->{MEM_TOTAL} > 0 ){
        $osInfo->{MEM_USAGE}     = int( ( $osInfo->{MEM_TOTAL} - $osInfo->{MEM_AVAILABLE} ) * 10000 / $osInfo->{MEM_TOTAL} + 0.5 ) / 100;
    }
}

sub getIpAddrs {
    my ( $self, $osInfo ) = @_;

    # IPAddress         IPSubnet
    # {"192.168.0.35"}  {"255.255.255.0"}
    # IPAddress                                     IPSubnet                 MACAddress
    # {"10.0.249.114", "fe80::1aa:f8e7:a15d:888d"}  {"255.255.255.0", "64"}  00:0C:29:5E:C8:C2
    my @ipV4Addrs   = ();
    my @ipV6Addrs   = ();
    my $ipInfoLines = $self->getCmdOutLines( 'wmic nicconfig where "IPEnabled = True" get ipaddress,ipsubnet,macaddress', 'Administrator', { charset => $self->{codepage} } );
    foreach my $line (@$ipInfoLines) {
        if ( $line =~ /\{(.*?)\}\s+\{(.*?)\}/ ) {
            my @ips      = split( /\s*,\s*/, $1 );
            my @netmasks = split( /\s*,\s*/, $2 );

            my $ipCount = scalar(@ips);
            for ( my $i = 0 ; $i < $ipCount ; $i++ ) {
                my $ip = $ips[$i];
                $ip =~ s/"//g;
                my $netmask = $netmasks[$i];
                $netmask =~ s/"//g;

                if ( $ip !~ /^127\./ and $ip ne '::1' ) {
                    if ( index( $ip, ':' ) > 0 ) {
                        my $block = Net::Netmask->safe_new("$ip/$netmask");
                        if ( defined($block) ) {
                            $netmask = $block->mask();
                        }
                        else {
                            print("WARN: Invalid CIDR $ip/$netmask\n");
                        }
                        push( @ipV6Addrs, { IP => $ip, NETMASK => $netmask } );
                    }
                    else {
                        push( @ipV4Addrs, { IP => $ip, NETMASK => $netmask } );
                    }
                }
            }
        }
    }

    $osInfo->{BIZ_IP}     = $self->getBizIp( \@ipV4Addrs, \@ipV6Addrs );
    $osInfo->{IP_ADDRS}   = \@ipV4Addrs;
    $osInfo->{IPV6_ADDRS} = \@ipV6Addrs;
}

sub getCPUCores {
    my ( $self, $osInfo ) = @_;

    my $cpuCores         = 0;
    my $cpuCorsInfoLines = $self->getCmdOutLines( 'wmic cpu get NumberOfCores', 'Administrator', { charset => $self->{codepage} } );
    foreach my $line (@$cpuCorsInfoLines) {
        $line =~ s/^\s*|\s*$//g;
        $cpuCores = $cpuCores + int($line);
    }
    $osInfo->{CPU_CORES} = $cpuCores;

    my $cpuLogicCores         = 0;
    my $cpuLogicCorsInfoLines = $self->getCmdOutLines( 'wmic cpu get NumberOfLogicaLProcessors', 'Administrator', { charset => $self->{codepage} } );
    foreach my $line (@$cpuLogicCorsInfoLines) {
        $line =~ s/^\s*|\s*$//g;
        $cpuLogicCores = $cpuLogicCores + int($line);
    }
    $osInfo->{CPU_LOGIC_CORES} = $cpuLogicCores;
}

sub getUsers {
    my ( $self, $osInfo ) = @_;

    my @users         = ();
    my $userInfoLines = $self->getCmdOutLines( 'wmic useraccount where disabled=false get name', 'Administrator', { charset => $self->{codepage} } );
    for ( my $i = 1 ; $i < scalar(@$userInfoLines) ; $i++ ) {
        my $userInfo = {};
        my $userName = $$userInfoLines[$i];
        $userName =~ s/^\s*|\s*$//g;
        if ( $userName ne '' ) {
            $userInfo->{NAME} = $userName;
            push( @users, $userInfo );
        }
    }
    $osInfo->{USERS} = \@users;
}

sub getMountPointInfo {
    my ( $self, $osInfo ) = @_;

    #逻辑磁盘（挂在点）信息的采集
    # c:\tmp\autoexec\cmdbcollect>wmic logicaldisk get Name,Size,FreeSpace
    # FreeSpace    Name  Size
    #             A:
    # 19005206528  C:    85897244672
    #             D:
    my @logicalDisks     = ();
    my $ldiskFieldIdxMap = {
        Name      => undef,
        Size      => undef,
        FreeSpace => undef
    };
    my $ldiskInfoLines = $self->getCmdOutLines( 'wmic logicaldisk get ' . join( ',', keys(%$ldiskFieldIdxMap) ), 'Administrator', { charset => $self->{codepage} } );

    #因为wmic获取数据的字段顺序不确定，所以要计算各个字段在哪一列
    my @ldiskHeadInfo = split( /\s+/, $$ldiskInfoLines[0] );
    for ( my $i = 0 ; $i <= $#ldiskHeadInfo ; $i++ ) {
        my $fieldName = $ldiskHeadInfo[$i];
        $ldiskFieldIdxMap->{$fieldName} = $i;
    }

    for ( my $i = 1 ; $i < scalar(@$ldiskInfoLines) ; $i++ ) {
        my @splits = split( /\s+/, $$ldiskInfoLines[$i] );
        my $size   = int( $splits[ $ldiskFieldIdxMap->{Size} ] * 100 / 1024 / 1024 / 1024 ) / 100;
        if ( $size > 0 ) {
            my $ldiskInfo = {};
            my $free      = int( $splits[ $ldiskFieldIdxMap->{FreeSpace} ] * 100 / 1024 / 1024 / 1024 ) / 100;
            $ldiskInfo->{NAME}      = $splits[ $ldiskFieldIdxMap->{Name} ];
            $ldiskInfo->{UNIT}      = 'GB';
            $ldiskInfo->{CAPACITY}  = $size;
            $ldiskInfo->{AVAILABLE} = $free;
            $ldiskInfo->{USED}      = $size - $free;
            $ldiskInfo->{USED_PCT}  = int( ( $size - $free ) * 10000 / $size ) / 100;
            push( @logicalDisks, $ldiskInfo );
        }
    }

    $osInfo->{MOUNT_POINTS} = \@logicalDisks;
}

sub getDiskInfo {
    my ( $self, $osInfo ) = @_;

    #TODO：物理磁盘LUN ID 的采集确认
    # c:\tmp\autoexec\cmdbcollect>wmic diskdrive get deviceId,size,serialnumber,scsiport,scsilogicalunit,scsitargetId,name
    # DeviceID            Name                SCSILogicalUnit  SCSIPort  SCSITargetId  SerialNumber                      Size
    # \\.\PHYSICALDRIVE0  \\.\PHYSICALDRIVE0  0                2         0             6000c29f49a80cce2b4b8dd0710281a4  85896599040

    #因为磁盘型号有空格，无法正确切分，所以单独查询，并通过序列号进行关联
    my $diskSNModelMap     = {};
    my $diskModelInfoLines = $self->getCmdOutLines( 'wmic diskdrive get serialnumber,model', 'Administrator', { charset => $self->{codepage} } );
    foreach my $line (@$diskModelInfoLines) {

        #6000c29f49a80cce2b4b8dd0710281a4
        if ( $line =~ /(\w{32})/ ) {
            my $sn = $1;
            $line =~ s/$sn//;
            $line =~ s/^\s*|\s*$//g;
            $diskSNModelMap->{$sn} = $line;
        }
    }

    my @disks           = ();
    my $diskFieldIdxMap = {
        DeviceId      => undef,
        Name          => undef,
        Size          => undef,
        SerialNumber  => undef,
        InterfaceType => undef
    };
    my $diskInfoLines = $self->getCmdOutLines( 'wmic diskdrive get ' . join( ',', keys(%$diskFieldIdxMap) ), 'Administrator', { charset => $self->{codepage} } );

    #因为wmic获取数据的字段顺序不确定，所以要计算各个字段在哪一列
    my @diskHeadInfo = split( /\s+/, $$diskInfoLines[0] );
    for ( my $i = 0 ; $i <= $#diskHeadInfo ; $i++ ) {
        my $fieldName = $diskHeadInfo[$i];
        $diskFieldIdxMap->{$fieldName} = $i;
    }
    for ( my $i = 1 ; $i < scalar(@$diskInfoLines) ; $i++ ) {
        my @splits  = split( /\s+/, $$diskInfoLines[$i] );
        my $sizeIdx = $diskFieldIdxMap->{Size};
        if ( not defined($sizeIdx) ) {
            next;
        }

        my $size = int( $splits[$sizeIdx] * 100 / 1024 / 1024 / 1024 ) / 100;
        my $sn   = $splits[ $diskFieldIdxMap->{SerialNumber} ];

        if ( defined($sn) ) {
            my $diskInfo = {};
            $diskInfo->{ID}       = $splits[ $diskFieldIdxMap->{ID} ];
            $diskInfo->{NAME}     = $splits[ $diskFieldIdxMap->{DeviceId} ];
            $diskInfo->{MODEL}    = $diskSNModelMap->{$sn};
            $diskInfo->{CAPACITY} = $size;
            $diskInfo->{UNIT}     = 'GB';
            $diskInfo->{SN}       = $sn;
            $diskInfo->{TYPE}     = $splits[ $diskFieldIdxMap->{InterfaceType} ];
            push( @disks, $diskInfo );
        }
    }

    $osInfo->{DISKS} = \@disks;
}

sub getPerformanceInfo {
    my ( $self, $osInfo ) = @_;

    my $cpuPercentInfo = $self->getCmdOutLines('wmic cpu get loadpercentage');

    my $cpuCount = 0;
    my $cpuLoad  = 0.0;
    for my $line (@$cpuPercentInfo) {
        if ( $line =~ /^\s*([\d\.]+)\s*$/ ) {
            $cpuCount = $cpuCount + 1;
            $cpuLoad  = $cpuLoad + $1;
        }
    }
    $osInfo->{CPU_USAGE}         = int( $cpuLoad * 100 ) / 100;
    $osInfo->{CPU_USAGE_PERCORE} = int( $cpuLoad * 100 / $cpuCount ) / 100;

    my $cpuQueueInfo = $self->getCmdOutLines('wmic path Win32_PerfFormattedData_PerfOS_System get ProcessorQueueLength');
    for my $line (@$cpuQueueInfo) {
        if ( $line =~ /^\s*([\d\.]+)\s*$/ ) {
            $osInfo->{CPU_QUEUE_LEN} = 0.0 + $1;
        }
    }
}

sub collectOsInfo {
    my ($self) = @_;

    my $osInfo = {};

    if ( $self->{justBaseInfo} == 0 ) {
        $self->getMiscInfo($osInfo);
        $self->getDNSInfo($osInfo);
        $self->getNTPInfo($osInfo);
        $self->getSymantecInfo($osInfo);
        $self->getSystemInfo($osInfo);
        $self->getIpAddrs($osInfo);
        $self->getCPUCores($osInfo);
        $self->getUsers($osInfo);
        $self->getMountPointInfo($osInfo);
        $self->getDiskInfo($osInfo);
    }
    else {
        $self->getSystemInfo($osInfo);
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
    }
}

sub getBoardInfo {
    my ( $self, $hostInfo ) = @_;

    my $biosSerialInfo = $self->getCmdOutLines('wmic bios get serialnumber');
    my $machineId      = $$biosSerialInfo[1];
    $machineId =~ s/^\s+|\s+$//g;
    $hostInfo->{MACHINE_ID}   = $machineId;
    $hostInfo->{BOARD_SERIAL} = $machineId;

    my $biosVerInfo = $self->getCmdOutLines('wmic bios get version');
    my $biosVer     = $$biosVerInfo[1];
    $biosVer =~ s/^\s+|\s+$//g;
    $hostInfo->{BIOS_VERSION} = $biosVer;

    my $sysVendorInfo = $self->getCmdOutLines('wmic bios get version');
    my $sysVendor     = $$sysVendorInfo[1];
    $sysVendor =~ s/^\s+|\s+$//g;
    $hostInfo->{SYS_VENDOR} = $sysVendor;

    my $productInfo = $self->getCmdOutLines( 'wmic computersystem get model', 'Administrator', { charset => $self->{codepage} } );
    my $productName = $$productInfo[1];
    $productName =~ s/^\s+|\s+$//g;
    $hostInfo->{PRODUCT_NAME} = $productName;

    my $memSlotsInfo = $self->getCmdOutLines('wmic memphysical get memorydevices');
    my $memSlots     = $$memSlotsInfo[1];
    $memSlots =~ s/^\s+|\s+$//g;
    $hostInfo->{MEM_SLOTS} = int($memSlots);

    my $memSpeedInfo = $self->getCmdOutLines('wmic memorychip get speed');
    my $memSpeed     = $$memSpeedInfo[1];
    $memSpeed =~ s/^\s+|\s+$//g;
    if ( $memSpeed ne '' ) {
        $hostInfo->{MEM_SPEED} = $memSpeed . 'MHz';
    }
    else {
        $hostInfo->{MEM_SPEED} = undef;
    }
}

sub getNicInfo {
    my ( $self, $hostInfo ) = @_;

    # Description                              MACAddress
    # Intel(R) PRO/1000 MT Network Connection  00:0C:29:28:7D:49
    my @nicInfos          = ();
    my $macsMap           = {};
    my $nicInfoLines      = $self->getCmdOutLines( 'wmic nicconfig where "IPEnabled = True" get description,macaddress', 'Administrator', { charset => $self->{codepage} } );
    my $nicInfoLinesCount = scalar(@$nicInfoLines);
    for ( my $i = 1 ; $i < $nicInfoLinesCount ; $i++ ) {
        my $line = $$nicInfoLines[$i];
        $line =~ s/^\s*|\s*$//g;

        my @nicInfoSegs = split( /\s+/, $line );
        my $nicMac      = lc( pop(@nicInfoSegs) );
        my $nicName     = substr( $line, 0, length($line) - 17 );
        if ( length($nicMac) == 17 and $nicName ne '' ) {
            $nicName =~ s/^\s*|\s*$//g;
            if ( not defined( $macsMap->{$nicName} ) ) {
                $macsMap->{$nicName} = 1;
                my $nicInfo = {};
                $nicInfo->{NAME}   = $nicName;
                $nicInfo->{MAC}    = $nicMac;
                $nicInfo->{STATUS} = 'up';
                push( @nicInfos, $nicInfo );
            }
        }
    }
    @nicInfos = sort { $a->{NAME} <=> $b->{NAME} } @nicInfos;
    $hostInfo->{ETH_INTERFACES} = \@nicInfos;

    if ( not defined( $hostInfo->{BOARD_SERIAL} ) and scalar(@nicInfos) > 0 ) {
        my $firstMac = $nicInfos[0]->{MAC};
        $hostInfo->{BOARD_SERIAL} = $firstMac;
        $hostInfo->{MACHINE_ID}   = $firstMac;
    }
}

sub collectHostInfo {
    my ($self) = @_;

    my $hostInfo = {};
    if ( $self->{justBaseInfo} == 0 ) {
        $self->getBoardInfo($hostInfo);
        $self->getNicInfo($hostInfo);
    }

    return $hostInfo;
}

sub getCodePage {
    my $codepage;

    if ( Win32::API->Import( 'kernel32', 'int GetACP()' ) ) {
        $codepage = 'cp' . GetACP();
    }
    return $codepage;
}

sub collect {
    my ($self) = @_;
    $self->{codepage} = $self->getCodePage();
    $self->{verbose}  = 0;
    my $osInfo   = $self->collectOsInfo();
    my $hostInfo = $self->collectHostInfo();

    # my $hostInfo;
    # if ( $osInfo->{IS_VIRTUAL} == 0 ){
    #     $hostInfo = $self->collectHostInfo();
    # }
    $osInfo->{ETH_INTERFACES} = $hostInfo->{ETH_INTERFACES};

    $hostInfo->{IS_VIRTUAL} = $osInfo->{IS_VIRTUAL};
    $hostInfo->{DISKS}      = $osInfo->{DISKS};

    $hostInfo->{CPU_COUNT}     = $osInfo->{CPU_COUNT};
    $hostInfo->{CPU_CORES}     = $osInfo->{CPU_CORES};
    $hostInfo->{CPU_MODEL}     = $osInfo->{CPU_MODEL};
    $hostInfo->{CPU_FREQUENCY} = $osInfo->{CPU_FREQUENCY};

    $hostInfo->{SYS_VENDOR}   = $osInfo->{SYS_VENDOR};
    $hostInfo->{PRODUCT_NAME} = $osInfo->{PRODUCT_NAME};
    $hostInfo->{BIOS_VERSION} = $osInfo->{BIOS_VERSION};
    $hostInfo->{PRODUCT_UUID} = $osInfo->{PRODUCT_UUID};

    $hostInfo->{MEM_TOTAL}     = $osInfo->{MEM_TOTAL};
    $hostInfo->{MEM_AVAILABLE} = $osInfo->{MEM_AVAILABLE};

    $self->collectOsPerfInfo($osInfo);

    if ( $osInfo->{IS_VIRTUAL} == 1 ) {
        return ( undef, $osInfo );
    }
    else {
        return ( $hostInfo, $osInfo );
    }
}

1;
