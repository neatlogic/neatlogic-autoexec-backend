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

sub collect {
    my ( $nodeIp, $installUser ) = @_;
    my %data = ();

    my $is_informix = `ps -ef|grep informix|grep -v grep |grep -v collection_informix`;
    if ( !defined $is_informix or $is_informix eq '' ) {
        print "not find informix .\n";
        exit 0;
    }

    my @arr_ins;
    my @users        = ();
    my @all_db_names = ();
    my $ip           = $nodeIp;
    $data{'DB类型'}    = 'Informix';
    $data{'agentIP'} = $nodeIp;
    $data{'服务IP'}    = $ip;

    my $informix_dir = `su - $installUser -c env|grep -i informixdir=|cut -d = -f 2`;
    chomp($informix_dir);

    my @ins_info = `cat $informix_dir/etc/sqlhosts|grep ^[^#]`;

    foreach my $instance (@ins_info) {
        my @splits   = split /\s+/, $instance;
        my $ins_name = $splits[0];
        chomp($ins_name);
        my $ins_port = $splits[-1];
        chomp($ins_port);

        if ( $ins_port !~ /^\d{4,6}$/ ) {
            my $services = `cat /etc/services|grep $ins_port`;
            if ( $services =~ /\d{4,6}/ ) {
                $ins_port = $&;
            }
        }
        my %ins = ();
        $ins{'IP'}   = $nodeIp;
        $ins{'服务端口'}   = $ins_port;
        $ins{'服务名称'} = $ins_name;

        my @ver_info     = `su - $installUser -c "onstat -|grep Informix"`;
        my $tmp_ver_info = $ver_info[-1];
        my @ver_split    = split /--/, $tmp_ver_info;
        my $ver          = $ver_split[0];

        $ins{'数据库版本'} = $ver;
        $data{'DBID'} = $ver;

        my $db_name_info = `su - $installUser -c "echo 'select * from sysdatabases'|dbaccess -e sysmaster\@$ins_name"`;

        my @db_names = ( $db_name_info =~ /(?<=name)\s+\S+/g );
        foreach (@db_names) {
            $_ =~ s/^\s+|\s+$//g;
        }

        my $str_name = join( ',', @db_names );

        $ins{'库名'}      = $str_name;
        $ins{'安装于操作系统'} = $nodeIp;
        push @arr_ins, \%ins;

        push @all_db_names, @db_names;
        foreach my $db_name (@db_names) {
            my $user_info = `su - $installUser -c "echo 'select * from sysusers'|dbaccess $db_name\@$ins_name "`;
            my @arr_user  = ( $user_info =~ /(?<=username)\s+\S+/g );
            s/^\s+|\s+$//g foreach (@arr_user);
            foreach (@arr_user) {
                push @users, $_;
            }
        }

    }
    $data{'数据库实例'} = \@arr_ins;
    $data{'包含用户'}  = \@users;
    $data{'包含服务名'} = \@all_db_names;

    return \%data;
}

1;
