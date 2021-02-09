use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::Server;

plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.94+ required for this test!'
  unless Mojo::IOLoop::Server::TLS;

use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/' => {text => 'works!'};

# Web server with valid certificates
my $daemon = Mojo::Server::Daemon->new(
  app    => app,
  ioloop => Mojo::IOLoop->singleton,
  silent => 1
);
my $listen
  = 'https://127.0.0.1'
  . '?cert=t/mojo/certs/server.crt'
  . '&key=t/mojo/certs/server.key'
  . '&ca=t/mojo/certs/ca.crt';
$daemon->listen([$listen])->start;
my $port = Mojo::IOLoop->acceptor($daemon->acceptors->[0])->port;

# No certificate
my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
my $tx = $ua->get("https://127.0.0.1:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';
$tx = $ua->get("https://127.0.0.1:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';

# Valid certificates
$ua->ca('t/mojo/certs/ca.crt')->cert('t/mojo/certs/client.crt')
  ->key('t/mojo/certs/client.key');
$tx = $ua->get("https://127.0.0.1:$port");
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Valid certificates (env)
$ua = Mojo::UserAgent->new(ioloop => $ua->ioloop);
{
  local $ENV{MOJO_CA_FILE}   = 't/mojo/certs/ca.crt';
  local $ENV{MOJO_CERT_FILE} = 't/mojo/certs/client.crt';
  local $ENV{MOJO_KEY_FILE}  = 't/mojo/certs/client.key';
  $tx = $ua->get("https://127.0.0.1:$port");
  is $ua->ca,   't/mojo/certs/ca.crt',     'right path';
  is $ua->cert, 't/mojo/certs/client.crt', 'right path';
  is $ua->key,  't/mojo/certs/client.key', 'right path';
  ok $tx->success, 'successful';
  is $tx->res->code, 200,      'right status';
  is $tx->res->body, 'works!', 'right content';
}

# Invalid certificate
$ua = Mojo::UserAgent->new(ioloop => $ua->ioloop);
$ua->cert('t/mojo/certs/bad.crt')->key('t/mojo/certs/bad.key');
$tx = $ua->get("https://127.0.0.1:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';

# Web server with valid certificates and no verification
$daemon = Mojo::Server::Daemon->new(
  app    => app,
  ioloop => Mojo::IOLoop->singleton,
  silent => 1
);
$listen
  = 'https://127.0.0.1'
  . '?cert=t/mojo/certs/server.crt'
  . '&key=t/mojo/certs/server.key'
  . '&ca=t/mojo/certs/ca.crt'
  . '&ciphers=AES256-SHA:ALL'
  . '&verify=0x00'
  . '&version=SSLv3';
$daemon->listen([$listen])->start;
$port = Mojo::IOLoop->acceptor($daemon->acceptors->[0])->port;

# Invalid certificate
$ua = Mojo::UserAgent->new(ioloop => $ua->ioloop);
$ua->cert('t/mojo/certs/bad.crt')->key('t/mojo/certs/bad.key');
IO::Socket::SSL::set_defaults(SSL_version => 'SSLv3');
$tx = $ua->get("https://127.0.0.1:$port");
ok $tx->success, 'successful';
ok !$tx->error, 'no error';
is $ua->ioloop->stream($tx->connection)->handle->get_cipher, 'AES256-SHA',
  'AES256-SHA has been negotiatied';
is $ua->ioloop->stream($tx->connection)->handle->get_sslversion, 'SSLv3',
  'SSLv3 has been negotiatied';

done_testing();
