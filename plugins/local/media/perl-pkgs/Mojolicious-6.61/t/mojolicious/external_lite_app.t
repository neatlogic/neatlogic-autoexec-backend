use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;

use FindBin;
require "$FindBin::Bin/external/myapp.pl";

use Test::Mojo;

my $t = Test::Mojo->new;

# Template from myapp.pl
$t->get_ok('/')->status_is(200)->content_is(<<'EOF');
myapp
works ♥!Insecure!Insecure!

too!works!!!Mojolicious::Plugin::Config::Sandbox
<a href="/">Test</a>
<form action="/%E2%98%83">
  <input type="submit" value="☃">
</form>
EOF

# Static file from myapp.pl
$t->get_ok('/index.html')->status_is(200)
  ->content_is("External static file!\n");

# Echo from myapp.pl
$t->get_ok('/echo')->status_is(200)->content_is('echo: nothing!');

# Chunked response from myapp.pl
$t->get_ok('/stream')->status_is(200)->content_is('hello!');

# URL generated by myapp.pl
$t->get_ok('/url/☃')->status_is(200)
  ->content_is('/url/%E2%98%83.json -> /%E2%98%83/stream!');

done_testing();
