###Status
[![Build Status](https://travis-ci.org/szabgab/expect.pm.png)](https://travis-ci.org/szabgab/expect.pm)


Expect.pm
=========

Expect requires the latest version of IO::Tty, also available from
CPAN.  IO::Stty has become optional but I'd suggest you also install
it.  If you use the highly recommended CPAN module, there is a
Bundle::Expect available that installs everything for you.

If you prefer manual installation, the usual

    perl Makefile.PL
    make
    make test
    make install

should work.

Note that IO::Tty is very system-dependend.  It has been extensively
reworked and tested, but there still may be systems that have
problems.

Please be sure to read the FAQ section in the Expect pod manpage, 
especially the section about using Expect to control telnet/ssh etc.
There are other ways to work around password entry, you definitely 
don't need Expect for ssh automatisation!

The Perl Expect module was inspired more by the functionality of
Tcl/Expect than any previous Expect-like tool such as Comm.pl or
chat2.pl.

The Tcl version of Expect is a creation of Don Libes (libes@nist.gov)
and can be found at http://expect.nist.gov/.  Don has written an
excellent in-depth tutorial of Tcl/Expect, which is _Exploring
Expect_.  It is the O'Reilly book with the monkey on the front.  Don
has several references to other articles on the Expect web page.

I try to stay as close to Tcl/Expect in interface and semantics as
possible (so I can refer questions to the Tcl/Expect docu).
Suggestions for improvement are always welcome.

There are two mailing lists available, expectperl-announce and
expectperl-discuss, at

  http://lists.sourceforge.net/lists/listinfo/expectperl-announce

and

  http://lists.sourceforge.net/lists/listinfo/expectperl-discuss

Thanks to everybody who wrote to me, either with bug reports,
enhancement suggestions or especially fixes!

Roland Giersig (maintainer of Expect.pm, IO::Tty, IO::Stty, Tie::Persistent)
RGiersig@cpan.org

2005-07-20
