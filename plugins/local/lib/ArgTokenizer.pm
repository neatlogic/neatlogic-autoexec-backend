#!/usr/bin/perl
use strict;

package ArgTokenizer;

sub new {
    my ($pkg) = @_;

    my $self = {};
    bless( $self, $pkg );

    return $self;
}

sub tokenize {
    my ( $self, $arguments, $stringify ) = @_;

    my $NO_TOKEN_STATE     = 0;
    my $NORMAL_TOKEN_STATE = 1;
    my $SINGLE_QUOTE_STATE = 2;
    my $DOUBLE_QUOTE_STATE = 3;

    my @argList = ();
    my $currArg = '';
    my $escaped = 0;
    my $state   = $NO_TOKEN_STATE;

    my @argChars = split( //, $arguments );

    for ( my $i = 0 ; $i <= $#argChars ; $i++ ) {
        my $c = $argChars[$i];
        if ( $escaped == 1 ) {
            $escaped = 0;
            $currArg = $currArg . $c;
        }
        else {
            if ( $state == $SINGLE_QUOTE_STATE ) {
                if ( $c eq "'" ) {
                    $state = $NORMAL_TOKEN_STATE;
                }
                else {
                    $currArg = $currArg . $c;
                }
            }
            elsif ( $state == $DOUBLE_QUOTE_STATE ) {
                if ( $c eq '"' ) {
                    $state = $NORMAL_TOKEN_STATE;
                }
                elsif ( $c eq '\\' ) {
                    $escaped = 1;
                    $currArg = $currArg . $c;
                }
                else {
                    $currArg = $currArg . $c;
                }
            }
            elsif ( $state == $NO_TOKEN_STATE or $state == $NORMAL_TOKEN_STATE ) {
                if ( $c eq '\\' ) {
                    $escaped = 1;
                    $state   = $NORMAL_TOKEN_STATE;
                    $currArg = $currArg . $c;
                }
                elsif ( $c eq '\'' ) {
                    $state = $SINGLE_QUOTE_STATE;
                }
                elsif ( $c eq '"' ) {
                    $state = $DOUBLE_QUOTE_STATE;
                }
                else {
                    if ( $c !~ /^\s$/ ) {
                        $currArg = $currArg . $c;
                        $state   = $NORMAL_TOKEN_STATE;
                    }
                    elsif ( $state == $NORMAL_TOKEN_STATE ) {

                        #Whitespace ends the token; start a new one
                        push( @argList, $currArg );
                        $currArg = '';
                        $state   = $NO_TOKEN_STATE;
                    }
                }
            }
            else {
                die("ERROR: ArgumentTokenizer state $state is invalid!");
            }
        }
    }

    if ($escaped) {
        push( @argList, $currArg );
    }
    elsif ( $state != $NO_TOKEN_STATE ) {
        push( @argList, $currArg );
    }

    #Format each argument if we've been told to stringify them
    if ($stringify) {
        for ( my $i = 0 ; $i <= $#argList ; $i++ ) {
            $argList[$i] = "\"" . $self->_escapeQuotesAndBackslashes( $argList[$i] ) . "\"";
        }
    }

    return \@argList;
}

sub _escapeQuotesAndBackslashes {
    my ( $self, $arg ) = @_;
    my @argChars = split( //, $arg );
    my $buf      = '';
    for ( my $i = 0 ; $i < $#argChars ; $i++ ) {
        my $c = $argChars[$i];

        if ( $c eq '\\' || $c eq '"' ) {
            $buf = $buf . '\\' . $c;
        }
        elsif ( $c eq '\n' ) {
            $buf = $buf . '\\n';
        }
        elsif ( $c eq '\t' ) {
            $buf = $buf . '\\t';
        }
        elsif ( $c eq '\r' ) {
            $buf = $buf . '\\r';
        }
        elsif ( $c eq '\b' ) {
            $buf = $buf . '\\b';
        }
        elsif ( $c eq '\f' ) {
            $buf = $buf . '\\f';
        }
        else {
            $buf = $buf . $c;
        }
    }

    return $buf;
}

1;
