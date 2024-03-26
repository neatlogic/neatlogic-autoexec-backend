use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../plib/lib/perl5";

package StorageHuawei_OceanStor;
use StorageBase;
our @ISA = qw(StorageBase);
use JSON;
use CollectUtils;
use File::Basename;
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;
use Cwd qw(abs_path);

sub new {
    my ( $type, %args ) = @_;
    my $self = {};

    my $node = $args{node};
    $self->{node} = $node;

    my $timeout = $args{timeout};
    if ( not defined($timeout) or $timeout eq '0' ) {
        $timeout = 10;
    }
    $self->{timeout} = $timeout;

    my $utils = CollectUtils->new();
    $self->{collectUtils} = $utils;

    bless( $self, $type );
    return $self;
}

sub collect {
    my $data;

    my ($self) = @_;

    my $nodeInfo = $self->{node};
    my $ip       = $nodeInfo->{host};
    my $port     = $nodeInfo->{protocolPort};
    my $user     = $nodeInfo->{username};
    my $password = $nodeInfo->{password};

    my ( $token, $device_id, $cookie ) = login( $ip, $port, $user, $password );

    $data                    = get_basic_configuration( $ip, $port, $token, $device_id, $cookie );
    $data->{'_OBJ_CATEGORY'} = 'STORAGE';
    $data->{'_OBJ_TYPE'}     = 'Huawei';
    $data->{'VENDOR'}        = 'Huawei';
    my $sn = $data->{'SERIAL_NUMBER'};

    my $ref_storage_luns  = get_data_volume( $ip, $port, $token, $device_id, $cookie );
    my $ref_storage_pools = get_data_pool( $ip, $port, $token, $device_id, $cookie );

    #整合数据
    foreach my $pool (@$ref_storage_pools) {
        my @luns;
        my $name = $pool->{NAME};
        $pool->{'STORAGE_SN'}    = $sn;
        $pool->{'_OBJ_CATEGORY'} = 'STORAGE';
        $pool->{'_OBJ_TYPE'}     = 'STORAGE_POOL';
        foreach my $lun (@$ref_storage_luns) {
            my $pool_name = $lun->{'POOL_NAME'};
            $lun->{'STORAGE_SN'}    = $sn;
            $lun->{'_OBJ_CATEGORY'} = 'STORAGE';
            $lun->{'_OBJ_TYPE'}     = 'STORAGE_LUN';
            if ( $name eq $pool_name ) {
                push @luns, $lun;
            }
        }
        $pool->{'LUNS'} = \@luns;
    }
    $data->{'POOL'} = $ref_storage_pools;
    $data->{'LUNS'} = $ref_storage_luns;

    my $ref_storage_disks = get_data_disk( $ip, $port, $token, $device_id, $cookie );
    $data->{'DISK'} = $ref_storage_disks;

    my $ref_storage_hostlink = get_data_hostlink( $ip, $port, $token, $device_id, $cookie );
    $data->{'HOSTLINK'} = $ref_storage_hostlink;

    my $ref_storage_power = get_data_power( $ip, $port, $token, $device_id, $cookie );
    $data->{'POWER'} = $ref_storage_power;

    my $ref_storage_fan = get_data_fan( $ip, $port, $token, $device_id, $cookie );
    $data->{'FAN'} = $ref_storage_fan;

    my $ref_storage_fcports     = get_data_fcport( $ip, $port, $token, $device_id, $cookie );
    my $ref_storage_controllers = get_data_node( $ip, $port, $token, $device_id, $cookie );

    my @tmp_controller;
    foreach my $controller (@$ref_storage_controllers) {
        $controller->{'STORAGE_SN'}    = $sn;
        $controller->{'_OBJ_CATEGORY'} = 'STORAGE';
        $controller->{'_OBJ_TYPE'}     = 'STORAGE_CONTROLLER';
        push @tmp_controller, $controller;
    }
    $data->{'CONTROLLER'} = \@tmp_controller;

    my @tmp_hba;
    foreach my $port (@$ref_storage_fcports) {
        $port->{'STORAGE_SN'}    = $sn;
        $port->{'_OBJ_CATEGORY'} = 'STORAGE';
        $port->{'_OBJ_TYPE'}     = 'STORAGE_HBA';
        push @tmp_hba, $port;
    }
    $data->{'HBA_INTERFACES'} = \@tmp_hba;

    #整合数据
    #foreach my $controller (@$ref_storage_controllers) {
    #    my @fcports;
    #    my $location = $controller->{LOCATION};
    #    $controller->{'STORAGE_SN'}    = $sn;
    #    $controller->{'_OBJ_CATEGORY'} = 'STORAGE';
    #    $controller->{'_OBJ_TYPE'}     = 'STORAGE_CONTROLLER';
    #    foreach my $port (@$ref_storage_fcports) {
    #        my $fcport_name = $port->{'NAME'};
    #        $port->{'STORAGE_SN'}    = $sn;
    #        $port->{'_OBJ_CATEGORY'} = 'STORAGE';
    #        $port->{'_OBJ_TYPE'}     = 'STORAGE_HBA';
    #        if ( $fcport_name =~ /^$location/ ) {
    #            push @fcports, $port;
    #        }
    #    }
    #    $controller->{'HBA'} = \@fcports;
    #}
    return $data;

}

sub get_data_volume {
    my ( $ip, $port, $token, $device_id, $cookie ) = @_;

    my $config_data = get_data_config( $ip, $port, $token, $device_id, $cookie, "Lun" );
    if ( $config_data eq "" ) {
        $config_data = get_data_config( $ip, $port, $token, $device_id, $cookie, "lun" );
    }

    if ( $config_data eq "" ) { return; }

    my @storage_luns;
    foreach my $element_id ( @{ $config_data->{data} } ) {
        my %storage_lun;
        $storage_lun{'_OBJ_CATEGORY'} = 'STORAGE';
        $storage_lun{'_OBJ_TYPE'}      = 'STORAGE_LUN';

        my $id_element     = $element_id->{ID};
        my $name           = $element_id->{NAME};
        my $cap            = $element_id->{"CAPACITY"};
        my $used_cap       = $element_id->{"ALLOCCAPACITY"};
        my $block_size     = $element_id->{"SECTORSIZE"};
        my $health_status  = $element_id->{"HEALTHSTATUS"};
        my $running_status = $element_id->{"RUNNINGSTATUS"};
        my $pool_name      = $element_id->{"PARENTNAME"};
        my $pool_id        = $element_id->{"PARENTID"};
        my $type           = $element_id->{"SUBTYPE"};
        my $wwn            = $element_id->{WWN};
        my $nguid          = $element_id->{NGUID};
        if ( !defined $id_element || !defined $name ) { next; }
        $storage_lun{'VALUME_ID'} = $id_element;
        $storage_lun{'NAME'}      = $name;

        if ( defined $pool_id && $pool_id ne "" ) {
            $storage_lun{'POOL_ID'} = $pool_id;

        }
        if ( defined $pool_name && $pool_name ne "" ) {
            $storage_lun{'POOL_NAME'} = $pool_name;
        }
        if ( defined $type && $type ne "" ) {
            if ( $type eq "0" ) {
                $type = "common LUN";
            }
            if ( $type eq "1" ) {
                $type = "vVol LUN";
            }
            if ( $type eq "2" ) {
                $type = "PE LUN";
            }
            $storage_lun{'TYPE'} = $type;
        }
        if ( defined $health_status && $health_status ne "" ) {
            $health_status = get_health_status_text($health_status);
            $storage_lun{'HEALTH_STATUS'} = $health_status;
        }
        if ( defined $running_status && $running_status ne "" ) {
            $running_status = get_running_status_text($running_status);
            $storage_lun{'RUNNING_STATUS'} = $running_status;
        }
        if ( defined $wwn && $wwn ne "" ) {
            $storage_lun{'WWN'} = $wwn;
        }
        if ( defined $nguid && $nguid ne "" ) {
            $storage_lun{'NGUID'} = $nguid;
        }
        ## add capacity
        if ( !isdigit($block_size) ) {
            $block_size = 512;    ### default
        }
        if ( isdigit($cap) ) {
            my $pom = ( $cap * $block_size ) / ( 1024 * 1024 * 1024 );
            $cap = round( $pom, 0 );
            $storage_lun{'CAPACITY'} = $cap;
        }
        if ( isdigit($used_cap) ) {
            my $pom = ( $used_cap * $block_size ) / ( 1024 * 1024 * 1024 );
            $used_cap = round( $pom, 0 );
            $storage_lun{'USED_CAPACITY'} = $used_cap;
        }
        if ( isdigit($cap) && isdigit($used_cap) ) {
            if ( $cap < $used_cap ) {
                $used_cap = $cap;
                $storage_lun{'USED_CAPACITY'} = $used_cap;
            }
            my $pom      = $cap - $used_cap;
            my $free_cap = round( $pom, 0 );
            $storage_lun{'FREE_CAPACITY'} = $free_cap;
        }
        push @storage_luns, \%storage_lun;
    }
    return \@storage_luns;
}

sub get_data_pool {
    my ( $ip, $port, $token, $device_id, $cookie ) = @_;
    my $config_data = get_data_config( $ip, $port, $token, $device_id, $cookie, "StoragePool" );
    if ( $config_data eq "" ) {
        $config_data = get_data_config( $ip, $port, $token, $device_id, $cookie, "storagepool" );
    }
    if ( $config_data eq "" ) { return; }

    my @storage_pools;
    foreach my $element_id ( @{ $config_data->{data} } ) {
        my %storage_pool;
        my $id_element = $element_id->{ID};
        my $name       = $element_id->{NAME};
        my $cap        = $element_id->{"USERTOTALCAPACITY"};
        my $used_cap   = $element_id->{"USERCONSUMEDCAPACITY"};
        my $free_cap   = $element_id->{"USERFREECAPACITY"};
        ### tier cap
        my $tier0          = $element_id->{"TIER0CAPACITY"};
        my $tier1          = $element_id->{"TIER1CAPACITY"};
        my $tier2          = $element_id->{"TIER2CAPACITY"};
        my $health_status  = $element_id->{"HEALTHSTATUS"};
        my $running_status = $element_id->{"RUNNINGSTATUS"};
        if ( !defined $id_element || !defined $name ) { next; }

        $storage_pool{'ID'}   = $id_element;
        $storage_pool{'NAME'} = $name;

        if ( defined $health_status && $health_status ne "" ) {
            $health_status = get_health_status_text($health_status);
            $storage_pool{'HEALTH_STATUS'} = $health_status;
        }
        if ( defined $running_status && $running_status ne "" ) {
            $running_status = get_running_status_text($running_status);
            $storage_pool{'RUNNING_STATUS'} = $running_status;
        }
        ### add capacity
        if ( isdigit($cap) ) {
            my $pom = ( $cap * 512 ) / ( 1024 * 1024 * 1024 );    ### in GB
            $cap = round( $pom, 1 );
            $storage_pool{'TOTAL_CAPACITY'} = $cap;
        }
        if ( isdigit($used_cap) ) {
            my $pom = ( $used_cap * 512 ) / ( 1024 * 1024 * 1024 );    ### in GB
            $used_cap = round( $pom, 1 );
            $storage_pool{'USED_CAPACITY'} = $used_cap;
        }
        if ( isdigit($free_cap) ) {
            my $pom = ( $free_cap * 512 ) / ( 1024 * 1024 * 1024 );    ### in GB
            $free_cap = round( $pom, 1 );
            $storage_pool{'FREE_CAPACITY'} = $free_cap;
        }
        if ( isdigit($tier0) && $tier0 != 0 ) {
            my $pom = ( $tier0 * 512 ) / ( 1024 * 1024 * 1024 );       ### in GB
            $tier0 = round( $pom, 1 );
        }
        if ( isdigit($tier1) && $tier1 != 0 ) {
            my $pom = ( $tier1 * 512 ) / ( 1024 * 1024 * 1024 );       ### in GB
            $tier1 = round( $pom, 1 );
        }
        if ( isdigit($tier2) && $tier2 != 0 ) {
            my $pom = ( $tier2 * 512 ) / ( 1024 * 1024 * 1024 );       ### in GB
            $tier2 = round( $pom, 1 );
        }
        push @storage_pools, \%storage_pool;
    }
    return \@storage_pools;
}

sub get_model_version {
    my $model = shift;

    my $dirname = dirname( abs_path($0) );
    my @models  = get_array_data( $dirname . "/huawei_models.txt" );
    ( my $model_string ) = grep ( m/^$model,/, @models );
    if ( defined $model_string ) {
        $model_string =~ s/^$model,//g;
        $model_string =~ s/\n//g;
        return $model_string;
    }

    if ( $model eq "61" )  { return "6800 V3"; }
    if ( $model eq "62" )  { return "6900 V3"; }
    if ( $model eq "63" )  { return "5600 V3"; }
    if ( $model eq "64" )  { return "5800 V3"; }
    if ( $model eq "68" )  { return "5500 V3"; }
    if ( $model eq "69" )  { return "2600 V3"; }
    if ( $model eq "70" )  { return "5300 V3"; }
    if ( $model eq "71" )  { return "2800 V3"; }
    if ( $model eq "72" )  { return "18500 V3"; }
    if ( $model eq "73" )  { return "18800 V3"; }
    if ( $model eq "74" )  { return "2200 V3"; }
    if ( $model eq "82" )  { return "2600 V3 for Video"; }
    if ( $model eq "84" )  { return "2600F V3"; }
    if ( $model eq "85" )  { return "5500F V3"; }
    if ( $model eq "86" )  { return "5600F V3"; }
    if ( $model eq "87" )  { return "5800F V3"; }
    if ( $model eq "88" )  { return "6800F V3"; }
    if ( $model eq "89" )  { return "18500F V3"; }
    if ( $model eq "90" )  { return "18800F V3"; }
    if ( $model eq "92" )  { return "2800 V5"; }
    if ( $model eq "93" )  { return "5300 V5"; }
    if ( $model eq "94" )  { return "5300F V5"; }
    if ( $model eq "95" )  { return "5500 V5"; }
    if ( $model eq "96" )  { return "5500F V5"; }
    if ( $model eq "97" )  { return "5600 V5"; }
    if ( $model eq "98" )  { return "5600F V5"; }
    if ( $model eq "99" )  { return "5800 V5"; }
    if ( $model eq "100" ) { return "5800F V5"; }
    if ( $model eq "101" ) { return "6800 V5"; }
    if ( $model eq "102" ) { return "6800F V5"; }
    if ( $model eq "103" ) { return "18500 V5"; }
    if ( $model eq "104" ) { return "18500F V5"; }
    if ( $model eq "105" ) { return "18800 V5"; }
    if ( $model eq "106" ) { return "18800F V5"; }
    if ( $model eq "107" ) { return "5500 V5 Elite"; }
    if ( $model eq "108" ) { return "2100 V3"; }
    if ( $model eq "116" ) { return "5110 V5"; }
    if ( $model eq "810" ) { return "Dorado3000 V3"; }

    return $model;
}

sub round {
    my $number         = shift;
    my $decimal_plates = shift;
    if ( !defined $decimal_plates ) {
        $decimal_plates = 3;
    }
    my $num = $number;
    if ( $number =~ /\./ ) {
        $number =~ s/.*\.//g;
        my $length = length($number);
        if ( $length > $decimal_plates ) {
            my $rounded = sprintf( "%.$decimal_plates" . "f", $num );
            return $rounded;
        }
        else {
            return $num;
        }
    }
    else {
        return $num;
    }
}

sub get_data_config {
    my ( $ip, $port, $token, $device_id, $cookie, $section ) = @_;
    my $url = "https://$ip:$port/deviceManager/rest/$device_id/$section";

    my $ua  = LWP::UserAgent->new( ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 } );
    my $req = HTTP::Request->new( GET => $url );
    $req->header( 'Content-Type' => 'application/json' );
    $req->header( 'Accept'       => 'application/json' );
    $req->header( 'Connection'   => 'keep-alive' );
    $req->header( 'iBaseToken'   => "$token" );
    $req->header( 'cookie'       => $cookie );
    my $res = $ua->request($req);

    if ( !$res->is_success ) {
        error("ERROR: Command $url failed!");
        error( $res->content );
        return "";
    }
    else {
        ### for debug
        #$section =~ s/\///g;
        #my $file = "$debug_data/$section.json";

        #store \$res->content, $file or error("Store data to file $file failed.");
        ###
        my $data = decode_json( $res->content );

        if ( ref( $data->{data} ) ne "ARRAY" && $data->{error}->{code} != 0 ) {
            my $error_description = $data->{error}->{description};
            my $error_code        = $data->{error}->{code};
            error("No element found for $section  description : $error_description error_code : $error_code");
            return "";
        }
        return $data;
    }
}

sub logout {
    my ( $ip, $port, $token, $device_id, $cookie ) = @_;

    my $url = "https://$ip:$port/deviceManager/rest/$device_id/sessions";

    my $ua  = LWP::UserAgent->new( ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 } );
    my $req = HTTP::Request->new( DELETE => $url );
    $req->header( 'Content-Type' => 'application/json' );
    $req->header( 'Accept'       => 'application/json' );
    $req->header( 'Connection'   => 'keep-alive' );
    $req->header( 'iBaseToken'   => "$token" );
    $req->header( 'cookie'       => $cookie );
    my $res = $ua->request($req);

    if ( !$res->is_success ) {
        error("ERROR: Logout to API failed\n");
        error( $res->content );
        return "";
    }

}

sub login {
    my ( $ip, $port, $user, $passwd ) = @_;
    my $url = "https://$ip:$port/deviceManager/rest/xxxxx/sessions";
    my %hash_filter;
    $hash_filter{"username"} = "$user";
    $hash_filter{"password"} = "$passwd";
    $hash_filter{"scope"}    = "0";
    my $json_body = encode_json( \%hash_filter );

    my $ua = LWP::UserAgent->new( ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 } );

    my $req = HTTP::Request->new( POST => $url );
    $req->header( 'Content-Type' => 'application/json' );
    $req->header( 'Accept'       => 'application/json' );
    $req->header( 'Connection'   => 'keep-alive' );

    $req->content($json_body);

    my $res = $ua->request($req);

    if ( !$res->is_success ) {
        error("ERROR: Login to API failed\n");
        error( $res->content );
        return "";
    }
    else {
        my $data      = decode_json( $res->content );
        my $token     = $data->{data}->{iBaseToken};
        my $device_id = $data->{data}->{deviceid};
        my $cookie    = $res->headers->{"set-cookie"};
        return ( $token, $device_id, $cookie );

    }

}

sub error {
    my $text     = shift;
    my $act_time = localtime();
    chomp($text);

    print STDERR "$act_time: $text : $!\n";
    return 1;
}

sub error_die {
    my $message  = shift;
    my $act_time = localtime();
    print STDERR "$act_time: $message : $!\n";
    exit(1);
}

sub get_array_data {
    my $file = shift;
    my $test = test_file_exist($file);
    if ($test) {
        open( FH, "< $file" ) || error( "Cannot read $file: $!" . __FILE__ . ":" . __LINE__ ) && return ();
        my @file_all = <FH>;
        close(FH);
        return @file_all;
    }
    else {
        error( "File not exist $file: $!" . __FILE__ . ":" . __LINE__ );
        my @file_empty = "";
        return @file_empty;
    }
}

sub get_health_status_text {
    my $number = shift;

    if ( $number == 1 ) {
        return "normal";
    }
    if ( $number == 0 ) {
        return "unknown";
    }
    if ( $number == 2 ) {
        return "faulty";
    }
    if ( $number == 3 ) {
        return "Pre-Fail";
    }
    if ( $number == 9 ) {
        return "inconsistent";
    }
    if ( $number == 4 ) {
        return "partially damaged";
    }
    if ( $number == 12 ) {
        return "low battery";
    }
    if ( $number == 5 ) {
        return "degraded";
    }

    return $number;

}

sub get_running_status_text {
    my $number = shift;

    if ( $number == 1 ) {
        return "normal";
    }
    if ( $number == 0 ) {
        return "unknown";
    }
    if ( $number == 2 ) {
        return "running";
    }
    if ( $number == 27 ) {
        return "online";
    }
    if ( $number == 28 ) {
        return "offline";
    }
    if ( $number == 48 ) {
        return "charging completed";
    }
    if ( $number == 50 ) {
        return "discharging";
    }
    if ( $number == 10 ) {
        return "link up";
    }
    if ( $number == 11 ) {
        return "link down";
    }
    if ( $number == 14 ) {
        return "pre-copy";
    }
    if ( $number == 16 ) {
        return "reconstruction";
    }
    if ( $number == 32 ) {
        return "balancing";
    }
    if ( $number == 53 ) {
        return "Initializing";
    }

    return $number;

}

sub isdigit {
    my $digit = shift;
    my $text  = shift;

    if ( !defined($digit) ) {
        return 0;
    }
    if ( $digit eq '' ) {
        return 0;
    }

    my $digit_work = $digit;
    $digit_work =~ s/[0-9]//g;
    $digit_work =~ s/\.//;
    $digit_work =~ s/^-//;
    $digit_work =~ s/e//;
    $digit_work =~ s/\+//;
    $digit_work =~ s/\-//;

    if ( length($digit_work) == 0 ) {

        # is a number
        return 1;
    }

    # NOT a number
    return 0;
}

sub get_basic_configuration {
    my ( $ip, $port, $token, $device_id, $cookie ) = @_;

    my $data = {};

    my $config_data        = get_data_config( $ip, $port, $token, $device_id, $cookie, "system/" );
    my $id                 = "";
    my $name               = "";
    my $health_status      = "";
    my $running_status     = "";
    my $cap                = "";
    my $used_cap           = "";
    my $free_cap           = "";
    my $version            = "";
    my $patch_version      = "";
    my $model_version      = "";
    my $serial_number      = "";
    my $cap_effective      = "";
    my $cap_used_effective = "";
    my $cap_free_effective = "";
    if ( $config_data eq "" ) { return; }
    my $config_data2      = get_data_config( $ip, $port, $token, $device_id, $cookie, "enclosure" );
    my $config_data3      = get_data_config( $ip, $port, $token, $device_id, $cookie, "effective_capacity_info" );
    my $block_size_global = 512;

    if ( ref($config_data) eq "HASH" ) {
        $id             = $config_data->{data}->{ID};
        $name           = $config_data->{data}->{NAME};
        $health_status  = $config_data->{data}->{"HEALTHSTATUS"};
        $running_status = $config_data->{data}->{"RUNNINGSTATUS"};
        $cap            = $config_data->{data}->{"TOTALCAPACITY"};
        $used_cap       = $config_data->{data}->{"USEDCAPACITY"};
        $free_cap       = $config_data->{data}->{"userFreeCapacity"};
        $version        = $config_data->{data}->{"PRODUCTVERSION"};
        $patch_version  = $config_data->{data}->{"patchVersion"};
        $model_version  = $config_data->{data}->{"PRODUCTMODE"};
        if ( !defined $id )            { $id            = ""; }
        if ( !defined $name )          { $name          = ""; }
        if ( !defined $cap )           { $cap           = ""; }
        if ( !defined $used_cap )      { $used_cap      = ""; }
        if ( !defined $free_cap )      { $free_cap      = ""; }
        if ( !defined $version )       { $version       = ""; }
        if ( !defined $patch_version ) { $patch_version = ""; }

        if ( defined $model_version ) {
            $model_version = get_model_version($model_version);
        }
        else {
            $model_version = "";
        }
        my $block_size = $config_data->{data}->{"SECTORSIZE"};

        if ( defined $health_status && $health_status ne "" ) {
            $health_status = get_health_status_text($health_status);
        }
        else { $health_status = ""; }
        if ( defined $running_status && $running_status ne "" ) {
            $running_status = get_running_status_text($running_status);
        }
        else { $running_status = ""; }
        if ( !isdigit($block_size) ) {
            $block_size = 512;    ### default
        }
        if ( isdigit($cap) ) {
            my $pom = ( $cap * $block_size ) / ( 1024 * 1024 * 1024 * 1024 );
            $cap = round( $pom, 3 );
        }
        if ( isdigit($used_cap) ) {
            my $pom = ( $used_cap * $block_size ) / ( 1024 * 1024 * 1024 * 1024 );
            $used_cap = round( $pom, 3 );
        }
        if ( isdigit($free_cap) ) {
            my $pom = ( $free_cap * $block_size ) / ( 1024 * 1024 * 1024 * 1024 );
            $free_cap = round( $pom, 3 );
            if ( $free_cap > $cap ) {
                $free_cap = $cap - $used_cap;
            }
        }
    }
    if ( $config_data2 ne "" && ref( $config_data2->{data} ) eq "ARRAY" ) {
        foreach my $line ( @{ $config_data2->{data} } ) {
            $serial_number = $line->{SERIALNUM};
            if ( defined $serial_number && $serial_number ne "" ) { last; }
        }
    }

    if ( $config_data3 ne "" && ref( $config_data3->{data} ) eq "HASH" ) {
        #### effective capacity
        $cap_effective      = $config_data3->{data}->{"totalEffectiveCapacity"};
        $cap_used_effective = $config_data3->{data}->{"usedEffectiveCapacity"};
        $cap_free_effective = $config_data3->{data}->{"freeEffectiveCapacity"};
        if ( !defined $cap_effective )      { $cap_effective      = ""; }
        if ( !defined $cap_used_effective ) { $cap_used_effective = ""; }
        if ( !defined $cap_free_effective ) { $cap_free_effective = ""; }
        if ( isdigit($cap_effective) ) {
            my $pom = ( $cap_effective * $block_size_global ) / ( 1024 * 1024 * 1024 * 1024 );
            $cap_effective = round( $pom, 3 );
        }
        if ( isdigit($cap_used_effective) ) {
            my $pom = ( $cap_used_effective * $block_size_global ) / ( 1024 * 1024 * 1024 * 1024 );
            $cap_used_effective = round( $pom, 3 );
        }
        if ( isdigit($cap_free_effective) ) {
            my $pom = ( $cap_free_effective * $block_size_global ) / ( 1024 * 1024 * 1024 * 1024 );
            $cap_free_effective = round( $pom, 3 );
        }

        if ( isdigit($cap_effective) && isdigit($cap_used_effective) && !isdigit($cap_free_effective) ) {
            $cap_free_effective = $cap_effective - $cap_used_effective;
        }
    }
    $data->{'ID'}                 = $id;
    $data->{'NAME'}               = $name;
    $data->{'PRODUCT_VERSION'}    = $version;
    $data->{'PATCH_VERSION'}      = $patch_version;
    $data->{'MODEL'}              = $model_version;
    $data->{'SERIAL_NUMBER'}      = $serial_number;
    $data->{'SN'}                 = $serial_number;
    $data->{'HEALTH_STATUS'}      = $health_status;
    $data->{'RUNNING_STATUS'}     = $running_status;
    $data->{'TOTAL_CAPACITY(TB)'} = $cap;
    $data->{'USED_CAPACITY(TB)'}  = $used_cap;
    $data->{'FREE_CAPACITY(TB)'}  = $free_cap;

    return $data;

}

sub test_file_exist {
    my $file = shift;
    my $run  = shift;
    if ( !defined $file || $file eq "" ) {
        error("File does not defined !");
        return 0;
    }
    if ( !-e $file || -z $file ) {
        if ( defined $run && -z $file ) { return 1; }
        else {
            return 0;
        }
    }
    else {
        return 1;
    }
}

sub get_data_node {
    my ( $ip, $port, $token, $device_id, $cookie ) = @_;
    my %temperatures;
    my $config_data = get_data_config( $ip, $port, $token, $device_id, $cookie, "Controller" );
    if ( $config_data eq "" ) {
        $config_data = get_data_config( $ip, $port, $token, $device_id, $cookie, "controller" );
    }
    my $enclosure_data = get_data_config( $ip, $port, $token, $device_id, $cookie, "enclosure" );
    if ( $config_data eq "" ) { return; }

    my @storage_controllers;
    foreach my $element_id ( @{ $config_data->{data} } ) {
        my %controller;

        my $id_element     = $element_id->{ID};
        my $name           = $element_id->{"NAME"};
        my $health_status  = $element_id->{"HEALTHSTATUS"};
        my $running_status = $element_id->{"RUNNINGSTATUS"};
        my $location       = $element_id->{LOCATION};
        my $version        = $element_id->{SOFTVER};

        #my $temperature    = $element_id->{TEMPERATURE};
        #if ( !isdigit($temperature) || $temperature =~ m/^-/ ) {
        #  $temperature = "";
        #}
        if ( !defined $id_element || !defined $name ) { next; }
        $controller{'ID'}          = $id_element;
        $controller{'NAME'}        = $id_element;
        $controller{'IOS_VERSION'} = $version;
        if ( defined $health_status && $health_status ne "" ) {
            $health_status = get_health_status_text($health_status);
            $controller{'HEALTH_STATUS'} = $health_status;
        }
        if ( defined $running_status && $running_status ne "" ) {
            $running_status = get_running_status_text($running_status);
            $controller{'RUNNING_STATUS'} = $running_status;
        }
        if ( defined $location ) {
            $controller{'LOCATION'} = $location;
        }
        push @storage_controllers, \%controller;
    }
    return \@storage_controllers;
}

sub get_data_disk {
    my ( $ip, $port, $token, $device_id, $cookie ) = @_;
    my $config_data = get_data_config( $ip, $port, $token, $device_id, $cookie, "Disk" );
    if ( $config_data eq "" ) {
        $config_data = get_data_config( $ip, $port, $token, $device_id, $cookie, "disk" );
    }
    if ( $config_data eq "" ) { return; }

    my @storage_disks;
    foreach my $element_id ( @{ $config_data->{data} } ) {
        my %disk;

        my $id_element       = $element_id->{ID};
        my $name             = $element_id->{"NAME"};
        my $health_status    = $element_id->{"HEALTHSTATUS"};
        my $running_status   = $element_id->{"RUNNINGSTATUS"};
        my $count_sectors    = $element_id->{"SECTORS"};
        my $size_sector      = $element_id->{"SECTORSIZE"};
        my $used_cap_percent = $element_id->{"CAPACITYUSAGE"};
        if ( !defined $name && defined $id_element ) {
            $name = $id_element;
        }
        if ( !defined $id_element || !defined $name ) { next; }
        $disk{"ID"}   = $id_element;
        $disk{"NAME"} = $name;
        if ( defined $health_status && $health_status ne "" ) {
            $health_status = get_health_status_text($health_status);
            $disk{"HEALTH_STATUS"} = $health_status;
        }
        if ( defined $running_status && $running_status ne "" ) {
            $running_status = get_running_status_text($running_status);
            $disk{"RUNNING_STATUS"} = $running_status;
        }
        if ( isdigit($size_sector) && isdigit($count_sectors) ) {
            my $pom = ( $size_sector * $count_sectors ) / ( 1024 * 1024 * 1024 );    ## in GB
            my $cap = round( $pom, 1 );
            if ( isdigit($used_cap_percent) ) {
                my $pom      = ( $used_cap_percent / 100 ) * $cap;
                my $used_cap = round( $pom,             1 );
                my $free_cap = round( $cap - $used_cap, 1 );
                $disk{"CAPACITY(GB)"} = $cap;
                $disk{"USED(GB)"}     = $used_cap;
                $disk{"FREE(GB)"}     = $free_cap;
            }
        }
        push @storage_disks, \%disk;
    }
    return \@storage_disks;
}

sub get_data_fcport {
    ### SAS FC FCoE
    my ( $ip, $port, $token, $device_id, $cookie ) = @_;

    #  my @type_port = ( "sas_port", "fc_port", "fcoe_port", "eth_port", "lif" );
    #my @type_port = ( "fc_port" );
    my @storage_fcports;
    my $config_data = get_data_config( $ip, $port, $token, $device_id, $cookie, "fc_port" );
    if ( $config_data eq "" ) { next; }
    foreach my $element_id ( @{ $config_data->{data} } ) {
        my %fc_port;

        my $id_element = $element_id->{"LOCATION"};
        my $name       = $element_id->{"LOCATION"};
        my $wwn        = $element_id->{"WWN"};

        #格式转换每隔2位添加:
        $wwn =~ s/(..)/$1:/g;
        $wwn =~ s/:$//;
        my $health_status  = $element_id->{"HEALTHSTATUS"};
        my $speed          = $element_id->{"RUNSPEED"};
        my $running_status = $element_id->{"RUNNINGSTATUS"};
        my $port_id_lif    = $element_id->{CURRENTPORTNAME};
        my $port_name_lif  = $element_id->{NAME};

        if ( !defined $id_element || !defined $name ) { next; }
        $fc_port{"ID"}   = $id_element;
        $fc_port{"NAME"} = $name;
        if ( defined $wwn && $wwn ne "" ) {
            $fc_port{"WWPN"} = $wwn;
        }

        if ( defined $health_status && $health_status ne "" ) {
            $health_status = get_health_status_text($health_status);
            $fc_port{"HEALTH_STATUS"} = $health_status;
        }
        if ( defined $speed && $speed ne "" ) {
            if ( isdigit($speed) && $speed !~ m/^-/ ) {
                my $pom = round( $speed / 1000, 0 );
                $speed = $pom;
            }
            if ( $speed eq "-1" ) {
                $speed = "port works incorrectly";
            }
            $fc_port{"PORT_SPEED(Gbit/s)"} = $speed;
        }
        if ( defined $running_status && $running_status ne "" ) {
            $running_status = get_running_status_text($running_status);
            $fc_port{"RUNNING_STATUS"} = $running_status;
        }
        push @storage_fcports, \%fc_port;
    }
    return \@storage_fcports;
}

#查询存储链路信息,可以看到存储的哪个wwn跟主机的哪个wwn连接
sub get_data_hostlink {
    my ( $ip, $port, $token, $device_id, $cookie ) = @_;
    my $config_data = get_data_config( $ip, $port, $token, $device_id, $cookie, "host_link?INITIATOR_TYPE=223" );

    if ( $config_data eq "" ) { return; }

    #print Dumper($config_data);
    my @host_links;
    foreach my $element_id ( @{ $config_data->{data} } ) {
        my %link;

        my $host_hba_wwn         = $element_id->{"INITIATOR_PORT_WWN"};
        my $storage_hba_wwn      = $element_id->{"TARGET_PORT_WWN"};
        my $storage_hba_portname = $element_id->{"port"};
        my $host_name            = $element_id->{"PARENTNAME"};
        my $health_status        = $element_id->{"HEALTHSTATUS"};
        my $running_status       = $element_id->{"RUNNINGSTATUS"};

        $link{"HOST_HBA_WWN"}         = $host_hba_wwn;
        $link{"STORAGE_HBA_WWN"}      = $storage_hba_wwn;
        $link{"HOST_NAME"}            = $host_name;
        $link{"STORAGE_HBA_PORTNAME"} = $storage_hba_portname;

        if ( defined $health_status && $health_status ne "" ) {
            $health_status = get_health_status_text($health_status);
            $link{"HEALTH_STATUS"} = $health_status;
        }

        if ( defined $running_status && $running_status ne "" ) {
            $running_status = get_running_status_text($running_status);
            $link{"RUNNING_STATUS"} = $running_status;
        }

        push @host_links, \%link;
    }

    return \@host_links;
}

#查询存储链路信息,可以看到存储的哪个wwn跟主机的哪个wwn连接
sub get_data_power {
    my ( $ip, $port, $token, $device_id, $cookie ) = @_;
    my $config_data = get_data_config( $ip, $port, $token, $device_id, $cookie, "power" );

    if ( $config_data eq "" ) { return; }

    #print Dumper($config_data);
    my @powers;
    foreach my $element_id ( @{ $config_data->{data} } ) {
        my %power;

        my $id             = $element_id->{"ID"};
        my $name           = $element_id->{"NAME"};
        my $location       = $element_id->{"LOCATION"};
        my $model          = $element_id->{"MODEL"};
        my $health_status  = $element_id->{"HEALTHSTATUS"};
        my $running_status = $element_id->{"RUNNINGSTATUS"};

        $power{"NAME"}     = $name;
        $power{"LOCATION"} = $location;
        $power{"MODEL"}    = $model;
        $power{"ID"}       = $id;

        if ( defined $health_status && $health_status ne "" ) {
            $health_status = get_health_status_text($health_status);
            $power{"HEALTH_STATUS"} = $health_status;
        }

        if ( defined $running_status && $running_status ne "" ) {
            $running_status = get_running_status_text($running_status);
            $power{"RUNNING_STATUS"} = $running_status;
        }

        push @powers, \%power;
    }

    return \@powers;
}

#查询存储链路信息,可以看到存储的哪个wwn跟主机的哪个wwn连接
sub get_data_fan {
    my ( $ip, $port, $token, $device_id, $cookie ) = @_;
    my $config_data = get_data_config( $ip, $port, $token, $device_id, $cookie, "fan" );

    if ( $config_data eq "" ) { return; }

    #print Dumper($config_data);
    my @fans;
    foreach my $element_id ( @{ $config_data->{data} } ) {
        my %fan;

        my $id             = $element_id->{"ID"};
        my $location       = $element_id->{"LOCATION"};
        my $name           = $element_id->{"NAME"};
        my $health_status  = $element_id->{"HEALTHSTATUS"};
        my $running_status = $element_id->{"RUNNINGSTATUS"};

        $fan{"ID"}       = $id;
        $fan{"LOCATION"} = $location;
        $fan{"NAME"}     = $name;

        if ( defined $health_status && $health_status ne "" ) {
            $health_status = get_health_status_text($health_status);
            $fan{"HEALTH_STATUS"} = $health_status;
        }

        if ( defined $running_status && $running_status ne "" ) {
            $running_status = get_running_status_text($running_status);
            $fan{"RUNNING_STATUS"} = $running_status;
        }

        push @fans, \%fan;
    }

    return \@fans;
}

