use Mojo::Base -strict;

use Test::More;
use Mojo::Cookie::Response;
use Mojo::Transaction::HTTP;
use Mojo::URL;
use Mojo::UserAgent::CookieJar;

# Missing values
my $jar = Mojo::UserAgent::CookieJar->new;
$jar->add(Mojo::Cookie::Response->new(domain => 'example.com'));
$jar->add(Mojo::Cookie::Response->new(name   => 'foo'));
$jar->add(Mojo::Cookie::Response->new(name => 'foo', domain => 'example.com'));
$jar->add(Mojo::Cookie::Response->new(domain => 'example.com', path => '/'));
is_deeply $jar->all, [], 'no cookies';

# Session cookie
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'example.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  ),
  Mojo::Cookie::Response->new(
    domain => 'example.com',
    path   => '/',
    name   => 'just',
    value  => 'works'
  )
);
my $cookies = $jar->find(Mojo::URL->new('http://example.com/foo'));
is $cookies->[0]->name,  'foo',   'right name';
is $cookies->[0]->value, 'bar',   'right value';
is $cookies->[1]->name,  'just',  'right name';
is $cookies->[1]->value, 'works', 'right value';
is $cookies->[2], undef, 'no third cookie';
$cookies = $jar->find(Mojo::URL->new('http://example.com/foo'));
is $cookies->[0]->name,  'foo',   'right name';
is $cookies->[0]->value, 'bar',   'right value';
is $cookies->[1]->name,  'just',  'right name';
is $cookies->[1]->value, 'works', 'right value';
is $cookies->[2], undef, 'no third cookie';
$cookies = $jar->find(Mojo::URL->new('http://example.com/foo'));
is $cookies->[0]->name,  'foo',   'right name';
is $cookies->[0]->value, 'bar',   'right value';
is $cookies->[1]->name,  'just',  'right name';
is $cookies->[1]->value, 'works', 'right value';
is $cookies->[2], undef, 'no third cookie';
$cookies = $jar->find(Mojo::URL->new('http://example.com/foo'));
is $cookies->[0]->name,  'foo',   'right name';
is $cookies->[0]->value, 'bar',   'right value';
is $cookies->[1]->name,  'just',  'right name';
is $cookies->[1]->value, 'works', 'right value';
is $cookies->[2], undef, 'no third cookie';
$cookies = $jar->find(Mojo::URL->new('http://example.com/foo'));
is $cookies->[0]->name,  'foo',   'right name';
is $cookies->[0]->value, 'bar',   'right value';
is $cookies->[1]->name,  'just',  'right name';
is $cookies->[1]->value, 'works', 'right value';
is $cookies->[2], undef, 'no third cookie';
$jar->empty;
$cookies = $jar->find(Mojo::URL->new('http://example.com/foo'));
is $cookies->[0], undef, 'no cookies';

# "localhost"
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'localhost',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  ),
  Mojo::Cookie::Response->new(
    domain => 'foo.localhost',
    path   => '/foo',
    name   => 'bar',
    value  => 'baz'
  )
);
$cookies = $jar->find(Mojo::URL->new('http://localhost/foo'));
is $cookies->[0]->name,  'foo', 'right name';
is $cookies->[0]->value, 'bar', 'right value';
is $cookies->[1], undef, 'no second cookie';
$cookies = $jar->find(Mojo::URL->new('http://foo.localhost/foo'));
is $cookies->[0]->name,  'bar', 'right name';
is $cookies->[0]->value, 'baz', 'right value';
is $cookies->[1]->name,  'foo', 'right name';
is $cookies->[1]->value, 'bar', 'right value';
is $cookies->[2], undef, 'no third cookie';
$cookies = $jar->find(Mojo::URL->new('http://foo.bar.localhost/foo'));
is $cookies->[0]->name,  'foo', 'right name';
is $cookies->[0]->value, 'bar', 'right value';
is $cookies->[1], undef, 'no second cookie';
$cookies = $jar->find(Mojo::URL->new('http://bar.foo.localhost/foo'));
is $cookies->[0]->name,  'bar', 'right name';
is $cookies->[0]->value, 'baz', 'right value';
is $cookies->[1]->name,  'foo', 'right name';
is $cookies->[1]->value, 'bar', 'right value';
is $cookies->[2], undef, 'no third cookie';

# Huge cookie
$jar = Mojo::UserAgent::CookieJar->new->max_cookie_size(1024);
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'example.com',
    path   => '/foo',
    name   => 'small',
    value  => 'x'
  ),
  Mojo::Cookie::Response->new(
    domain => 'example.com',
    path   => '/foo',
    name   => 'big',
    value  => 'x' x 1024
  ),
  Mojo::Cookie::Response->new(
    domain => 'example.com',
    path   => '/foo',
    name   => 'huge',
    value  => 'x' x 1025
  )
);
$cookies = $jar->find(Mojo::URL->new('http://example.com/foo'));
is $cookies->[0]->name,  'small', 'right name';
is $cookies->[0]->value, 'x',     'right value';
is $cookies->[1]->name,  'big',   'right name';
is $cookies->[1]->value, 'x' x 1024, 'right value';
is $cookies->[2], undef, 'no second cookie';

# Expired cookies
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'example.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  ),
  Mojo::Cookie::Response->new(
    domain  => 'labs.example.com',
    path    => '/',
    name    => 'baz',
    value   => '24',
    max_age => -1
  )
);
my $expired = Mojo::Cookie::Response->new(
  domain => 'labs.example.com',
  path   => '/',
  name   => 'baz',
  value  => '23'
);
$jar->add($expired->expires(time - 1));
$cookies = $jar->find(Mojo::URL->new('http://labs.example.com/foo'));
is $cookies->[0]->name,  'foo', 'right name';
is $cookies->[0]->value, 'bar', 'right value';
is $cookies->[1], undef, 'no second cookie';

# Replace cookie
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'example.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar1'
  ),
  Mojo::Cookie::Response->new(
    domain => 'example.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar2'
  )
);
$cookies = $jar->find(Mojo::URL->new('http://example.com/foo'));
is $cookies->[0]->name,  'foo',  'right name';
is $cookies->[0]->value, 'bar2', 'right value';
is $cookies->[1], undef, 'no second cookie';

# Switch between secure and normal cookies
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'example.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'foo',
    secure => 1
  )
);
$cookies = $jar->find(Mojo::URL->new('https://example.com/foo'));
is $cookies->[0]->name,  'foo', 'right name';
is $cookies->[0]->value, 'foo', 'right value';
$cookies = $jar->find(Mojo::URL->new('http://example.com/foo'));
is scalar @$cookies, 0, 'no insecure cookie';
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'example.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  )
);
$cookies = $jar->find(Mojo::URL->new('http://example.com/foo'));
is $cookies->[0]->name,  'foo', 'right name';
is $cookies->[0]->value, 'bar', 'right value';
$cookies = $jar->find(Mojo::URL->new('https://example.com/foo'));
is $cookies->[0]->name,  'foo', 'right name';
is $cookies->[0]->value, 'bar', 'right value';
is $cookies->[1], undef, 'no second cookie';

# "(" in path
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'example.com',
    path   => '/foo(bar',
    name   => 'foo',
    value  => 'bar'
  )
);
$cookies = $jar->find(Mojo::URL->new('http://example.com/foo(bar'));
is $cookies->[0]->name,  'foo', 'right name';
is $cookies->[0]->value, 'bar', 'right value';
is $cookies->[1], undef, 'no second cookie';
$cookies = $jar->find(Mojo::URL->new('http://example.com/foo(bar/baz'));
is $cookies->[0]->name,  'foo', 'right name';
is $cookies->[0]->value, 'bar', 'right value';
is $cookies->[1], undef, 'no second cookie';

# Gather and prepare cookies without domain and path
$jar = Mojo::UserAgent::CookieJar->new;
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://mojolicious.org/perldoc/Mojolicious');
$tx->res->cookies(
  Mojo::Cookie::Response->new(name => 'foo', value => 'without'));
$jar->collect($tx);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://mojolicious.org/perldoc');
$jar->prepare($tx);
is $tx->req->cookie('foo')->name,  'foo',     'right name';
is $tx->req->cookie('foo')->value, 'without', 'right value';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://mojolicious.org/perldoc');
$jar->prepare($tx);
is $tx->req->cookie('foo')->name,  'foo',     'right name';
is $tx->req->cookie('foo')->value, 'without', 'right value';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://www.mojolicious.org/perldoc');
$jar->prepare($tx);
is $tx->req->cookie('foo'), undef, 'no cookie';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://mojolicious.org/whatever');
$jar->prepare($tx);
is $tx->req->cookie('foo'), undef, 'no cookie';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://...many...dots...');
$jar->prepare($tx);
is $tx->req->cookie('foo'), undef, 'no cookie';

# Gather and prepare cookies with same name (with and without domain)
$jar = Mojo::UserAgent::CookieJar->new;
$tx  = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://example.com/test');
$tx->res->cookies(
  Mojo::Cookie::Response->new(name => 'foo', value => 'without'),
  Mojo::Cookie::Response->new(
    name   => 'foo',
    value  => 'with',
    domain => 'example.com'
  )
);
$jar->collect($tx);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://example.com/test');
$jar->prepare($tx);
$cookies = $tx->req->every_cookie('foo');
is $cookies->[0]->name,  'foo',     'right name';
is $cookies->[0]->value, 'without', 'right value';
is $cookies->[1]->name,  'foo',     'right name';
is $cookies->[1]->value, 'with',    'right value';
is $cookies->[2], undef, 'no third cookie';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://www.example.com/test');
$jar->prepare($tx);
$cookies = $tx->req->every_cookie('foo');
is $cookies->[0]->name,  'foo',  'right name';
is $cookies->[0]->value, 'with', 'right value';
is $cookies->[1], undef, 'no second cookie';

# Gather and prepare cookies for "localhost" (valid and invalid)
$jar = Mojo::UserAgent::CookieJar->new;
$tx  = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://localhost:3000');
$tx->res->cookies(
  Mojo::Cookie::Response->new(
    name   => 'foo',
    value  => 'local',
    domain => 'localhost'
  ),
  Mojo::Cookie::Response->new(
    name   => 'bar',
    value  => 'local',
    domain => 'bar.localhost'
  )
);
$jar->collect($tx);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://localhost:8080');
$jar->prepare($tx);
is $tx->req->cookie('foo')->name,  'foo',   'right name';
is $tx->req->cookie('foo')->value, 'local', 'right value';
is $tx->req->cookie('bar'), undef, 'no cookie';

# Gather and prepare cookies for unknown public suffix (with IDNA)
$jar = Mojo::UserAgent::CookieJar->new;
$tx  = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://bücher.com/foo');
$tx->res->cookies(
  Mojo::Cookie::Response->new(
    domain => 'com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  ),
  Mojo::Cookie::Response->new(
    domain => 'xn--bcher-kva.com',
    path   => '/foo',
    name   => 'bar',
    value  => 'baz'
  )
);
$jar->collect($tx);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://bücher.com/foo');
$jar->prepare($tx);
is $tx->req->cookie('foo')->name,  'foo', 'right name';
is $tx->req->cookie('foo')->value, 'bar', 'right value';
is $tx->req->cookie('bar')->name,  'bar', 'right name';
is $tx->req->cookie('bar')->value, 'baz', 'right value';

# Gather and prepare cookies for public suffix (with IDNA)
$jar = Mojo::UserAgent::CookieJar->new;
$tx  = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://bücher.com/foo');
$tx->res->cookies(
  Mojo::Cookie::Response->new(
    domain => 'com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  ),
  Mojo::Cookie::Response->new(
    domain => 'xn--bcher-kva.com',
    path   => '/foo',
    name   => 'bar',
    value  => 'baz'
  )
);
$jar->ignore(sub { shift->domain eq 'com' })->collect($tx);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://bücher.com/foo');
$jar->prepare($tx);
is $tx->req->cookie('foo'), undef, 'no cookie';
is $tx->req->cookie('bar')->name,  'bar', 'right name';
is $tx->req->cookie('bar')->value, 'baz', 'right value';

# Gather and prepare cookies with domain and path
$jar = Mojo::UserAgent::CookieJar->new;
$tx  = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://LABS.bücher.Com/perldoc/Mojolicious');
$tx->res->cookies(
  Mojo::Cookie::Response->new(
    name   => 'foo',
    value  => 'with',
    domain => 'labs.xn--bcher-kva.com',
    path   => '/perldoc'
  ),
  Mojo::Cookie::Response->new(
    name   => 'bar',
    value  => 'with',
    domain => 'xn--bcher-kva.com',
    path   => '/'
  ),
  Mojo::Cookie::Response->new(
    name   => '0',
    value  => 'with',
    domain => '.xn--bcher-kva.cOm',
    path   => '/%70erldoc/Mojolicious/'
  ),
);
$jar->collect($tx);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://labs.bücher.COM/perldoc/Mojolicious/Lite');
$jar->prepare($tx);
is $tx->req->cookie('foo')->name,  'foo',  'right name';
is $tx->req->cookie('foo')->value, 'with', 'right value';
is $tx->req->cookie('bar')->name,  'bar',  'right name';
is $tx->req->cookie('bar')->value, 'with', 'right value';
is $tx->req->cookie('0')->name,    '0',    'right name';
is $tx->req->cookie('0')->value,   'with', 'right value';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://bücher.COM/perldoc/Mojolicious/Lite');
$jar->prepare($tx);
is $tx->req->cookie('foo'), undef, 'no cookie';
is $tx->req->cookie('bar')->name,  'bar',  'right name';
is $tx->req->cookie('bar')->value, 'with', 'right value';
is $tx->req->cookie('0')->name,    '0',    'right name';
is $tx->req->cookie('0')->value,   'with', 'right value';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://labs.bücher.COM/Perldoc');
$jar->prepare($tx);
is $tx->req->cookie('foo'), undef, 'no cookie';
is $tx->req->cookie('bar')->name,  'bar',  'right name';
is $tx->req->cookie('bar')->value, 'with', 'right value';

# Gather and prepare cookies with IP address
$jar = Mojo::UserAgent::CookieJar->new;
$tx  = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://213.133.102.53/perldoc/Mojolicious');
$tx->res->cookies(
  Mojo::Cookie::Response->new(
    name   => 'foo',
    value  => 'valid',
    domain => '213.133.102.53'
  ),
  Mojo::Cookie::Response->new(name => 'bar', value => 'too')
);
$jar->collect($tx);
$tx = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://213.133.102.53/perldoc/Mojolicious');
$jar->prepare($tx);
is $tx->req->cookie('foo')->name,  'foo',   'right name';
is $tx->req->cookie('foo')->value, 'valid', 'right value';
is $tx->req->cookie('bar')->name,  'bar',   'right name';
is $tx->req->cookie('bar')->value, 'too',   'right value';

# Gather cookies with invalid expiration
$jar = Mojo::UserAgent::CookieJar->new;
$tx  = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://example.com');
$tx->res->cookies(
  Mojo::Cookie::Response->new(
    name    => 'foo',
    value   => 'bar',
    max_age => 'invalid'
  ),
  Mojo::Cookie::Response->new(name => 'bar', value => 'baz', max_age => 86400)
);
$jar->collect($tx);
is $jar->all->[0]->name,  'foo', 'right name';
is $jar->all->[0]->value, 'bar', 'right value';
ok !$jar->all->[0]->expires, 'does not expire';
is $jar->all->[1]->name,  'bar', 'right name';
is $jar->all->[1]->value, 'baz', 'right value';
ok $jar->all->[1]->expires, 'expires';

# Gather cookies with invalid domain
$jar = Mojo::UserAgent::CookieJar->new;
$tx  = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://labs.example.com/perldoc/Mojolicious');
$tx->res->cookies(
  Mojo::Cookie::Response->new(
    name   => 'foo',
    value  => 'invalid',
    domain => 'a.s.example.com'
  ),
  Mojo::Cookie::Response->new(
    name   => 'foo',
    value  => 'invalid',
    domain => 'mojolicious.org'
  )
);
$jar->collect($tx);
is_deeply $jar->all, [], 'no cookies';

# Gather cookies with invalid domain (IP address)
$jar = Mojo::UserAgent::CookieJar->new;
$tx  = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://213.133.102.53/perldoc/Mojolicious');
$tx->res->cookies(
  Mojo::Cookie::Response->new(
    name   => 'foo',
    value  => 'valid',
    domain => '213.133.102.53.'
  ),
  Mojo::Cookie::Response->new(
    name   => 'foo',
    value  => 'valid',
    domain => '.133.102.53'
  ),
  Mojo::Cookie::Response->new(
    name   => 'foo',
    value  => 'invalid',
    domain => '102.53'
  ),
  Mojo::Cookie::Response->new(
    name   => 'foo',
    value  => 'invalid',
    domain => '53'
  )
);
$jar->collect($tx);
is_deeply $jar->all, [], 'no cookies';

# Gather cookies with invalid path
$jar = Mojo::UserAgent::CookieJar->new;
$tx  = Mojo::Transaction::HTTP->new;
$tx->req->url->parse('http://labs.example.com/perldoc/Mojolicious');
$tx->res->cookies(
  Mojo::Cookie::Response->new(
    name  => 'foo',
    value => 'invalid',
    path  => '/perldoc/index.html'
  ),
  Mojo::Cookie::Response->new(
    name  => 'foo',
    value => 'invalid',
    path  => '/perldocMojolicious'
  ),
  Mojo::Cookie::Response->new(
    name  => 'foo',
    value => 'invalid',
    path  => '/perldoc.Mojolicious'
  )
);
$jar->collect($tx);
is_deeply $jar->all, [], 'no cookies';

done_testing();
