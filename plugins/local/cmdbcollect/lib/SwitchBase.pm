#!/usr/bin/perl
use strict;

package SwitchBase;

sub new {
    my ($class) = @_;
    my $self = {};
    bless( $self, $class );
    return $self;
}

#重载此方法，调整snmp oid的设置
sub before {
    my ( $self, $collector ) = @_;

    #$collector->addScalarOid( SN => '1.3.6.1.2.1.47.1.1.1.1.11.1' );
    #$collector->addTableOid( PORTS_TABLE_FOR_TEST => [ { NAME => '1.3.6.1.2.1.2.2.1.2' }, { MAC => '1.3.6.1.2.1.2.2.1.6' } ] );
    #$collector->setCommonOid( PORT_TYPE => '1.3.6.1.2.1.2.2.1.3' );
}

#重载此方法，进行数据调整，或者补充其他非SNMP数据
sub after {
    my ( $self, $collector ) = @_;

    #my $data = $collector->{DATA};
    #my $model = $data->{MODEL};
    #if ( defined($model) ){
    #    my @lines = split(/\n/, $model);
    #    $data->{MODEL} = $lines[0];
    #}
}

1;

