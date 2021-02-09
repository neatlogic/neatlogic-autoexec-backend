#!/usr/bin/perl -w

###############################################################################
#
# Example of how to use the Spreadsheet::WriteExcel merge_range() workbook
# method with complex formatting.
#
# reverse('�'), September 2002, John McNamara, jmcnamara@cpan.org
#

use strict;
use Spreadsheet::WriteExcel;

# Create a new workbook and add a worksheet
my $workbook  = Spreadsheet::WriteExcel->new('merge4.xls');
my $worksheet = $workbook->add_worksheet();


# Increase the cell size of the merged cells to highlight the formatting.
$worksheet->set_row($_, 30) for (1..11);
$worksheet->set_column('B:D', 20);


###############################################################################
#
# Example 1: Text centered vertically and horizontally
#
my $format1 = $workbook->add_format(
                                    border  => 6,
                                    bold    => 1,
                                    color   => 'red',
                                    valign  => 'vcenter',
                                    align   => 'center',
                                   );



$worksheet->merge_range('B2:D3', 'Vertical and horizontal', $format1);


###############################################################################
#
# Example 2: Text aligned to the top and left
#
my $format2 = $workbook->add_format(
                                    border  => 6,
                                    bold    => 1,
                                    color   => 'red',
                                    valign  => 'top',
                                    align   => 'left',
                                  );



$worksheet->merge_range('B5:D6', 'Aligned to the top and left', $format2);


###############################################################################
#
# Example 3:  Text aligned to the bottom and right
#
my $format3 = $workbook->add_format(
                                    border  => 6,
                                    bold    => 1,
                                    color   => 'red',
                                    valign  => 'bottom',
                                    align   => 'right',
                                  );



$worksheet->merge_range('B8:D9', 'Aligned to the bottom and right', $format3);


###############################################################################
#
# Example 4:  Text justified (i.e. wrapped) in the cell
#
my $format4 = $workbook->add_format(
                                    border  => 6,
                                    bold    => 1,
                                    color   => 'red',
                                    valign  => 'top',
                                    align   => 'justify',
                                  );



$worksheet->merge_range('B11:D12', 'Justified: '.'so on and ' x18, $format4);

