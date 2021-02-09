# $Id: DES.pm,v 1.7 2001/05/02 21:59:33 btrott Exp $

package Net::SSH::Perl::Cipher::DES;

use strict;
use warnings;

use Net::SSH::Perl::Cipher;
use base qw( Net::SSH::Perl::Cipher );

use Net::SSH::Perl::Cipher::CBC;
use Crypt::DES;

sub new {
    my $class = shift;
    my $ciph = bless { }, $class;
    $ciph->init(@_) if @_;
    $ciph;
}

sub init {
    my $ciph = shift;
    my($key, $iv) = @_;
    my $des = Crypt::DES->new(substr $key, 0, 8);
    $ciph->{cbc} = Net::SSH::Perl::Cipher::CBC->new($des, $iv);
}

sub encrypt {
    my($ciph, $text) = @_;
    $ciph->{cbc}->encrypt($text);
}

sub decrypt {
    my($ciph, $text) = @_;
    $ciph->{cbc}->decrypt($text);
}

1;
__END__

=head1 NAME

Net::SSH::Perl::Cipher::DES - Wrapper for SSH DES support

=head1 SYNOPSIS

    use Net::SSH::Perl::Cipher;
    my $cipher = Net::SSH::Perl::Cipher->new('DES', $key);
    print $cipher->encrypt($plaintext);

=head1 DESCRIPTION

I<Net::SSH::Perl::Cipher::DES> provides DES encryption
support for I<Net::SSH::Perl>. To do so it wraps around
I<Crypt::DES>, a C/XS implementation of the DES algorithm.

The DES algorithm used here is in CBC filter mode with a
key length of 8 bytes.

=head1 AUTHOR & COPYRIGHTS

Please see the Net::SSH::Perl manpage for author, copyright,
and license information.

=cut
