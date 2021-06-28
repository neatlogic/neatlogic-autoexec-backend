#!/usr/bin/perl

package oracle_unix;

use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use warnings;
use utf8;
use File::Basename;
use Encode;
use Utils;

sub sqlplusRun {
    my ( $oracle_home, $sid, $cmd, $user ) = @_;
    my $ORACLE_HOME = $oracle_home;
    my $PATH        = $ENV{'PATH'};
    if ( not defined($user) or $user eq '' ) {
        $user = 'oracle';
    }
    my $runPath = qq(export ORACLE_HOME=$ORACLE_HOME;export ORACLE_SID=$sid;export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH);
    my $execute = "su - $user -c '$runPath;sqlplus -s / as sysdba' << EOF
$cmd
exit; 
EOF";
    my $result = `$execute`;
    return $result;
}

sub localRun {
    my ( $oracle_home, $sid, $cmd, $user ) = @_;
    if ( not defined($user) or $user eq '' ) {
        $user = 'oracle';
    }
    my $ORACLE_HOME = $oracle_home;
    my $PATH        = $ENV{'PATH'};
    my $runPath     = qq(export ORACLE_HOME=$ORACLE_HOME;export ORACLE_SID=$sid;export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH);
    my $result      = `su - $user -c '$runPath;$cmd'`;
    return $result;
}

sub get_pubip {
    my ($nodeIp) = @_;
    my $pubip;
    my $hostname = `hostname`;
    chomp($hostname);
    my @hosts_file = `cat /etc/hosts|grep "^[^#]"`;
    foreach (@hosts_file) {
        if (/^(\d+\.\d+\.\d+\.\d+)\s+\Q$hostname\E$/) {
            $pubip = $1;
            last;
        }

    }
    if ( !defined $pubip or $pubip eq '' ) {
        $pubip = $nodeIp;
    }
    return $pubip;
}

sub get_data_tablespace {
    my ( $oracle_home, $sid, $nodeIp, $data ) = @_;

    my @tablespace_arr_data_file;
    my $datafilesQuery = q(
        set linesize 250                                               
        set pagesize 1000                                              
        break on tablespace_name                                       
        column tablespace_name format a25                              
        column file_name format a50                                                                          
        column autoextensible format a10                           
        select tablespace_name tbsname, file_name, round(bytes/1024/1024/1024, 2) , autoextensible  from dba_data_files  order by 1,3 asc;
    );

    my $datafilesResult = sqlplusRun( $oracle_home, $sid, $datafilesQuery );
    $datafilesResult =~ s/^\s+|\s+$//g;
    my @datafiles_arr = split /\n/, $datafilesResult;

    if ( $datafiles_arr[0] =~ /mail/i ) {
        @datafiles_arr = @datafiles_arr[ 2 .. $#datafiles_arr ];
    }
    @datafiles_arr = @datafiles_arr[ 2 .. $#datafiles_arr ];
    @datafiles_arr = grep { $_ !~ /^\s*$|selected|Elapsed/ } @datafiles_arr;

    foreach (@datafiles_arr) {
        my %data_file = ();
        my @tmp = split /\s+/, $_;
        $data_file{'tablespace_name'} = $tmp[0];
        $data_file{'File_Name'}       = $tmp[1];
        $data_file{'大小'}          = $tmp[2];
        $data_file{'Auto_EXT'}        = $tmp[3];
        push @tablespace_arr_data_file, \%data_file;
    }
    $data->{'包含表文件'} = \@tablespace_arr_data_file;
    my $tablespaceQuery = q(
        set linesize 250                                               
        set pagesize 1000
        select distinct tablespace_name from dba_data_files;
    );
    my @tablespace_arr_data_tablespace;
    my $tablespaceResult = sqlplusRun( $oracle_home, $sid, $tablespaceQuery );
    if ( $tablespaceResult =~ /ERROR/ ) {
        print "data_tablespace select error \n";
        return @tablespace_arr_data_tablespace;
    }
    $tablespaceResult =~ s/^\s+|\s+$//g;
    my @tablespace_arr = split /\n/, $tablespaceResult;
    if ( $tablespace_arr[0] =~ /mail/i ) {
        @tablespace_arr = @tablespace_arr[ 2 .. $#tablespace_arr ];
    }
    @tablespace_arr = @tablespace_arr[ 2 .. $#tablespace_arr ];
    @tablespace_arr = grep { $_ !~ /^\s*$|selected|Elapsed/ } @tablespace_arr;

    $data->{'包含表空间'} = \@tablespace_arr;
}

sub get_grid_version_byRac {
    my ( $oracle_home, $sid ) = @_;
    my $gridversionQuery = q(select substr(BANNER,instr(BANNER,'Release',1)+7,11) from v\$version where rownum <=1;);
    my $gridversionResult = sqlplusRun( $oracle_home, $sid, $gridversionQuery );
    $gridversionResult =~ s/^\s+|\s+$//g;
    my @gridversion_arr = split /\n/, $gridversionResult;
    my $grid_ver = $gridversion_arr[-1];
    $grid_ver =~ s/^\s+|\s+$//g;
    return $grid_ver;
}

sub get_grid_version {
    my ( $oracle_home, $sid ) = @_;
    my $bannerQuery = q(select banner from v\$version where rownum <=1;);
    my $bannerResult = sqlplusRun( $oracle_home, $sid, $bannerQuery );
    $bannerResult =~ s/^\s+|\s+$//g;
    my @banner_arr = split /\n/, $bannerResult;
    my $o_ver = $banner_arr[-1];
    $o_ver =~ s/^\s+|\s+$//g;
    return $o_ver;
}

sub get_dbid {
    my ( $oracle_home, $sid ) = @_;
    my $query = q(select dbid from v\$database;);
    my $result = sqlplusRun( $oracle_home, $sid, $query );
    $result =~ s/^\s+|\s+$//g;
    my @arr0 = split /\n/, $result;
    my $dbid = $arr0[-1];
    $dbid =~ s/^\s+|\s+$//g;
    return $dbid;
}

sub get_isRAC {
    my ( $oracle_home, $sid ) = @_;
    my $clusterDatabaseQuery = q(
        set linesize 300 pagesize 999 echo off feedback off heading off underline off;
        select name,value from v\$parameter where name='cluster_database';
    );
    my $clusterDatabaseResult = sqlplusRun( $oracle_home, $sid, $clusterDatabaseQuery );
    my $res;
    if ( $clusterDatabaseResult =~ /TRUE/ ) {
        $res = 'RAC';
    }
    else {
        $res = '单实例';
    }
    return $res;
}

sub get_db_servername {
    my ( $oracle_home, $sid ) = @_;
    my @arr_server_name;
    my $servernameQuery = q(
        set linesize 300 pagesize 999;  
        select value from v\$parameter where NAME='service_names' union select a.name from dba_services a,v\$database b where b.DATABASE_ROLE='PRIMARY' and a.name not like 'SYS%';
    );
    my $servernameResult = sqlplusRun( $oracle_home, $sid, $servernameQuery );
    if ( $servernameResult =~ /ERROR/ ) {
        print "server_name select error\n";
        return @arr_server_name;
    }
    $servernameResult =~ s/^\s+|\s+$//g;
    my @servername_arr = split /\n/, $servernameResult;
    if ( $servername_arr[0] =~ /mail/i ) {
        @servername_arr = @servername_arr[ 2 .. $#servername_arr ];
    }
    @servername_arr = @servername_arr[ 2 .. $#servername_arr ];
    @servername_arr = grep { $_ !~ /^\s*$|selected|Elapsed/ } @servername_arr;
    chomp(@servername_arr);
    foreach my $servername (@servername_arr) {
        if ( $servername =~ /,/ ) {
            my @splits = split /,/, $servername;
            foreach my $item (@splits) {
                $item =~ s/^\s+|\s+$//g;
                push @arr_server_name, $item;
            }
        }
        else {
            $servername =~ s/^\s+|\s+$//g;
            push @arr_server_name, $servername;
        }
    }
    return @arr_server_name;
}

sub get_db_userinfo {
    my ( $oracle_home, $sid ) = @_;
    my $userQuery = q(
        set linesize 300 pagesize 1000   
        col username for a25                               
        col default_tablespace for a20;  
        select  du.username,du.default_tablespace from dba_users du where du.account_status='OPEN' and du.default_tablespace not in('SYSTEM','SYSAUX') order by 1,2;
    );
    my $userResult = sqlplusRun( $oracle_home, $sid, $userQuery );
    my @arr_user_info;
    if ( $userResult =~ /ERROR/ ) {
        print "sql exec error\n";
        return @arr_user_info;
    }
    $userResult =~ s/^\s+|\s+$//g;
    my @user_arr = split /\n/, $userResult;
    if ( $user_arr[0] =~ /mail/i ) {
        @user_arr = @user_arr[ 2 .. $#user_arr ];
    }
    @user_arr = @user_arr[ 2 .. $#user_arr ];
    @user_arr = grep { $_ !~ /^\s*$|selected|Elapsed/ } @user_arr;
    foreach (@user_arr) {
        my @tmp = split /\s+/, $_;
        my %user_info = ();
        $user_info{'用户'}                = $tmp[0];
        $user_info{'缺省数据表空间'} = $tmp[1];
        push @arr_user_info, \%user_info;
    }
    return @arr_user_info;
}

sub get_diskgroup {
    my ( $oracle_home, $sid, $nodeIp, $data ) = @_;

    my $diskgroupQuery = q(
        set linesize 500;                                                                                                       
        col name for a15;                                                                                                       
        col total_mb for 9999999999;                                                                                            
        col type for a15                                                                                                        
        select name , type ,total_mb from v\$asm_diskgroup;
    );
    my $diskgroupResult = sqlplusRun( $oracle_home, $sid, $diskgroupQuery );

    my @arr_diskgroup;
    if ( $diskgroupResult =~ /ERROR/ ) {
        print "select diskgroup error \n";
        return @arr_diskgroup;
    }
    $diskgroupResult =~ s/^\s+|\s+$//g;
    my @diskgroup_arr = split /\n/, $diskgroupResult;

    if ( $diskgroup_arr[0] =~ /mail/i ) {
        @diskgroup_arr = @diskgroup_arr[ 2 .. $#diskgroup_arr ];
    }
    @diskgroup_arr = @diskgroup_arr[ 2 .. $#diskgroup_arr ];
    @diskgroup_arr = grep { $_ !~ /^\s*$|selected|Elapsed/ } @diskgroup_arr;

    foreach (@diskgroup_arr) {
        my @tmp = split /\s+/, $_;
        my %diskgroup = ();

        $diskgroup{'DiskGroup_Name'} = $tmp[0];
        $diskgroup{'Diskgroup_Type'} = $tmp[1];
        $diskgroup{'Total_Mb'}       = $tmp[2];
        push @arr_diskgroup, \%diskgroup;
    }
    $data->{'asm_diskgroup'} = \@arr_diskgroup;

    my $asmdiskQuery = q(
        set linesize 200;     
        set pagesize 1000;                                                                                                          
        column failgroup format a15;                                                                                                
        col NAME format a50;                                                                                                        
        column path format a50;                                                                                                     
        select ad.name, adk.name , ad.failgroup , ad.total_mb, ad.path from v\$asm_disk ad,v\$asm_diskgroup adk where ad.GROUP_NUMBER=adk.GROUP_NUMBER order by path;
    );
    my $asmdiskResult = sqlplusRun( $oracle_home, $sid, $asmdiskQuery );
    $asmdiskResult =~ s/^\s+|\s+$//g;
    my @asmdisk_arr = split /\n/, $asmdiskResult;

    if ( $asmdisk_arr[0] =~ /mail/i ) {
        @asmdisk_arr = @asmdisk_arr[ 2 .. $#asmdisk_arr ];
    }
    @asmdisk_arr = @asmdisk_arr[ 2 .. $#asmdisk_arr ];
    @asmdisk_arr = grep { $_ !~ /^\s*$|selected|Elapsed/ } @asmdisk_arr;

    my @arr_asm_disk;
    foreach (@asmdisk_arr) {
        my @tmp = split /\s+/, $_;
        my %asm_disk = ();
        $asm_disk{'名称'}         = $tmp[0];
        $asm_disk{'Diskgroup_Name'} = $tmp[1];
        $asm_disk{'Fail_Group'}     = $tmp[2];
        $asm_disk{'Total_Mb'}       = $tmp[3];
        $asm_disk{'路径'}         = $tmp[4];

        my $disk_path = $tmp[4];
        my $dir;
        eval { $dir = dirname($disk_path) };
        if ( !$@ ) {
            my $basename = basename($disk_path);
            chdir($dir);
            my $output = `ls -al|grep $basename`;

            my $id;
            if ( $output =~ /\d+,\s+\d+/ ) {
                $id = $&;
            }
            chdir('/dev');
            my @all_output = `ls -al`;

            my $logic_disk;
            foreach my $line (@all_output) {
                chomp($line);
                if ( $line =~ /\Q$id\E/ ) {
                    my @splits = split /\s+/, $line;
                    if ( $splits[-1] ne $basename ) {
                        $logic_disk = $splits[-1];
                        last;
                    }
                }
            }
            my $full_path = '/dev/' . $logic_disk;
            $asm_disk{'逻辑磁盘'} = $nodeIp . ':' . $full_path;
        }
        push @arr_asm_disk, \%asm_disk;
    }
    $data->{'asm_disk'} = \@arr_asm_disk;

}

sub get_ora_base {
    my ( $oracle_home, $sid ) = @_;
    my $ora_base;
    my $cmd = localRun( $oracle_home, $sid, "env|grep -i oracle_base|cut -d = -f 2'|tail -n1" );
    system($cmd);
    if ( $? == 0 ) {
        $ora_base = `$cmd`;
        chomp($ora_base);
    }
    else {
        $ora_base = '';
    }
    return $ora_base;
}

sub get_ora_dblog {
    my ( $oracle_home, $sid, $nodeIp ) = @_;
    my $dblogQuery = q(
        select value from v\$diag_info where name='Diag Trace';
    );
    my $dblogResult = sqlplusRun( $oracle_home, $sid, $dblogQuery );
    $dblogResult =~ s/^\s+|\s+$//g;
    my @dblog_arr = split /\n/, $dblogResult;
    my $dir       = $dblog_arr[-1];
    my $abs_path  = $dir . '/alert*.log';
    my $log       = `ls $abs_path`;
    chomp($log);
    return $log;
}

sub get_db_instance {
    my ( $oracle_home, $sid, $nodeIp, $scan_ip, $data ) = @_;
    my @arr_oracle_ins;
    my %oracle_ins = ();
    $oracle_ins{'scan_ip'} = $scan_ip;
    $oracle_ins{'DBID'} = get_dbid( $oracle_home, $sid );
    my $vip;

    my $hostname = `hostname`;
    chomp($hostname);
    $hostname = $hostname . '-vip';
    $vip      = `grep "^[^#]" /etc/hosts|grep $hostname |awk '{print \$1}'`;
    chomp($vip);
    if ( !defined $vip or $vip eq '' ) {
        $vip = get_pubip($nodeIp);
    }
    $oracle_ins{'Virtual_IP'} = $vip;
    $oracle_ins{'agentIP'}    = $nodeIp;

    my $pubip = get_pubip($nodeIp);
    $oracle_ins{'安装于OS'} = $pubip;

    my $home = $oracle_home;
    $oracle_ins{'ORA_HOME'} = $home;
    $oracle_ins{'端口'}   = $data->{'服务端口'};

    my $dbversionQuery = q(
        select substr(BANNER,instr(BANNER,'Release',1)+7,11) from v\$version where rownum <=1;
    );
    my $dbversionResult = sqlplusRun( $oracle_home, $sid, $dbversionQuery );
    $dbversionResult =~ s/^\s+|\s+$//g;
    my @dbversion_arr = split /\n/, $dbversionResult;
    my $oracle_ver = $dbversion_arr[-1];
    $oracle_ver =~ s/^\s+|\s+$//g;
    $oracle_ins{'数据库版本'} = $oracle_ver;

    my $db_log;
    my $crs_log;
    my $asm_log;

    if ( $oracle_ver =~ /^10\./ ) {
        my $oracle_base = get_ora_base( $oracle_home, $sid );
        if ($oracle_base) {
            my $cmd_dblog = "ls $oracle_base/admin/`echo $sid |sed 's/.\$/*/'`/bdump/alert_$sid.log";
            $db_log = `$cmd_dblog`;

            #$db_log = get_ora_dblog($oracle_home, $sid);
            chomp($db_log);
            $oracle_ins{'数据库日志'} = $db_log;

            if ( $data->{'架构类型'} eq 'RAC' ) {
                my @ora_crs = localRun( $oracle_home, $sid, 'env|grep -i ora_crs_home|cut -d = -f 2' );
                my $ora_crs_home = $ora_crs[-1];
                chomp($ora_crs_home);
                my @tmp = split /\n/, $ora_crs_home;
                $ora_crs_home = $tmp[-1];
                if ( defined $ora_crs_home and $ora_crs_home ne '' ) {
                    my $cmd_crslog = "ls $ora_crs_home/log/`hostname`/alert`hostname`.log";
                    my $crs_log    = `$cmd_crslog`;
                    chomp($crs_log);
                    $oracle_ins{'CRS日志'} = $crs_log;
                }
            }
        }

    }
    elsif ( $oracle_ver =~ /^11\./ ) {

        $db_log = get_ora_dblog( $oracle_home, $sid );
        chomp($db_log);

        $oracle_ins{'数据库日志'} = $db_log;

        if ( $data->{'架构类型'} eq 'RAC' ) {
            my @grid = localRun( $oracle_home, $sid, 'env|grep -i ORACLE_HOME|cut -d = -f 2', 'grid' );
            my $grid_home = $grid[-1];
            chomp($grid_home);

            my $cmd_crslog = "ls $grid_home/log/`hostname`/alert*.log";
            my $crs_log    = `$cmd_crslog`;
            chomp($crs_log);

            $oracle_ins{'CRS日志'} = $crs_log;

            my $exec   = "ps -ef|grep pmon|grep ASM|grep -v grep";
            my $result = `$exec`;
            if ($result) {
                my @grid = localRun( $oracle_home, $sid, 'env|grep -i ORACLE_BASE|cut -d = -f 2', 'grid' );
                my $grid_base = $grid[-1];
                chomp($grid_base);
                my @sid = localRun( $oracle_home, $sid, 'env|grep -i ORACLE_SID|cut -d = -f 2', 'grid' );
                my $grid_sid = $sid[-1];
                chomp($grid_sid);
                my $cmd_asmlog = "ls $grid_base/diag/asm/+asm/$grid_sid/trace/alert*.log";
                my $asm_log    = `$cmd_asmlog`;
                chomp($asm_log);
                $oracle_ins{'ASM日志'} = $asm_log;
            }
        }
        else {
            my $exec   = "ps -ef|grep pmon|grep ASM|grep -v grep";
            my $result = `$exec`;
            if ( defined $result and $result ne '' ) {
                my @grid = localRun( $oracle_home, $sid, 'env|grep -i ORACLE_BASE|cut -d = -f 2', 'grid' );
                my $grid_base = $grid[-1];
                chomp($grid_base);
                my @sid = localRun( $oracle_home, $sid, 'env|grep -i ORACLE_SID|cut -d = -f 2', 'grid' );
                my $grid_sid = $sid[-1];
                chomp($grid_sid);
                my $cmd_asmlog = "ls $grid_base/diag/asm/+asm/$grid_sid/trace/alert*.log";
                my $asm_log    = `$cmd_asmlog`;
                chomp($asm_log);

                $oracle_ins{'ASM日志'} = $asm_log;

                my @home = localRun( $oracle_home, $sid, 'env|grep -i ORACLE_HOME|cut -d = -f 2', 'grid' );
                my $grid_home = $home[-1];
                chomp($grid_home);

                my $cmd_crslog = "ls $grid_home/log/`hostname`/alert*.log";
                my $crs_log    = `$cmd_crslog`;
                chomp($crs_log);
                $oracle_ins{'CRS日志'} = $crs_log;
            }

        }

    }
    elsif ( $oracle_ver =~ /^12\./ ) {

        $db_log = get_ora_dblog( $oracle_home, $sid );
        chomp($db_log);
        $oracle_ins{'数据库日志'} = $db_log;

        if ( $data->{'架构类型'} eq 'RAC' ) {
            my @grid = localRun( $oracle_home, $sid, 'env|grep -i ORACLE_BASE|cut -d = -f 2', 'grid' );
            my $grid_base = $grid[-1];
            chomp($grid_base);

            my $cmd_crslog = "ls $grid_base/diag/crs/`hostname`/crs/trace/alert*.log";
            my $crs_log    = `$cmd_crslog`;
            chomp($crs_log);

            $oracle_ins{'CRS日志'} = $crs_log;

            my $exec   = "ps -ef|grep pmon|grep ASM|grep -v grep";
            my $result = `$exec`;
            if ($result) {

                my @grid = localRun( $oracle_home, $sid, 'env|grep -i ORACLE_SID|cut -d = -f 2', 'grid' );
                my $grid_sid = $grid[-1];
                chomp($grid_sid);
                my $cmd_asmlog = "ls $grid_base/diag/asm/+asm/$grid_sid/trace/alert*.log";
                my $asm_log    = `$cmd_asmlog`;
                chomp($asm_log);

                $oracle_ins{'ASM日志'} = $asm_log;
            }
        }
        else {
            my $exec   = "ps -ef|grep pmon|grep ASM|grep -v grep";
            my $result = `$exec`;
            if ( defined $result and $result ne '' ) {
                my @grid = localRun( $oracle_home, $sid, 'env|grep -i ORACLE_BASE|cut -d = -f 2', 'grid' );
                my $grid_base = $grid[-1];
                chomp($grid_base);
                my @sid = localRun( $oracle_home, $sid, 'env|grep -i ORACLE_SID|cut -d = -f 2', 'grid' );
                my $grid_sid = $sid[-1];
                chomp($grid_sid);
                my $cmd_asmlog = "ls $grid_base/diag/asm/+asm/$grid_sid/trace/alert*.log";
                my $asm_log    = `$cmd_asmlog`;

                chomp($asm_log);
                $oracle_ins{'ASM日志'} = $asm_log;

                my $cmd_crslog = "ls $grid_base/diag/crs/`hostname`/crs/trace/alert*.log";
                my $crs_log    = `$cmd_crslog`;
                chomp($crs_log);
                $oracle_ins{'CRS日志'} = $crs_log;
            }

        }

    }

    my $dbconfigQuery = q(
        set linesize 200;     
        set pagesize 1000;
        col name format a50;
        col value format a100;
        select name ,value from v\$parameter where name in ('instance_name','sga_max_size','log_archive_dest_1','memory_target','service_names')
        union all
        select PARAMETER CHARACTERSET,VALUE from nls_database_parameters where PARAMETER='NLS_CHARACTERSET' order by 1;
    );
    my $dbconfigResult = sqlplusRun( $oracle_home, $sid, $dbconfigQuery );

    if ( $dbconfigResult =~ /ERROR/ ) {
        $dbconfigResult = '';
    }
    $dbconfigResult =~ s/^\s+|\s+$//g;
    my @dbconfigR_arr = split /\n/, $dbconfigResult;
    if ( $dbconfigR_arr[0] =~ /mail/i ) {
        @dbconfigR_arr = @dbconfigR_arr[ 2 .. $#dbconfigR_arr ];
    }
    @dbconfigR_arr = @dbconfigR_arr[ 2 .. $#dbconfigR_arr ];
    @dbconfigR_arr = grep { $_ !~ /^\s*$|selected|Elapsed/ } @dbconfigR_arr;

    my @value;
    foreach (@dbconfigR_arr) {
        my @tmp = split /\s+/, $_;
        if ( !$tmp[1] ) {
            $tmp[1] = '';
        }
        if ( $tmp[0] eq 'log_archive_dest_1' ) {
            my @tmp = split /(?<=log_archive_dest_1)\s+/, $_;
            push @value, $tmp[1];
            next;
        }
        push @value, $tmp[1];
    }
    $oracle_ins{'内存'}        = $value[5];
    $oracle_ins{'memory_target'} = $value[3];
    $oracle_ins{'归档目录'}  = $value[2];
    $oracle_ins{'实例名'}     = $value[1];
    $oracle_ins{'服务名称'}  = $value[4];
    $oracle_ins{'字符集'}     = $value[0];
    if ( $oracle_ver =~ /^10\./ ) {
        my $log_archive_destQuery = q(
            set linesize 200;     
            set pagesize 1000;
            col name format a50;
            col value format a100;
            select name,value from v\$parameter where name='log_archive_dest' 
            union 
            select name,value from v\$parameter where name='log_archive_dest_1';
        );
        my $log_archive_destResult = sqlplusRun( $oracle_home, $sid, $log_archive_destQuery );
        if ( $log_archive_destResult =~ /location=\S+/i ) {
            $oracle_ins{'归档目录'} = $&;
        }
        else {
            $oracle_ins{'归档目录'} = '';
        }
    }

    my $log_openQuery = q(
        set linesize 200;     
        set pagesize 1000;
        select log_mode from v\$database ;
    );
    my $log_openResult = sqlplusRun( $oracle_home, $sid, $log_openQuery );

    if ( $log_openResult =~ /NOARCHIVELOG/i ) {
        $oracle_ins{'归档目录'} = 'NOARCHIVELOG';
        $oracle_ins{'归档模式'} = 'NOARCHIVELOG';
    }
    else {
        $oracle_ins{'归档模式'} = 'ARCHIVELOG';
    }

    push @arr_oracle_ins, \%oracle_ins;

    #return @arr_oracle_ins;
    $data->{'数据库实例'} = \@arr_oracle_ins;
}

sub collect {
    my ($nodeIp)     = @_;
    my @collect_data = ();
    my $is_oracle    = `ps -ef|grep oracle |grep -v $$|grep -v grep`;
    if ( !$is_oracle ) {
        print "not find oracle process . \n";
        return @collect_data;
        exit 0;
    }

    my $os_type = `uname`;
    chomp($os_type);

    my @arr_ins;
    my @or_home;
    if ( $os_type eq 'Linux' ) {
        my @arr_ins_tmp = `ps -ef|grep pmon|grep ora_|grep -v "sh -c"|awk '{print \$8}'`;
        chomp(@arr_ins_tmp);
        my @arr_proc = `ps -ef|grep pmon|grep ora_|grep -v "sh -c"|awk '{print \$2}'`;
        chomp(@arr_proc);

        foreach (@arr_ins_tmp) {
            if (/_(\w+)_(\w+)$/) {
                push @arr_ins, $2;
            }
        }
        foreach my $i (@arr_proc) {
            my $dir = "/proc/$i/environ";
            my $a   = `cat $dir |tr '\\0' '\\n'|grep ORACLE_HOME|cut -d = -f 2`;
            $a =~ s/^\s+|\s+$//g;
            push @or_home, $a;
        }
    }
    else {
        my @arr_ins_tmp = `ps -ef|grep pmon|grep ora_|awk '{print \$NF}'`;
        chomp(@arr_ins_tmp);
        my @arr_proc = `ps -ef|grep pmon|grep ora_|awk '{print \$2}'`;
        chomp(@arr_proc);

        foreach (@arr_ins_tmp) {
            if (/_(\w+)_(\w+)$/) {
                push @arr_ins, $2;
            }
        }
        foreach my $proc (@arr_proc) {
            my $a = `ps ewww $proc|grep ORACLE_HOME`;
            if ( $a =~ /ORACLE_HOME=(\S+)\s+/ ) {
                push @or_home, $1;
            }
        }
    }
    chomp(@arr_ins);
    chomp(@or_home);

    my @relation;
    for ( my $i = 0 ; $i < scalar @arr_ins ; $i++ ) {
        my %data        = ();
        my $oracle_home = $or_home[$i];
        my $sid         = $arr_ins[$i];

        my $dbid = get_dbid( $oracle_home, $sid );
        $data{'DBID'}         = $dbid;
        $data{'DB类型'}     = 'Oracle';
        $data{'架构类型'} = get_isRAC( $oracle_home, $sid );

        my $scan_ip;
        if ( $data{'架构类型'} eq '单实例' ) {
            $scan_ip = $nodeIp;
        }
        else {
            $scan_ip = `grep "^[^#]" /etc/hosts|grep -i SCAN |head -n 2|tail -n1|awk '{print \$1}'`;
            $scan_ip =~ s/^\s+|\s+$//g;
            if ( !defined $scan_ip or $scan_ip eq '' ) {
                $scan_ip = get_pubip($nodeIp);
            }
        }
        $data{'服务IP'} = $scan_ip;
        $data{'agentIP'}  = $nodeIp;
        my $port_info = localRun( $oracle_home, $sid, 'lsnrctl status |grep PORT|head -n1' );
        my $db_port;
        if ( $port_info =~ /PORT=(\d+)/ ) {
            $db_port              = $1;
            $data{'服务端口'} = $db_port;
            $data{'CDB类型'}    = '非CDB';
        }

        my $o_ver = get_grid_version( $oracle_home, $sid );

        my $is_asm = `ps -ef|grep pmon|grep ASM|grep -v grep`;

        if ( $o_ver =~ /10g/ ) {
            $data{'GI版本号'} = '';
        }
        else {
            if ( $data{'架构类型'} eq 'RAC' ) {
                $data{'GI版本号'} = get_grid_version_byRac( $oracle_home, $sid );
            }
            else {
                if ( defined $is_asm and $is_asm ne '' ) {
                    $data{'GI版本号'} = get_grid_version_byRac( $oracle_home, $sid );
                }
            }
        }

        my $grid_home = localRun( $oracle_home, $sid, 'env|grep ORACLE_HOME|cut -d = -f 2', 'grid' );
        chomp($grid_home);
        $data{'GRID_HOME'} = $grid_home;

        my @servernames = get_db_servername( $oracle_home, $sid );
        $data{'包含服务名'} = \@servernames;

        my @users = get_db_userinfo( $oracle_home, $sid );
        $data{'包含用户'} = \@users;

        get_data_tablespace( $oracle_home, $sid, $nodeIp, \%data );

        get_diskgroup( $oracle_home, $sid, $nodeIp, \%data );

        get_db_instance( $oracle_home, $sid, $nodeIp, $scan_ip, \%data );

        push( @collect_data, \%data );
    }
    return @collect_data;
}

1;
