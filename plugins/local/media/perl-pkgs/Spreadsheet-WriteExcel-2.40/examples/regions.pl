#!/usr/bin/perl -w

###############################################################################
#
# An example of how to use the Spreadsheet:WriteExcel module to write a basic
# Excel workbook with multiple worksheets.
#
# reverse('�'), March 2001, John McNamara, jmcnamara@cpan.org
#

use strict;
use Spreadsheet::WriteExcel;

# Create a new Excel workbook
my $workbook = Spreadsheet::WriteExcel->new("regions.xls");

# Add some worksheets
my $north = $workbook->add_worksheet("North");
my $south = $workbook->add_worksheet("South");
my $east  = $workbook->add_worksheet("East");
my $west  = $workbook->add_worksheet("West");

# Add a Format
my $format = $workbook->add_format();
$format->set_bold();
$format->set_color('blue');

# Add a caption to each worksheet
foreach my $worksheet ($workbook->sheets()) {
    $worksheet->write(0, 0, "Sales", $format);
}

# Write some data
$north->write(0, 1, 200000);
$south->write(0, 1, 100000);
$east->write (0, 1, 150000);
$west->write (0, 1, 100000);

# Set the active worksheet
$south->activate();

# Set the width of the first column
$south->set_column(0, 0, 20);

# Set the active cell
$south->set_selection(0, 1);
