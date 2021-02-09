#!/usr/bin/perl -w

######################################################################
#
# This program shows several examples of how to set up headers and
# footers with Spreadsheet::WriteExcel.
#
# The control characters used in the header/footer strings are:
#
#     Control             Category            Description
#     =======             ========            ===========
#     &L                  Justification       Left
#     &C                                      Center
#     &R                                      Right
#
#     &P                  Information         Page number
#     &N                                      Total number of pages
#     &D                                      Date
#     &T                                      Time
#     &F                                      File name
#     &A                                      Worksheet name
#
#     &fontsize           Font                Font size
#     &"font,style"                           Font name and style
#     &U                                      Single underline
#     &E                                      Double underline
#     &S                                      Strikethrough
#     &X                                      Superscript
#     &Y                                      Subscript
#
#     &&                  Miscellaneous       Literal ampersand &
#
# See the main Spreadsheet::WriteExcel documentation for more information.
#
# reverse('�'), March 2002, John McNamara, jmcnamara@cpan.org
#


use strict;
use Spreadsheet::WriteExcel;

my $workbook  = Spreadsheet::WriteExcel->new("headers.xls");
my $preview   = "Select Print Preview to see the header and footer";


######################################################################
#
# A simple example to start
#
my $worksheet1  = $workbook->add_worksheet('Simple');

my $header1     = '&CHere is some centred text.';

my $footer1     = '&LHere is some left aligned text.';


$worksheet1->set_header($header1);
$worksheet1->set_footer($footer1);

$worksheet1->set_column('A:A', 50);
$worksheet1->write('A1', $preview);




######################################################################
#
# This is an example of some of the header/footer variables.
#
my $worksheet2  = $workbook->add_worksheet('Variables');

my $header2     = '&LPage &P of &N'.
                  '&CFilename: &F' .
                  '&RSheetname: &A';

my $footer2     = '&LCurrent date: &D'.
                  '&RCurrent time: &T';



$worksheet2->set_header($header2);
$worksheet2->set_footer($footer2);


$worksheet2->set_column('A:A', 50);
$worksheet2->write('A1', $preview);
$worksheet2->write('A21', "Next sheet");
$worksheet2->set_h_pagebreaks(20);



######################################################################
#
# This example shows how to use more than one font
#
my $worksheet3 = $workbook->add_worksheet('Mixed fonts');

my $header3    = '&C' .
                 '&"Courier New,Bold"Hello ' .
                 '&"Arial,Italic"World';

my $footer3    = '&C' .
                 '&"Symbol"e' .
                 '&"Arial" = mc&X2';

$worksheet3->set_header($header3);
$worksheet3->set_footer($footer3);

$worksheet3->set_column('A:A', 50);
$worksheet3->write('A1', $preview);




######################################################################
#
# Example of line wrapping
#
my $worksheet4 = $workbook->add_worksheet('Word wrap');

my $header4    = "&CHeading 1\nHeading 2\nHeading 3";

$worksheet4->set_header($header4);

$worksheet4->set_column('A:A', 50);
$worksheet4->write('A1', $preview);




######################################################################
#
# Example of inserting a literal ampersand &
#
my $worksheet5 = $workbook->add_worksheet('Ampersand');

my $header5    = "&CCuriouser && Curiouser - Attorneys at Law";

$worksheet5->set_header($header5);

$worksheet5->set_column('A:A', 50);
$worksheet5->write('A1', $preview);

