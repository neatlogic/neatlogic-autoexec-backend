###############################################################################
#
# Example of how to use the Spreadsheet::WriteExcel module to send an Excel
# file to a browser using mod_perl 1 and Apache
#
# This module ties *XLS directly to Apache, and with the correct
# content-disposition/types it will prompt the user to save
# the file, or open it at this location.
#
# This script is a modification of the Spreadsheet::WriteExcel cgi.pl example.
#
# Change the name of this file to Cgi.pm.
# Change the package location to where ever you locate this package.
# In the example below it is located in the WriteExcel directory.
#
# Your httpd.conf entry for this module, should you choose to use it
# as a stand alone app, should look similar to the following:
#
#     <Location /spreadsheet-test>
#       SetHandler perl-script
#       PerlHandler Spreadsheet::WriteExcel::Cgi
#       PerlSendHeader On
#     </Location>
#
# The PerlHandler name above and the package name below *have* to match.

# Apr 2001, Thomas Sullivan, webmaster@860.org
# Feb 2001, John McNamara, jmcnamara@cpan.org

package Spreadsheet::WriteExcel::Cgi;

##########################################
# Pragma Definitions
##########################################
use strict;

##########################################
# Required Modules
##########################################
use Apache::Constants qw(:common);
use Apache::Request;
use Apache::URI; # This may not be needed
use Spreadsheet::WriteExcel;

##########################################
# Main App Body
##########################################
sub handler {
    # New apache object
    # Should you decide to use it.
    my $r = Apache::Request->new(shift);

    # Set the filename and send the content type
    # This will appear when they save the spreadsheet
    my $filename ="cgitest.xls";

    ####################################################
    ## Send the content type headers
    ####################################################
    print "Content-disposition: attachment;filename=$filename\n";
    print "Content-type: application/vnd.ms-excel\n\n";

    ####################################################
    # Tie a filehandle to Apache's STDOUT.
    # Create a new workbook and add a worksheet.
    ####################################################
    tie *XLS => 'Apache';
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
    $worksheet->write(0, 0, "Hi Excel!", $format);

    # You must close the workbook for Content-disposition
    $workbook->close();
}

1;
