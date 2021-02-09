package Test::Foo;
use Mojo::Base 'Mojolicious::Controller';

sub bar  {1}
sub home {1}

package Test::Controller;
use Mojo::Base 'Mojolicious::Controller';

has 'render_called';

sub new {
  shift->SUPER::new(@_)->tap(sub { $_->app->log->level('fatal') });
}

sub render { shift->render_called(1) }

package main;
use Mojo::Base -strict;

use Test::More;
use Mojo::Upload;
use Mojolicious;

# Fresh controller
my $app = Mojolicious->new(secrets => ['works']);
my $c = $app->build_controller;
is $c->url_for('/'), '/', 'routes are working';

# Set
$c->stash(foo => 'bar');
is $c->stash('foo'), 'bar', 'set and return a stash value';

# Ref value
my $stash = $c->stash;
is ref $stash, 'HASH', 'return a hash reference';
is $stash->{foo}, 'bar', 'right value';

# Replace
$c->stash(foo => 'baz');
is $c->stash('foo'), 'baz', 'replace and return a stash value';

# Set 0
$c->stash(zero => 0);
is $c->stash('zero'), 0, 'set and return 0 value';

# Replace with 0
$c->stash(foo => 0);
is $c->stash('foo'), 0, 'replace and return 0 value';

# Use 0 as key
$c->stash(0 => 'boo');
is $c->stash('0'), 'boo', 'set and get with 0 as key';

# Delete
$stash = $c->stash;
delete $stash->{foo};
delete $stash->{0};
delete $stash->{zero};
is $c->stash->{foo}, undef, 'element has been deleted';
is $c->stash->{0}, undef, 'element has been deleted';
is $c->stash->{zero}, undef, 'element has been deleted';
$c->stash('foo' => 'zoo');
delete $c->stash->{foo};
is $c->stash->{foo}, undef, 'element has been deleted';

# Set via hash
$c->stash({a => 1, b => 2});
$stash = $c->stash;
is $c->stash->{a}, 1, 'right value';
is $c->stash->{b}, 2, 'right value';

# Override captures
is $c->param('foo'), undef, 'no value';
is $c->param(foo => 'works')->param('foo'), 'works', 'right value';
is $c->param(foo => 'too')->param('foo'),   'too',   'right value';
is $c->param(foo => qw(just works))->param('foo'), 'works', 'right value';
is_deeply $c->every_param('foo'), [qw(just works)], 'right values';
is_deeply $c->every_param('bar'), [], 'no values';
is $c->param(foo => undef)->param('foo'), undef, 'no value';
is $c->param(foo => Mojo::Upload->new(name => 'bar'))->param('foo')->name,
  'bar', 'right value';
is $c->param(foo => ['ba;r', 'baz'])->param('foo'), 'baz', 'right value';
is_deeply $c->every_param('foo'), ['ba;r', 'baz'], 'right values';

# Reserved stash values are hidden
$c = $app->build_controller;
is $c->param(action => 'test')->param('action'), undef, 'value is reserved';
is $c->param(app    => 'test')->param('app'),    undef, 'value is reserved';
is $c->param(cb     => 'test')->param('cb'),     undef, 'value is reserved';
is $c->param(controller => 'test')->param('controller'), undef,
  'value is reserved';
is $c->param(data    => 'test')->param('data'),    undef, 'value is reserved';
is $c->param(extends => 'test')->param('extends'), undef, 'value is reserved';
is $c->param(format  => 'test')->param('format'),  undef, 'value is reserved';
is $c->param(handler => 'test')->param('handler'), undef, 'value is reserved';
is $c->param(inline  => 'test')->param('inline'),  undef, 'value is reserved';
is $c->param(json    => 'test')->param('json'),    undef, 'value is reserved';
is $c->param(layout  => 'test')->param('layout'),  undef, 'value is reserved';
is $c->param(namespace => 'test')->param('namespace'), undef,
  'value is reserved';
is $c->param(path     => 'test')->param('path'),     undef, 'value is reserved';
is $c->param(status   => 'test')->param('status'),   undef, 'value is reserved';
is $c->param(template => 'test')->param('template'), undef, 'value is reserved';
is $c->param(text     => 'test')->param('text'),     undef, 'value is reserved';
is $c->param(variant  => 'test')->param('variant'),  undef, 'value is reserved';

# Controller with application and routes
$c = $app->controller_class('Test::Controller')->build_controller;
my $d = $c->app->routes;
ok $d, 'initialized';
$d->namespaces(['Test']);
$d->route('/')->over([])->to(controller => 'foo', action => 'home');
$d->route('/foo/(capture)')->to(controller => 'foo', action => 'bar');

# Cache
$c = $app->build_controller;
$c->req->method('GET');
$c->req->url->parse('/');
ok $d->dispatch($c), 'dispatched';
is $c->stash->{controller}, 'foo',  'right value';
is $c->stash->{action},     'home', 'right value';
is $c->match->stack->[0]{controller}, 'foo',  'right value';
is $c->match->stack->[0]{action},     'home', 'right value';
ok $c->render_called, 'rendered';
my $cache = $d->cache->get('GET:/:0');
ok $cache, 'route has been cached';
$c = $app->build_controller;
$c->req->method('GET');
$c->req->url->parse('/');
$d->match($c);
is $c->stash->{controller}, undef, 'no value';
is $c->stash->{action},     undef, 'no value';
is $c->match->stack->[0]{controller}, 'foo',  'right value';
is $c->match->stack->[0]{action},     'home', 'right value';
ok !$c->render_called, 'not rendered';
$c = $app->build_controller;
$c->req->method('GET');
$c->req->url->parse('/');
ok $d->dispatch($c), 'dispatched';
is $c->stash->{controller}, 'foo',  'right value';
is $c->stash->{action},     'home', 'right value';
is $c->match->stack->[0]{controller}, 'foo',  'right value';
is $c->match->stack->[0]{action},     'home', 'right value';
ok $c->render_called, 'rendered';
is_deeply $d->cache->get('GET:/:0'), $cache, 'cached route has been reused';

# 404 clean stash
$c = $app->build_controller;
$c->req->method('GET');
$c->req->url->parse('/not_found');
ok !$d->dispatch($c), 'not dispatched';
ok !$c->render_called, 'nothing rendered';

# No escaping
$c = $app->build_controller;
$c->req->method('POST');
$c->req->url->parse('/foo/hello');
$c->stash(test => 23);
ok $d->dispatch($c), 'dispatched';
is $c->stash->{controller}, 'foo',   'right value';
is $c->stash->{action},     'bar',   'right value';
is $c->stash->{capture},    'hello', 'right value';
is $c->stash->{test},       23,      'right value';
is $c->param('controller'), undef,   'no value';
is $c->param('action'),     undef,   'no value';
is $c->param('capture'),    'hello', 'right value';
$c->param(capture => 'bye');
is $c->param('controller'), undef, 'no value';
is $c->param('action'),     undef, 'no value';
is $c->param('capture'),    'bye', 'right value';
$c->param(capture => undef);
is $c->param('controller'), undef, 'no value';
is $c->param('action'),     undef, 'no value';
is $c->param('capture'),    undef, 'no value';
$c->req->param(foo => 'bar');
is $c->param('controller'), undef, 'no value';
is $c->param('action'),     undef, 'no value';
is $c->param('capture'),    undef, 'no value';
is $c->param('foo'),        'bar', 'right value';
$c->req->param(bar => 'baz');
is $c->param('controller'), undef, 'no value';
is $c->param('action'),     undef, 'no value';
is $c->param('capture'),    undef, 'no value';
is $c->param('foo'),        'bar', 'right value';
is $c->param('bar'),        'baz', 'right value';
$c->req->param(action => 'baz');
is $c->param('controller'), undef, 'no value';
is $c->param('action'),     'baz', 'no value';
is $c->param('capture'),    undef, 'no value';
is $c->param('foo'),        'bar', 'right value';
is $c->param('bar'),        'baz', 'right value';
ok $c->render_called, 'rendered';

# Escaping
$c = $app->build_controller;
$c->req->method('GET');
$c->req->url->parse('/foo/hello%20there');
ok $d->dispatch($c), 'dispatched';
is $c->stash->{controller}, 'foo',         'right value';
is $c->stash->{action},     'bar',         'right value';
is $c->stash->{capture},    'hello there', 'right value';
is $c->param('controller'), undef,         'no value';
is $c->param('action'),     undef,         'no value';
is $c->param('capture'),    'hello there', 'right value';
ok $c->render_called, 'rendered';

# Escaping UTF-8
$c = $app->build_controller;
$c->req->method('GET');
$c->req->url->parse('/foo/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82');
ok $d->dispatch($c), 'dispatched';
is $c->stash->{controller}, 'foo',          'right value';
is $c->stash->{action},     'bar',          'right value';
is $c->stash->{capture},    'привет', 'right value';
is $c->param('controller'), undef,          'no value';
is $c->param('action'),     undef,          'no value';
is $c->param('capture'),    'привет', 'right value';
ok $c->render_called, 'rendered';

# Not a WebSocket transaction
eval { $c->send('test') };
like $@, qr/^No WebSocket connection to send message to/, 'right error';

done_testing();
