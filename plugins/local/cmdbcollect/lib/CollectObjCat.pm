#!/usr/bin/perl
use strict;

package CollectObjCat;

our $TYPES = {
    SYS          => 'SYS',             #应用系统，逻辑单元
    SUBSYS       => 'SUBSYS',          #系统模块，逻辑单元
    INS          => 'INS',             #进程实例，所有软件实例进程都可以放到这个集合，_OBJ_TYPE:Tomcat、Apache...
    DB           => 'DB',              #数据库，_OBJ_TYPE:Oracle、Mysql...
    DBINS        => 'DBINS',           #数据库实例，，_OBJ_TYPE:Oracle、Mysql...
    OS           => 'OS',              #操作系统，_OBJ_TYPE:Linux、Windows、AIX...
    HOST         => 'HOST',            #主机（硬件），_OBJ_TYPE:各个品牌名
    SERVERDEV    => 'SERVERDEV',       #主机（硬件），_OBJ_TYPE:各个品牌名
    NETDEV       => 'NETDEV',          #网络设备，_OBJ_TYPE:各个品牌名
    SECDEV       => 'SECDEV',          #安全设备，_OBJ_TYPE:各个品牌名
    VIRTUALIZED  => 'VIRTUALIZED',     #虚拟化管理服务
    SWITCH       => 'SWITCH',          #交换机，_OBJ_TYPE:各个品牌名
    FIREWALL     => 'SECDEV',          #防火墙，_OBJ_TYPE:各个品牌名
    LOADBALANCER => 'LOADBALANCER',    #负载均衡设备，_OBJ_TYPE:各个品牌名
    STORAGE      => 'STORAGE',         #存储， _OBJ_TYPE:各个品牌名
    FCSWITCH     => 'FCDEV',           #SAN光交， _OBJ_TYPE:各个品牌名
    CLUSTER      => 'CLUSTER',         #集群， _OBJ_TYPE:DBCluster|INSCluster|OSCluster
};

#Deprecated，废弃，改为在local/cmdbcollect/savedata里声明每个类别的主键定义
our $PK_CONFIG = {
    INS          => [ 'MGMT_IP',       'PORT' ],
    DB           => [ 'NAME',          'PRIMARY_IP', 'PORT' ],
    CLUSTER      => [ 'NAME',          'UNIQUE_NAME' ],
    DBINS        => [ 'INSTANCE_NAME', 'MGMT_IP', 'PORT' ],
    OS           => ['MGMT_IP'],
    HOST         => [ 'MGMT_IP', 'BOARD_SERIAL' ],
    SERVERDEV    => [ 'MGMT_IP', 'BOARD_SERIAL' ],
    NETDEV       => [ 'MGMT_IP', 'SN' ],
    SECDEV       => [ 'MGMT_IP', 'SN' ],
    VIRTUALIZED  => ['MGMT_IP'],
    SWITCH       => [ 'MGMT_IP', 'SN' ],
    FIREWALL     => [ 'MGMT_IP', 'SN' ],
    LOADBALANCER => [ 'MGMT_IP', 'SN' ],
    STORAGE      => [ 'MGMT_IP', 'SN' ],
    FCSWITCH     => [ 'MGMT_IP', 'SN' ]
};

our $INDEX_FIELDS = {
    DBINS    => [ 'IP', 'VIP' ],
    HOST     => ['OS_ID'],
    OS       => [ 'OS_ID', 'HBA_INTERFACES.WWNN', 'HBA_INTERFACES.WWPN' ],
    CLUSTER  => ['MEMBER_PEER'],
    SWITCH   => ['DEV_NAME'],
    STORAGE  => [ 'HBA_INTERFACES.WWNN', 'HBA_INTERFACES.WWPN' ],
    FCSWITCH => [ 'WWNN', 'PORTS.WWPN', 'LINK_TABLE.PEER_WWPN' ]
};

sub get {
    my ( $self, $objCatName ) = @_;
    my $objCat = $TYPES->{$objCatName};
    if ( not defined($objCat) ) {
        die("_OBJ_CATEGORY:$objCatName not exists.\n");
    }

    return $objCat;
}

sub getPK {
    my ( $self, $objCat ) = @_;
    return $PK_CONFIG->{$objCat};
}

sub getIndexFields {
    my ( $self, $objCat ) = @_;
    my $indexFields = $INDEX_FIELDS->{$objCat};
    if ( not defined($indexFields) ) {
        $indexFields = [];
    }
    return $indexFields;
}

sub validate {
    my ( $self, $objCat ) = @_;
    if ( defined( $TYPES->{$objCat} ) ) {
        return 1;
    }

    return 0;
}

1;
