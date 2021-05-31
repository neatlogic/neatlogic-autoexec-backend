#  Copyright 2012 - present MongoDB, Inc.
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
package MongoDB::MongoClient;

# ABSTRACT: A connection to a MongoDB server or multi-server deployment

use version;
our $VERSION = 'v2.2.2';

use Moo;
use MongoDB::ClientSession;
use MongoDB::Cursor;
use MongoDB::Error;
use MongoDB::Op::_Command;
use MongoDB::Op::_FSyncUnlock;
use MongoDB::ReadConcern;
use MongoDB::ReadPreference;
use MongoDB::WriteConcern;
use MongoDB::_Constants;
use MongoDB::_Credential;
use MongoDB::_Dispatcher;
use MongoDB::_SessionPool;
use MongoDB::_Topology;
use MongoDB::_URI;
use BSON 1.012000;
use Digest::MD5;
use UUID::URandom;
use Tie::IxHash;
use Time::HiRes qw/usleep/;
use Carp 'carp', 'croak', 'confess';
use Safe::Isa 1.000007;
use Scalar::Util qw/reftype weaken/;
use boolean;
use Encode;
use MongoDB::_Types qw(
    ArrayOfHashRef
    AuthMechanism
    Boolish
    BSONCodec
    CompressionType
    Document
    HeartbeatFreq
    MaxStalenessNum
    NonNegNum
    ReadPrefMode
    ReadPreference
    ZlibCompressionLevel
);
use Types::Standard qw(
    CodeRef
    HashRef
    ArrayRef
    InstanceOf
    Undef
    Int
    Num
    Str
    Maybe
);

use namespace::clean -except => 'meta';

#--------------------------------------------------------------------------#
# public attributes
#
# Of these, only host, port and bson_codec are set without regard for
# connection string options.  The rest are built lazily in BUILD so that
# option precedence can be resolved.
#--------------------------------------------------------------------------#

#pod =attr host
#pod
#pod The C<host> attribute specifies either a single server to connect to (as
#pod C<hostname> or C<hostname:port>), or else a L<connection string URI|/CONNECTION
#pod STRING URI> with a seed list of one or more servers plus connection options.
#pod
#pod B<NOTE>: Options specified in the connection string take precedence over options
#pod provided as constructor arguments.
#pod
#pod Defaults to the connection string URI C<mongodb://localhost:27017>.
#pod
#pod For IPv6 support, you must have a recent version of L<IO::Socket::IP>
#pod installed.  This module ships with the Perl core since v5.20.0 and is
#pod available on CPAN for older Perls.
#pod
#pod =cut

has host => (
    is      => 'ro',
    isa     => Str,
    default => 'mongodb://localhost:27017',
);

#pod =attr app_name
#pod
#pod This attribute specifies an application name that should be associated with
#pod this client.  The application name will be communicated to the server as
#pod part of the initial connection handshake, and will appear in
#pod connection-level and operation-level diagnostics on the server generated on
#pod behalf of this client.  This may be set in a connection string with the
#pod C<appName> option.
#pod
#pod The default is the empty string, which indicates a lack of an application
#pod name.
#pod
#pod The application name must not exceed 128 bytes.
#pod
#pod =cut

has app_name => (
    is  => 'lazy',
    isa => Str,
    builder => '_build_app_name',
);

sub _build_app_name {
    my ($self) = @_;
    my $app_name = $self->__uri_or_else(
        u => 'appname',
        e => 'app_name',
        d => '',
    );
    unless ( length($app_name) <= 128 ) {
        MongoDB::UsageError->throw("app name must be at most 128 bytes");
    }
    return $app_name;
}

#pod =attr auth_mechanism
#pod
#pod This attribute determines how the client authenticates with the server.
#pod Valid values are:
#pod
#pod =for :list
#pod * NONE
#pod * DEFAULT
#pod * MONGODB-CR
#pod * MONGODB-X509
#pod * GSSAPI
#pod * PLAIN
#pod * SCRAM-SHA-1
#pod
#pod If not specified, then if no username or C<authSource> URI option is provided,
#pod it defaults to NONE.  Otherwise, it is set to DEFAULT, which chooses
#pod SCRAM-SHA-1 if available or MONGODB-CR otherwise.
#pod
#pod This may be set in a connection string with the C<authMechanism> option.
#pod
#pod =cut

has auth_mechanism => (
    is      => 'lazy',
    isa     => AuthMechanism,
    builder => '_build_auth_mechanism',
);

sub _build_auth_mechanism {
    my ($self) = @_;

    my $source = $self->_uri->options->{authsource} // "";
    my $default = length( $self->username ) || length($source) ? 'DEFAULT' : 'NONE';

    return $self->__uri_or_else(
        u => 'authmechanism',
        e => 'auth_mechanism',
        d => $default,
    );
}

#pod =attr auth_mechanism_properties
#pod
#pod This is an optional hash reference of authentication mechanism specific properties.
#pod See L</AUTHENTICATION> for details.
#pod
#pod This may be set in a connection string with the C<authMechanismProperties>
#pod option.  If given, the value must be key/value pairs joined with a ":".
#pod Multiple pairs must be separated by a comma.  If ": or "," appear in a key or
#pod value, they must be URL encoded.
#pod
#pod =cut

has auth_mechanism_properties => (
    is      => 'lazy',
    isa     => HashRef,
    builder => '_build_auth_mechanism_properties',
);

sub _build_auth_mechanism_properties {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'authmechanismproperties',
        e => 'auth_mechanism_properties',
        d => {},
    );
}

#pod =attr bson_codec
#pod
#pod An object that provides the C<encode_one> and C<decode_one> methods, such as
#pod from L<BSON>.  It may be initialized with a hash reference that will
#pod be coerced into a new L<BSON> object.
#pod
#pod If not provided, a L<BSON> object with default values will be generated.
#pod
#pod =cut

has bson_codec => (
    is      => 'lazy',
    isa     => BSONCodec,
    coerce  => BSONCodec->coercion,
    writer  => '_set_bson_codec',
    builder => '_build_bson_codec',
);

sub _build_bson_codec {
    my ($self) = @_;
    return BSON->new();
}

#pod =attr compressors
#pod
#pod An array reference of compression type names. Currently, C<zlib>, C<zstd> and
#pod C<snappy> are supported.
#pod
#pod =cut

has compressors => (
    is      => 'lazy',
    isa     => ArrayRef[CompressionType],
    builder => '_build_compressors',
);

sub _build_compressors {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'compressors',
        e => 'compressors',
        d => [],
    );
}

#pod =attr zlib_compression_level
#pod
#pod An integer from C<-1> to C<9> specifying the compression level to use
#pod when L</compression> is set to C<zlib>.
#pod
#pod B<Note>: When the special value C<-1> is given, the default compression
#pod level will be used.
#pod
#pod =cut

has zlib_compression_level => (
    is      => 'lazy',
    isa     => ZlibCompressionLevel,
    builder => '_build_zlib_compression_level',
);

sub _build_zlib_compression_level {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'zlibcompressionlevel',
        e => 'zlib_compression_level',
        d => -1,
    );
}

#pod =attr connect_timeout_ms
#pod
#pod This attribute specifies the amount of time in milliseconds to wait for a
#pod new connection to a server.
#pod
#pod The default is 10,000 ms.
#pod
#pod If set to a negative value, connection operations will block indefinitely
#pod until the server replies or until the operating system TCP/IP stack gives
#pod up (e.g. if the name can't resolve or there is no process listening on the
#pod target host/port).
#pod
#pod A zero value polls the socket during connection and is thus likely to fail
#pod except when talking to a local process (and perhaps even then).
#pod
#pod This may be set in a connection string with the C<connectTimeoutMS> option.
#pod
#pod =cut

has connect_timeout_ms => (
    is      => 'lazy',
    isa     => Num,
    builder => '_build_connect_timeout_ms',
);

sub _build_connect_timeout_ms {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'connecttimeoutms',
        e => 'connect_timeout_ms',
        d => 10000,
    );
}

#pod =attr db_name
#pod
#pod Optional.  If an L</auth_mechanism> requires a database for authentication,
#pod this attribute will be used.  Otherwise, it will be ignored. Defaults to
#pod "admin".
#pod
#pod This may be provided in the L<connection string URI|/CONNECTION STRING URI> as
#pod a path between the authority and option parameter sections.  For example, to
#pod authenticate against the "admin" database (showing a configuration option only
#pod for illustration):
#pod
#pod     mongodb://localhost/admin?readPreference=primary
#pod
#pod =cut

has db_name => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_db_name',
);

sub _build_db_name {
    my ($self) = @_;
    return __string( $self->_uri->db_name, $self->_deferred->{db_name} );
}

#pod =attr heartbeat_frequency_ms
#pod
#pod The time in milliseconds (non-negative) between scans of all servers to
#pod check if they are up and update their latency.  Defaults to 60,000 ms.
#pod
#pod This may be set in a connection string with the C<heartbeatFrequencyMS> option.
#pod
#pod =cut

has heartbeat_frequency_ms => (
    is      => 'lazy',
    isa     => HeartbeatFreq,
    builder => '_build_heartbeat_frequency_ms',
);

sub _build_heartbeat_frequency_ms {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'heartbeatfrequencyms',
        e => 'heartbeat_frequency_ms',
        d => 60000,
    );
}

#pod =attr j
#pod
#pod If true, the client will block until write operations have been committed to the
#pod server's journal. Prior to MongoDB 2.6, this option was ignored if the server was
#pod running without journaling. Starting with MongoDB 2.6, write operations will fail
#pod if this option is used when the server is running without journaling.
#pod
#pod This may be set in a connection string with the C<journal> option as the
#pod strings 'true' or 'false'.
#pod
#pod =cut

has j => (
    is      => 'lazy',
    isa     => Boolish,
    builder => '_build_j',
);

sub _build_j {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'journal',
        e => 'j',
        d => undef,
    );
}

#pod =attr local_threshold_ms
#pod
#pod The width of the 'latency window': when choosing between multiple suitable
#pod servers for an operation, the acceptable delta in milliseconds
#pod (non-negative) between shortest and longest average round-trip times.
#pod Servers within the latency window are selected randomly.
#pod
#pod Set this to "0" to always select the server with the shortest average round
#pod trip time.  Set this to a very high value to always randomly choose any known
#pod server.
#pod
#pod Defaults to 15 ms.
#pod
#pod See L</SERVER SELECTION> for more details.
#pod
#pod This may be set in a connection string with the C<localThresholdMS> option.
#pod
#pod =cut

has local_threshold_ms => (
    is      => 'lazy',
    isa     => NonNegNum,
    builder => '_build_local_threshold_ms',
);

sub _build_local_threshold_ms {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'localthresholdms',
        e => 'local_threshold_ms',
        d => 15,
    );
}

#pod =attr max_staleness_seconds
#pod
#pod The C<max_staleness_seconds> parameter represents the maximum replication lag in
#pod seconds (wall clock time) that a secondary can suffer and still be
#pod eligible for reads. The default is -1, which disables staleness checks.
#pod Otherwise, it must be a positive integer.
#pod
#pod B<Note>: this will only be used for server versions 3.4 or greater, as that
#pod was when support for staleness tracking was added.
#pod
#pod If the read preference mode is 'primary', then C<max_staleness_seconds> must not
#pod be supplied.
#pod
#pod The C<max_staleness_seconds> must be at least the C<heartbeat_frequency_ms>
#pod plus 10 seconds (which is how often the server makes idle writes to the
#pod oplog).
#pod
#pod This may be set in a connection string with the C<maxStalenessSeconds> option.
#pod
#pod =cut

has max_staleness_seconds => (
    is      => 'lazy',
    isa     => MaxStalenessNum,
    builder => '_build_max_staleness_seconds',
);

sub _build_max_staleness_seconds {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'maxstalenessseconds',
        e => 'max_staleness_seconds',
        d => -1,
    );
}

#pod =attr max_time_ms
#pod
#pod Specifies the maximum amount of time in (non-negative) milliseconds that the
#pod server should use for working on a database command.  Defaults to 0, which disables
#pod this feature.  Make sure this value is shorter than C<socket_timeout_ms>.
#pod
#pod B<Note>: this will only be used for server versions 2.6 or greater, as that
#pod was when the C<$maxTimeMS> meta-operator was introduced.
#pod
#pod You are B<strongly> encouraged to set this variable if you know your
#pod environment has MongoDB 2.6 or later, as getting a definitive error response
#pod from the server is vastly preferred over a getting a network socket timeout.
#pod
#pod This may be set in a connection string with the C<maxTimeMS> option.
#pod
#pod =cut

has max_time_ms => (
    is      => 'lazy',
    isa     => NonNegNum,
    builder => '_build_max_time_ms',
);

sub _build_max_time_ms {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'maxtimems',
        e => 'max_time_ms',
        d => 0,
    );
}

#pod =attr monitoring_callback
#pod
#pod Specifies a code reference used to receive monitoring events.  See
#pod L<MongoDB::Monitoring> for more details.
#pod
#pod =cut

has monitoring_callback => (
    is  => 'ro',
    isa => Maybe [CodeRef],
);

#pod =attr password
#pod
#pod If an L</auth_mechanism> requires a password, this attribute will be
#pod used.  Otherwise, it will be ignored.
#pod
#pod This may be provided in the L<connection string URI|/CONNECTION STRING URI> as
#pod a C<username:password> pair in the leading portion of the authority section
#pod before a C<@> character.  For example, to authenticate as user "mulder" with
#pod password "trustno1":
#pod
#pod     mongodb://mulder:trustno1@localhost
#pod
#pod If the username or password have a ":" or "@" in it, they must be URL encoded.
#pod An empty password still requires a ":" character.
#pod
#pod =cut

has password => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_password',
);

sub _build_password {
    my ($self) = @_;
    return
        defined( $self->_uri->password )        ? $self->_uri->password
      : defined( $self->_deferred->{password} ) ? $self->_deferred->{password}
      :                                           '';
}

#pod =attr port
#pod
#pod If a network port is not specified as part of the C<host> attribute, this
#pod attribute provides the port to use.  It defaults to 27107.
#pod
#pod =cut

has port => (
    is      => 'ro',
    isa     => Int,
    default => 27017,
);

#pod =attr read_concern_level
#pod
#pod The read concern level determines the consistency level required
#pod of data being read.
#pod
#pod The default level is C<undef>, which means the server will use its configured
#pod default.
#pod
#pod If the level is set to "local", reads will return the latest data a server has
#pod locally.
#pod
#pod Additional levels are storage engine specific.  See L<Read
#pod Concern|http://docs.mongodb.org/manual/search/?query=readConcern> in the MongoDB
#pod documentation for more details.
#pod
#pod This may be set in a connection string with the the C<readConcernLevel> option.
#pod
#pod =cut

has read_concern_level => (
    is      => 'lazy',
    isa     => Maybe [Str],
    builder => '_build_read_concern_level',
);

sub _build_read_concern_level {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'readconcernlevel',
        e => 'read_concern_level',
        d => undef,
    );
}

#pod =attr read_pref_mode
#pod
#pod The read preference mode determines which server types are candidates
#pod for a read operation.  Valid values are:
#pod
#pod =for :list
#pod * primary
#pod * primaryPreferred
#pod * secondary
#pod * secondaryPreferred
#pod * nearest
#pod
#pod For core documentation on read preference see
#pod L<http://docs.mongodb.org/manual/core/read-preference/>.
#pod
#pod This may be set in a connection string with the C<readPreference> option.
#pod
#pod =cut

has read_pref_mode => (
    is      => 'lazy',
    isa     => ReadPrefMode,
    coerce  => ReadPrefMode->coercion,
    builder => '_build_read_pref_mode',
);

sub _build_read_pref_mode {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'readpreference',
        e => 'read_pref_mode',
        d => 'primary',
    );
}

#pod =attr read_pref_tag_sets
#pod
#pod The C<read_pref_tag_sets> parameter is an ordered list of tag sets used to
#pod restrict the eligibility of servers, such as for data center awareness.  It
#pod must be an array reference of hash references.
#pod
#pod The application of C<read_pref_tag_sets> varies depending on the
#pod C<read_pref_mode> parameter.  If the C<read_pref_mode> is 'primary', then
#pod C<read_pref_tag_sets> must not be supplied.
#pod
#pod For core documentation on read preference see
#pod L<http://docs.mongodb.org/manual/core/read-preference/>.
#pod
#pod This may be set in a connection string with the C<readPreferenceTags> option.
#pod If given, the value must be key/value pairs joined with a ":".  Multiple pairs
#pod must be separated by a comma.  If ": or "," appear in a key or value, they must
#pod be URL encoded.  The C<readPreferenceTags> option may appear more than once, in
#pod which case each document will be added to the tag set list.
#pod
#pod =cut

has read_pref_tag_sets => (
    is      => 'lazy',
    isa     => ArrayOfHashRef,
    coerce  => ArrayOfHashRef->coercion,
    builder => '_build_read_pref_tag_sets',
);

sub _build_read_pref_tag_sets {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'readpreferencetags',
        e => 'read_pref_tag_sets',
        d => [ {} ],
    );
}

#pod =attr replica_set_name
#pod
#pod Specifies the replica set name to connect to.  If this string is non-empty,
#pod then the topology is treated as a replica set and all server replica set
#pod names must match this or they will be removed from the topology.
#pod
#pod This may be set in a connection string with the C<replicaSet> option.
#pod
#pod =cut

has replica_set_name => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_replica_set_name',
);

sub _build_replica_set_name {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'replicaset',
        e => 'replica_set_name',
        d => '',
    );
}

#pod =attr retry_reads
#pod
#pod =cut

has retry_reads => (
    is      => 'lazy',
    isa     => Boolish,
    builder => '_build_retry_reads',
);

sub _build_retry_reads {
    my ( $self ) = @_;
    return $self->__uri_or_else(
        u => 'retryreads',
        e => 'retry_reads',
        d => 1,
    );
}

#pod =attr retry_writes
#pod
#pod Whether the client should use retryable writes for supported commands. The
#pod default value is true, which means that commands which support retryable writes
#pod will be retried on certain errors, such as C<not master> and C<node is
#pod recovering> errors.
#pod
#pod This may be set in a connection string with the C<retryWrites> option.
#pod
#pod Note that this is only supported on MongoDB > 3.6 in Replica Set or Shard
#pod Clusters, and will be ignored on other deployments.
#pod
#pod Unacknowledged write operations also do not support retryable writes, even when
#pod retry_writes has been enabled.
#pod
#pod The supported single statement write operations are currently as follows:
#pod
#pod =for :list
#pod * C<insert_one>
#pod * C<update_one>
#pod * C<replace_one>
#pod * C<delete_one>
#pod * C<find_one_and_delete>
#pod * C<find_one_and_replace>
#pod * C<find_one_and_update>
#pod
#pod The supported multi statement write operations are as follows:
#pod
#pod =for :list
#pod * C<insert_many>
#pod * C<bulk_write>
#pod
#pod The multi statement operations may be ether ordered or unordered. Note that for
#pod C<bulk_write> operations, the request may not include update_many or
#pod delete_many operations.
#pod
#pod =cut

has retry_writes => (
    is      => 'lazy',
    isa     => Boolish,
    builder => '_build_retry_writes',
);

sub _build_retry_writes {
    my ( $self ) = @_;
    return $self->__uri_or_else(
        u => 'retrywrites',
        e => 'retry_writes',
        d => 1,
    );
}

#pod =attr server_selection_timeout_ms
#pod
#pod This attribute specifies the amount of time in milliseconds to wait for a
#pod suitable server to be available for a read or write operation.  If no
#pod server is available within this time period, an exception will be thrown.
#pod
#pod The default is 30,000 ms.
#pod
#pod See L</SERVER SELECTION> for more details.
#pod
#pod This may be set in a connection string with the C<serverSelectionTimeoutMS>
#pod option.
#pod
#pod =cut

has server_selection_timeout_ms => (
    is      => 'lazy',
    isa     => Num,
    builder => '_build_server_selection_timeout_ms',
);

sub _build_server_selection_timeout_ms {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'serverselectiontimeoutms',
        e => 'server_selection_timeout_ms',
        d => 30000,
    );
}

#pod =attr server_selection_try_once
#pod
#pod This attribute controls whether the client will make only a single attempt
#pod to find a suitable server for a read or write operation.  The default is true.
#pod
#pod When true, the client will B<not> use the C<server_selection_timeout_ms>.
#pod Instead, if the topology information is stale and needs to be checked or
#pod if no suitable server is available, the client will make a single
#pod scan of all known servers to try to find a suitable one.
#pod
#pod When false, the client will continually scan known servers until a suitable
#pod server is found or the C<serverSelectionTimeoutMS> is reached.
#pod
#pod See L</SERVER SELECTION> for more details.
#pod
#pod This may be set in a connection string with the C<serverSelectionTryOnce>
#pod option.
#pod
#pod =cut

has server_selection_try_once => (
    is      => 'lazy',
    isa     => Boolish,
    builder => '_build_server_selection_try_once',
);

sub _build_server_selection_try_once {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'serverselectiontryonce',
        e => 'server_selection_try_once',
        d => 1,
    );
}

#pod =attr server_selector
#pod
#pod Optional. This takes a function that augments the server selection rules.
#pod The function takes as a parameter a list of server descriptions representing
#pod the suitable servers for the read or write operation, and returns a list of
#pod server descriptions that should still be considered suitable. Most users
#pod should rely on the default server selection algorithm and should not need
#pod to set this attribute.
#pod
#pod =cut

has server_selector => (
    is  => 'ro',
    isa => Maybe[CodeRef],
);

#pod =attr socket_check_interval_ms
#pod
#pod If a socket to a server has not been used in this many milliseconds, an
#pod C<ismaster> command will be issued to check the status of the server before
#pod issuing any reads or writes. Must be non-negative.
#pod
#pod The default is 5,000 ms.
#pod
#pod This may be set in a connection string with the C<socketCheckIntervalMS>
#pod option.
#pod
#pod =cut

has socket_check_interval_ms => (
    is      => 'lazy',
    isa     => NonNegNum,
    builder => '_build_socket_check_interval_ms',
);

sub _build_socket_check_interval_ms {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'socketcheckintervalms',
        e => 'socket_check_interval_ms',
        d => 5000,
    );
}

#pod =attr socket_timeout_ms
#pod
#pod This attribute specifies the amount of time in milliseconds to wait for a
#pod reply from the server before issuing a network exception.
#pod
#pod The default is 30,000 ms.
#pod
#pod If set to a negative value, socket operations will block indefinitely
#pod until the server replies or until the operating system TCP/IP stack
#pod gives up.
#pod
#pod The driver automatically sets the TCP keepalive option when initializing the
#pod socket. For keepalive related issues, check the MongoDB documentation for
#pod L<Does TCP keepalive time affect MongoDB Deployments?|https://docs.mongodb.com/v3.2/faq/diagnostics/#does-tcp-keepalive-time-affect-mongodb-deployments>.
#pod
#pod A zero value polls the socket for available data and is thus likely to fail
#pod except when talking to a local process (and perhaps even then).
#pod
#pod This may be set in a connection string with the C<socketTimeoutMS> option.
#pod
#pod =cut

has socket_timeout_ms => (
    is      => 'lazy',
    isa     => Num,
    builder => '_build_socket_timeout_ms',
);

sub _build_socket_timeout_ms {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'sockettimeoutms',
        e => 'socket_timeout_ms',
        d => 30000,
    );
}

#pod =attr ssl
#pod
#pod     ssl => 1
#pod     ssl => \%ssl_options
#pod
#pod This tells the driver that you are connecting to an SSL mongodb instance.
#pod
#pod You must have L<IO::Socket::SSL> 1.42+ and L<Net::SSLeay> 1.49+ installed for
#pod SSL support.
#pod
#pod The C<ssl> attribute takes either a boolean value or a hash reference of
#pod options to pass to IO::Socket::SSL.  For example, to set a CA file to validate
#pod the server certificate and set a client certificate for the server to validate,
#pod you could set the attribute like this:
#pod
#pod     ssl => {
#pod         SSL_ca_file   => "/path/to/ca.pem",
#pod         SSL_cert_file => "/path/to/client.pem",
#pod     }
#pod
#pod If C<SSL_ca_file> is not provided, server certificates are verified against a
#pod default list of CAs, either L<Mozilla::CA> or an operating-system-specific
#pod default CA file.  To disable verification, you can use
#pod C<< SSL_verify_mode => 0x00 >>.
#pod
#pod B<You are strongly encouraged to use your own CA file for increased security>.
#pod
#pod Server hostnames are also validated against the CN name in the server
#pod certificate using C<< SSL_verifycn_scheme => 'http' >>.  You can use the
#pod scheme 'none' to disable this check.
#pod
#pod B<Disabling certificate or hostname verification is a security risk and is not
#pod recommended>.
#pod
#pod This may be set to the string 'true' or 'false' in a connection string with the
#pod C<ssl> option, which will enable ssl with default configuration.  (See
#pod L<connection string URI|/CONNECTION STRING URI> for additional TLS
#pod configuration options.)
#pod
#pod =cut

has ssl => (
    is      => 'lazy',
    isa     => Boolish|HashRef,
    builder => '_build_ssl',
);

sub _build_ssl {
    my ($self) = @_;

    # options will be undef if not provided
    my $uri_ssl = $self->__ssl_from_uri();
    my $opt_ssl = exists $self->_deferred->{ssl} ? $self->_deferred->{ssl} : undef;

    # no SSL options exist
    if ( !defined $uri_ssl && !defined $opt_ssl ) {
        return 0;
    }

    # validate deferred ssl arg type
    if ( ref $opt_ssl && ref $opt_ssl ne 'HASH' ) {
        MongoDB::UsageError->throw("ssl attribute must be scalar or hashref")
    }

    # no URI SSL defined means use opts SSL
    if ( !defined $uri_ssl ) {
        return $opt_ssl;
    }

    # if URI SSL is false, that takes precedence
    if ( ! $uri_ssl ) {
        return $uri_ssl;
    }

    # if opt SSL isn't a hashref, it's irrelevant
    if ( ref $opt_ssl ne 'HASH' ) {
        return $uri_ssl;
    }

    # if uri SSL isn't a hashref, we prefer opt SSL hashref
    if ( ref $uri_ssl ne 'HASH' ) {
        return $opt_ssl;
    }

    # both are hashes, so merge them with URI taking precedence
    return { %$opt_ssl, %$uri_ssl };
}

my @tls_options = qw(
    tlsallowinvalidcertificates
    tlsallowinvalidhostnames
    tlscafile
    tlscertificatekeyfile
    tlscertificatekeyfilepassword
    tlsinsecure
);

sub __ssl_from_uri {
    my ($self) = @_;
    my $uri_options = $self->_uri->options;
    my $saw_tls_boolean = exists $uri_options->{tls};
    my $saw_tls_options = grep { length } map { exists $uri_options->{$_} } @tls_options;

    if (!$saw_tls_options) {
        return $saw_tls_boolean ? $uri_options->{tls} : undef;
    }

    my $ssl = {};
    if (exists($uri_options->{tlscafile})) {
        $ssl->{SSL_ca_file} = $uri_options->{tlscafile};
    }
    if (exists($uri_options->{tlscertificatekeyfile})) {
        $ssl->{SSL_cert_file} = $uri_options->{tlscertificatekeyfile};
    }
    if (exists($uri_options->{tlscertificatekeyfilepassword})) {
        $ssl->{SSL_passwd_cb} = sub { $uri_options->{tlscertificatekeyfilepassword} };
    }
    if (exists($uri_options->{tlsallowinvalidhostnames})) {
        $ssl->{SSL_verifycn_scheme} = 'none';
    }
    if (exists($uri_options->{tlsallowinvalidcertificates})) {
        $ssl->{SSL_verify_mode} = 0x00;
    }
    if (exists($uri_options->{tlsinsecure})) {
        $ssl->{SSL_verify_mode} = 0x00;
        $ssl->{SSL_verifycn_scheme} = 'none';
    }
    return $ssl;
}

#pod =attr username
#pod
#pod Optional username for this client connection.  If this field is set, the client
#pod will attempt to authenticate when connecting to servers.  Depending on the
#pod L</auth_mechanism>, the L</password> field or other attributes will need to be
#pod set for authentication to succeed.
#pod
#pod This may be provided in the L<connection string URI|/CONNECTION STRING URI> as
#pod a C<username:password> pair in the leading portion of the authority section
#pod before a C<@> character.  For example, to authenticate as user "mulder" with
#pod password "trustno1":
#pod
#pod     mongodb://mulder:trustno1@localhost
#pod
#pod If the username or password have a ":" or "@" in it, they must be URL encoded.
#pod An empty password still requires a ":" character.
#pod
#pod =cut

has username => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_username',
);

sub _build_username {
    my ($self) = @_;

    return
        defined( $self->_uri->username )        ? $self->_uri->username
      : defined( $self->_deferred->{username} ) ? $self->_deferred->{username}
      :                                           '';
}

#pod =attr w
#pod
#pod The client I<write concern>.
#pod
#pod =over 4
#pod
#pod =item * C<0> Unacknowledged. MongoClient will B<NOT> wait for an acknowledgment that
#pod the server has received and processed the request. Older documentation may refer
#pod to this as "fire-and-forget" mode.  This option is not recommended.
#pod
#pod =item * C<1> Acknowledged. MongoClient will wait until the
#pod primary MongoDB acknowledges the write.
#pod
#pod =item * C<2> Replica acknowledged. MongoClient will wait until at least two
#pod replicas (primary and one secondary) acknowledge the write. You can set a higher
#pod number for more replicas.
#pod
#pod =item * C<all> All replicas acknowledged.
#pod
#pod =item * C<majority> A majority of replicas acknowledged.
#pod
#pod =back
#pod
#pod If not set, the server default is used, which is typically "1".
#pod
#pod In MongoDB v2.0+, you can "tag" replica members. With "tagging" you can
#pod specify a custom write concern For more information see L<Data Center
#pod Awareness|http://docs.mongodb.org/manual/data-center-awareness/>
#pod
#pod This may be set in a connection string with the C<w> option.
#pod
#pod =cut

has w => (
    is      => 'lazy',
    isa     => Int|Str|Undef,
    builder => '_build_w',
);

sub _build_w {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'w',
        e => 'w',
        d => undef,
    );
}

#pod =attr wtimeout
#pod
#pod The number of milliseconds an operation should wait for C<w> secondaries to
#pod replicate it.
#pod
#pod Defaults to 1000 (1 second). If you set this to undef, it could block indefinitely
#pod (or until socket timeout is reached).
#pod
#pod See C<w> above for more information.
#pod
#pod This may be set in a connection string with the C<wTimeoutMS> option.
#pod
#pod =cut

has wtimeout => (
    is      => 'lazy',
    isa     => Maybe[Int],
    builder => '_build_wtimeout',
);

sub _build_wtimeout {
    my ($self) = @_;
    return $self->__uri_or_else(
        u => 'wtimeoutms',
        e => 'wtimeout',
        d => 1000,
    );
}

#--------------------------------------------------------------------------#
# computed attributes - these are private and can't be set in the
# constructor, but have a public accessor
#--------------------------------------------------------------------------#

#pod =method read_preference
#pod
#pod Returns a L<MongoDB::ReadPreference> object constructed from
#pod L</read_pref_mode> and L</read_pref_tag_sets>
#pod
#pod B<The use of C<read_preference> as a mutator has been removed.>  Read
#pod preference is read-only.  If you need a different read preference for
#pod a database or collection, you can specify that in C<get_database> or
#pod C<get_collection>.
#pod
#pod =cut

has _read_preference => (
    is       => 'lazy',
    isa      => ReadPreference,
    reader   => 'read_preference',
    init_arg => undef,
    builder  => '_build__read_preference',
);

sub _build__read_preference {
    my ($self) = @_;
    return MongoDB::ReadPreference->new(
        ( defined $self->read_pref_mode     ? ( mode     => $self->read_pref_mode )     : () ),
        ( defined $self->read_pref_tag_sets ? ( tag_sets => $self->read_pref_tag_sets ) : () ),
        ( defined $self->max_staleness_seconds ? ( max_staleness_seconds => $self->max_staleness_seconds ) : () ),
    );
}

#pod =method write_concern
#pod
#pod Returns a L<MongoDB::WriteConcern> object constructed from L</w>, L</write_concern>
#pod and L</j>.
#pod
#pod =cut

has _write_concern => (
    is     => 'lazy',
    isa    => InstanceOf['MongoDB::WriteConcern'],
    reader   => 'write_concern',
    init_arg => undef,
    builder  => '_build__write_concern',
);

sub _build__write_concern {
    my ($self) = @_;

    return MongoDB::WriteConcern->new( $self->_write_concern_options );
}

# Seperated out for use in transaction option defaults
sub _write_concern_options {
    my ($self) = @_;

    return (
        wtimeout => $self->wtimeout,
        # Must check for defined as w can be 0, and defaults to undef
        ( defined $self->w ? ( w => $self->w ) : () ),
        ( defined $self->j ? ( j => $self->j ) : () ),
    );
}


#pod =method read_concern
#pod
#pod Returns a L<MongoDB::ReadConcern> object constructed from
#pod L</read_concern_level>.
#pod
#pod =cut

has _read_concern => (
    is     => 'lazy',
    isa    => InstanceOf['MongoDB::ReadConcern'],
    reader   => 'read_concern',
    init_arg => undef,
    builder  => '_build__read_concern',
);

sub _build__read_concern {
    my ($self) = @_;

    return MongoDB::ReadConcern->new(
        ( $self->read_concern_level ?
            ( level => $self->read_concern_level ) : () ),
    );
}

#--------------------------------------------------------------------------#
# private attributes
#--------------------------------------------------------------------------#

# used for a more accurate 'is this client the same one' for sessions, instead
# of memory location which just feels... yucky
has _id => (
    is  => 'ro',
    init_arg => undef,
    default => sub { UUID::URandom::create_uuid_string() },
);

# collects constructor options and defer them so precedence can be resolved
# against the _uri options; unlike other private args, this needs a valid
# init argument
has _deferred => (
    is       => 'ro',
    isa      => HashRef,
    init_arg => '_deferred',
    default  => sub { {} },
);

#pod =method topology_type
#pod
#pod Returns an enumerated topology type.  If the L</replica_set_name> is set,
#pod the value will be either 'ReplicaSetWithPrimary' or 'ReplicaSetNoPrimary'
#pod (if the primary is down or not yet discovered).  Without
#pod L</replica_set_name>, if there is more than one server in the list of
#pod hosts, the type will be 'Sharded'.
#pod
#pod With only a single host and no replica set name, the topology type will
#pod start as 'Direct' until the server is contacted the first time, after which
#pod the type will be 'Sharded' for a mongos or 'Single' for standalone server
#pod or direct connection to a replica set member.
#pod
#pod =cut

has _topology => (
    is       => 'lazy',
    isa      => InstanceOf ['MongoDB::_Topology'],
    init_arg => undef,
    builder  => '_build__topology',
    handles  => {
        topology_type => 'type',
        _cluster_time => 'cluster_time',
        _update_cluster_time => 'update_cluster_time',
    },
    clearer  => '_clear__topology',
);

sub _build__topology {
    my ($self) = @_;

    my $type =
        length( $self->replica_set_name ) ? 'ReplicaSetNoPrimary'
      : @{ $self->_uri->hostids } > 1     ? 'Sharded'
      :                                     'Direct';

    MongoDB::_Topology->new(
        uri                          => $self->_uri,
        type                         => $type,
        app_name                     => $self->app_name,
        replica_set_name             => $self->replica_set_name,
        server_selection_timeout_sec => $self->server_selection_timeout_ms / 1000,
        server_selection_try_once    => $self->server_selection_try_once,
        local_threshold_sec          => $self->local_threshold_ms / 1000,
        heartbeat_frequency_sec      => $self->heartbeat_frequency_ms / 1000,
        min_server_version           => MIN_SERVER_VERSION,
        max_wire_version             => MAX_WIRE_VERSION,
        min_wire_version             => MIN_WIRE_VERSION,
        credential                   => $self->_credential,
        link_options                 => {
            connect_timeout => $self->connect_timeout_ms >= 0 ? $self->connect_timeout_ms / 1000
            : undef,
            socket_timeout => $self->socket_timeout_ms >= 0 ? $self->socket_timeout_ms / 1000
            : undef,
            with_ssl => !!$self->ssl,
            ( ref( $self->ssl ) eq 'HASH' ? ( SSL_options => $self->ssl ) : () ),
        },
        monitoring_callback => $self->monitoring_callback,
        compressors => $self->compressors,
        zlib_compression_level => $self->zlib_compression_level,
        socket_check_interval_sec => $self->socket_check_interval_ms / 1000,
        server_selector => $self->server_selector,
    );
}

has _credential => (
    is       => 'lazy',
    isa      => InstanceOf ['MongoDB::_Credential'],
    init_arg => undef,
    builder  => '_build__credential',
);

sub _build__credential {
    my ($self) = @_;
    my $mechanism = $self->auth_mechanism;
    my $uri_options = $self->_uri->options;
    my $source = $uri_options->{authsource};
    my $cred = MongoDB::_Credential->new(
        monitoring_callback  => $self->monitoring_callback,
        mechanism            => $mechanism,
        mechanism_properties => $self->auth_mechanism_properties,
        ( $self->username ? ( username => $self->username ) : () ),
        ( $self->password ? ( password => $self->password ) : () ),
        ( $source ? ( source   => $source )  : () ),
        ( $self->db_name ? ( db_name => $self->db_name ) : () ),
    );
    return $cred;
}

has _uri => (
    is       => 'lazy',
    isa      => InstanceOf ['MongoDB::_URI'],
    init_arg => undef,
    builder  => '_build__uri',
);

sub _build__uri {
    my ($self) = @_;
    if ( $self->host =~ m{^[\w\+]+://} ) {
        return MongoDB::_URI->new( uri => $self->host );
    }
    else {
        my $uri = $self->host =~ /:\d+$/
                ? $self->host
                : sprintf("%s:%s", map { $self->$_ } qw/host port/ );
        return MongoDB::_URI->new( uri => ("mongodb://$uri") );
    }
}

has _dispatcher => (
    is       => 'lazy',
    isa      => InstanceOf ['MongoDB::_Dispatcher'],
    init_arg => undef,
    builder  => '_build__dispatcher',
    handles  => [
        qw(
          send_direct_op
          send_primary_op
          send_retryable_read_op
          send_read_op
          send_retryable_write_op
          send_write_op
          )
    ],
);

sub _build__dispatcher {
    my $self = shift;
    return MongoDB::_Dispatcher->new(
        topology     => $self->_topology,
        retry_writes => $self->retry_writes,
        retry_reads  => $self->retry_reads,
    );
}

has _server_session_pool => (
    is => 'lazy',
    isa => InstanceOf['MongoDB::_SessionPool'],
    init_arg => undef,
    builder => '_build__server_session_pool',
);

sub _build__server_session_pool {
    my $self = shift;
    return MongoDB::_SessionPool->new(
        dispatcher => $self->_dispatcher,
        topology   => $self->_topology,
    );
}

#--------------------------------------------------------------------------#
# Constructor customization
#--------------------------------------------------------------------------#

# these attributes are lazy, built from either _uri->options or from
# _config_options captured in BUILDARGS
my @deferred_options = qw(
  app_name
  auth_mechanism
  auth_mechanism_properties
  connect_timeout_ms
  db_name
  heartbeat_frequency_ms
  j
  local_threshold_ms
  max_staleness_seconds
  max_time_ms
  read_pref_mode
  read_pref_tag_sets
  replica_set_name
  retry_writes
  retry_reads
  server_selection_timeout_ms
  server_selection_try_once
  socket_check_interval_ms
  socket_timeout_ms
  ssl
  username
  password
  w
  wtimeout
  read_concern_level
);

around BUILDARGS => sub {
    my $orig = shift;
    my $class = shift;
    my $hr = $class->$orig(@_);
    my $deferred = {};
    for my $k ( @deferred_options ) {
        $deferred->{$k} = delete $hr->{$k}
          if exists $hr->{$k};
    }
    $hr->{_deferred} = $deferred;
    return $hr;
};

sub BUILD {
    my ($self, $opts) = @_;

    my $uri = $self->_uri;

    my @addresses = @{ $uri->hostids };

    # resolve and validate all deferred attributes
    $self->$_ for @deferred_options;

    # resolve and validate read pref and write concern
    $self->read_preference;
    $self->write_concern;

    # Add error handler to codec if user didn't provide their own
    unless ( $self->bson_codec->error_callback ) {
        $self->_set_bson_codec(
            $self->bson_codec->clone(
                error_callback => sub {
                    my ($msg, $ref, $op) = @_;
                    if ( $op =~ /^encode/ ) {
                        MongoDB::DocumentError->throw(
                            message => $msg,
                            document => $ref
                        );
                    }
                    else {
                        MongoDB::DecodingError->throw($msg);
                    }
                },
            )
        );
    }

    # Instantiate topology
    $self->_topology;

    return;
}

#--------------------------------------------------------------------------#
# helper functions
#--------------------------------------------------------------------------#

sub __uri_or_else {
    my ( $self, %spec ) = @_;
    my $uri_options = $self->_uri->options;
    my $deferred    = $self->_deferred;
    my ( $u, $e, $default ) = @spec{qw/u e d/};
    return
        exists $uri_options->{$u} ? $uri_options->{$u}
      : exists $deferred->{$e}    ? $deferred->{$e}
      :                             $default;
}

sub __string {
    local $_;
    my ($first) = grep { defined && length } @_;
    return $first || '';
}

#--------------------------------------------------------------------------#
# public methods - network communication
#--------------------------------------------------------------------------#

#pod =method connect
#pod
#pod     $client->connect;
#pod
#pod Calling this method is unnecessary, as connections are established
#pod automatically as needed.  It is kept for backwards compatibility.  Calling it
#pod will check all servers in the deployment which ensures a connection to any
#pod that are available.
#pod
#pod See L</reconnect> for a method that is useful when using forks or threads.
#pod
#pod =cut

sub connect {
    my ($self) = @_;
    $self->_topology->scan_all_servers;
    return 1;
}

#pod =method disconnect
#pod
#pod     $client->disconnect;
#pod
#pod Drops all connections to servers.
#pod
#pod =cut

sub disconnect {
    my ($self) = @_;
    $self->_topology->close_all_links;
    return 1;
}

#pod =method reconnect
#pod
#pod     $client->reconnect;
#pod
#pod This method closes all connections to the server, as if L</disconnect> were
#pod called, and then immediately reconnects.  It also clears the session
#pod cache.  Use this after forking or spawning off a new thread.
#pod
#pod =cut

sub reconnect {
    my ($self) = @_;
    $self->_topology->close_all_links;
    $self->_server_session_pool->reset_pool;
    $self->_topology->scan_all_servers(1);
    return 1;
}

#pod =method topology_status
#pod
#pod     $client->topology_status;
#pod     $client->topology_status( refresh => 1 );
#pod
#pod Returns a hash reference with server topology information like this:
#pod
#pod     {
#pod         'topology_type' => 'ReplicaSetWithPrimary'
#pod         'replica_set_name' => 'foo',
#pod         'last_scan_time'   => '1433766895.183241',
#pod         'servers'          => [
#pod             {
#pod                 'address'     => 'localhost:50003',
#pod                 'ewma_rtt_ms' => '0.223462326',
#pod                 'type'        => 'RSSecondary'
#pod             },
#pod             {
#pod                 'address'     => 'localhost:50437',
#pod                 'ewma_rtt_ms' => '0.268435456',
#pod                 'type'        => 'RSArbiter'
#pod             },
#pod             {
#pod                 'address'     => 'localhost:50829',
#pod                 'ewma_rtt_ms' => '0.737782272',
#pod                 'type'        => 'RSPrimary'
#pod             }
#pod         },
#pod     }
#pod
#pod If the 'refresh' argument is true, then the topology will be scanned
#pod to update server data before returning the hash reference.
#pod
#pod =cut

sub topology_status {
    my ($self, %opts) = @_;
    $self->_topology->scan_all_servers(1) if $opts{refresh};
    return $self->_topology->status_struct;
}

#pod =method start_session
#pod
#pod     $client->start_session;
#pod     $client->start_session( $options );
#pod
#pod Returns a new L<MongoDB::ClientSession> with the supplied options.
#pod
#pod will throw a C<MongoDB::ConfigurationError> if sessions are not supported by
#pod the connected MongoDB deployment.
#pod
#pod the options hash is an optional hash which can have the following keys:
#pod
#pod =for :list
#pod * C<causalConsistency> - Enable Causally Consistent reads for this session.
#pod   Defaults to true.
#pod
#pod for more information see L<MongoDB::ClientSession/options>.
#pod
#pod =cut

sub start_session {
    my ( $self, $opts ) = @_;

    unless ( $self->_topology->_supports_sessions ) {
        MongoDB::ConfigurationError->throw( "Sessions are not supported by this MongoDB deployment" );
    }

    return $self->_start_client_session( 1, $opts );
}

sub _maybe_get_implicit_session {
    my ($self) = @_;

    # Dont return an error as implicit sessions need to be backwards compatible
    return undef unless $self->_topology->_supports_sessions; ## no critic

    return $self->_start_client_session(0);
}

sub _start_client_session {
    my ( $self, $is_explicit, $opts ) = @_;

    $opts ||= {};

    my $session = $self->_server_session_pool->get_server_session;
    return MongoDB::ClientSession->new(
        client => $self,
        options => $opts,
        _is_explicit => $is_explicit,
        server_session => $session,
    );
}

#--------------------------------------------------------------------------#
# semi-private methods; these are public but undocumented and their
# semantics might change in future releases
#--------------------------------------------------------------------------#

# Undocumented in old MongoDB::MongoClient; semantics don't translate, but
# best approximation is checking if we can send a command to a server
sub connected {
    my ($self) = @_;
    return eval { $self->send_admin_command([ismaster => 1]); 1 };
}

sub send_admin_command {
    my ( $self, $command, $read_pref ) = @_;

    $read_pref = MongoDB::ReadPreference->new(
        ref($read_pref) ? $read_pref : ( mode => $read_pref ) )
      if $read_pref && ref($read_pref) ne 'MongoDB::ReadPreference';

    my $op = MongoDB::Op::_Command->_new(
        db_name             => 'admin',
        query               => $command,
        query_flags         => {},
        bson_codec          => $self->bson_codec,
        read_preference     => $read_pref,
        session             => $self->_maybe_get_implicit_session,
        monitoring_callback => $self->monitoring_callback,
    );

    return $self->send_retryable_read_op( $op );
}

# Ostensibly the same as above, but allows for specific addressing - uses 'send_direct_op'.
sub _send_direct_admin_command {
     my ( $self, $address, $command, $read_pref ) = @_;

    $read_pref = MongoDB::ReadPreference->new(
        ref($read_pref) ? $read_pref : ( mode => $read_pref ) )
      if $read_pref && ref($read_pref) ne 'MongoDB::ReadPreference';

    my $op = MongoDB::Op::_Command->_new(
        db_name             => 'admin',
        query               => $command,
        query_flags         => {},
        bson_codec          => $self->bson_codec,
        read_preference     => $read_pref,
        session             => $self->_maybe_get_implicit_session,
        monitoring_callback => $self->monitoring_callback,
    );

    return $self->send_direct_op( $op, $address );
}

#--------------------------------------------------------------------------#
# database helper methods
#--------------------------------------------------------------------------#

#pod =method list_databases
#pod
#pod     # get all information on all databases
#pod     my @dbs = $client->list_databases;
#pod
#pod     # get only the foo databases
#pod     my @foo_dbs = $client->list_databases({ filter => { name => qr/^foo/ } });
#pod
#pod Lists all databases with information on each database. Supports filtering by
#pod any of the output fields under the C<filter> argument, such as:
#pod
#pod =for :list
#pod * C<name>
#pod * C<sizeOnDisk>
#pod * C<empty>
#pod * C<shards>
#pod
#pod =cut

sub list_databases {
    my ( $self, $args ) = @_;
    my @databases;
    eval {
        my $output = $self->send_admin_command([ listDatabases => 1, ( $args ? %$args : () ) ])->output;
        if (ref($output) eq 'HASH' && exists $output->{databases}) {
            @databases = @{ $output->{databases} };
        }
        return 1;
    } or do {
        my $error = $@ || "Unknown error";
        if ( $error->$_isa("MongoDB::DatabaseError" ) ) {
            return if $error->result->output->{code} == CANT_OPEN_DB_IN_READ_LOCK();
        }
        die $error;
    };
    return @databases;
}

#pod =method database_names
#pod
#pod     my @dbs = $client->database_names;
#pod
#pod     # get only the foo database names
#pod     my @foo_dbs = $client->database_names({ filter => { name => qr/^foo/ } });
#pod
#pod List of all database names on the MongoDB server. Supports filters in the same
#pod way as L</"list_databases">.
#pod
#pod =cut

sub database_names {
    my ( $self, $args ) = @_;

    $args ||= {};
    $args->{nameOnly} = 1;
    my @output = $self->list_databases($args);

    my @databases = map { $_->{name} } @output;

    return @databases;
}

#pod =method get_database, db
#pod
#pod     my $database = $client->get_database('foo');
#pod     my $database = $client->get_database('foo', $options);
#pod     my $database = $client->db('foo', $options);
#pod
#pod Returns a L<MongoDB::Database> instance for the database with the given
#pod C<$name>.
#pod
#pod It takes an optional hash reference of options that are passed to the
#pod L<MongoDB::Database> constructor.
#pod
#pod The C<db> method is an alias for C<get_database>.
#pod
#pod =cut

sub get_database {
    my ( $self, $database_name, $options ) = @_;
    return MongoDB::Database->new(
        read_preference => $self->read_preference,
        write_concern   => $self->write_concern,
        read_concern    => $self->read_concern,
        bson_codec      => $self->bson_codec,
        max_time_ms     => $self->max_time_ms,
        ( $options ? %$options : () ),
        # not allowed to be overridden by options
        _client       => $self,
        name          => $database_name,
    );
}

{ no warnings 'once'; *db = \&get_database }

#pod =method get_namespace, ns
#pod
#pod     my $collection = $client->get_namespace('test.foo');
#pod     my $collection = $client->get_namespace('test.foo', $options);
#pod     my $collection = $client->ns('test.foo', $options);
#pod
#pod Returns a L<MongoDB::Collection> instance for the given namespace.
#pod The namespace has both the database name and the collection name
#pod separated with a dot character.
#pod
#pod This is a quick way to get a collection object if you don't need
#pod the database object separately.
#pod
#pod It takes an optional hash reference of options that are passed to the
#pod L<MongoDB::Collection> constructor.  The intermediate L<MongoDB::Database>
#pod object will be created with default options.
#pod
#pod The C<ns> method is an alias for C<get_namespace>.
#pod
#pod =cut

sub get_namespace {
    my ( $self, $ns, $options ) = @_;
    MongoDB::UsageError->throw("namespace requires a string argument")
      unless defined($ns) && length($ns);
    my ( $db, $coll ) = split /\./, $ns, 2;
    MongoDB::UsageError->throw("$ns is not a valid namespace")
      unless defined($db) && defined($coll);
    return $self->db($db)->coll( $coll, $options );
}

{ no warnings 'once'; *ns = \&get_namespace }

#pod =method fsync(\%args)
#pod
#pod     $client->fsync();
#pod
#pod A function that will forces the server to flush all pending writes to the storage layer.
#pod
#pod The fsync operation is synchronous by default, to run fsync asynchronously, use the following form:
#pod
#pod     $client->fsync({async => 1});
#pod
#pod The primary use of fsync is to lock the database during backup operations. This will flush all data to the data storage layer and block all write operations until you unlock the database. Note: you can still read while the database is locked.
#pod
#pod     $conn->fsync({lock => 1});
#pod
#pod =cut

sub fsync {
    my ($self, $args) = @_;

    $args ||= {};

    # Pass this in as array-ref to ensure that 'fsync => 1' is the first argument.
    return $self->get_database('admin')->run_command([fsync => 1, %$args]);
}

#pod =method fsync_unlock
#pod
#pod     $conn->fsync_unlock();
#pod
#pod Unlocks a database server to allow writes and reverses the operation of a $conn->fsync({lock => 1}); operation.
#pod
#pod =cut

sub fsync_unlock {
    my ($self) = @_;

    my $op = MongoDB::Op::_FSyncUnlock->_new(
        db_name             => 'admin',
        client              => $self,
        bson_codec          => $self->bson_codec,
        monitoring_callback => $self->monitoring_callback,
    );

    return $self->send_primary_op($op);
}

sub _get_session_from_hashref {
    my ( $self, $hashref ) = @_;

    my $session = delete $hashref->{session};

    if ( defined $session ) {
        MongoDB::UsageError->throw( "Cannot use session from another client" )
            if ( $session->client->_id ne $self->_id );
        MongoDB::UsageError->throw( "Cannot use session which has ended" )
            if ! defined $session->session_id;
    } else {
        $session = $self->_maybe_get_implicit_session;
    }

    return $session;
}

#pod =method watch
#pod
#pod Watches for changes on the cluster.
#pod
#pod Perform an aggregation with an implicit initial C<$changeStream> stage
#pod and returns a L<MongoDB::ChangeStream> result which can be used to
#pod iterate over the changes in the cluster. This functionality is
#pod available since MongoDB 4.0.
#pod
#pod     my $stream = $client->watch();
#pod     my $stream = $client->watch( \@pipeline );
#pod     my $stream = $client->watch( \@pipeline, \%options );
#pod
#pod     while (1) {
#pod
#pod         # This inner loop will only run until no more changes are
#pod         # available.
#pod         while (my $change = $stream->next) {
#pod             # process $change
#pod         }
#pod     }
#pod
#pod The returned stream will not block forever waiting for changes. If you
#pod want to respond to changes over a longer time use C<maxAwaitTimeMS> and
#pod regularly call C<next> in a loop.
#pod
#pod See L<MongoDB::Collection/watch> for details on usage and available
#pod options.
#pod
#pod =cut

sub watch {
    my ( $self, $pipeline, $options ) = @_;

    $pipeline ||= [];
    $options ||= {};

    my $session = $self->_get_session_from_hashref( $options );

    return MongoDB::ChangeStream->new(
        exists($options->{startAtOperationTime})
            ? (start_at_operation_time => delete $options->{startAtOperationTime})
            : (),
        exists($options->{fullDocument})
            ? (full_document => delete $options->{fullDocument})
            : (full_document => 'default'),
        exists($options->{resumeAfter})
            ? (resume_after => delete $options->{resumeAfter})
            : (),
        exists($options->{startAfter})
            ? (start_after => delete $options->{startAfter})
            : (),
        exists($options->{maxAwaitTimeMS})
            ? (max_await_time_ms => delete $options->{maxAwaitTimeMS})
            : (),
        client => $self,
        all_changes_for_cluster => 1,
        pipeline => $pipeline,
        session => $session,
        options => $options,
        op_args => {
            read_concern => $self->read_concern,
            db_name => 'admin',,
            coll_name => 1,
            full_name => 'admin.1',
            bson_codec => $self->bson_codec,
            write_concern => $self->write_concern,
            read_concern => $self->read_concern,
            read_preference => $self->read_preference,
            monitoring_callback => $self->monitoring_callback,
        },
    );
}

sub _primary_server_version {
    my $self = shift;
    my $build = $self->send_admin_command( [ buildInfo => 1 ] )->output;
    my ($version_str) = $build->{version} =~ m{^([0-9.]+)};
    return version->parse("v$version_str");
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MongoDB::MongoClient - A connection to a MongoDB server or multi-server deployment

=head1 VERSION

version v2.2.2

=head1 SYNOPSIS

    use MongoDB; # also loads MongoDB::MongoClient

    # connect to localhost:27017
    my $client = MongoDB::MongoClient->new;

    # connect to specific host and port
    my $client = MongoDB::MongoClient->new(
        host => "mongodb://mongo.example.com:27017"
    );

    # connect to a replica set (set name *required*)
    my $client = MongoDB::MongoClient->new(
        host => "mongodb://mongo1.example.com,mongo2.example.com",
        replica_set_name => 'myset',
    );

    # connect to a replica set with URI (set name *required*)
    my $client = MongoDB::MongoClient->new(
        host => "mongodb://mongo1.example.com,mongo2.example.com/?replicaSet=myset",
    );

    my $db = $client->get_database("test");
    my $coll = $db->get_collection("people");

    $coll->insert({ name => "John Doe", age => 42 });
    my @people = $coll->find()->all();

=head1 DESCRIPTION

The C<MongoDB::MongoClient> class represents a client connection to one or
more MongoDB servers.

By default, it connects to a single server running on the local machine
listening on the default port 27017:

    # connects to localhost:27017
    my $client = MongoDB::MongoClient->new;

It can connect to a database server running anywhere, though:

    my $client = MongoDB::MongoClient->new(host => 'example.com:12345');

See the L</"host"> attribute for more options for connecting to MongoDB.

MongoDB can be started in L<authentication
mode|http://docs.mongodb.org/manual/core/authentication/>, which requires
clients to log in before manipulating data.  By default, MongoDB does not start
in this mode, so no username or password is required to make a fully functional
connection.  To configure the client for authentication, see the
L</AUTHENTICATION> section.

The actual socket connections are lazy and created on demand.  When the client
object goes out of scope, all socket will be closed.  Note that
L<MongoDB::Database>, L<MongoDB::Collection> and related classes could hold a
reference to the client as well.  Only when all references are out of scope
will the sockets be closed.

=head1 ATTRIBUTES

=head2 host

The C<host> attribute specifies either a single server to connect to (as
C<hostname> or C<hostname:port>), or else a L<connection string URI|/CONNECTION
STRING URI> with a seed list of one or more servers plus connection options.

B<NOTE>: Options specified in the connection string take precedence over options
provided as constructor arguments.

Defaults to the connection string URI C<mongodb://localhost:27017>.

For IPv6 support, you must have a recent version of L<IO::Socket::IP>
installed.  This module ships with the Perl core since v5.20.0 and is
available on CPAN for older Perls.

=head2 app_name

This attribute specifies an application name that should be associated with
this client.  The application name will be communicated to the server as
part of the initial connection handshake, and will appear in
connection-level and operation-level diagnostics on the server generated on
behalf of this client.  This may be set in a connection string with the
C<appName> option.

The default is the empty string, which indicates a lack of an application
name.

The application name must not exceed 128 bytes.

=head2 auth_mechanism

This attribute determines how the client authenticates with the server.
Valid values are:

=over 4

=item *

NONE

=item *

DEFAULT

=item *

MONGODB-CR

=item *

MONGODB-X509

=item *

GSSAPI

=item *

PLAIN

=item *

SCRAM-SHA-1

=back

If not specified, then if no username or C<authSource> URI option is provided,
it defaults to NONE.  Otherwise, it is set to DEFAULT, which chooses
SCRAM-SHA-1 if available or MONGODB-CR otherwise.

This may be set in a connection string with the C<authMechanism> option.

=head2 auth_mechanism_properties

This is an optional hash reference of authentication mechanism specific properties.
See L</AUTHENTICATION> for details.

This may be set in a connection string with the C<authMechanismProperties>
option.  If given, the value must be key/value pairs joined with a ":".
Multiple pairs must be separated by a comma.  If ": or "," appear in a key or
value, they must be URL encoded.

=head2 bson_codec

An object that provides the C<encode_one> and C<decode_one> methods, such as
from L<BSON>.  It may be initialized with a hash reference that will
be coerced into a new L<BSON> object.

If not provided, a L<BSON> object with default values will be generated.

=head2 compressors

An array reference of compression type names. Currently, C<zlib>, C<zstd> and
C<snappy> are supported.

=head2 zlib_compression_level

An integer from C<-1> to C<9> specifying the compression level to use
when L</compression> is set to C<zlib>.

B<Note>: When the special value C<-1> is given, the default compression
level will be used.

=head2 connect_timeout_ms

This attribute specifies the amount of time in milliseconds to wait for a
new connection to a server.

The default is 10,000 ms.

If set to a negative value, connection operations will block indefinitely
until the server replies or until the operating system TCP/IP stack gives
up (e.g. if the name can't resolve or there is no process listening on the
target host/port).

A zero value polls the socket during connection and is thus likely to fail
except when talking to a local process (and perhaps even then).

This may be set in a connection string with the C<connectTimeoutMS> option.

=head2 db_name

Optional.  If an L</auth_mechanism> requires a database for authentication,
this attribute will be used.  Otherwise, it will be ignored. Defaults to
"admin".

This may be provided in the L<connection string URI|/CONNECTION STRING URI> as
a path between the authority and option parameter sections.  For example, to
authenticate against the "admin" database (showing a configuration option only
for illustration):

    mongodb://localhost/admin?readPreference=primary

=head2 heartbeat_frequency_ms

The time in milliseconds (non-negative) between scans of all servers to
check if they are up and update their latency.  Defaults to 60,000 ms.

This may be set in a connection string with the C<heartbeatFrequencyMS> option.

=head2 j

If true, the client will block until write operations have been committed to the
server's journal. Prior to MongoDB 2.6, this option was ignored if the server was
running without journaling. Starting with MongoDB 2.6, write operations will fail
if this option is used when the server is running without journaling.

This may be set in a connection string with the C<journal> option as the
strings 'true' or 'false'.

=head2 local_threshold_ms

The width of the 'latency window': when choosing between multiple suitable
servers for an operation, the acceptable delta in milliseconds
(non-negative) between shortest and longest average round-trip times.
Servers within the latency window are selected randomly.

Set this to "0" to always select the server with the shortest average round
trip time.  Set this to a very high value to always randomly choose any known
server.

Defaults to 15 ms.

See L</SERVER SELECTION> for more details.

This may be set in a connection string with the C<localThresholdMS> option.

=head2 max_staleness_seconds

The C<max_staleness_seconds> parameter represents the maximum replication lag in
seconds (wall clock time) that a secondary can suffer and still be
eligible for reads. The default is -1, which disables staleness checks.
Otherwise, it must be a positive integer.

B<Note>: this will only be used for server versions 3.4 or greater, as that
was when support for staleness tracking was added.

If the read preference mode is 'primary', then C<max_staleness_seconds> must not
be supplied.

The C<max_staleness_seconds> must be at least the C<heartbeat_frequency_ms>
plus 10 seconds (which is how often the server makes idle writes to the
oplog).

This may be set in a connection string with the C<maxStalenessSeconds> option.

=head2 max_time_ms

Specifies the maximum amount of time in (non-negative) milliseconds that the
server should use for working on a database command.  Defaults to 0, which disables
this feature.  Make sure this value is shorter than C<socket_timeout_ms>.

B<Note>: this will only be used for server versions 2.6 or greater, as that
was when the C<$maxTimeMS> meta-operator was introduced.

You are B<strongly> encouraged to set this variable if you know your
environment has MongoDB 2.6 or later, as getting a definitive error response
from the server is vastly preferred over a getting a network socket timeout.

This may be set in a connection string with the C<maxTimeMS> option.

=head2 monitoring_callback

Specifies a code reference used to receive monitoring events.  See
L<MongoDB::Monitoring> for more details.

=head2 password

If an L</auth_mechanism> requires a password, this attribute will be
used.  Otherwise, it will be ignored.

This may be provided in the L<connection string URI|/CONNECTION STRING URI> as
a C<username:password> pair in the leading portion of the authority section
before a C<@> character.  For example, to authenticate as user "mulder" with
password "trustno1":

    mongodb://mulder:trustno1@localhost

If the username or password have a ":" or "@" in it, they must be URL encoded.
An empty password still requires a ":" character.

=head2 port

If a network port is not specified as part of the C<host> attribute, this
attribute provides the port to use.  It defaults to 27107.

=head2 read_concern_level

The read concern level determines the consistency level required
of data being read.

The default level is C<undef>, which means the server will use its configured
default.

If the level is set to "local", reads will return the latest data a server has
locally.

Additional levels are storage engine specific.  See L<Read
Concern|http://docs.mongodb.org/manual/search/?query=readConcern> in the MongoDB
documentation for more details.

This may be set in a connection string with the the C<readConcernLevel> option.

=head2 read_pref_mode

The read preference mode determines which server types are candidates
for a read operation.  Valid values are:

=over 4

=item *

primary

=item *

primaryPreferred

=item *

secondary

=item *

secondaryPreferred

=item *

nearest

=back

For core documentation on read preference see
L<http://docs.mongodb.org/manual/core/read-preference/>.

This may be set in a connection string with the C<readPreference> option.

=head2 read_pref_tag_sets

The C<read_pref_tag_sets> parameter is an ordered list of tag sets used to
restrict the eligibility of servers, such as for data center awareness.  It
must be an array reference of hash references.

The application of C<read_pref_tag_sets> varies depending on the
C<read_pref_mode> parameter.  If the C<read_pref_mode> is 'primary', then
C<read_pref_tag_sets> must not be supplied.

For core documentation on read preference see
L<http://docs.mongodb.org/manual/core/read-preference/>.

This may be set in a connection string with the C<readPreferenceTags> option.
If given, the value must be key/value pairs joined with a ":".  Multiple pairs
must be separated by a comma.  If ": or "," appear in a key or value, they must
be URL encoded.  The C<readPreferenceTags> option may appear more than once, in
which case each document will be added to the tag set list.

=head2 replica_set_name

Specifies the replica set name to connect to.  If this string is non-empty,
then the topology is treated as a replica set and all server replica set
names must match this or they will be removed from the topology.

This may be set in a connection string with the C<replicaSet> option.

=head2 retry_reads

=head2 retry_writes

Whether the client should use retryable writes for supported commands. The
default value is true, which means that commands which support retryable writes
will be retried on certain errors, such as C<not master> and C<node is
recovering> errors.

This may be set in a connection string with the C<retryWrites> option.

Note that this is only supported on MongoDB > 3.6 in Replica Set or Shard
Clusters, and will be ignored on other deployments.

Unacknowledged write operations also do not support retryable writes, even when
retry_writes has been enabled.

The supported single statement write operations are currently as follows:

=over 4

=item *

C<insert_one>

=item *

C<update_one>

=item *

C<replace_one>

=item *

C<delete_one>

=item *

C<find_one_and_delete>

=item *

C<find_one_and_replace>

=item *

C<find_one_and_update>

=back

The supported multi statement write operations are as follows:

=over 4

=item *

C<insert_many>

=item *

C<bulk_write>

=back

The multi statement operations may be ether ordered or unordered. Note that for
C<bulk_write> operations, the request may not include update_many or
delete_many operations.

=head2 server_selection_timeout_ms

This attribute specifies the amount of time in milliseconds to wait for a
suitable server to be available for a read or write operation.  If no
server is available within this time period, an exception will be thrown.

The default is 30,000 ms.

See L</SERVER SELECTION> for more details.

This may be set in a connection string with the C<serverSelectionTimeoutMS>
option.

=head2 server_selection_try_once

This attribute controls whether the client will make only a single attempt
to find a suitable server for a read or write operation.  The default is true.

When true, the client will B<not> use the C<server_selection_timeout_ms>.
Instead, if the topology information is stale and needs to be checked or
if no suitable server is available, the client will make a single
scan of all known servers to try to find a suitable one.

When false, the client will continually scan known servers until a suitable
server is found or the C<serverSelectionTimeoutMS> is reached.

See L</SERVER SELECTION> for more details.

This may be set in a connection string with the C<serverSelectionTryOnce>
option.

=head2 server_selector

Optional. This takes a function that augments the server selection rules.
The function takes as a parameter a list of server descriptions representing
the suitable servers for the read or write operation, and returns a list of
server descriptions that should still be considered suitable. Most users
should rely on the default server selection algorithm and should not need
to set this attribute.

=head2 socket_check_interval_ms

If a socket to a server has not been used in this many milliseconds, an
C<ismaster> command will be issued to check the status of the server before
issuing any reads or writes. Must be non-negative.

The default is 5,000 ms.

This may be set in a connection string with the C<socketCheckIntervalMS>
option.

=head2 socket_timeout_ms

This attribute specifies the amount of time in milliseconds to wait for a
reply from the server before issuing a network exception.

The default is 30,000 ms.

If set to a negative value, socket operations will block indefinitely
until the server replies or until the operating system TCP/IP stack
gives up.

The driver automatically sets the TCP keepalive option when initializing the
socket. For keepalive related issues, check the MongoDB documentation for
L<Does TCP keepalive time affect MongoDB Deployments?|https://docs.mongodb.com/v3.2/faq/diagnostics/#does-tcp-keepalive-time-affect-mongodb-deployments>.

A zero value polls the socket for available data and is thus likely to fail
except when talking to a local process (and perhaps even then).

This may be set in a connection string with the C<socketTimeoutMS> option.

=head2 ssl

    ssl => 1
    ssl => \%ssl_options

This tells the driver that you are connecting to an SSL mongodb instance.

You must have L<IO::Socket::SSL> 1.42+ and L<Net::SSLeay> 1.49+ installed for
SSL support.

The C<ssl> attribute takes either a boolean value or a hash reference of
options to pass to IO::Socket::SSL.  For example, to set a CA file to validate
the server certificate and set a client certificate for the server to validate,
you could set the attribute like this:

    ssl => {
        SSL_ca_file   => "/path/to/ca.pem",
        SSL_cert_file => "/path/to/client.pem",
    }

If C<SSL_ca_file> is not provided, server certificates are verified against a
default list of CAs, either L<Mozilla::CA> or an operating-system-specific
default CA file.  To disable verification, you can use
C<< SSL_verify_mode => 0x00 >>.

B<You are strongly encouraged to use your own CA file for increased security>.

Server hostnames are also validated against the CN name in the server
certificate using C<< SSL_verifycn_scheme => 'http' >>.  You can use the
scheme 'none' to disable this check.

B<Disabling certificate or hostname verification is a security risk and is not
recommended>.

This may be set to the string 'true' or 'false' in a connection string with the
C<ssl> option, which will enable ssl with default configuration.  (See
L<connection string URI|/CONNECTION STRING URI> for additional TLS
configuration options.)

=head2 username

Optional username for this client connection.  If this field is set, the client
will attempt to authenticate when connecting to servers.  Depending on the
L</auth_mechanism>, the L</password> field or other attributes will need to be
set for authentication to succeed.

This may be provided in the L<connection string URI|/CONNECTION STRING URI> as
a C<username:password> pair in the leading portion of the authority section
before a C<@> character.  For example, to authenticate as user "mulder" with
password "trustno1":

    mongodb://mulder:trustno1@localhost

If the username or password have a ":" or "@" in it, they must be URL encoded.
An empty password still requires a ":" character.

=head2 w

The client I<write concern>.

=over 4

=item * C<0> Unacknowledged. MongoClient will B<NOT> wait for an acknowledgment that
the server has received and processed the request. Older documentation may refer
to this as "fire-and-forget" mode.  This option is not recommended.

=item * C<1> Acknowledged. MongoClient will wait until the
primary MongoDB acknowledges the write.

=item * C<2> Replica acknowledged. MongoClient will wait until at least two
replicas (primary and one secondary) acknowledge the write. You can set a higher
number for more replicas.

=item * C<all> All replicas acknowledged.

=item * C<majority> A majority of replicas acknowledged.

=back

If not set, the server default is used, which is typically "1".

In MongoDB v2.0+, you can "tag" replica members. With "tagging" you can
specify a custom write concern For more information see L<Data Center
Awareness|http://docs.mongodb.org/manual/data-center-awareness/>

This may be set in a connection string with the C<w> option.

=head2 wtimeout

The number of milliseconds an operation should wait for C<w> secondaries to
replicate it.

Defaults to 1000 (1 second). If you set this to undef, it could block indefinitely
(or until socket timeout is reached).

See C<w> above for more information.

This may be set in a connection string with the C<wTimeoutMS> option.

=head1 METHODS

=head2 read_preference

Returns a L<MongoDB::ReadPreference> object constructed from
L</read_pref_mode> and L</read_pref_tag_sets>

B<The use of C<read_preference> as a mutator has been removed.>  Read
preference is read-only.  If you need a different read preference for
a database or collection, you can specify that in C<get_database> or
C<get_collection>.

=head2 write_concern

Returns a L<MongoDB::WriteConcern> object constructed from L</w>, L</write_concern>
and L</j>.

=head2 read_concern

Returns a L<MongoDB::ReadConcern> object constructed from
L</read_concern_level>.

=head2 topology_type

Returns an enumerated topology type.  If the L</replica_set_name> is set,
the value will be either 'ReplicaSetWithPrimary' or 'ReplicaSetNoPrimary'
(if the primary is down or not yet discovered).  Without
L</replica_set_name>, if there is more than one server in the list of
hosts, the type will be 'Sharded'.

With only a single host and no replica set name, the topology type will
start as 'Direct' until the server is contacted the first time, after which
the type will be 'Sharded' for a mongos or 'Single' for standalone server
or direct connection to a replica set member.

=head2 connect

    $client->connect;

Calling this method is unnecessary, as connections are established
automatically as needed.  It is kept for backwards compatibility.  Calling it
will check all servers in the deployment which ensures a connection to any
that are available.

See L</reconnect> for a method that is useful when using forks or threads.

=head2 disconnect

    $client->disconnect;

Drops all connections to servers.

=head2 reconnect

    $client->reconnect;

This method closes all connections to the server, as if L</disconnect> were
called, and then immediately reconnects.  It also clears the session
cache.  Use this after forking or spawning off a new thread.

=head2 topology_status

    $client->topology_status;
    $client->topology_status( refresh => 1 );

Returns a hash reference with server topology information like this:

    {
        'topology_type' => 'ReplicaSetWithPrimary'
        'replica_set_name' => 'foo',
        'last_scan_time'   => '1433766895.183241',
        'servers'          => [
            {
                'address'     => 'localhost:50003',
                'ewma_rtt_ms' => '0.223462326',
                'type'        => 'RSSecondary'
            },
            {
                'address'     => 'localhost:50437',
                'ewma_rtt_ms' => '0.268435456',
                'type'        => 'RSArbiter'
            },
            {
                'address'     => 'localhost:50829',
                'ewma_rtt_ms' => '0.737782272',
                'type'        => 'RSPrimary'
            }
        },
    }

If the 'refresh' argument is true, then the topology will be scanned
to update server data before returning the hash reference.

=head2 start_session

    $client->start_session;
    $client->start_session( $options );

Returns a new L<MongoDB::ClientSession> with the supplied options.

will throw a C<MongoDB::ConfigurationError> if sessions are not supported by
the connected MongoDB deployment.

the options hash is an optional hash which can have the following keys:

=over 4

=item *

C<causalConsistency> - Enable Causally Consistent reads for this session. Defaults to true.

=back

for more information see L<MongoDB::ClientSession/options>.

=head2 list_databases

    # get all information on all databases
    my @dbs = $client->list_databases;

    # get only the foo databases
    my @foo_dbs = $client->list_databases({ filter => { name => qr/^foo/ } });

Lists all databases with information on each database. Supports filtering by
any of the output fields under the C<filter> argument, such as:

=over 4

=item *

C<name>

=item *

C<sizeOnDisk>

=item *

C<empty>

=item *

C<shards>

=back

=head2 database_names

    my @dbs = $client->database_names;

    # get only the foo database names
    my @foo_dbs = $client->database_names({ filter => { name => qr/^foo/ } });

List of all database names on the MongoDB server. Supports filters in the same
way as L</"list_databases">.

=head2 get_database, db

    my $database = $client->get_database('foo');
    my $database = $client->get_database('foo', $options);
    my $database = $client->db('foo', $options);

Returns a L<MongoDB::Database> instance for the database with the given
C<$name>.

It takes an optional hash reference of options that are passed to the
L<MongoDB::Database> constructor.

The C<db> method is an alias for C<get_database>.

=head2 get_namespace, ns

    my $collection = $client->get_namespace('test.foo');
    my $collection = $client->get_namespace('test.foo', $options);
    my $collection = $client->ns('test.foo', $options);

Returns a L<MongoDB::Collection> instance for the given namespace.
The namespace has both the database name and the collection name
separated with a dot character.

This is a quick way to get a collection object if you don't need
the database object separately.

It takes an optional hash reference of options that are passed to the
L<MongoDB::Collection> constructor.  The intermediate L<MongoDB::Database>
object will be created with default options.

The C<ns> method is an alias for C<get_namespace>.

=head2 fsync(\%args)

    $client->fsync();

A function that will forces the server to flush all pending writes to the storage layer.

The fsync operation is synchronous by default, to run fsync asynchronously, use the following form:

    $client->fsync({async => 1});

The primary use of fsync is to lock the database during backup operations. This will flush all data to the data storage layer and block all write operations until you unlock the database. Note: you can still read while the database is locked.

    $conn->fsync({lock => 1});

=head2 fsync_unlock

    $conn->fsync_unlock();

Unlocks a database server to allow writes and reverses the operation of a $conn->fsync({lock => 1}); operation.

=head2 watch

Watches for changes on the cluster.

Perform an aggregation with an implicit initial C<$changeStream> stage
and returns a L<MongoDB::ChangeStream> result which can be used to
iterate over the changes in the cluster. This functionality is
available since MongoDB 4.0.

    my $stream = $client->watch();
    my $stream = $client->watch( \@pipeline );
    my $stream = $client->watch( \@pipeline, \%options );

    while (1) {

        # This inner loop will only run until no more changes are
        # available.
        while (my $change = $stream->next) {
            # process $change
        }
    }

The returned stream will not block forever waiting for changes. If you
want to respond to changes over a longer time use C<maxAwaitTimeMS> and
regularly call C<next> in a loop.

See L<MongoDB::Collection/watch> for details on usage and available
options.

=for Pod::Coverage connected
send_admin_command
send_direct_op
send_read_op
send_write_op

=head1 DEPLOYMENT TOPOLOGY

MongoDB can operate as a single server or as a distributed system.  One or more
servers that collectively provide access to a single logical set of MongoDB
databases are referred to as a "deployment".

There are three types of deployments:

=over 4

=item *

Single server – a stand-alone mongod database

=item *

Replica set – a set of mongod databases with data replication and fail-over capability

=item *

Sharded cluster – a distributed deployment that spreads data across one or more shards, each of which can be a replica set.  Clients communicate with a mongos process that routes operations to the correct share.

=back

The state of a deployment, including its type, which servers are members, the
server types of members and the round-trip network latency to members is
referred to as the "topology" of the deployment.

To the greatest extent possible, the MongoDB driver abstracts away the details
of communicating with different deployment types.  It determines the deployment
topology through a combination of the connection string, configuration options
and direct discovery communicating with servers in the deployment.

=head1 CONNECTION STRING URI

MongoDB uses a pseudo-URI connection string to specify one or more servers to
connect to, along with configuration options.

NOTE: any non-printable ASCII characters should be UTF-8 encoded and converted
URL-escaped characters.

To connect to more than one database server, provide host or host:port pairs
as a comma separated list:

    mongodb://host1[:port1][,host2[:port2],...[,hostN[:portN]]]

This list is referred to as the "seed list".  An arbitrary number of hosts can
be specified.  If a port is not specified for a given host, it will default to
27017.

If multiple hosts are given in the seed list or discovered by talking to
servers in the seed list, they must all be replica set members or must all be
mongos servers for a sharded cluster.

A replica set B<MUST> have the C<replicaSet> option set to the replica set
name.

If there is only single host in the seed list and C<replicaSet> is not
provided, the deployment is treated as a single server deployment and all
reads and writes will be sent to that host.

Providing a replica set member as a single host without the set name is the
way to get a "direct connection" for carrying out administrative activities
on that server.

The connection string may also have a username and password:

    mongodb://username:password@host1:port1,host2:port2

The username and password must be URL-escaped.

A optional database name for authentication may be given:

    mongodb://username:password@host1:port1,host2:port2/my_database

Finally, connection string options may be given as URI attribute pairs in a query
string:

    mongodb://host1:port1,host2:port2/?ssl=1&wtimeoutMS=1000
    mongodb://username:password@host1:port1,host2:port2/my_database?ssl=1&wtimeoutMS=1000

The currently supported connection string options are:

=over 4

=item *

C<appName>

=item *

C<authMechanism>

=item *

C<authMechanismProperties>

=item *

C<authSource>

=item *

C<compressors>

=item *

C<connect>

=item *

C<connectTimeoutMS>

=item *

C<heartbeatFrequencyMS>

=item *

C<journal>

=item *

C<localThresholdMS>

=item *

C<maxStalenessSeconds>

=item *

C<maxTimeMS>

=item *

C<readConcernLevel>

=item *

C<readPreference>

=item *

C<readPreferenceTags>

=item *

C<replicaSet>

=item *

C<retryReads>

=item *

C<retryWrites>

=item *

C<serverSelectionTimeoutMS>

=item *

C<serverSelectionTryOnce>

=item *

C<socketCheckIntervalMS>

=item *

C<socketTimeoutMS>

=item *

C<ssl>

=item *

C<tls> (an alias for C<ssl>)

=item *

C<tlsAllowInvalidCertificates>

=item *

C<tlsAllowInvalidHostnames>

=item *

C<tlsCAFile>

=item *

C<tlsCertificateKeyFile>

=item *

C<tlsCertificateKeyFilePassword>

=item *

C<tlsInsecure>

=item *

C<w>

=item *

C<wTimeoutMS>

=item *

C<zlibCompressionLevel>

=back

B<NOTE>: Options specified in the connection string take precedence over options
provided as constructor arguments.

See the official MongoDB documentation on connection strings for more on the URI
format and connection string options:
L<http://docs.mongodb.org/manual/reference/connection-string/>.

=head1 SERVER SELECTION

For a single server deployment or a direct connection to a mongod or
mongos, all reads and writes are sent to that server.  Any read-preference
is ignored.

When connected to a deployment with multiple servers, such as a replica set
or sharded cluster, the driver chooses a server for operations based on the
type of operation (read or write), application-provided server selector, the
types of servers available and a read preference.

For a replica set deployment, writes are sent to the primary (if available)
and reads are sent to a server based on the L</read_preference> attribute,
which defaults to sending reads to the primary.  See
L<MongoDB::ReadPreference> for more.

For a sharded cluster reads and writes are distributed across mongos
servers in the seed list.  Any read preference is passed through to the
mongos and used by it when executing reads against shards.

If multiple servers can service an operation (e.g. multiple mongos servers,
or multiple replica set members), one is chosen by filtering with server
selector and then at random from within the "latency window".  The server
with the shortest average round-trip time (RTT) is always in the window.
Any servers with an average round-trip time less than or equal to the
shortest RTT plus the L</local_threshold_ms> are also in the latency window.

If a suitable server is not immediately available, what happens next
depends on the L</server_selection_try_once> option.

If that option is true, a single topology scan will be performed.
Afterwards if a suitable server is available, it will be returned;
otherwise, an exception is thrown.

If that option is false, the driver will do topology scans repeatedly
looking for a suitable server.  When more than
L</server_selection_timeout_ms> milliseconds have elapsed since the start
of server selection without a suitable server being found, an exception is
thrown.

B<Note>: the actual maximum wait time for server selection could be as long
C<server_selection_timeout_ms> plus the amount of time required to do a
topology scan.

=head1 SERVER MONITORING AND FAILOVER

When the client first needs to find a server for a database operation, all
servers from the L</host> attribute are scanned to determine which servers to
monitor.  If the deployment is a replica set, additional hosts may be
discovered in this process.  Invalid hosts are dropped.

After the initial scan, whenever the servers have not been checked in
L</heartbeat_frequency_ms> milliseconds, the scan will be repeated.  This
amortizes monitoring time over many of operations.  Additionally, if a
socket has been idle for a while, it will be checked before being used for
an operation.

If a server operation fails because of a "not master" or "node is
recovering" error, or if there is a network error or timeout, then the
server is flagged as unavailable and exception will be thrown.  See
L<MongoDB::Errors> for exception types.

If the error is caught and handled, the next operation will rescan all
servers immediately to update its view of the topology.  The driver can
continue to function as long as servers are suitable per L</SERVER
SELECTION>.

When catching an exception, users must determine whether or not their
application should retry an operation based on the specific operation
attempted and other use-case-specific considerations.  For automating
retries despite exceptions, consider using the L<Try::Tiny::Retry> module.

=head1 TRANSPORT LAYER SECURITY

B<Warning>: industry best practices, and some regulations, require the use
of TLS 1.1 or newer.

Some operating systems or versions may not provide an OpenSSL version new
enough to support the latest TLS protocols.  If your OpenSSL library
version number is less than 1.0.1, then support for TLS 1.1 or newer is not
available. Contact your operating system vendor for a solution or upgrade
to a newer operating system distribution.

See also the documentation for L<Net::SSLeay> for details on installing and
compiling against OpenSSL.

TLS connections in the driver rely on the default settings provided by
L<IO::Socket::SSL>, but allow you to pass custom configuration to it.
Please read its documentation carefully to see how to control your TLS
configuration.

=head1 AUTHENTICATION

The MongoDB server provides several authentication mechanisms, though some
are only available in the Enterprise edition.

MongoDB client authentication is controlled via the L</auth_mechanism>
attribute, which takes one of the following values:

B<NOTE>: MONGODB-CR was deprecated with the release of MongoDB 3.6 and
is no longer supported by MongoDB 4.0.

=over 4

=item *

MONGODB-CR -- legacy username-password challenge-response (< 4.0)

=item *

SCRAM-SHA-1 -- secure username-password challenge-response (3.0+)

=item *

MONGODB-X509 -- SSL client certificate authentication (2.6+)

=item *

PLAIN -- LDAP authentication via SASL PLAIN (Enterprise only)

=item *

GSSAPI -- Kerberos authentication (Enterprise only)

=back

The mechanism to use depends on the authentication configuration of the
server.  See the core documentation on authentication:
L<http://docs.mongodb.org/manual/core/access-control/>.

Usage information for each mechanism is given below.

=head2 MONGODB-CR and SCRAM-SHA-1 (for username/password)

These mechanisms require a username and password, given either as
constructor attributes or in the C<host> connection string.

If a username is provided and an authentication mechanism is not specified,
the client will use SCRAM-SHA-1 for version 3.0 or later servers and will
fall back to MONGODB-CR for older servers.

    my $mc = MongoDB::MongoClient->new(
        host => "mongodb://mongo.example.com/",
        username => "johndoe",
        password => "trustno1",
    );

    my $mc = MongoDB::MongoClient->new(
        host => "mongodb://johndoe:trustno1@mongo.example.com/",
    );

Usernames and passwords will be UTF-8 encoded before use.  The password is
never sent over the wire -- only a secure digest is used.  The SCRAM-SHA-1
mechanism is the Salted Challenge Response Authentication Mechanism
defined in L<RFC 5802|http://tools.ietf.org/html/rfc5802>.

The default database for authentication is 'admin'.  If another database
name should be used, specify it with the C<db_name> attribute or via the
connection string.

    db_name => auth_db

    mongodb://johndoe:trustno1@mongo.example.com/auth_db

=head2 MONGODB-X509 (for SSL client certificate)

X509 authentication requires SSL support (L<IO::Socket::SSL>), requires
that a client certificate be configured in the ssl parameters, and requires
specifying the "MONGODB-X509" authentication mechanism.

    my $mc = MongoDB::MongoClient->new(
        host => "mongodb://sslmongo.example.com/",
        ssl => {
            SSL_ca_file   => "certs/ca.pem",
            SSL_cert_file => "certs/client.pem",
        },
        auth_mechanism => "MONGODB-X509",
    );

B<Note>: Since MongoDB Perl driver v1.8.0, you no longer need to specify a
C<username> parameter for X509 authentication; the username will be
extracted automatically from the certificate.

=head2 PLAIN (for LDAP)

This mechanism requires a username and password, which will be UTF-8
encoded before use.  The C<auth_mechanism> parameter must be given as a
constructor attribute or in the C<host> connection string:

    my $mc = MongoDB::MongoClient->new(
        host => "mongodb://mongo.example.com/",
        username => "johndoe",
        password => "trustno1",
        auth_mechanism => "PLAIN",
    );

    my $mc = MongoDB::MongoClient->new(
        host => "mongodb://johndoe:trustno1@mongo.example.com/authMechanism=PLAIN",
    );

=head2 GSSAPI (for Kerberos)

Kerberos authentication requires the CPAN module L<Authen::SASL> and a
GSSAPI-capable backend.

On Debian systems, L<Authen::SASL> may be available as
C<libauthen-sasl-perl>; on RHEL systems, it may be available as
C<perl-Authen-SASL>.

The L<Authen::SASL::Perl> backend comes with L<Authen::SASL> and requires
the L<GSSAPI> CPAN module for GSSAPI support.  On Debian systems, this may
be available as C<libgssapi-perl>; on RHEL systems, it may be available as
C<perl-GSSAPI>.

Installing the L<GSSAPI> module from CPAN rather than an OS package
requires C<libkrb5> and the C<krb5-config> utility (available for
Debian/RHEL systems in the C<libkrb5-dev> package).

Alternatively, the L<Authen::SASL::XS> or L<Authen::SASL::Cyrus> modules
may be used.  Both rely on Cyrus C<libsasl>.  L<Authen::SASL::XS> is
preferred, but not yet available as an OS package.  L<Authen::SASL::Cyrus>
is available on Debian as C<libauthen-sasl-cyrus-perl> and on RHEL as
C<perl-Authen-SASL-Cyrus>.

Installing L<Authen::SASL::XS> or L<Authen::SASL::Cyrus> from CPAN requires
C<libsasl>.  On Debian systems, it is available from C<libsasl2-dev>; on
RHEL, it is available in C<cyrus-sasl-devel>.

To use the GSSAPI mechanism, first run C<kinit> to authenticate with the ticket
granting service:

    $ kinit johndoe@EXAMPLE.COM

Configure MongoDB::MongoClient with the principal name as the C<username>
parameter and specify 'GSSAPI' as the C<auth_mechanism>:

    my $mc = MongoDB::MongoClient->new(
        host => 'mongodb://mongo.example.com',
        username => 'johndoe@EXAMPLE.COM',
        auth_mechanism => 'GSSAPI',
    );

Both can be specified in the C<host> connection string, keeping in mind
that the '@' in the principal name must be encoded as "%40":

    my $mc = MongoDB::MongoClient->new(
        host =>
          'mongodb://johndoe%40EXAMPLE.COM@mongo.example.com/?authMechanism=GSSAPI',
    );

The default service name is 'mongodb'.  It can be changed with the
C<auth_mechanism_properties> attribute or in the connection string.

    auth_mechanism_properties => { SERVICE_NAME => 'other_service' }

    mongodb://.../?authMechanism=GSSAPI&authMechanismProperties=SERVICE_NAME:other_service

=head1 THREAD-SAFETY AND FORK-SAFETY

You B<MUST> call the L</reconnect> method on any MongoDB::MongoClient objects
after forking or spawning a thread.

B<NOTE>: Per L<threads> documentation, use of Perl threads is discouraged by the
maintainers of Perl and the MongoDB Perl driver does not test or provide support
for use with threads.

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
