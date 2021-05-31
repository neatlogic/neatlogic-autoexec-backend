#  Copyright 2009 - present MongoDB, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

use strict;
use warnings;
package MongoDB::OID;

# ABSTRACT: (DEPRECATED) A Mongo Object ID

use version;
our $VERSION = 'v2.2.2';


use Moo;
extends 'BSON::OID';
use namespace::clean -except => 'meta';

with $_ for qw(
  MongoDB::Role::_DeprecationWarner
);

sub BUILD {
    my $self = shift;
    $self->_warn_deprecated_class(__PACKAGE__, ["BSON::OID"], 0);
};

around BUILDARGS => sub {
    my $orig = shift;
    my $class = shift;
    if ( @_ == 0 ) {
        return {};
    }
    if ( @_ == 1 ) {
        return { oid => pack("H*",$_[0]) };
    }
    # convert 'value' to 'oid'
    my %args = @_;
    if ( $args{value} ) {
        $args{oid} = pack("H*", delete $args{value});
    }
    return $orig->($class, %args);
};

# This private constructor bypasses everything Moo does for us and just
# jams an OID into a blessed hashref.  This is only for use in super-hot
# code paths, like document insertion.
sub _new_oid {
    return bless { oid => BSON::OID::_generate_oid() }, "BSON::OID";
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MongoDB::OID - (DEPRECATED) A Mongo Object ID

=head1 VERSION

version v2.2.2

=head1 DESCRIPTION

This class is now an empty subclass of L<BSON::OID>.

=head1 AUTHORS

=over 4

=item *

David Golden <david@mongodb.com>

=item *

Rassi <rassi@mongodb.com>

=item *

Mike Friedman <friedo@friedo.com>

=item *

Kristina Chodorow <k.chodorow@gmail.com>

=item *

Florian Ragwitz <rafl@debian.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2020 by MongoDB, Inc.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
