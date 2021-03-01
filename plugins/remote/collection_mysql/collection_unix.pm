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
use Data::Dumper;

sub get_binpath {
    my $return          = system('which mysql > /dev/null 2>&1');
    my $child_exit_code = $return >> 8;
    my $abs_path;
    if ( $child_exit_code != 0 ) {
        my $path_info = `cat /etc/profile|grep mysql`;
        my $bin_path  = ( split /:/, $path_info )[-1];
        chomp($bin_path);
        $abs_path = $bin_path . 'mysql';
    }
    else {
        $abs_path = 'mysql';
    }
    return $abs_path;
}

sub queryCmd {
    my ( $mysqlProcess, $user, $user_pwd ) = @_;
    my $mysql_path = get_binpath();
    my $cmd;
    my $sock;
    if ( $mysqlProcess =~ /--socket=(\S+)/ ) {
        $sock = $1;
        $cmd  = "$mysql_path -hlocalhost -u$user -p$user_pwd --socket=$sock";
    }
    else {
        $cmd = "$mysql_path -hlocalhost -u$user -p$user_pwd";
    }
    return $cmd;
}

sub get_user {
    my ($queryCmd) = @_;
    my @users;
    my @output_user = `$queryCmd -e "select distinct user from mysql.user where user not in ('mysql.session','mysql.sys')"`;
    splice @output_user, 0, 1;
    chomp(@output_user);

    my @output_host = `$queryCmd -e "select concat(user,'\@','',host,'') from mysql.user where user not in ('mysql.session','mysql.sys')"`;
    @output_host = grep { $_ !~ /Logging/ } @output_host;
    splice @output_host, 0, 1;
    chomp(@output_host);

    foreach my $user (@output_user) {
        if ( defined $user and $user ne '' ) {
            my %user_ins  = ();
            my @tab_space = grep { $_ =~ /\Q$user\E/ } @output_host;
            my $ts        = join( ',', @tab_space );
            $user_ins{'用户'}      = $user;
            $user_ins{'缺省数据表空间'} = $ts;
            push @users, \%user_ins;
        }
    }
    return @users;
}

sub collect {
    my ( $nodeIp, $user, $password ) = @_;
    my %data = ();

    my $mysqlProcess = `ps -ef|grep -P "\/mysqld\\s"|grep -v grep |grep -v collection_mysql |head -n 1`;
    if ( !$mysqlProcess ) {
        print "not find mysql .\n";
        exit 0;
    }

    my $queryCmd = queryCmd( $mysqlProcess, $user, $password );

    my $is_connect = `$queryCmd -e "show databases"`;
    if ( !defined $is_connect or $is_connect eq '' ) {
        print "connect failed using $user\n";
        exit 1;
    }

    $data{'DB类型'} = 'MySQL';
    my $ip = $nodeIp;
    $data{'服务IP'}    = $ip;
    $data{'agentIP'} = $nodeIp;

    my @arr_ins      = ();
    my %ins          = ();
    my $slave_status = `$queryCmd -e "show slave status\\G" |grep -w Slave_IO_Running |awk -F ":" {'print \$2'}`;
    my @binlog_dump  = `$queryCmd -e "select substring_index(host,':',1) from information_schema.processlist where COMMAND='Binlog Dump'"`;
    @binlog_dump = grep { $_ !~ /Logging\s+to/ } @binlog_dump;

    if ( $slave_status =~ /yes/i && @binlog_dump != 0 ) {
        $data{'架构类型'} = '主主';
        $ins{'主备角色'}  = '主库';
    }
    elsif ( $slave_status =~ /yes/i && @binlog_dump == 0 ) {
        $data{'架构类型'} = '主从';
        $ins{'主备角色'}  = '备库';
    }
    elsif ( $slave_status !~ /yes/i && @binlog_dump != 0 ) {
        $data{'架构类型'} = '主从';
        $ins{'主备角色'}  = '主库';
    }
    elsif ( $slave_status !~ /yes/i && @binlog_dump == 0 ) {
        $data{'架构类型'} = '单实例';
        $ins{'主备角色'}  = '单实例';
    }

    my @output_dbname = `$queryCmd -e "show databases"`;

    chomp(@output_dbname);
    @output_dbname = grep { $_ !~ /Logging/ } @output_dbname;
    @output_dbname = grep { $_ ne 'information_schema' } @output_dbname;
    @output_dbname = grep { $_ ne 'Database' } @output_dbname;
    @output_dbname = grep { $_ ne 'mysql' } @output_dbname;
    @output_dbname = grep { $_ ne 'sys' } @output_dbname;
    @output_dbname = grep { $_ ne 'performance_schema' } @output_dbname;

    my $dbnames = join( ',', @output_dbname );

    #$ins{'库名称'}     = $dbnames;
    $data{'包含服务名'}  = \@output_dbname;
    $ins{'IP'}      = $ip;
    $ins{'安装于操作系统'} = $ip;
    my @output_port = `$queryCmd -e "show variables like 'port'"`;
    foreach (@output_port) {
        if (/port/) {
            my @tmp = split /\s+/, $_;
            $ins{'端口'}    = $tmp[1];
            $data{'服务端口'} = $tmp[1];
            $data{'DBID'} = $tmp[1];
        }
    }

    $ins{'实例名'} = $ip . ':' . $ins{'端口'};

    my $slave_ip;
    chomp(@binlog_dump);
    if ( @binlog_dump != 0 ) {
        if ( $binlog_dump[-1] =~ /\d+\.\d+\.\d+\.\d+/ ) {
            $slave_ip = $&;
            $data{'备库'} = $slave_ip . ':' . $ins{'端口'};
        }
        else {
            my $match = `grep $binlog_dump[-1] /etc/hosts`;
            if ($match) {
                $match =~ /\d+\.\d+\.\d+\.\d+/;
                $slave_ip = $&;
                $data{'备库'} = $slave_ip . ':' . $ins{'端口'};
            }
        }
    }

    my @output_charset = `$queryCmd -e "show variables like '%character%'"`;
    foreach (@output_charset) {
        if (/character_set_system/) {
            my @tmp = split /\s+/, $_;
            $ins{'字符集'} = $tmp[1];
        }
    }

    my @output_ver = `$queryCmd -e "select version()"`;
    chomp( $output_ver[-1] );
    $ins{'数据库版本'} = $output_ver[-1];

    my $output_kpa = `ps -ef|grep keepalived|grep -v grep`;
    if ( defined $output_kpa and $output_kpa ne '' ) {
        $ins{'是否安装keepalived'} = '是';
        my $output_vip = `cat /etc/keepalived/keepalived.conf`;
        if ( $output_vip =~ /virtual_ipaddress\s+\{\s+(\d+\.\d+\.\d+\.\d+)/i ) {
            $ins{'vip'} = $1;
        }
    }
    else {
        $ins{'是否安装keepalived'} = '否';
    }

    my @output_instdir = `$queryCmd -e "show variables like 'basedir'"`;
    foreach (@output_instdir) {
        if (/basedir/) {
            my @tmp = split /\s+/, $_;
            $ins{'安装目录'} = $tmp[1] || "";
        }
    }

    my @output_datadir = `$queryCmd -e "show variables like '%datadir%'"`;
    foreach (@output_datadir) {
        if (/datadir/) {
            my @tmp = split /\s+/, $_;
            $ins{'数据目录'} = $tmp[1] || "";
        }
    }

    my @output_logdir = `$queryCmd -e "show variables like 'log_bin_basename'"`;
    foreach (@output_logdir) {
        if (/log_bin_basename/) {
            my @tmp = split /\s+/, $_;
            $ins{'binlog目录'} = $tmp[1] || "";
        }
    }

    my @output_errlogdir = `$queryCmd -e "show variables like 'log_error'"`;
    foreach (@output_errlogdir) {
        if (/log_error/) {
            my @tmp = split /\s+/, $_;
            $ins{'错误日志目录'} = $tmp[1] || "";
        }
    }

    push @arr_ins, \%ins;
    $data{'数据库实例'} = \@arr_ins;

    my @user = get_user($queryCmd);
    $data{'包含用户'} = \@user;

    return \%data;
}

1;
