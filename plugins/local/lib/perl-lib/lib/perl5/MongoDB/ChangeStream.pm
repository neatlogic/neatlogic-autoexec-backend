#  Copyright 2018 - present MongoDB, Inc.
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
package MongoDB::ChangeStream;

# ABSTRACT: A stream providing update information for collections.

use version;
our $VERSION = 'v2.2.2';

use Moo;
use MongoDB::Cursor;
use MongoDB::Op::_ChangeStream;
use MongoDB::Error;
use Safe::Isa;
use BSON::Timestamp;
use MongoDB::_Types qw(
    MongoDBCollection
    ArrayOfHashRef
    Boolish
    BSONTimestamp
    ClientSession
);
use Types::Standard qw(
    InstanceOf
    HashRef
    Maybe
    Str
    Num
);

use namespace::clean -except => 'meta';

has _result => (
    is => 'rw',
    isa => InstanceOf['MongoDB::QueryResult'],
    init_arg => undef,
);

has _client => (
    is => 'ro',
    isa => InstanceOf['MongoDB::MongoClient'],
    init_arg => 'client',
    required => 1,
);

has _op_args => (
    is => 'ro',
    isa => HashRef,
    init_arg => 'op_args',
    required => 1,
);

has _pipeline => (
    is => 'ro',
    isa => ArrayOfHashRef,
    init_arg => 'pipeline',
    required => 1,
);

has _full_document => (
    is => 'ro',
    isa => Str,
    init_arg => 'full_document',
    predicate => '_has_full_document',
);

has _resume_after => (
    is => 'ro',
    init_arg => 'resume_after',
    predicate => '_has_resume_after',
);

has _start_after => (
    is => 'ro',
    init_arg => 'start_after',
    predicate => '_has_start_after',
);

has _all_changes_for_cluster => (
    is => 'ro',
    isa => Boolish,
    init_arg => 'all_changes_for_cluster',
    default => sub { 0 },
);

has _start_at_operation_time => (
    is => 'ro',
    isa => BSONTimestamp,
    init_arg => 'start_at_operation_time',
    predicate => '_has_start_at_operation_time',
    coerce => sub {
        ref($_[0]) ? $_[0] : BSON::Timestamp->new(seconds => $_[0])
    },
);

has _session => (
    is => 'ro',
    isa => Maybe[ClientSession],
    init_arg => 'session',
);

has _options => (
    is => 'ro',
    isa => HashRef,
    init_arg => 'options',
    default => sub { {} },
);

has _max_await_time_ms => (
    is => 'ro',
    isa => Num,
    init_arg => 'max_await_time_ms',
    predicate => '_has_max_await_time_ms',
);

has _last_operation_time => (
    is => 'rw',
    init_arg => undef,
    predicate => '_has_last_operation_time',
);

has _last_resume_token => (
    is => 'rw',
    init_arg => undef,
    predicate => '_has_last_resume_token',
);

sub BUILD {
    my ($self) = @_;

    # starting point is construction time instead of first next call
    $self->_execute_query;
}

sub _execute_query {
    my ($self) = @_;

    my $resume_opt = {};

    # seen prior results, continuing after last resume token
    if ($self->_has_last_resume_token) {
        $resume_opt->{resume_after} = $self->_last_resume_token;
    }
    elsif ( $self->_has_start_after ) {
        $self->_last_resume_token(
            $resume_opt->{start_after} = $self->_start_after
        );
    }
    # no results yet, but we have operation time from prior query
    elsif ($self->_has_last_operation_time) {
        $resume_opt->{start_at_operation_time} = $self->_last_operation_time;
    }
    # no results and no prior operation time, send specified options
    else {
        $resume_opt->{start_at_operation_time} = $self->_start_at_operation_time
            if $self->_has_start_at_operation_time;
        if ( $self->_has_resume_after ) {
            $self->_last_resume_token(
                $resume_opt->{resume_after} = $self->_resume_after
            );
        }
    }

    my $op = MongoDB::Op::_ChangeStream->new(
        pipeline => $self->_pipeline,
        all_changes_for_cluster => $self->_all_changes_for_cluster,
        session => $self->_session,
        options => $self->_options,
        client => $self->_client,
        $self->_has_full_document
            ? (full_document => $self->_full_document)
            : (),
        $self->_has_max_await_time_ms
            ? (maxAwaitTimeMS => $self->_max_await_time_ms)
            : (),
        %$resume_opt,
        %{ $self->_op_args },
    );

    my $res = $self->_client->send_retryable_read_op($op);
    $self->_result($res->{result});
    $self->_last_operation_time($res->{operationTime})
        if exists $res->{operationTime};
}

#pod =head1 STREAM METHODS
#pod
#pod =cut

#pod =head2 next
#pod
#pod     $change_stream = $collection->watch(...);
#pod     $change = $change_stream->next;
#pod
#pod Waits for the next change in the collection and returns it.
#pod
#pod B<Note>: This method will wait for the amount of milliseconds passed
#pod as C<maxAwaitTimeMS> to L<MongoDB::Collection/watch> or the server's
#pod default wait-time. It will not wait indefinitely.
#pod
#pod =cut

sub next {
    my ($self) = @_;

    my $change;
    my $retried;
    while (1) {
        last if eval {
            $change = $self->_result->next;
            1; # successfully fetched result
        } or do {
            my $error = $@ || "Unknown error";
            if (
                not($retried)
                and $error->$_isa('MongoDB::Error')
                and $error->_is_resumable
            ) {
                $retried = 1;
                $self->_execute_query;
            }
            else {
                die $error;
            }
            0; # failed, cursor was rebuilt
        };
    }

    # this differs from drivers that block indefinitely. we have to
    # deal with the situation where no results are available.
    if (not defined $change) {
        return undef; ## no critic
    }

    if (exists $change->{'postBatchResumeToken'}) {
        $self->_last_resume_token( $change->{'postBatchResumeToken'} );
        return $change;
    }
    elsif (exists $change->{_id}) {
        $self->_last_resume_token( $change->{_id} );
        return $change;
    }
    else {
        MongoDB::InvalidOperationError->throw(
            "Cannot provide resume functionality when the ".
            "resume token is missing");
    }
}

#pod =head2 get_resume_token
#pod
#pod Users can inspect the C<_id> on each C<ChangeDocument> to use as a
#pod resume token. But since MongoDB 4.2, C<aggregate> and C<getMore> responses
#pod also include a C<postBatchResumeToken>. Drivers use one or the other
#pod when automatically resuming.
#pod
#pod This method retrieves the same resume token that would be used to
#pod automatically resume. Users intending to store the resume token
#pod should use this method to get the most up to date resume token.
#pod
#pod For instance:
#pod
#pod     if ($local_change) {
#pod         process_change($local_change);
#pod     }
#pod
#pod     eval {
#pod         my $change_stream = $coll->watch([], { resumeAfter => $local_resume_token });
#pod         while ( my $change = $change_stream->next) {
#pod             $local_resume_token = $change_stream->get_resume_token;
#pod             $local_change = $change;
#pod             process_change($local_change);
#pod         }
#pod     };
#pod     if (my $err = $@) {
#pod         $log->error($err);
#pod     }
#pod
#pod In this case the current change is always persisted locally,
#pod including the resume token, such that on restart the application
#pod can still process the change while ensuring that the change stream
#pod continues from the right logical time in the oplog. It is the
#pod application's responsibility to ensure that C<process_change> is
#pod idempotent, this design merely makes a reasonable effort to process
#pod each change at least once.
#pod
#pod =cut

sub get_resume_token { $_[0]->_last_resume_token }

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MongoDB::ChangeStream - A stream providing update information for collections.

=head1 VERSION

version v2.2.2

=head1 SYNOPSIS

    $stream = $collection->watch( $pipeline, $options );
    while(1) {

        # This inner loop will only iterate until there are no more
        # changes available.
        while (my $change = $stream->next) {
            ...
        }
    }

=head1 DESCRIPTION

This class models change stream results as returned by the
L<MongoDB::Collection/watch> method.

=head1 STREAM METHODS

=head2 next

    $change_stream = $collection->watch(...);
    $change = $change_stream->next;

Waits for the next change in the collection and returns it.

B<Note>: This method will wait for the amount of milliseconds passed
as C<maxAwaitTimeMS> to L<MongoDB::Collection/watch> or the server's
default wait-time. It will not wait indefinitely.

=head2 get_resume_token

Users can inspect the C<_id> on each C<ChangeDocument> to use as a
resume token. But since MongoDB 4.2, C<aggregate> and C<getMore> responses
also include a C<postBatchResumeToken>. Drivers use one or the other
when automatically resuming.

This method retrieves the same resume token that would be used to
automatically resume. Users intending to store the resume token
should use this method to get the most up to date resume token.

For instance:

    if ($local_change) {
        process_change($local_change);
    }

    eval {
        my $change_stream = $coll->watch([], { resumeAfter => $local_resume_token });
        while ( my $change = $change_stream->next) {
            $local_resume_token = $change_stream->get_resume_token;
            $local_change = $change;
            process_change($local_change);
        }
    };
    if (my $err = $@) {
        $log->error($err);
    }

In this case the current change is always persisted locally,
including the resume token, such that on restart the application
can still process the change while ensuring that the change stream
continues from the right logical time in the oplog. It is the
application's responsibility to ensure that C<process_change> is
idempotent, this design merely makes a reasonable effort to process
each change at least once.

=head1 SEE ALSO

The L<Change Streams manual section|https://docs.mongodb.com/manual/changeStreams/>.

The L<Change Streams specification|https://github.com/mongodb/specifications/blob/master/source/change-streams.rst>.

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
