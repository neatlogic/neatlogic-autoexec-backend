#  Copyright 2013 - present MongoDB, Inc.
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
package MongoDB::BSON::Regexp;

# ABSTRACT: (DEPRECATED) Regular expression type

use version;
our $VERSION = 'v2.2.2';

use Moo;
extends 'BSON::Regex';

with $_ for qw(
  MongoDB::Role::_DeprecationWarner
);

sub BUILD {
    my $self = shift;
    $self->_warn_deprecated_class(__PACKAGE__, ["BSON::Regex"], 0);
};

1;

=pod

=encoding UTF-8

=head1 NAME

MongoDB::BSON::Regexp - (DEPRECATED) Regular expression type

=head1 VERSION

version v2.2.2

=head1 DESCRIPTION

This class is now an empty subclass of L<BSON::Regex>.

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

__END__


# vim: set ts=4 sts=4 sw=4 et tw=75:
