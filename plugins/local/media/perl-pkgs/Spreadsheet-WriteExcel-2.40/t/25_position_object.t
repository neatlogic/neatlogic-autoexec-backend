#!/usr/bin/perl -w

###############################################################################
#
# A test for Spreadsheet::WriteExcel.
#
# Tests for the _position_object() Worksheet method used to calculate the
# vertices that define the position of a graphical object within a worksheet.
#
# See the the _position_object() comments for a full explanation.
#
# reverse('�'), September 2005, John McNamara, jmcnamara@cpan.org
#


use strict;

use Spreadsheet::WriteExcel;
use Test::More tests => 27;


###############################################################################
#
# Tests setup
#
my $test_file = "temp_test_file.xls";
my $workbook  = Spreadsheet::WriteExcel->new($test_file);
my $worksheet = $workbook->add_worksheet();


###############################################################################
#
# Tests extracted from images imported into Excel.
#
#
# input    = ($col_start, $row_start, $x1, $y1, $width, $height)
#            (0,          1,          2,   3,   4,      5      )
#
# expected = ($col_start, $x1, $row_start, $y1, $col_end, $x2, $row_end, $y2)
#            (0,          1,   2,          3,   4,        5,   6,        7  )
#
my @tests = (
    # Input                    # Expected results
    [ [0, 0,  0, 0,   1,   1], [ 0,   0,  0,   0,  0,   16,  0,  15] ],
    [ [0, 0,  0, 0,   2,   2], [ 0,   0,  0,   0,  0,   32,  0,  30] ],
    [ [0, 0,  0, 0,   3,   3], [ 0,   0,  0,   0,  0,   48,  0,  45] ],
    [ [0, 0,  0, 0,   4,   4], [ 0,   0,  0,   0,  0,   64,  0,  60] ],
    [ [0, 0,  0, 0,   5,   5], [ 0,   0,  0,   0,  0,   80,  0,  75] ],
    [ [0, 0,  0, 0,   6,   6], [ 0,   0,  0,   0,  0,   96,  0,  90] ],
    [ [0, 0,  0, 0,   7,   7], [ 0,   0,  0,   0,  0,  112,  0, 105] ],
    [ [0, 0,  0, 0,   8,   8], [ 0,   0,  0,   0,  0,  128,  0, 120] ],
    [ [0, 0,  0, 0,   9,   9], [ 0,   0,  0,   0,  0,  144,  0, 136] ],
    [ [0, 0,  0, 0,  10,  10], [ 0,   0,  0,   0,  0,  160,  0, 151] ],
    [ [0, 0,  0, 0,  15,  15], [ 0,   0,  0,   0,  0,  240,  0, 226] ],
    [ [0, 0,  0, 0,  16,  16], [ 0,   0,  0,   0,  0,  256,  0, 241] ],
    [ [0, 0,  0, 0,  17,  17], [ 0,   0,  0,   0,  0,  272,  1,   0] ],
    [ [0, 0,  0, 0,  18,  18], [ 0,   0,  0,   0,  0,  288,  1,  15] ],
    [ [0, 0,  0, 0,  19,  19], [ 0,   0,  0,   0,  0,  304,  1,  30] ],
    [ [0, 0,  0, 0,  62,   8], [ 0,   0,  0,   0,  0,  992,  0, 120] ],
    [ [0, 0,  0, 0,  63,   8], [ 0,   0,  0,   0,  0, 1008,  0, 120] ],
    [ [0, 0,  0, 0,  64,   8], [ 0,   0,  0,   0,  1,    0,  0, 120] ],
    [ [0, 0,  0, 0,  65,   8], [ 0,   0,  0,   0,  1,   16,  0, 120] ],
    [ [0, 0,  0, 0,  66,   8], [ 0,   0,  0,   0,  1,   32,  0, 120] ],
    [ [0, 0,  0, 0, 200, 200], [ 0,   0,  0,   0,  3,  128, 11, 196] ],
    [ [1, 4,  0, 0,  64,  16], [ 1,   0,  4,   0,  2,    0,  4, 241] ],
    [ [1, 4,  1, 0,  64,  16], [ 1,  16,  4,   0,  2,   16,  4, 241] ],
    [ [1, 4,  2, 0,  64,  16], [ 1,  32,  4,   0,  2,   32,  4, 241] ],
    [ [1, 4,  2, 1,  64,  16], [ 1,  32,  4,  15,  2,   32,  5,   0] ],
    [ [1, 4,  2, 2,  64,  16], [ 1,  32,  4,  30,  2,   32,  5,  15] ],

    # Test for comment box standard sizes.
    [ [2, 1, 15, 7, 128,  74], [ 2, 240,  1, 105,  4,  240,  5, 196] ],
);


for my $testcase (@tests) {
    my $input    = $testcase->[0];
    my $expected = $testcase->[1];
    my @results  = $worksheet->_position_object(@$input);
    my $caption  = sprintf " \t_position_object  %3dw x h%-3d  Offset = (%2d, %d)  Cell = (%d, %d)",
                            $input->[4],
                            $input->[5],
                            $input->[2],
                            $input->[3],
                            $input->[0],
                            $input->[1];

    is_deeply(\@results, $expected, $caption);
}


###############################################################################
#
# Cleanup
#
$workbook->close();
unlink $test_file;


__END__



