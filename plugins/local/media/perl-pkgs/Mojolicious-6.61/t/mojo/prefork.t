use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_PREFORK to enable this test (developer only!)'
  unless $ENV{TEST_PREFORK};

use File::Basename 'dirname';
use File::Spec::Functions 'catfile';
use Mojo::IOLoop::Server;
use Mojo::Server::Prefork;
use Mojo::UserAgent;
use Mojo::Util 'spurt';

# Manage and clean up PID file
my $prefork = Mojo::Server::Prefork->new;
my $file    = $prefork->pid_file;
ok !$prefork->check_pid, 'no process id';
spurt "\n", $file;
ok -e $file, 'file exists';
ok !$prefork->check_pid, 'no process id';
ok !-e $file, 'file has been cleaned up';
$prefork->ensure_pid_file;
ok -e $file, 'file exists';
is $prefork->check_pid, $$, 'right process id';
undef $prefork;
ok !-e $file, 'file has been cleaned up';

# Bad PID file
my $bad = catfile dirname(__FILE__), 'does_not_exist', 'test.pid';
$prefork = Mojo::Server::Prefork->new(pid_file => $bad);
$prefork->app->log->level('fatal');
my $log = '';
my $cb = $prefork->app->log->on(message => sub { $log .= pop });
eval { $prefork->ensure_pid_file };
like $@,     qr/Can't create process id file/, 'right error';
unlike $log, qr/Creating process id file/,     'right message';
like $log,   qr/Can't create process id file/, 'right message';
$prefork->app->log->unsubscribe(message => $cb);

# Multiple workers and graceful shutdown
my $port = Mojo::IOLoop::Server::->generate_port;
$prefork = Mojo::Server::Prefork->new(
  heartbeat_interval => 0.5,
  listen             => ["http://*:$port"]
);
$prefork->unsubscribe('request');
$prefork->on(
  request => sub {
    my ($prefork, $tx) = @_;
    $tx->res->code(200)->body('just works!');
    $tx->resume;
  }
);
is $prefork->workers, 4, 'start with four workers';
my (@spawn, @reap, $worker, $tx, $graceful);
$prefork->on(spawn => sub { push @spawn, pop });
$prefork->on(
  heartbeat => sub {
    my ($prefork, $pid) = @_;
    $worker = $pid;
    return if $prefork->healthy < 4;
    $tx = Mojo::UserAgent->new->get("http://127.0.0.1:$port");
    kill 'QUIT', $$;
  }
);
$prefork->on(reap => sub { push @reap, pop });
$prefork->on(finish => sub { $graceful = pop });
$log = '';
$cb = $prefork->app->log->on(message => sub { $log .= pop });
is $prefork->healthy, 0, 'no healthy workers';
$prefork->run;
is scalar @spawn, 4, 'four workers spawned';
is scalar @reap,  4, 'four workers reaped';
ok !!grep { $worker eq $_ } @spawn, 'worker has a heartbeat';
ok $graceful, 'server has been stopped gracefully';
is_deeply [sort @spawn], [sort @reap], 'same process ids';
is $tx->res->code, 200,           'right status';
is $tx->res->body, 'just works!', 'right content';
like $log, qr/Listening at/,                         'right message';
like $log, qr/Manager $$ started/,                   'right message';
like $log, qr/Creating process id file/,             'right message';
like $log, qr/Stopping worker $spawn[0] gracefully/, 'right message';
like $log, qr/Worker $spawn[0] stopped/,             'right message';
like $log, qr/Manager $$ stopped/,                   'right message';
$prefork->app->log->unsubscribe(message => $cb);

# Process id file
is $prefork->check_pid, $$, 'right process id';
my $pid = $prefork->pid_file;
ok -e $pid, 'process id file has been created';
undef $prefork;
ok !-e $pid, 'process id file has been removed';

# One worker and immediate shutdown
$port    = Mojo::IOLoop::Server->generate_port;
$prefork = Mojo::Server::Prefork->new(
  accepts            => 500,
  heartbeat_interval => 0.5,
  listen             => ["http://*:$port"],
  workers            => 1
);
$prefork->unsubscribe('request');
$prefork->on(
  request => sub {
    my ($prefork, $tx) = @_;
    $tx->res->code(200)->body('works too!');
    $tx->resume;
  }
);
my $count = $tx = $graceful = undef;
@spawn = @reap = ();
$prefork->on(spawn => sub { push @spawn, pop });
$prefork->once(
  heartbeat => sub {
    $tx = Mojo::UserAgent->new->get("http://127.0.0.1:$port");
    kill 'TERM', $$;
  }
);
$prefork->on(reap => sub { push @reap, pop });
$prefork->on(finish => sub { $graceful = pop });
$prefork->run;
is $prefork->ioloop->max_accepts, 500, 'right value';
is scalar @spawn, 1, 'one worker spawned';
is scalar @reap,  1, 'one worker reaped';
ok !$graceful, 'server has been stopped immediately';
is $tx->res->code, 200,          'right status';
is $tx->res->body, 'works too!', 'right content';

done_testing();
