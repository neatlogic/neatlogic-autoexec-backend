#!/usr/bin/perl -w


###############################################################################
#
# A template for submitting a bug report.
#
# Run this program and read the output from the command line.
#
# reverse('�'), March 2004, John McNamara, jmcnamara@cpan.org
#


use strict;

print << 'HINTS_1';

REPORTING A BUG OR ASKING A QUESTION

    Feel free to report bugs or ask questions. However, to save time
    consider the following steps first:

    Read the documentation:

        The Spreadsheet::WriteExcel documentation has been refined in
        response to user questions. Therefore, if you have a question it is
        possible that someone else has asked it before you and that it is
        already addressed in the documentation. Since there is a lot of
        documentation to get through you should at least read the table of
        contents and search for keywords that you are interested in.

    Look at the example programs:

        There are over 70 example programs shipped with the standard
        Spreadsheet::WriteExcel distribution. Many of these were created in
        response to user questions. Try to identify an example program that
        corresponds to your query and adapt it to your needs.

HINTS_1
print "Press enter ..."; <STDIN>;

print << 'HINTS_2';

    If you submit a bug report here are some pointers.

    1.  Put "WriteExcel:" at the beginning of the subject line. This helps
        to filter genuine messages from spam.

    2.  Describe the problems as clearly and as concisely as possible.

    3.  Send a sample program. It is often easier to describe a problem in
        code than in written prose.

    4.  The sample program should be as small as possible to demonstrate the
        problem. Don't copy and past large sections of your program. The
        program should also be self contained and working.

    A sample bug report is generated below. If you use this format then it
    will help to analyse your question and respond to it more quickly.

    Please don't send patches without contacting the author first.


HINTS_2
print "Press enter ..."; <STDIN>;


print << 'EMAIL';

=======================================================================

To:      John McNamara <jmcnamara@cpan.org>
Subject: WriteExcel: Problem with something.

Hi John,

I am using Spreadsheet::WriteExcel and I have encountered a problem. I
want it to do SOMETHING but the module appears to do SOMETHING_ELSE.

Here is some code that demonstrates the problem.

    #!/usr/bin/perl -w

    use strict;
    use Spreadsheet::WriteExcel;

    my $workbook  = Spreadsheet::WriteExcel->new("reload.xls");
    my $worksheet = $workbook->add_worksheet();

    $worksheet->write(0, 0, "Hi Excel!");

    __END__


I tested using Excel XX (or Gnumeric or OpenOffice.org).

My automatically generated system details are as follows:
EMAIL


print "\n    Perl version   : $]";
print "\n    OS name        : $^O";
print "\n    Module versions: (not all are required)\n";


my @modules = qw(
                  Spreadsheet::WriteExcel
                  Spreadsheet::ParseExcel
                  OLE::Storage_Lite
                  Parse::RecDescent
                  File::Temp
                  Digest::MD4
                  Digest::Perl::MD4
                  Digest::MD5
                );


for my $module (@modules) {
    my $version;
    eval "require $module";

    if (not $@) {
        $version = $module->VERSION;
        $version = '(unknown)' if not defined $version;
    }
    else {
        $version = '(not installed)';
    }

    printf "%21s%-24s\t%s\n", "", $module, $version;
}


print << "BYE";
Yours etc.,

A. Person
--

BYE

__END__
