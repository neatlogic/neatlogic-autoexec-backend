#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

use strict;

package OSGatherWindows;

use POSIX qw(uname);

use Win32;
use Win32::API;

use OSGatherBase;
our @ISA = qw(OSGatherBase);

sub getWinCodePage {
    my ($self) = @_;
    my $charSet = 'GBK';

    if ( Win32::API->Import( 'kernel32', 'int GetACP()' ) ) {
        $charSet = GetACP();
    }
    return $charSet;
}

sub collectOsInfo {
    my ($self) = @_;

    my $utils  = $self->{collectUtils};
    my $osInfo = {};

    my $charSet = $self->getWinCodePage();

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

    my $biosSerialInfo = $self->getCmdOutLines('wmic bios get serialnumber');
    my $machineId      = $$biosSerialInfo[1];
    $machineId =~ s/^\s+|\s+$//g;
    $osInfo->{MACHINE_ID} = $machineId;

    #TODO: 补充是否虚拟机的判断
    $osInfo->{IS_VIRTUAL} = 0;
    if ( $machineId =~ /^vmware/i or $machineId =~ /^kvm/i or $machineId =~ /Nutanix/ ) {
        $osInfo->{IS_VIRTUAL} = 1;
    }

    my @dnsServers = ();
    my $dnsInfo    = $self->getCmdOutLines('wmic nicconfig get DNSServerSearchOrder /value|findstr "DNSServerSearchOrder={"');
    foreach my $line (@$dnsInfo) {
        while ( $line =~ /(\d+\.\d+\.\d+\.\d+)/g ) {
            push( @dnsServers, $1 );
        }
    }
    $osInfo->{DNS_SERVERS} = \@dnsServers;

    my @ntpServers   = ();
    my $ntpInfoLines = $self->getCmdOutLines('w32tm /query /configuration');
    foreach my $line (@$ntpInfoLines) {
        if ( $line =~ /NtpServer:\s*(\S+),/ ) {
            push( @ntpServers, $1 );
        }
    }
    $osInfo->{NTP_SERVERS} = \@ntpServers;
    $osInfo->{NTP_ENABLE}  = 0;
    if ( scalar(@ntpServers) > 0 ) {
        $osInfo->{NTP_ENABLE} = 1;
    }

    my $symantecProc = $self->getCmdOut('tasklist | findstr "ccSvcHst"');
    $osInfo->{SYMANTEC_INSTALLED} = 0;
    if ( $symantecProc =~ /ccSvcHst/ ) {
        $osInfo->{SYMANTEC_INSTALLED} = 1;
    }

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
            push( @patches, $1 );
        }
        elsif ( $line =~ /^(\S.*?):\s*(.*?)\s*$/ ) {
            $sysInfo->{$1} = $2;
        }
    }
    $osInfo->{PATCHES_APPLIED} = \@patches;
    $osInfo->{CPU_COUNT}       = $cpuCount;
    $osInfo->{CPU_CORES}       = $cpuCount;
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

    my @ipV4Addrs = ();
    my $ipInfo    = $self->getCmdOut('wmic nicconfig where "IPEnabled = True" get ipaddress');
    while ( $ipInfo =~ /(\d+\.\d+\.\d+\.\d+)/sg ) {
        my $ip = $1;
        if ( $ip ne '127.0.0.1' ) {
            push( @ipV4Addrs, $1 );
        }
    }
    $osInfo->{IP_ADDRS} = \@ipV4Addrs;

    #TODO: IPV6 address的采集

    my @users         = ();
    my $userInfoLines = $self->getCmdOutLines('wmic useraccount where disabled=false get name');
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

    #TODO: 磁盘信息的采集
    my @disks = ();
    $osInfo->{DISKS} = \@disks;

    return $osInfo;
}

sub collectHostInfo {
    my ($self) = @_;

    my $utils    = $self->{collectUtils};
    my $hostInfo = {};

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

    my $productInfo = $self->getCmdOutLines('wmic computersystem get model');
    my $productName = $$productInfo[1];
    $productName =~ s/^\s+|\s+$//g;
    $hostInfo->{PRODUCT_NAME} = $productName;

    my $productInfo = $self->getCmdOutLines('wmic computersystem get model');
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

    # Description                              MACAddress
    # Intel(R) PRO/1000 MT Network Connection  00:0C:29:28:7D:49
    my @nicInfos          = ();
    my $nicInfoLines      = $self->getCmdOutLines('wmic nicconfig where "IPEnabled = True" get description,macaddress');
    my $nicInfoLinesCount = scalar(@$nicInfoLines);
    for ( my $i = 1 ; $i < $nicInfoLinesCount ; $i++ ) {
        my $line        = $$nicInfoLines[$i];
        my $nicInfo     = {};
        my @nicInfoSegs = split( /\s+/, $line );
        $nicInfo->{MAC} = pop(@nicInfoSegs);
        my $nicName = substr( $line, 0, length($line) - length( $nicInfo->{MAC} ) );
        $nicName =~ s/^\s*|\s*$//g;
        if ( $nicName ne '' ) {
            $nicInfo->{NAME}       = $nicName;
            $nicInfo->{LINK_STATE} = 'up';
            push( @nicInfos, $nicInfo );
        }
    }
    $hostInfo->{NET_INTERFACES} = \@nicInfos;

    return $hostInfo;
}

sub collect {
    my ($self)   = @_;
    my $osInfo   = $self->collectOsInfo();
    my $hostInfo = $self->collectHostInfo();

    # my $hostInfo;
    # if ( $osInfo->{IS_VIRTUAL} == 0 ){
    #     $hostInfo = $self->collectHostInfo();
    # }
    $osInfo->{NET_INTERFACES} = $hostInfo->{NET_INTERFACES};

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

    return ( $hostInfo, $osInfo );
}

1;
