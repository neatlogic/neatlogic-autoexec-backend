#!/usr/bin/perl -w

###############################################################################
#
# Example of how to use the Spreadsheet::WriteExcel merge_cells() workbook
# method with complex formatting and rotation.
#
#
# reverse('�'), September 2002, John McNamara, jmcnamara@cpan.org
#

use strict;
use Spreadsheet::WriteExcel;

# Create a new workbook and add a worksheet
my $workbook  = Spreadsheet::WriteExcel->new('merge5.xls');
my $worksheet = $workbook->add_worksheet();


# Increase the cell size of the merged cells to highlight the formatting.
$worksheet->set_row($_, 36)         for (3..8);
$worksheet->set_column($_, $_ , 15) for (1,3,5);


###############################################################################
#
# Rotation 1, letters run from top to bottom
#
my $format1 = $workbook->add_format(
                                    border      => 6,
                                    bold        => 1,
                                    color       => 'red',
                                    valign      => 'vcentre',
                                    align       => 'centre',
                                    rotation    => 270,
                                  );


$worksheet->merge_range('B4:B9', 'Rotation 270', $format1);


###############################################################################
#
# Rotation 2, 90� anticlockwise
#
my $format2 = $workbook->add_format(
                                    border      => 6,
                                    bold        => 1,
                                    color       => 'red',
                                    valign      => 'vcentre',
                                    align       => 'centre',
                                    rotation    => 90,
                                  );


$worksheet->merge_range('D4:D9', 'Rotation 90�', $format2);



###############################################################################
#
# Rotation 3, 90� clockwise
#
my $format3 = $workbook->add_format(
                                    border      => 6,
                                    bold        => 1,
                                    color       => 'red',
                                    valign      => 'vcentre',
                                    align       => 'centre',
                                    rotation    => -90,
                                  );


$worksheet->merge_range('F4:F9', 'Rotation -90�', $format3);

