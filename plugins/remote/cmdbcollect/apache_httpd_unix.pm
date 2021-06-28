#!/usr/bin/perl

package apache_httpd_unix;

use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use warnings;
use utf8;
use File::Basename;
use Encode;
use Utils;

sub collect {
    my ($nodeIp)     = @_;
    my @collect_data = ();
    my %data         = ();

    my $httpd_pro = `ps -ef|grep httpd |grep -v $$|grep -v grep|tail -n1`;
    if ( !defined $httpd_pro or $httpd_pro eq '' ) {
        print "not find apache httpd process .\n";
        return @collect_data;
        exit 0;
    }
    else {
        my $is_rpm_inst = 0;
        my $conf_path;
        my $inst_path;
        my $bin_path;
        if ( $httpd_pro =~ /\s+\/usr\/sbin\/httpd\s+|\s+\/opt\/lampp\/bin\/httpd\s+/ ) {
            $is_rpm_inst = 1;
            $bin_path    = '/usr/sbin/';
            $conf_path   = '/etc/httpd/conf';
            $inst_path   = '/etc/httpd';
        }
        else {
            if ( $httpd_pro =~ /\s+(\S+)httpd\s+/ ) {
                if ( $1 eq './' ) {
                    print "relative path\n";
                    exit 1;
                }
                $is_rpm_inst = 0;
                $conf_path   = dirname($1) . '/conf';
                $inst_path   = dirname($1);
                $bin_path    = $1;
            }
        }

        my @result;
        my @arr_mid;
        my $name = `hostname`;
        chomp($name);
        $data{'名称'} = $name;
        my $ip = $nodeIp;
        $data{'IP'}              = $ip;
        $data{'agentIP'}         = $ip;
        $data{'部署于'}       = $ip;
        $data{'中间件类型'} = 'Httpd';
        $data{'安装路径'}    = $inst_path;
        $data{'bin路径'}       = $bin_path;
        $data{'conf路径'}      = $conf_path;

        chdir($bin_path);
        my $os_name = `uname`;
        chomp($os_name);
        my $ver;
        if ( $os_name eq 'AIX' ) {
            $ver = `./apachectl -v|grep version|awk '{print \$3}'`;
        }
        else {
            $ver = `./httpd -v|grep version|awk '{print \$3}'`;
        }
        chomp($ver);
        $data{'版本'} = $ver;

        chdir($conf_path);
        my $cmd       = "cat httpd.conf|grep ^Listen";
        my @arr_port  = `$cmd`;
        my @instances = ();
        foreach (@arr_port) {
            my %apache = ();
            my @tmp    = split /\s+/;
            my $port   = $tmp[1];
            $apache{'代理端口'} = $port;
            push @instances, \%apache;
        }
        $data{'服务配置'} = \@instances;
        push( @collect_data, \%data );
    }
    return @collect_data;
}

1;
