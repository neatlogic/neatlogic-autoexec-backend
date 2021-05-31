#  Copyright 2014 - present MongoDB, Inc.
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
package MongoDB::QueryResult::Filtered;

# ABSTRACT: An iterator for Mongo query results with client-side filtering

use version;
our $VERSION = 'v2.2.2';

use Moo;
use Types::Standard qw(
    CodeRef
);

extends 'MongoDB::QueryResult';

use namespace::clean;

# N.B.: _post_filter may also munge documents in addition to filtering;
# it *must* be run on all documents
has _post_filter => (
    is       => 'ro',
    isa      => CodeRef,
    required => 1,
);

sub has_next {
    my ($self) = @_;
    my $limit = $self->_limit;
    if ( $limit > 0 && ( $self->cursor_at + 1 ) > $limit ) {
        $self->_kill_cursor;
        return 0;
    }
    while ( !$self->_drained || $self->_get_more ) {
        my $peek = $self->_docs->[0];
        if ( $self->_post_filter->($peek) ) {
            # if meets criteria, has_next is true
            return 1;
        }
        else {
            # otherwise throw it away and repeat
            $self->_inc_cursor_at;
            $self->_next_doc;
        }
    }
    # ran out of docs, so nothing left
    return 0;
}

sub all {
    my ($self) = @_;
    my @ret;
    push @ret, grep { $self->_post_filter->($_) } $self->_drain_docs
        while $self->has_next;
    return @ret;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MongoDB::QueryResult::Filtered - An iterator for Mongo query results with client-side filtering

=head1 VERSION

version v2.2.2

=for Pod::Coverage has_next

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
