###############################################################################
#
# Example of how to use the Spreadsheet::WriteExcel module to send an Excel
# file to a browser using mod_perl 2 and Apache.
#
# This module ties *XLS directly to Apache, and with the correct
# content-disposition/types it will prompt the user to save
# the file, or open it at this location.
#
# This script is a modification of the Spreadsheet::WriteExcel cgi.pl example.
#
# Change the name of this file to MP2Test.pm.
# Change the package location to where ever you locate this package.
# In the example below it is located in the WriteExcel directory.
#
# Your httpd.conf entry for this module, should you choose to use it
# as a stand alone app, should look similar to the following:
#
#     PerlModule Apache2::RequestRec
#     PerlModule APR::Table
#     PerlModule Apache2::RequestIO
#
#     <Location /spreadsheet-test>
#        SetHandler perl-script
#        PerlResponseHandler Spreadsheet::WriteExcel::MP2Test
#     </Location>
#
# The PerlResponseHandler must match the package name below.

# Jun 2004, Matisse Enzer, matisse@matisse.net  (mod_perl 2 version)
# Apr 2001, Thomas Sullivan, webmaster@860.org
# Feb 2001, John McNamara, jmcnamara@cpan.org

package Spreadsheet::WriteExcel::MP2Test;

##########################################
# Pragma Definitions
##########################################
use strict;

##########################################
# Required Modules
##########################################
use Apache2::Const -compile => qw( :common );
use Spreadsheet::WriteExcel;

##########################################
# Main App Body
##########################################
sub handler {
    my($r) = @_;  # Apache request object is passed to handler in mod_perl 2

    # Set the filename and send the content type
    # This will appear when they save the spreadsheet
    my $filename ="mod_perl2_test.xls";

    ####################################################
    ## Send the content type headers the mod_perl 2 way
    ####################################################
    $r->headers_out->{'Content-Disposition'} = "attachment;filename=$filename";
    $r->content_type('application/vnd.ms-excel');

    ####################################################
    # Tie a filehandle to Apache's STDOUT.
    # Create a new workbook and add a worksheet.
    ####################################################
    tie *XLS => $r;  # The mod_perl 2 way. Tie to the Apache::RequestRec object
    binmode(*XLS);

    my $workbook  = Spreadsheet::WriteExcel->new(\*XLS);
    my $worksheet = $workbook->add_worksheet();


    # Set the column width for column 1
    $worksheet->set_column(0, 0, 20);


    # Create a format
    my $format = $workbook->add_format();
    $format->set_bold();
    $format->set_size(15);
    $format->set_color('blue');


    # Write to the workbook
    $worksheet->write(0, 0, 'Hi Excel! from ' . $r->hostname , $format);

    # You must close the workbook for Content-disposition
    $workbook->close();
    return Apache2::Const::OK;
}

1;
