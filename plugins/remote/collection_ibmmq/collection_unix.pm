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

    my $first_test = `ps -ef|grep lsr|grep -v grep`;
    if ( !$first_test ) {
        print "not find IBMmq process .\n";
        return @collect_data;
        exit 0;
    }

    system('su - mqm -c "echo  "');
    if ( $? != 0 ) {
        print "not find IBMmq process .\n";
        return @collect_data;
        exit 0;
    }

    my $hostname = `hostname`;
    chomp($hostname);
    $data{'名称'}      = $hostname;
    $data{'IP'}      = $nodeIp;
    $data{'agentIP'} = $nodeIp;

    my $ver = `su - mqm -c dspmqver|grep Version|awk '{print \$2}'`;
    chomp($ver);
    $data{'版本'}   = $ver;
    $data{'安装路径'} = '/opt/mqm/';
    $data{'部署于'}  = $nodeIp;

    my @instances;
    my $mangername;
    my $output = `su - mqm -c 'dspmq'`;
    my @names  = $output =~ /(?<=QMNAME\()(\S+)\)/g;
    if ( @names == 0 ) {
        print "does't has queen manager\n";
        exit 1;
    }
    else {
        foreach my $name (@names) {
            my %ins = ();
            $ins{'队列管理器名称'} = $name;

            $ins{'IP'} = $nodeIp;
            my $port_info = `ps -ef|grep $name|grep -v grep`;
            my $port;
            if ( $port_info =~ /(?<=-p\s)(\d+)/ ) {
                $port = $1;
            }
            $ins{'端口'}         = $port;
            $ins{'uniqueName'} = $nodeIp . $port;

            my $sid_info = `su - mqm -c "echo 'dis qmgr ccsid'|runmqsc $name"`;
            my $sid;
            if ( $sid_info =~ /(?<=CCSID\()(\S+)(?=\))/ ) {
                $sid = $1;
            }
            $ins{'ccsid'} = $sid;

            my @arr_queen  = ();
            my @queen_info = `su - mqm -c "echo 'dis q(*)'|runmqsc $name"`;
            foreach (@queen_info) {
                if (/QUEUE\((\S+)\)\s+TYPE\((\S+)\)/) {
                    my %queen = ();
                    $queen{'队列名称'} = $1;
                    $queen{'队列类型'} = $2;
                    push @arr_queen, \%queen;
                }
            }

            my @arr_channel  = ();
            my @channel_info = `su - mqm -c "echo 'dis chl(*)'|runmqsc $name"`;
            foreach (@channel_info) {
                if (/CHANNEL\((\S+)\)\s+CHLTYPE\((\S+)\)/) {
                    my %channel = ();
                    $channel{'通道名称'} = $1;
                    $channel{'通道类型'} = $2;
                    push @arr_channel, \%channel;
                }
            }
            $ins{'包含MQ队列'} = \@arr_queen;
            $ins{'包含MQ通道'} = \@arr_channel;
            push @instances, \%ins;
        }
    }
    $data{'服务配置'} = \@instances;
    push(@collect_data , \%data);

    return @collect_data;
}

1;
