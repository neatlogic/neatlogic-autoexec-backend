#!/usr/bin/perl -w

##############################################################################
#
# A simple formatting example using Spreadsheet::WriteExcel.
#
# This program demonstrates the indentation cell format.
#
# reverse('�'), May 2004, John McNamara, jmcnamara@cpan.org
#


use strict;
use Spreadsheet::WriteExcel;

my $workbook  = Spreadsheet::WriteExcel->new('indent.xls');

my $worksheet = $workbook->add_worksheet();
my $indent1   = $workbook->add_format(indent => 1);
my $indent2   = $workbook->add_format(indent => 2);

$worksheet->set_column('A:A', 40);


$worksheet->write('A1', "This text is indented 1 level",  $indent1);
$worksheet->write('A2', "This text is indented 2 levels", $indent2);


__END__
