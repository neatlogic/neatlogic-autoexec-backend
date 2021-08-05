#!/usr/bin/perl

package jetty_unix;

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
    my ($nodeIp) = @_;
    my @collect_data = ();

    my $pro_jetty = `ps -ef | grep Djetty.home|grep -v grep`;
    if ( !$pro_jetty ) {
        print "not find jetty process.\n";
        return @collect_data;
        exit(0);
    }
    
    my @arr_inst_path = $pro_jetty =~ /(?<=-Djetty\.home=)(\S+)(?=\s)/g;
    if ( @arr_inst_path != 0 ) {
        foreach my $inst_path (@arr_inst_path) {
            my %data = ();
            $data{'安装路径'} = $inst_path;
            chdir($inst_path);
            system('java -jar start.jar --version');

            if ( $? == 0 ) {
                my $ver = `java -jar start.jar --version|&  awk '{print \$2}'`;
                if ( $ver !~ /server/i ) {
                    chomp($ver);
                    $data{'版本'} = $ver;
                }
            }
            my $name = `hostname`;
            chomp($name);
            $data{'agentIP'}         = $nodeIp;
            $data{'名称'}          = $name;
            $data{'中间件类型'} = 'jetty';
            $data{'IP'}              = $nodeIp;
            $data{'部署于'}       = $nodeIp;

            my $port;
            my $config_path = $inst_path . '/etc/jetty.xml';
            my $line        = `cat $config_path|grep jetty.port`;
            if ( $line =~ /"(\d+)"/ ) {
                $port = $1;
            }
            $data{'端口'} = $port;
            push( @collect_data, \%data );
        }
    }
    return @collect_data;
}

1;
