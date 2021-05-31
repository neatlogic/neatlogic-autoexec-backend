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
package MongoDB::BulkWriteResult;

# ABSTRACT: MongoDB bulk write result document

use version;
our $VERSION = 'v2.2.2';

# empty superclass for backcompatibility; add a variable to the
# package namespace so Perl thinks it's a real package
$MongoDB::WriteResult::VERSION = $VERSION;

use Moo;
use MongoDB::Error;
use MongoDB::_Constants;
use MongoDB::_Types qw(
    ArrayOfHashRef
    Numish
);
use Types::Standard qw(
    HashRef
    Undef
);
use namespace::clean;

# fake empty superclass for backcompat
our @ISA;
push @ISA, 'MongoDB::WriteResult';

with $_ for qw(
  MongoDB::Role::_PrivateConstructor
  MongoDB::Role::_WriteResult
);

has [qw/upserted inserted/] => (
    is       => 'ro',
    required => 1,
    isa      => ArrayOfHashRef,
);

has inserted_ids => (
    is       => 'lazy',
    builder  => '_build_inserted_ids',
    init_arg => undef,
    isa      => HashRef,
);

sub _build_inserted_ids {
    my ($self) = @_;
    return { map { $_->{index}, $_->{_id} } @{ $self->inserted } };
}

has upserted_ids => (
    is       => 'lazy',
    builder  => '_build_upserted_ids',
    init_arg => undef,
    isa      => HashRef,
);

sub _build_upserted_ids {
    my ($self) = @_;
    return { map { $_->{index}, $_->{_id} } @{ $self->upserted } };
}

for my $attr (qw/inserted_count upserted_count matched_count deleted_count/) {
    has $attr => (
        is       => 'ro',
        writer   => "_set_$attr",
        required => 1,
        isa      => Numish,
    );
}

# This should always be initialized either as a number or as undef so that
# merges accumulate correctly.  It should be undef if talking to a server < 2.6
# or if talking to a mongos and not getting the field back from an update.  The
# default is undef, which will be sticky and ensure this field stays undef.

has modified_count => (
    is       => 'ro',
    writer   => '_set_modified_count',
    required => 1,
    isa      => (Numish|Undef),
);

sub has_modified_count {
    my ($self) = @_;
    return defined( $self->modified_count );
}

has op_count => (
    is       => 'ro',
    writer   => '_set_op_count',
    required => 1,
    isa      => Numish,
);

has batch_count => (
    is       => 'ro',
    writer   => '_set_batch_count',
    required => 1,
    isa      => Numish,
);

#--------------------------------------------------------------------------#
# emulate old API
#--------------------------------------------------------------------------#

my %OLD_API_ALIASING = (
    nInserted                => 'inserted_count',
    nUpserted                => 'upserted_count',
    nMatched                 => 'matched_count',
    nModified                => 'modified_count',
    nRemoved                 => 'deleted_count',
    writeErrors              => 'write_errors',
    writeConcernErrors       => 'write_concern_errors',
    count_writeErrors        => 'count_write_errors',
    count_writeConcernErrors => 'count_write_concern_errors',
);

while ( my ( $old, $new ) = each %OLD_API_ALIASING ) {
    no strict 'refs';
    *{$old} = \&{$new};
}

#--------------------------------------------------------------------------#
# private functions
#--------------------------------------------------------------------------#

# defines how an logical operation type gets mapped to a result
# field from the actual command result
my %op_map = (
    insert => [ inserted_count => sub { $_[0]->{n} } ],
    delete => [ deleted_count  => sub { $_[0]->{n} } ],
    update => [ matched_count  => sub { $_[0]->{n} } ],
    upsert => [ matched_count  => sub { $_[0]->{n} - @{ $_[0]->{upserted} || [] } } ],
);

my @op_map_keys = sort keys %op_map;

sub _parse_cmd_result {
    my $class = shift;
    my $args = ref $_[0] eq 'HASH' ? shift : {@_};

    unless ( 2 == grep { exists $args->{$_} } qw/op result/ ) {
        MongoDB::UsageError->throw("parse requires 'op' and 'result' arguments");
    }

    my ( $op, $op_count, $batch_count, $result, $cmd_doc, $idx_map ) =
      @{$args}{qw/op op_count batch_count result cmd_doc idx_map/};

    $result = $result->output
      if eval { $result->isa("MongoDB::CommandResult") };

    MongoDB::UsageError->throw("op argument to parse must be one of: @op_map_keys")
      unless grep { $op eq $_ } @op_map_keys;
    MongoDB::UsageError->throw("results argument to parse must be a hash reference")
      unless ref $result eq 'HASH';

    my %attrs = (
        batch_count => $batch_count || 1,
        $op_count ? ( op_count => $op_count ) : (),
        inserted_count => 0,
        upserted_count => 0,
        matched_count  => 0,
        deleted_count  => 0,
        upserted       => [],
        inserted       => [],
    );

    $attrs{write_errors} = $result->{writeErrors} ? $result->{writeErrors} : [];

    # rename writeConcernError -> write_concern_errors; coerce it to arrayref

    $attrs{write_concern_errors} =
      $result->{writeConcernError} ? [ $result->{writeConcernError} ] : [];

    # if we have upserts, change type to calculate differently
    if ( $result->{upserted} ) {
        $op                      = 'upsert';
        $attrs{upserted}       = $result->{upserted};
        $attrs{upserted_count} = @{ $result->{upserted} };
    }

    my %error_idx = (
        map { $_->{index} => 1 } @{ $result->{writeErrors} },
    );

    # recover _ids from documents
    if ( exists($result->{n}) && $op eq 'insert' ) {
        my @pairs;
        my $docs = {@$cmd_doc}->{documents};
        for my $i ( 0 .. $result->{n}-1 ) {
            next if $error_idx{$i};
            push @pairs, { index => $i, _id => $docs->[$i]{metadata}{_id} };
        }
        $attrs{inserted} = \@pairs;
    }

    # change 'n' into an op-specific count
    if ( exists $result->{n} ) {
        my ( $key, $builder ) = @{ $op_map{$op} };
        $attrs{$key} = $builder->($result);
    }

    # for an update/upsert we want the exact response whether numeric or undef
    # so that new undef responses become sticky; for all other updates, we
    # consider it 0 and let it get sorted out in the merging

    $attrs{modified_count} = ( $op eq 'update' || $op eq 'upsert' ) ?
    $result->{nModified} : 0;

    # Remap all indices back to original queue index
    # in unordered batches, these numbers can end up pointing to the wrong index
    for my $attr (qw/write_errors upserted inserted/) {
        map { $_->{index} = $idx_map->[$_->{index}] } @{ $attrs{$attr} };
    }

    return $class->_new(%attrs);
}

# these are for single results only
sub _parse_write_op {
    my $class = shift;
    my $op    = shift;

    my %attrs = (
        batch_count  => 1,
        op_count     => 1,
        write_errors => $op->write_errors,
        write_concern_errors => $op->write_concern_errors,
        inserted_count       => 0,
        upserted_count       => 0,
        matched_count        => 0,
        modified_count       => undef,
        deleted_count        => 0,
        upserted             => [],
        inserted             => [],
    );

    my $has_write_error = @{ $attrs{write_errors} };

    # parse by type
    my $type = ref($op);
    if ( $type eq 'MongoDB::InsertOneResult' ) {
        if ( $has_write_error ) {
            $attrs{inserted_count} = 0;
            $attrs{inserted} = [];
        }
        else {
            $attrs{inserted_count} = 1;
            $attrs{inserted} = [ { index => 0, _id => $op->inserted_id } ];
        }
    }
    elsif ( $type eq 'MongoDB::DeleteResult' ) {
        $attrs{deleted_count} = $op->deleted_count;
    }
    elsif ( $type eq 'MongoDB::UpdateResult' ) {
        if ( defined $op->upserted_id ) {
            my $upsert = { index => 0, _id => $op->upserted_id };
            $attrs{upserted}       = [$upsert];
            $attrs{upserted_count} = 1;
            # modified_count *must* always be defined for 2.6+ servers
            # matched_count is here for clarity and consistency
            $attrs{matched_count}  = 0;
            $attrs{modified_count} = 0;
        }
        else {
            $attrs{matched_count}  = $op->matched_count;
            $attrs{modified_count} = $op->modified_count;
        }
    }
    else {
        MongoDB::InternalError->throw("can't parse unknown result class $op");
    }

    return $class->_new(%attrs);
}

sub _merge_result {
    my ( $self, $result ) = @_;

    # Add simple counters
    for my $attr (qw/inserted_count upserted_count matched_count deleted_count/) {
        my $setter = "_set_$attr";
        $self->$setter( $self->$attr + $result->$attr );
    }

    # If modified_count is defined in both results we're merging, then we're
    # talking to a 2.6+ mongod or we're talking to a 2.6+ mongos and have only
    # seen responses with modified_count.  In any other case, we set
    # modified_count to undef, which then becomes "sticky"

    if ( defined $self->modified_count && defined $result->modified_count ) {
        $self->_set_modified_count( $self->modified_count + $result->modified_count );
    }
    else {
        $self->_set_modified_count(undef);
    }

    # Append error and upsert docs, index is dealt with in _parse_cmd_result
    for my $attr (qw/write_errors upserted inserted/) {
        push @{ $self->$attr }, @{ $result->$attr };
    }

    # Append write concern errors without modification (they have no index)
    push @{ $self->write_concern_errors }, @{ $result->write_concern_errors };

    $self->_set_op_count( $self->op_count + $result->op_count );
    $self->_set_batch_count( $self->batch_count + $result->batch_count );

    return 1;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MongoDB::BulkWriteResult - MongoDB bulk write result document

=head1 VERSION

version v2.2.2

=head1 SYNOPSIS

    # returned directly
    my $result = $bulk->execute;

    # from a WriteError or WriteConcernError
    my $result = $error->result;

    if ( $result->acknowledged ) {
        ...
    }

=head1 DESCRIPTION

This class encapsulates the results from a bulk write operation. It may be
returned directly from C<execute> or it may be in the C<result> attribute of a
C<MongoDB::DatabaseError> subclass like C<MongoDB::WriteError> or
C<MongoDB::WriteConcernError>.

=head1 ATTRIBUTES

=head2 inserted_count

Number of documents inserted

=head2 upserted_count

Number of documents upserted

=head2 matched_count

Number of documents matched for an update or replace operation.

=head2 deleted_count

Number of documents removed

=head2 modified_count

Number of documents actually modified by an update operation. This
is not necessarily the same as L</matched_count> if the document was
not actually modified as a result of the update.

This field is not available from legacy servers before version 2.6.
If results are seen from a legacy server (or from a mongos proxying
for a legacy server) this attribute will be C<undef>.

You can call C<has_modified_count> to find out if this attribute is
defined or not.

=head2 upserted

An array reference containing information about upserted documents (if any).
Each document will have the following fields:

=over 4

=item *

index — 0-based index indicating which operation failed

=item *

_id — the object ID of the upserted document

=back

=head2 upserted_ids

A hash reference built lazily from C<upserted> mapping indexes to object
IDs.

=head2 inserted

An array reference containing information about inserted documents (if any).
Documents are just as in C<upserted>.

=head2 inserted_ids

A hash reference built lazily from C<inserted> mapping indexes to object
IDs.

=head2 write_errors

An array reference containing write errors (if any).  Each error document
will have the following fields:

=over 4

=item *

index — 0-based index indicating which operation failed

=item *

code — numeric error code

=item *

errmsg — textual error string

=item *

op — a representation of the actual operation sent to the server

=back

=head2 write_concern_errors

An array reference containing write concern errors (if any).  Each error
document will have the following fields:

=over 4

=item *

index — 0-based index indicating which operation failed

=item *

code — numeric error code

=back

=head2 op_count

The number of operations sent to the database.

=head2 batch_count

The number of database commands issued to the server.  This will be less
than the C<op_count> if multiple operations were grouped together.

=head1 METHODS

=head2 assert

Throws an error if write errors or write concern errors occurred.

=head2 assert_no_write_error

Throws a MongoDB::WriteError if C<count_write_errors> is non-zero; otherwise
returns 1.

=head2 assert_no_write_concern_error

Throws a MongoDB::WriteConcernError if C<count_write_concern_errors> is
non-zero; otherwise returns 1.

=head2 count_write_errors

Returns the number of write errors

=head2 count_write_concern_errors

Returns the number of write errors

=head2 last_code

Returns the last C<code> field from either the list of C<write_errors> or
C<write_concern_errors> or 0 if there are no errors.

=head2 last_errmsg

Returns the last C<errmsg> field from either the list of C<write_errors> or
C<write_concern_errors> or the empty string if there are no errors.

=head2 last_wtimeout

True if a write concern timed out or false otherwise.

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
