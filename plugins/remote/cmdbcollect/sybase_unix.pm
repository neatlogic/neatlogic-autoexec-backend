#!/usr/bin/perl

package sybase_unix;

use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use warnings;
use utf8;
use File::Basename;
use Encode;
use Utils;

sub isqlRun {
    my ( $cmd, $user ) = @_;
    my $PATH = $ENV{'PATH'};
    if ( not defined($user) or $user eq '' ) {
        $user = 'sybase';
    }
    my $runPath = qq(export $PATH);
    my $execute = "su - $user -c '$runPath;isql -Usa -P -w 120' << EOF
$cmd
exit; 
EOF";
    my $result = `$execute`;
    return $result;
}

sub localRun {
    my ( $cmd, $user ) = @_;
    if ( not defined($user) or $user eq '' ) {
        $user = 'sybase';
    }
    my $PATH    = $ENV{'PATH'};
    my $runPath = qq(export $PATH);
    my $result  = `su - $user -c '$runPath;$cmd'`;
    return $result;
}

sub collect {
    my ($nodeIp) = @_;
    my @collect_data = ();

    my $is_sybase = `ps -ef|grep /sybase/|grep -v grep`;

    if ( !defined $is_sybase or $is_sybase eq '' ) {
        print "not find sybase process";
        return @collect_data;
        exit 0;
    }

    my %data = ();
    $data{'服务IP'} = $nodeIp;
    $data{'agentIP'}  = $nodeIp;

    my @arr_ins;
    my $sybase_dir = localRun('env|grep SYBASE=|cut -d = -f 2');
    chomp($sybase_dir);

    my $text = `cat $sybase_dir/interfaces`;
    my %hash = $text =~ /(\S+)\s+master.*(\d{4,5})\s+/g;
    if (%hash) {
        foreach my $key ( keys %hash ) {
            my %ins      = ();
            my $ser_name = $key;
            my $port     = $hash{$key};

            $ins{'IP'}                    = $nodeIp;
            $ins{'安装于操作系统'} = $nodeIp;
            $ins{'端口'}                = $port;
            $ins{'服务名称'}          = $ser_name;
            my $ver;
            my $ver_info = localRun("isql -v");
            if ( $ver_info =~ /Utility\/(\S+)\// ) {
                $ver = $1;
            }
            my $query = q(
                sp_helpdb
                go
            );
            my $name_info = isqlRun($query);
            my @arr_names = $name_info =~ /\s(\S+)\s+\d+\.\d\sMB/g;

            my $str_name = join( ',', @arr_names );

            $ins{'库名'} = $str_name;

            my $ver_output = localRun("dataserver -v");
            if ( $ver_output =~ /Enterprise\/(\d+\.\d+)\/EBF/ ) {
                $ver = $1;
            }
            $ins{'数据库版本'} = $ver;
            $data{'DBID'}           = $ver;
            push @arr_ins, \%ins;
        }
    }

    my @arr_user;
    my $user_query = q(
        sp_helpuser
        go
    );
    my $user_info = isqlRun($user_query);
    my @users     = $user_info =~ /\s(\w+)\s+\d+/g;

    $data{'数据库实例'} = \@arr_ins;
    $data{'包含用户'}    = \@users;

    push @collect_data, \%data;
    return @collect_data;
}

1;
