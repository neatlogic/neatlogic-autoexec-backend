#!/usr/bin/perl

###############################################################################
#
# A test for Spreadsheet::ParseExcel.
#
# Regression tests for Worksheet properties and methods.
#
# The tests are mainly in pairs where direct hash access (old methodology)
# is tested along with the method calls (>= version 0.50 methodology).
#
# The tests in this testsuite are mainly for non-default Worksheet properties.
# See also 04_regression.t for testing of default properties.
#
# reverse('�'), January 2009, John McNamara, jmcnamara@cpan.org
#

use strict;
use warnings;
use Spreadsheet::ParseExcel;
use Test::More tests => 76;

###############################################################################
#
# Tests setup.
#
my $file     = 't/excel_files/worksheet_01.xls';
my $parser   = Spreadsheet::ParseExcel->new();
my $workbook = $parser->Parse($file);
my $worksheet;
my $got_1;
my $got_2;
my $expected_1;
my $expected_2;
my $caption;

###############################################################################
#
# Test 1, 2
#
$caption    = "Test cell value";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 'This sheet has:';
$got_1      = $worksheet->{Cells}->[0]->[0]->value();
$got_2      = $worksheet->get_cell( 0, 0 )->value();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 3, 4.
#
$caption    = "Test worksheet name";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 'Sheet2';
$got_1      = $worksheet->{Name};
$got_2      = $worksheet->get_name();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 5, 6.
#
$caption    = "Test row range";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 0;
$expected_2 = 35;
$got_1      = ( $worksheet->row_range() )[0];
$got_2      = ( $worksheet->row_range() )[1];
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_2, $caption );

###############################################################################
#
# Test 7, 8.
#
$caption    = "Test col range";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 0;
$expected_2 = 9;
$got_1      = ( $worksheet->col_range() )[0];
$got_2      = ( $worksheet->col_range() )[1];
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_2, $caption );

###############################################################################
#
# Test 9, 10.
#
$caption    = "Test worksheet number";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1;
$got_1      = $worksheet->{_SheetNo};
$got_2      = $worksheet->sheet_num();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 11, 12.
#
$caption    = "Test default row height";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 21;
$got_1      = $worksheet->{DefRowHeight};
$got_2      = $worksheet->get_default_row_height;
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 13, 14.
#
$caption    = "Test default column width";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 8.43;
$got_1      = $worksheet->{DefColWidth};
$got_2      = $worksheet->get_default_col_width;
$caption    = " \tWorksheet regression: " . $caption;

_is_float( $got_1, $expected_1, $caption );
_is_float( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 15, 16.
#
$caption    = "Test row '3' height";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 48.75;
$got_1      = $worksheet->{RowHeight}->[2];
$got_2      = ( $worksheet->get_row_heights() )[2];
$caption    = " \tWorksheet regression: " . $caption;

_is_float( $got_1, $expected_1, $caption );
_is_float( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 17, 18.
#
$caption    = "Test column 'A' width";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 31;
$got_1      = $worksheet->{ColWidth}->[0];
$got_2      = ( $worksheet->get_col_widths() )[0];
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 19, 20.
#
$caption    = "Test landscape print setting";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 0;
$got_1      = $worksheet->{Landscape};
$got_2      = $worksheet->is_portrait();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 21, 22.
#
$caption    = "Test print scale";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 75;
$got_1      = $worksheet->{Scale};
$got_2      = $worksheet->get_print_scale();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 23, 24. Note, use Sheet3 for counter example.
#
$caption    = "Test print fit to page";
$worksheet  = $workbook->worksheet('Sheet3');
$expected_1 = 1;
$got_1      = $worksheet->{PageFit};
$expected_2 = '2x3';
$got_2      = join 'x', $worksheet->get_fit_to_pages();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_2, $caption );

###############################################################################
#
# Test 25, 26. Note, use Sheet3 for counter example.
#
$caption    = "Test print fit to page width";
$worksheet  = $workbook->worksheet('Sheet3');
$expected_1 = 2;
$got_1      = $worksheet->{FitWidth};
$expected_2 = 2;
$got_2      = ( $worksheet->get_fit_to_pages() )[0];
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_2, $caption );

###############################################################################
#
# Test 27, 28. Note, use Sheet3 for counter example.
#
$caption    = "Test print fit to page height";
$worksheet  = $workbook->worksheet('Sheet3');
$expected_1 = 3;
$got_1      = $worksheet->{FitHeight};
$expected_2 = 3;
$got_2      = ( $worksheet->get_fit_to_pages() )[1];
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_2, $caption );

###############################################################################
#
# Test 29, 30.
#
$caption    = "Test paper size";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 11;
$got_1      = $worksheet->{PaperSize};
$got_2      = $worksheet->get_paper();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 31, 32.
#
$caption    = "Test user defined start page for printing";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1;
$got_1      = $worksheet->{UsePage};
$expected_2 = 2;
$got_2      = $worksheet->get_start_page();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_2, $caption );

###############################################################################
#
# Test 33, 34.
#
$caption    = "Test user defined start page for printing";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 2;
$got_1      = $worksheet->{PageStart};
$got_2      = $worksheet->get_start_page();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 35, 36.
#
$caption    = "Test left margin";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1.2;
$got_1      = $worksheet->{LeftMargin};
$got_2      = $worksheet->get_margin_left();
$caption    = " \tWorksheet regression: " . $caption;

_is_float( $got_1, $expected_1, $caption );
_is_float( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 37, 38.
#
$caption    = "Test right margin";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1.4;
$got_1      = $worksheet->{RightMargin};
$got_2      = $worksheet->get_margin_right();
$caption    = " \tWorksheet regression: " . $caption;

_is_float( $got_1, $expected_1, $caption );
_is_float( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 39, 40.
#
$caption    = "Test top margin";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1.1;
$got_1      = $worksheet->{TopMargin};
$got_2      = $worksheet->get_margin_top();
$caption    = " \tWorksheet regression: " . $caption;

_is_float( $got_1, $expected_1, $caption );
_is_float( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 41, 42.
#
$caption    = "Test bottom margin";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1.5;
$got_1      = $worksheet->{BottomMargin};
$got_2      = $worksheet->get_margin_bottom();
$caption    = " \tWorksheet regression: " . $caption;

_is_float( $got_1, $expected_1, $caption );
_is_float( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 43, 44.
#
$caption    = "Test header margin";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 0.5;
$got_1      = $worksheet->{HeaderMargin};
$got_2      = $worksheet->get_margin_header();
$caption    = " \tWorksheet regression: " . $caption;

_is_float( $got_1, $expected_1, $caption );
_is_float( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 45, 46.
#
$caption    = "Test footer margin";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1.6;
$got_1      = $worksheet->{FooterMargin};
$got_2      = $worksheet->get_margin_footer();
$caption    = " \tWorksheet regression: " . $caption;

_is_float( $got_1, $expected_1, $caption );
_is_float( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 47, 48.
#
$caption    = "Test center horizontally";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1;
$got_1      = $worksheet->{HCenter};
$got_2      = $worksheet->is_centered_horizontally();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 49, 50.
#
$caption    = "Test center vertically";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1;
$got_1      = $worksheet->{VCenter};
$got_2      = $worksheet->is_centered_vertically();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 51, 52.
#
$caption    = "Test header";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = '&CThis is the header';
$got_1      = $worksheet->{Header};
$got_2      = $worksheet->get_header();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 53, 54.
#
$caption    = "Test Footer";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = '&LThis is the footer';
$got_1      = $worksheet->{Footer};
$got_2      = $worksheet->get_footer();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 55, 56.
#
$caption    = "Test print with gridlines";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1;
$got_1      = $worksheet->{PrintGrid};
$got_2      = $worksheet->is_print_gridlines();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 57, 58.
#
$caption    = "Test print with row and column headers";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1;
$got_1      = $worksheet->{PrintHeaders};
$got_2      = $worksheet->is_print_row_col_headers();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 59, 60.
#
$caption    = "Test print in black and white";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1;
$got_1      = $worksheet->{NoColor};
$got_2      = $worksheet->is_print_black_and_white();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 61, 62.
#
$caption    = "Test print in draft quality";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1;
$got_1      = $worksheet->{Draft};
$got_2      = $worksheet->is_print_draft();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 63, 64.
#
$caption    = "Test print comments";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1;
$got_1      = $worksheet->{Notes};
$got_2      = $worksheet->is_print_comments();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 65, 66.
#
$caption    = "Test print over then down";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 1;
$got_1      = $worksheet->{LeftToRight};
$got_2      = $worksheet->get_print_order();
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 67, 68.
#
$caption    = "Test horizontal page breaks";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = [6, 20];
$got_1      = $worksheet->{HPageBreak};
$got_2      = $worksheet->get_h_pagebreaks();
$caption    = " \tWorksheet regression: " . $caption;

is_deeply( $got_1, $expected_1, $caption );
is_deeply( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 69, 70.
#
$caption    = "Test vertical page breaks";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = [2];
$got_1      = $worksheet->{VPageBreak};
$got_2      = $worksheet->get_v_pagebreaks();
$caption    = " \tWorksheet regression: " . $caption;

is_deeply( $got_1, $expected_1, $caption );
is_deeply( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 71, 72.
#
$caption    = "Test merged areas";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = [ [29, 1, 30, 4] ];
$got_1      = $worksheet->{MergedArea};
$got_2      = $worksheet->get_merged_areas();
$caption    = " \tWorksheet regression: " . $caption;

is_deeply( $got_1, $expected_1, $caption );
is_deeply( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 73, 74.
#
$caption    = "Test hidden row 34";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 21;
$got_1      = $worksheet->{RowHeight}->[33];
$got_2      = ( $worksheet->get_row_heights() )[33];
$caption    = " \tWorksheet regression: " . $caption;

is( $got_1, $expected_1, $caption );
is( $got_2, $expected_1, $caption );

###############################################################################
#
# Test 75, 76.
#
$caption    = "Test column hidden 'A' width";
$worksheet  = $workbook->worksheet('Sheet2');
$expected_1 = 10.71;
$got_1      = $worksheet->{ColWidth}->[7];
$got_2      = ( $worksheet->get_col_widths() )[7];
$caption    = " \tWorksheet regression: " . $caption;

_is_float( $got_1, $expected_1, $caption );
_is_float( $got_2, $expected_1, $caption );

###############################################################################
#
# _is_float()
#
# Helper function for float comparison. This is mainly to prevent failing tests
# on 64bit systems with extended doubles where the 128bit precision is compared
# against Excel's 64bit precision.
#
sub _is_float {

    my ( $got, $expected, $caption ) = @_;

    my $max = 1;
    $max = abs($got)      if abs($got) > $max;
    $max = abs($expected) if abs($expected) > $max;

    if ( abs( $got - $expected ) <= 1e-15 * $max ) {
        ok( 1, $caption );
    }
    else {
        is( $got, $expected, $caption );
    }
}

__END__
