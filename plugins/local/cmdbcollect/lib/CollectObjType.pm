#!/usr/bin/perl
use strict;

package CollectObjType;

our $TYPES = {
    SYS          => 'SYS',             #应用系统，逻辑单元
    SUBSYS       => 'SUBSYS',          #系统模块，逻辑单元
    INS          => 'INS',             #进程实例，所有软件实例进程都可以放到这个集合
    DB           => 'DB',              #数据库实例
    OS           => 'OS',              #操作系统
    HOST         => 'HOST',            #主机（硬件）
    VIRTUALIZED  => 'VIRTUALIZED',     #虚拟化管理服务
    SWITCH       => 'SWITCH',          #交换机
    FIREWALL     => 'FIREWALL',        #防火墙
    LOADBALANCER => 'LOADBALANCER',    #负载均衡设备
    STORAGE      => 'STORAGE',         #存储
    FCSWITCH     => 'FCSWITCH',        #SAN光交
    APP_CLUSTER  => 'APP_CLUSTER',     #应用集群
    DB_CLUSTER   => 'DB_CLUSTER',      #DB集群
    OS_CLUSTER   => 'OS_CLUSTER'       #操作系统集群
};

sub get {
    my ( $self, $objTypeName ) = @_;
    my $objType = $TYPES->{$objTypeName};
    if ( not defined($objType) ) {
        die("OBJECT_TYPE:$objTypeName not exists.\n");
    }

    return $objType;
}

sub validate {
    my ( $self, $objType ) = @_;
    if ( defined( $TYPES->{$objType} ) ) {
        return 1;
    }

    return 0;
}
