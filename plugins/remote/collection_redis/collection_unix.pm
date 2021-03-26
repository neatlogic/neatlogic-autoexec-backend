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

sub dbRun {
    my ( $bin, $port, $auth, $cmd ) = @_;
    my $execute = "$bin -h 127.0.0.1 -p $port -a $auth << EOF
$cmd
exit 
EOF";
    my $result = `$execute`;
    return handleResult($result);
}

sub handleResult {
    my ($result)   = @_;
    my @result_arr = split /\n/, $result;
    my %result     = ();
    foreach my $line (@result_arr) {
        if ( $line !~ /^#/ig and $line !~ /^Warning: Using a password/ig ) {
            my @tmp_arr = Utils::str_split( $line, ':' );
            if ( defined( @tmp_arr[1] ) ) {
                my $key   = @tmp_arr[0];
                my $value = @tmp_arr[1];
                $value =~ s/[\n\r]*//g;
                $result{$key} = $value;
            }
        }
    }
    return %result;
}

sub collect {
    my ( $nodeIp, $auth ) = @_;
    my @collect_data = ();
    my $redis_pro    = `ps -ef |grep redis-server |grep -v grep`;
    if ( !defined $redis_pro or $redis_pro eq '' ) {
        print "not find redis process.\n";
        return @collect_data;
        exit 0;
    }
    else {
        my @redis = Utils::str_split( $redis_pro, '\n' );
        my $cli   = `which redis-cli`;
        my $cli_bin;
        if ( $cli !~ /\/usr\/bin\/which/ ) {
            chomp($cli);
            $cli_bin = $cli;
        }
        foreach my $line (@redis) {
            my %data      = ();
            my @arr       = split /\s+/, $line;
            my $pid       = $arr[1];
            my @info      = Utils::str_split( $arr[-2], ':' );
            my $port      = @info[1];
            my $host_name = `hostname`;
            chomp($host_name);
            $data{'名称'} = $host_name;

            my $ip = $nodeIp;
            $data{'IP'}      = $ip;
            $data{'agentIP'} = $ip;
            $data{'部署于'}     = $ip;
            $data{'数据库类型'}   = 'redis';
            if ( not defined($cli_bin) and $cli_bin eq '' ) {
                my $abs_path = `ls -al /proc/$pid/exe|awk '{print \$NF}'`;
                $cli_bin = dirname($abs_path) . "/" . 'redis-cli';
            }
            my %info_data = dbRun( $cli_bin, $port, $auth, 'info' );

            $data{'数据库版本'}  = $info_data{'redis_version'};
            $data{'端口'}     = $info_data{'tcp_port'};
            $data{'安装目录'}   = dirname( $info_data{'executable'} );
            $data{'配置文件目录'} = $info_data{'config_file'};

            my $logfile = $info_data{'logfile'};
            if(not defined($logfile)){
                $logfile = '';
            }
            $data{'日志文件目录'} = $logfile;
            $data{'事件处理机制'} = $info_data{'multiplexing_api'};
            $data{'runid'}  = $info_data{'run_id'};

            $data{'架构类型'} = '单实例';
            my $redis_mode = $info_data{'redis_mode'};
            if ( $redis_mode eq 'cluster' ) {
                $data{'架构类型'} = '主从';
                my $role = $info_data{'role'};
                if ( $role eq 'slave' ) {
                    my $master_host = $info_data{'master_host'};
                    my $master_port = $info_data{'master_port'};
                    $data{'主库'} = $master_host . ":" . $master_port;
                }
                else {
                    my $cns       = int( $info_data{'connected_slaves'} );
                    my @slave_arr = ();
                    for ( $a = 0 ; $a < $cns ; $a = $a + 1 ) {
                        my $slave = $info_data{ 'slave' . $a };
                        $slave =~ s/'slave'$a//g;
                        my @slave_tmp = Utils::str_split( $slave, ',' );
                        my $slave_host;
                        my $slave_port;
                        foreach my $st (@slave_tmp) {
                            if ( $st =~ /ip/ig ) {
                                my @st_tmp = Utils::str_split( $st, '=' );
                                $slave_host = @st_tmp[1];
                            }
                            if ( $st =~ /port/ig ) {
                                my @st_tmp = Utils::str_split( $st, '=' );
                                $slave_port = @st_tmp[1];
                            }
                        }
                        push( @slave_arr, $slave_host . ":" . $slave_port );
                    }
                    $data{'备库'} = \@slave_arr;
                }
            }
            push( @collect_data, \%data );
        }
    }
    return @collect_data;
}

1;
