#!/usr/bin/perl
use strict;

package ApolloCtl;
use FindBin;
use POSIX qw(strftime);
use JSON qw(to_json from_json encode_json decode_json);
use URI::Escape;
use Data::Dumper qw(Dumper);

use WebCtl;

#API URL例子："openapi/v1/envs/${env}/apps/${appid}/clusters/${cluster}/namespaces/${namespace}/items/${key}?operator=${operator}"

sub new {
    my ( $type, %args ) = @_;

    my $apolloUrl = $args{url};
    $apolloUrl =~ s/\/+$//;

    #对apollo里的应用id等信息进行uri escape，避免有特殊字符
    my $env     = uri_escape( $args{env} );
    my $appId   = uri_escape( $args{appId} );
    my $cluster = uri_escape( $args{cluster} );

    my $self = {
        env      => $args{env},
        appId    => $args{appId},
        cluster  => $args{cluster},
        operator => $args{operator},
        token    => $args{token},
        baseUri  => "$apolloUrl/openapi/v1/envs/$env/apps/$appId/clusters/$cluster/namespaces/"
    };

    my $webCtl = WebCtl->new();

    #使用Header的基于token的认证
    $webCtl->setHeaders( { Authorization => $args{token} } );
    $self->{webCtl} = $webCtl;

    bless( $self, $type );
    return $self;
}

#获取某个namespace下的所有的配置型key value对
#返回一个hashmap，key value对就是配置项
sub getAllItems {
    my ( $self, $namespace ) = @_;
    my $url     = $self->{baseUri} . uri_escape($namespace) . '/releases/latest';
    my $webCtl  = $self->{webCtl};
    my $content = $webCtl->doRest( 'GET', $url );

    my $rc    = from_json($content);
    my $items = $rc->{configurations};
    if ( not defined($items) ) {
        $items = {};
    }

    return $items;
}

#新建一个配置key value对
sub createItem {
    my ( $self, $namespace, $key, $value ) = @_;
    my $url  = $self->{baseUri} . uri_escape($namespace) . '/items';
    my $data = {
        'key'                 => $key,
        'value'               => $value,
        'dataChangeCreatedBy' => $self->{operator}
    };

    my $webCtl = $self->{webCtl};
    $webCtl->doRest( 'POST', $url, $data );
}

#更新一个已经存在的key value对
sub updateItem {
    my ( $self, $namespace, $key, $value ) = @_;

    my $url  = $self->{baseUri} . uri_escape($namespace) . '/items/' . uri_escape($key);
    my $data = {
        'key'                      => $key,
        'value'                    => $value,
        'dataChangeLastModifiedBy' => $self->{operator}
    };

    my $webCtl = $self->{webCtl};
    $webCtl->doRest( 'PUT', $url, $data );
}

#删除一个key
sub deleteItem {
    my ( $self, $namespace, $key ) = @_;
    my $url = $self->{baseUri} . uri_escape($namespace) . '/items/' . uri_escape($key) . '?operator=' . uri_escape( $self->{operator} );

    my $webCtl = $self->{webCtl};
    $webCtl->doRest( 'DELETE', $url );
}

#发布生效更新
sub releaseItems {
    my ( $self, $namespace ) = @_;
    my $timeStr      = strftime( "%Y%m%d%H%M%S", localtime );
    my $releaseTitle = "$timeStr-release";
    my $url          = $self->{baseUri} . uri_escape($namespace) . '/releases';
    my $data         = {
        'releaseTitle' => $releaseTitle,
        'releasedBy'   => $self->{operator}
    };

    my $webCtl = $self->{webCtl};
    $webCtl->doRest( 'POST', $url, $data );
}

1;

