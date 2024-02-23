#!/usr/bin/perl
use FindBin;

use lib $FindBin::Bin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../plib/lib/perl5";

use strict;

package FCSwitchHuawei;

use FCSwitchBase;
our @ISA = qw(FCSwitchBase);

use Net::OpenSSH;

#重载此方法，调整snmp oid的设置
sub before {
    my ($self) = @_;
    $self->SUPER::before();
    #SN可能要调整，如果有多个可能，就在数组里添加
    #$self->addScalarOid( SN => [ '1.3.6.1.4.1.9.3.6.3.0', '1.3.6.1.4.1.9.5.1.2.19.0', '1.3.6.1.2.1.47.1.1.1.1.11.1001', '1.3.6.1.2.1.47.1.1.1.1.11.2001', '1.3.6.1.4.1.9.9.92.1.1.1.2.0' ] );
}

#重载此方法，进行数据调整，或者补充其他非SNMP数据
sub after {
    my ($self) = @_;
    $self->SUPER::after();
    #my $data = $self->{DATA};
    #my $model = $data->{MODEL};
    #if ( defined($model) ){
    #    my @lines = split(/\n/, $model);
    #    $data->{MODEL} = $lines[0];
    #}
}

1;

