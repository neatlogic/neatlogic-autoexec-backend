#!/usr/bin/perl

package mongodb_unix;

use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use warnings;
use utf8;
use File::Basename;
use Encode;
use Utils;
use JSON;

sub dbRun {
    my ( $bin, $port, $user, $password, $cmd ) = @_;
    my $execute = "$bin 127.0.0.1:$port/ -u $user -p $password << EOF
$cmd
exit; 
EOF";
    my $result = `$execute`;
    return handleResult($result);
}

sub handleResult {
    my ($result) = @_;
    $result =~ s/^\s+|\s+$//g;
    my @result_arr = split /\n/, $result;
    my @newResult = ();
    foreach my $line (@result_arr) {
        if ( $line !~ /^MongoDB shell/ig and $line !~ /^connecting to/ig and $line !~ /^Implicit session/ig and $line !~ /^MongoDB server/ig and $line !~ /^switched to db/ig ) {
            push( @newResult, $line );
        }
    }
    return @newResult;
}

sub collect {
    my ( $nodeIp, $user, $password ) = @_;
    my @collect_data = ();

    my @is_mongodb = `ps -ef |grep mongodb |grep -v grep |grep -v $$`;
    chomp(@is_mongodb);

    if ( @is_mongodb == 0 ) {
        print "no find mongodb process\n";
        return @collect_data;
        exit 0;
    }

    foreach my $info (@is_mongodb) {
        my %data = ();
        my $conf_path;
        my $install_base;
        my $bin;
        my @info_arr = split /\s+/, $info;
        if ( $info =~ /--config/ ) {
            $conf_path = $info_arr[-1];
            chomp($conf_path);
            $install_base = dirname($conf_path);
            $bin          = $install_base . "/bin/mongo";
        }
        else {
            my $pid    = $info_arr[1];
            my $runbin = `ls -al /proc/$pid/exe|awk '{print \$NF}'`;
            $bin          = dirname($runbin) . "/mongo";
            $install_base = dirname( dirname($runbin) );
            $conf_path    = $install_base . "/" . "mongodb.conf";
        }

        my $host_name = `hostname`;
        chomp($host_name);
        $data{'名称'} = $host_name;

        my $ip = $nodeIp;
        $data{'服务IP'}        = $ip;
        $data{'agentIP'}         = $ip;
        $data{'数据库类型'} = 'mongodb';

        my $port;
        my $dbpath;
        my $logpath;
        my $auth;
        if ( -e $conf_path ) {
            open( FILE, "< $conf_path " ) or die "can not open file: $!";
            while ( my $read_line = <FILE> ) {
                if ( $read_line and $read_line =~ /port=(\S+)\s+/ ) {
                    $port = $1;
                    $port =~ /(\d+)/;
                }
                if ( $read_line and $read_line =~ /dbpath=(\S+)\s+/ ) {
                    $dbpath = $1;
                }
                if ( $read_line and $read_line =~ /logpath=(\S+)\s+/ ) {
                    $logpath = $1;
                    $logpath = dirname($logpath);
                }
                if ( $read_line and $read_line =~ /auth=(\S+)\s+/ ) {
                    $auth = $1;
                }
            }
            close(FILE);
        }

        my $version = `$bin --version`;
        $version =~ /\"version\": (\S+)\s+/;
        $version = $1;
        $version =~ s/,//g;
        $version =~ s/"//g;
        $data{'服务端口'}    = $port;
        $data{'DBID'}            = $port;
        $data{'数据库版本'} = $version;
        $data{'安装目录'}    = $install_base;
        $data{'数据目录'}    = $dbpath;
        $data{'日志目录'}    = $logpath;

        my %ins = ();
        $ins{'IP'}           = $nodeIp;
        $ins{'端口'}       = $port;
        $ins{'日志目录'} = $logpath;

        #BSON只支持UTF-8
        $ins{'字符集'}             = 'UTF-8';
        $ins{'安装于操作系统'} = $nodeIp;

        my @ins_arr = ();
        push @ins_arr, \%ins;
        $data{'数据库实例'} = \@ins_arr;

        my $servernameQuery = q(
            use admin;
            show dbs ;
        );
        my @servername_arr = dbRun( $bin, $port, $user, $password, $servernameQuery );
        my @newServername_arr = ();
        foreach my $line (@servername_arr) {
            if ( $line =~ /Error: Authenticatio/ ) {
                print("user or password error ,login mongo db failed .\n");
                return @collect_data;
                exit(1);
            }
            else {
                my @tmp_arr = Utils::str_split( $line, '\s+' );
                push( @newServername_arr, $tmp_arr[0] );
            }
        }
        $data{'包含服务名'} = \@newServername_arr;

        my $usersQuery = q(
            use admin ;
            db.system.users.find({},{"user":1 , "db" :2}) ;
        );
        my @users_arr = dbRun( $bin, $port, $user, $password, $usersQuery );
        my @newUsers_arr = ();
        foreach my $line (@users_arr) {
            my $tmp = decode_json($line);
            push( @newUsers_arr, $tmp->{'user'} );
        }
        $data{'包含用户'} = \@newUsers_arr;

        push( @collect_data, \%data );
    }

    return @collect_data;
}

1;
