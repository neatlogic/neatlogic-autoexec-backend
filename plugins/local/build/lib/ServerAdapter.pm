#!/usr/bin/perl
use strict;

package ServerAdapter;

sub getIdPath {
    my ( $self, $namePath ) = @_;
    $namePath =~ s/^\/+|\/+$//g;
    my @dpNames = split( '/', $namePath );

    my $param = {};
    my $idx   = 0;
    for my $level ( 'sysName', 'moduleName', 'envName' ) {
        $param->{$level} = @dpNames[$idx];
        $idx = $idx + 1;
    }

    #TODO: vcall api convert namePath to idPath

    my $idPath = $namePath;
    return $idPath;
}

sub getVer {
    my ( $self, $buildEnv ) = @_;

    #获取版本详细信息：repoType, repo, branch, tag, tagsDir, lastBuildNo, isFreeze, startRev, endRev
    #startRev: 如果是新版本，则获取同一个仓库地址和分支的所有版本最老的一次build的startRev
    #               如果是现有的版本，则获取当前版本的startRev
    #               如果获取不到则默认是0
    my $version = $buildEnv->{VERSION};
    my $param   = {
        sysId    => $buildEnv->{SYS_ID},
        subSysId => $buildEnv->{MODULE_ID},
        version  => $version,
        buildNo  => $buildEnv->{BUILDNO}
    };

    #TODO: call api get verInfo by param

    my $verInfo = {
        version     => $version,
        repoType    => 'GIT',
        repo        => 'http://192.168.0.82:7070/luoyu/webTest.git',
        trunk       => 'master',
        branch      => '2.0.0',
        tag         => undef,
        tagsDir     => undef,
        isFreeze    => 0,
        lastBuildNo => 0,
        startRev    => 'bda9fb6f',
        endRev      => '80306e35',
        username    => 'wenhb',
        password    => 'won8802654'
    };

    return $verInfo;
}

sub updateVer {

    #getver之后update版本信息，更新版本的相关属性
    #repoType, repo, trunk, branch, tag, tagsDir, lastBuildNo, isFreeze, startRev, endRev

    return;
}

1;
