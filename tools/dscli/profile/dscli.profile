#
# DS CLI Profile
#

#
# Management Console/Node IP Address(es)
#   hmc1 and hmc2 are equivalent to -hmc1 and -hmc2 command options.
#hmc1:	127.0.0.1
#hmc2:	127.0.0.1

#
# Default target Storage Image ID
#    "devid" and "remotedevid" are equivalent to 
#    "-dev storage_image_ID" and "-remotedev storage_image_ID" command options, respectively. 
#devid:			IBM.2107-AZ12341
#remotedevid:	IBM.2107-AZ12341

#
# locale
#    Default locale is based on user environment.
#locale:		en

#
# Displayed format for the banner message date and time
#   locale  : Date/time format specified using locale preferences. (default)
#   iso8601 : Date/time format specified by ISO 8601
banner_date:	locale

# Timeout value of client/server synchronous communication in second.
#    DSCLI command timeout value may be longer than client/server communication
#    timeout value since multiple requests may be made by one DSCLI command
#    The number of the requests made to server depends on DSCLI commands.
#    The default timeout value is 900 seconds.
#timeout:		900

# Socket connection timeout value in seconds.
#    The timeout value must be greater than zero.
#    System default socket timeout value is used if timeout value is set to zero.
#    The default connection timeout value is 20 seconds.
#timeout.connection: 20

#
# Output settings
#
# ID format of objects:
#   on:		fully qualified format
#   off:	short format
fullid:		off

# Paging and Rows per page. 
# paging enables/disables paging the output per line numbers specified by "rows".
# "paging" is equivalent to "-p on|off" option.
#   on  : Stop scrolling per output lines defined by "rows".
#   off : No paging. (default)
# "rows" is equivalent to "-r #" option.
paging:		off
#rows:		24

# Output format type for ls commands, which can take one of the following values:
#   default: Default output
#   xml    : XML format
#   delim  : delimit columns using a character specified by "delim"
#   stanza  : Horizontal table format
# "format" is equivalent to option "-fmt default|xml|delim|stanza".
#format:		default

# delimiter character for ls commands.
#delim:		|
# Display banner message. "banner" is equivalent to option "-bnr on|off".
#   on  : Banner messages are displayed. (default)
#   off : No Banner messages are displayed.
banner:		on

#
# Display table header for ls commands. "header" is equivalent to option "-hdr on|off".
#   on  : Table headers are displayed. (default)
#   off : No table headers are displayed.
header:		on

#
# Display verbose information. "verbose" is equivalent to option "-v on|off".
#   on  : Display verbose information.
#   off : No verbose information.
verbose:	off

# Echo each dscli command.
#   on  : Echo commands to standard out prior to execution. Passwords within command line arguments will be hidden.
#   off : No command echo. (default)
#echo:off

# If echo is on and echoprefix is specified, its value will be printed on the line before the echoed command.
#echoprefix:dscli>

# The max number of records for performance report .
#   The default max number of records for performance report is 256. The value for it is suggested to be
#   not larger than 3000. If the target is dapair, the value is suggested to be not larger than 1500.
#maxNumReports:	256

#  The port for communication to the HMC(s).
#   1750  : Force the dscli to use the legacy 1750 port for communication.
#   1751  : Force the dscli to use 1751 which allows for a higher encryption protocol.
#   1718  : Force the dscli to use 1718 which is only supported for ESS 800 model. 
#   Not specifying port causes the dscli to try 1751 first,
#   then revert to 1750 if the server doesn't support 1751,
#   and finally attempt 1718 if the server is ESS 800 model.
#   Therefore, if you want quicker connection times to down level servers
#   avoid the try/fail by setting port to 1750.
# port:1750


# End of Profile