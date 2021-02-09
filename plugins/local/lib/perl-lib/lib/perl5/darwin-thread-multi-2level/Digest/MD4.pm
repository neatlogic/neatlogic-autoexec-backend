package Digest::MD4;

use strict;
use vars qw($VERSION @ISA @EXPORT_OK);

$VERSION = '1.9';  # ActivePerl version adds hexhash() for compatibility

require Exporter;
*import = \&Exporter::import;
@EXPORT_OK = qw(md4 md4_hex md4_base64);

require DynaLoader;
@ISA=qw(DynaLoader);

eval {
    Digest::MD4->bootstrap($VERSION);
};
if ($@) {
    my $olderr = $@;
    eval {
	# Try to load the pure perl version
	require Digest::Perl::MD4;

	Digest::Perl::MD4->import(qw(md4 md4_hex md4_base64));
	push(@ISA, "Digest::Perl::MD4");  # make OO interface work
    };
    if ($@) {
	# restore the original error
	die $olderr;
    }
}
else {
    *reset = \&new;
}
# hash() and hexhash() was in Digest::MD4 1.1. Deprecated
sub hash {
    my ($self, $data) = @_;
    if (ref($self))
    {
	# This is an instance method call so reset the current context
	$self->reset();
    }
    else
    {
	# This is a static method invocation, create a temporary MD4 context
	$self = new Digest::MD4;
    }
    
    # Now do the hash
    $self->add($data);
    $self->digest();
}

sub hexhash
{
    my ($self, $data) = @_;

    unpack("H*", ($self->hash($data)));
}

1;
__END__

=head1 NAME

Digest::MD4 - Perl interface to the MD4 Algorithm

=head1 SYNOPSIS

 # Functional style
 use Digest::MD4 qw(md4 md4_hex md4_base64);

 $digest = md4($data);
 $digest = md4_hex($data);
 $digest = md4_base64($data);

 # OO style
 use Digest::MD4;

 $ctx = Digest::MD4->new;

 $ctx->add($data);
 $ctx->addfile(*FILE);

 $digest = $ctx->digest;
 $digest = $ctx->hexdigest;
 $digest = $ctx->b64digest;

=head1 DESCRIPTION

The C<Digest::MD4> module allows you to use the RSA Data Security
Inc. MD4 Message Digest algorithm from within Perl programs.  The
algorithm takes as input a message of arbitrary length and produces as
output a 128-bit "fingerprint" or "message digest" of the input.

The C<Digest::MD4> module provide a procedural interface for simple
use, as well as an object oriented interface that can handle messages
of arbitrary length and which can read files directly.

=head1 FUNCTIONS

The following functions are provided by the C<Digest::MD4> module.
None of these functions are exported by default.

=over 4

=item md4($data,...)

This function will concatenate all arguments, calculate the MD4 digest
of this "message", and return it in binary form.  The returned string
will be 16 bytes long.

The result of md4("a", "b", "c") will be exactly the same as the
result of md4("abc").

=item md4_hex($data,...)

Same as md4(), but will return the digest in hexadecimal form. The
length of the returned string will be 32 and it will only contain
characters from this set: '0'..'9' and 'a'..'f'.

=item md4_base64($data,...)

Same as md4(), but will return the digest as a base64 encoded string.
The length of the returned string will be 22 and it will only contain
characters from this set: 'A'..'Z', 'a'..'z', '0'..'9', '+' and
'/'.

Note that the base64 encoded string returned is not padded to be a
multiple of 4 bytes long.  If you want interoperability with other
base64 encoded md4 digests you might want to append the redundant
string "==" to the result.

=back

=head1 METHODS

The object oriented interface to C<Digest::MD4> is described in this
section.  After a C<Digest::MD4> object has been created, you will add
data to it and finally ask for the digest in a suitable format.  A
single object can be used to calculate multiple digests.

The following methods are provided:

=over 4

=item $md4 = Digest::MD4->new

The constructor returns a new C<Digest::MD4> object which encapsulate
the state of the MD4 message-digest algorithm.

If called as an instance method (i.e. $md4->new) it will just reset the
state the object to the state of a newly created object.  No new
object is created in this case.

=item $md4->reset

This is just an alias for $md4->new.

=item $md4->clone

This a copy of the $md4 object. It is useful when you do not want to
destroy the digests state, but need an intermediate value of the
digest, e.g. when calculating digests iteratively on a continuous data
stream.  Example:

    my $md4 = Digest::MD4->new;
    while (<>) {
	$md4->add($_);
	print "Line $.: ", $md4->clone->hexdigest, "\n";
    }

=item $md4->add($data,...)

The $data provided as argument are appended to the message we
calculate the digest for.  The return value is the $md4 object itself.

All these lines will have the same effect on the state of the $md4
object:

    $md4->add("a"); $md4->add("b"); $md4->add("c");
    $md4->add("a")->add("b")->add("c");
    $md4->add("a", "b", "c");
    $md4->add("abc");

=item $md4->addfile($io_handle)

The $io_handle will be read until EOF and its content appended to the
message we calculate the digest for.  The return value is the $md4
object itself.

The addfile() method will croak() if it fails reading data for some
reason.  If it croaks it is unpredictable what the state of the $md4
object will be in. The addfile() method might have been able to read
the file partially before it failed.  It is probably wise to discard
or reset the $md4 object if this occurs.

In most cases you want to make sure that the $io_handle is in
C<binmode> before you pass it as argument to the addfile() method.

=item $md4->digest

Return the binary digest for the message.  The returned string will be
16 bytes long.

Note that the C<digest> operation is effectively a destructive,
read-once operation. Once it has been performed, the C<Digest::MD4>
object is automatically C<reset> and can be used to calculate another
digest value.  Call $md4->clone->digest if you want to calculate the
digest without reseting the digest state.

=item $md4->hexdigest

Same as $md4->digest, but will return the digest in hexadecimal
form. The length of the returned string will be 32 and it will only
contain characters from this set: '0'..'9' and 'a'..'f'.

=item $md4->b64digest

Same as $md4->digest, but will return the digest as a base64 encoded
string.  The length of the returned string will be 22 and it will only
contain characters from this set: 'A'..'Z', 'a'..'z', '0'..'9', '+'
and '/'.


The base64 encoded string returned is not padded to be a multiple of 4
bytes long.  If you want interoperability with other base64 encoded
md4 digests you might want to append the string "==" to the result.

=back


=head1 EXAMPLES

The simplest way to use this library is to import the md4_hex()
function (or one of its cousins):

    use Digest::MD4 qw(md4_hex);
    print "Digest is ", md4_hex("foobarbaz"), "\n";

The above example would print out the message:

    Digest is b2b2b528f632f554ae9cb2c02c904eeb

The same checksum can also be calculated in OO style:

    use Digest::MD4;
    
    $md4 = Digest::MD4->new;
    $md4->add('foo', 'bar');
    $md4->add('baz');
    $digest = $md4->hexdigest;
    
    print "Digest is $digest\n";

With OO style you can break the message arbitrary.  This means that we
are no longer limited to have space for the whole message in memory, i.e.
we can handle messages of any size.

This is useful when calculating checksum for files:

    use Digest::MD4;

    my $file = shift || "/etc/passwd";
    open(FILE, $file) or die "Can't open '$file': $!";
    binmode(FILE);

    $md4 = Digest::MD4->new;
    while (<FILE>) {
        $md4->add($_);
    }
    close(FILE);
    print $md4->b64digest, " $file\n";

Or we can use the addfile method for more efficient reading of
the file:

    use Digest::MD4;

    my $file = shift || "/etc/passwd";
    open(FILE, $file) or die "Can't open '$file': $!";
    binmode(FILE);

    print Digest::MD4->new->addfile(*FILE)->hexdigest, " $file\n";

Perl 5.8 support Unicode characters in strings.  Since the MD4
algorithm is only defined for strings of bytes, it can not be used on
strings that contains chars with ordinal number above 255.  The MD4
functions and methods will croak if you try to feed them such input
data:

    use Digest::MD4 qw(md4_hex);

    my $str = "abc\x{300}";
    print md4_hex($str), "\n";  # croaks
    # Wide character in subroutine entry

What you can do is calculate the MD4 checksum of the UTF-8
representation of such strings.  This is achieved by filtering the
string through encode_utf8() function:

    use Digest::MD4 qw(md4_hex);
    use Encode qw(encode_utf8);

    my $str = "abc\x{300}";
    print md4_hex(encode_utf8($str)), "\n";
    # fc2ef2836f9bc3f44ed6d7adee2f1533

=head1 SEE ALSO

L<Digest>,
L<Digest::MD2>,
L<Digest::SHA1>,
L<Digest::HMAC>

L<md4sum(1)>

RFC 1320

=head1 COPYRIGHT

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

 Copyright 1998-2003 Gisle Aas.
 Copyright 1995-1996 Neil Winton.
 Copyright 1991-1992 RSA Data Security, Inc.

The MD4 algorithm is defined in RFC 1320. This implementation is
derived from the reference C code in RFC 1320 which is covered by
the following copyright statement:

=over 4

=item

   Copyright (C) 1990-2, RSA Data Security, Inc. All rights reserved.

   License to copy and use this software is granted provided that it
   is identified as the "RSA Data Security, Inc. MD4 Message-Digest
   Algorithm" in all material mentioning or referencing this software
   or this function.

   License is also granted to make and use derivative works provided
   that such works are identified as "derived from the RSA Data
   Security, Inc. MD4 Message-Digest Algorithm" in all material
   mentioning or referencing the derived work.

   RSA Data Security, Inc. makes no representations concerning either
   the merchantability of this software or the suitability of this
   software for any particular purpose. It is provided "as is"
   without express or implied warranty of any kind.

   These notices must be retained in any copies of any part of this
   documentation and/or software.

=back

This copyright does not prohibit distribution of any version of Perl
containing this extension under the terms of the GNU or Artistic
licenses.

=head1 AUTHORS

The original C<MD5> interface was written by Neil Winton
(C<N.Winton@axion.bt.co.uk>).

The C<Digest::MD5> module is written by Gisle Aas <gisle@ActiveState.com>.

The C<Digest::MD4> module is derived from Digest::MD5 by Mike McCauley (mikem@airspayce.com)

=cut
