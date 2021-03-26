package collection_unix;

#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use utf8;
use File::Basename;
use Encode;
use Utils;

sub collect {
    my ($nodeIp) = @_;
    my @collect_data =();
    my %data = ();

    my $istuxedo = `ps -ef|grep tuxedo|grep -v grep |grep -v collection_tuxedo`;
    if ( not defined($istuxedo) or $istuxedo eq '') {
        print "no find tuxedo process.\n";
        return @collect_data;
        exit 0;
    }

    my $user = `ps -ef|grep tuxedo |grep -v grep|head -n1|awk '{print \$1}'`;
    chomp($user);

    my $test_tmadmin = "su - $user -c 'tmadmin -v' >> /dev/null";
    system($test_tmadmin);
    if ( $? != 0 ) {
        print "has tuxedo process but exec tmadmin failed\n";
        exit 0;
    }

    my $ip = `hostname -i`;
    chomp($ip);
    if ( $ip eq '127.0.0.1' ) {
        $ip = $nodeIp;
    }

    $data{'IP'}      = $ip;
    $data{'agentIP'} = $nodeIp;

    $data{'uniqueName'} = $ip . ':' . $data{'中间件类型'};

    my $name = `hostname`;
    chomp($name);
    $data{'名称'} = $name;

    my $ver_info = `su - $user -c "tmadmin -v " > ver.txt 2>&1`;
    $ver_info = `cat ver.txt`;
    my $ver;
    if ( defined $ver_info and $ver_info ne '' ) {
        if ( $ver_info =~ /\d{1,2}\.\d{1,2}\.\d{1,2}\.\d{1,2}\.\d{1,2}/ ) {
            $ver = $&;
        }
    }
    $data{'版本'} = $ver;

    my $cmd = "su - $user -c tmunloadcf >> /dev/null";
    system($cmd);
    if ( $? != 0 ) {
        print "execute tmunloadcf failed\n";
        exit 1;
    }

    my $install_path = `su - $user -c "tmunloadcf |grep TUXDIR|head -n1|cut -d = -f 2"`;
    chomp($install_path);
    $install_path = substr $install_path, 1, -2;
    $data{'安装路径'} = $install_path;
    $data{'部署于'}  = $ip;

    my @tux_instances = ();

    my $domain_id = `su - $user -c "tmunloadcf |grep -i domainid"|awk '{print \$2}'`;
    chomp($domain_id);
    $domain_id = substr $domain_id, 1, -1;

    my $a = `su - $user -c tmunloadcf`;
    my $server_info;
    if ( $a =~ /(?<=(\*SERVERS))(.*)(?=(\*MODULES))/s ) {
        $server_info = $&;
    }
    else {
        print "not match\n";
    }
    $server_info =~ s/^\s+|\s+$//g;

    my @servers = $server_info =~ /"\S+"\s+.*?="\d+"(?=\n)?/sg;

    foreach my $server (@servers) {
        my %tux = ();
        $tux{'domainId'} = $domain_id;
        $tux{'应用IP'}     = $ip;

        if ( $server =~ /SRVID=(\d+)/ ) {
            $tux{'serverId'} = $1;
        }
        if ( $server =~ /^"(\S+)"/ ) {
            $tux{'server名称'} = $1;
        }
        if ( $server =~ /SRVGRP="(\S+)"/ ) {
            $tux{'组'} = $1;
        }
        if ( $server =~ /CLOPT/ and $server =~ /-s\s+(\S+)\s+/ ) {
            $tux{'端口'} = $1;
        }
        elsif ( $server =~ /CLOPT/ and $server =~ /-n\s+\/\/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\:(\d{1,5})/ ) {
            $tux{'端口'} = $1;
        }
        push @tux_instances, \%tux;
    }
    $data{'服务配置'}  = \@tux_instances;
    push(@collect_data , \%data);

    return @collect_data;
}

1;
