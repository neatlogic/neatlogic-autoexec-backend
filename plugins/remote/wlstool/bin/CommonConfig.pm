#!/usr/bin/perl
use FindBin;

use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

package CommonConfig;

use strict;
use IO::File;
use Time::Local;
use Crypt::RC4;
use Fcntl qw(:flock);

sub _rc4_encrypt_hex ($$) {
    my ( $key, $data ) = ( $_[0], $_[1] );
    return join( '', unpack( 'H*', RC4( $key, $data ) ) );
}

sub _rc4_decrypt_hex ($$) {
    my ( $key, $data ) = ( $_[0], $_[1] );
    return RC4( $key, pack( 'H*', $data ) );
}

sub new {
    my ( $pkg, $configPath, $configFile ) = @_;
    $pkg = ref($pkg) || $pkg;
    unless ($pkg) {
        $pkg = "CommonConfig";
    }

    my $self = {};
    bless( $self, $pkg );

    $self->{MY_KEY} = 'f6I7wXKpleT1khAOp8NvKdifBhJnI2Zi';
    $self->{path}   = $configPath;
    $self->{file}   = $configFile;
    $self->{config} = {};

    $self->loadConfig();

    return $self;
}

sub checkConfigChanged {
    my ($self) = shift @_;
    my $lastModifiedTime = ( stat( $self->{file} ) )[9];

    if ( $self->{lastModifiedTime} < $lastModifiedTime ) {
        $self->loadConfig();
        return 1;
    }
    return 0;
}

sub getConfigLine {
    my ( $self, $configPath, $configFile, $configName ) = @_;
    my $line;
    my $fh = new IO::File();

    my $confPath   = "$configPath/$configFile";
    my $newContent = '';

    if ( $fh->open("+>>$confPath") ) {
        flock( $fh, LOCK_SH );
        $fh->seek( 0, 0 );

        my $isModified = 0;

        while ( $line = <$fh> ) {
            my $orgLine = $line;
            $line =~ s/([^\\])#.*$/$1/;
            $line =~ s/\\#/#/g;

            if ( $line =~ /^\s*include\s+(.*)\s*$/i ) {
                $self->getConfigLine( $configPath, $1, $configName );
            }
            else {
                if ( $line =~ /^[\w\.-]*(pass|pwd)[\w\.-]*\s*=\s*(.*?)\s*$/i ) {
                    my $valText = $2;
                    if ( $valText ne '' and $valText !~ /^\{ENCRYPTED\}/ ) {
                        $isModified = 1;
                        my $valTextEncrypted = '{ENCRYPTED}' . _rc4_encrypt_hex( $self->{MY_KEY}, $valText );
                        $orgLine =~ s/$valText/$valTextEncrypted/;
                    }
                    else {
                        my $valTextEncrypted = $valText;
                        $valTextEncrypted =~ s/^\{ENCRYPTED\}\s*//;
                        my $valTextPlain = _rc4_decrypt_hex( $self->{MY_KEY}, $valTextEncrypted );
                        $line =~ s/$valText/$valTextPlain/;
                    }
                }

                $configName = $self->parseLine( $line, $configName );
            }

            $newContent = $newContent . $orgLine;
        }

        if ( $isModified == 1 ) {
            flock( $fh, LOCK_UN );
            flock( $fh, LOCK_EX );
            $fh->truncate(0);
            print $fh ($newContent);
            $fh->flush();
        }

        $fh->close();
    }
    else {

        #print STDERR ( "Can\'t open config file $configPath/$configFile\n");
        die("ERROR: Can\'t open config file $configPath/$configFile\n");
    }
}

sub loadConfig {
    my ($self) = shift @_;
    my $configs = $self->{config};
    my ( $config, $configName );

    my ( $key, $value, $temp );

    $self->getConfigLine( $self->{path}, $self->{file} );
    $self->{lastModifiedTime} = ( stat( $self->{file} ) )[9];

    #restruct the hash map, make the config inheritate the global and group configs
    my $globalConfig = $configs->{global};
    my ( $mode, $modeConfig );

    foreach my $configName ( keys(%$configs) ) {
        my $newConfig = {};

        $config = $configs->{$configName};

        if ( ref($config) eq 'HASH' && $configName ne 'global' ) {
            while ( ( $key, $value ) = each %$globalConfig ) {

                #change to save the value in the orgion map
                if ( !exists( $config->{$key} ) ) {
                    $config->{$key} = $value;
                }
            }

            if ( exists( $config->{mode} ) ) {
                $mode = lc( $config->{mode} );

                if ( exists( $configs->{$mode} ) ) {
                    $modeConfig = $configs->{$mode};
                    while ( ( $key, $value ) = each %$modeConfig ) {

                        #change to save the value in the orgion map
                        if ( !exists( $config->{$key} ) ) {
                            $config->{$key} = $value;
                        }
                    }
                }
            }

        }
    }

}

sub getAllConfig() {
    my $self = shift @_;

    return $self->{config};
}

sub getConfig() {
    my ( $self, $configName, $scope ) = @_;

    my $configValue;
    if ( defined($scope) and $scope ne '' ) {
        $configValue = $self->{config}->{ $scope . '.' . lc($configName) };
        if ( not defined($configValue) or $configValue eq '' ) {
            $configValue = $self->{config}->{ lc($configName) };
        }
    }
    else {
        $configValue = $self->{config}->{ lc($configName) };
    }

    return $configValue;
}

sub parseLine {
    my ( $self, $line, $configName ) = @_;
    my ( $key, $temp );
    my $configs = $self->{config};
    my $config  = $configs->{$configName};

    #skip the blank or comment lines
    if ( $line =~ /^\s*$/ || $line =~ /^\s*#/ || $line =~ /^\s*;/ ) {
        return $configName;
    }

    if ( $line =~ /^\s*\[(.*?)\]\s*/ ) {
        $configName = lc($1);

        #If exists use the orgion corrected by wenhb 2005/09/15
        if ( !exists( $configs->{$configName} ) ) {
            $configs->{$configName} = {};
        }
        else {
            $temp = $configs->{$configName};
            foreach $key ( keys(%$temp) ) {
                delete( $temp->{$key} );
            }
        }
        ###########
    }
    elsif ( $line =~ /^\s*(.*?)\s*=\s*(.*)\s*$/ ) {

        #$line =~ /^\s*(.*?)\s*=\s*(.*)\s*$/;
        my $orgKey = $1;
        my $key    = lc($orgKey);
        my $value  = $2;
        my $temp;

        if ( $value =~ /^\s*\{(.*)\}\s*$/ ) {
            $value = $1;
            my ( $valMap, $valPart );
            $valMap = {};

            foreach $valPart ( split( /\s*,\s*/, $value ) ) {
                if ( $valPart =~ /^\s*(.*?)\s*=\s*(.*)\s*$/ ) {
                    if ( exists( $valMap->{$1} ) ) {
                        $temp = $valMap->{$1};
                        if ( ref($temp) eq 'ARRAY' ) {
                            push( @$temp, $2 );
                        }
                        else {
                            my @mapArray = ( $valMap->{$1}, $2 );
                            $valMap->{$1} = \@mapArray;
                        }
                    }
                    else {
                        $valMap->{$1} = $2;
                    }
                }
                else {
                    print STDERR("Malform config line $line ($valPart) must in key=value form.\n");
                }
            }

            $value = $valMap;
        }
        else {
            $value =~ s/^\s*//;
            $value =~ s/\s*$//;

            while ( $value =~ /<<(.*?)>>/g ) {
                $temp = $1;

                $value =~ s/<<$temp>>/$configs->{$temp}/;
            }
        }

        if ( !defined($config) ) {
            $configs->{$key}    = $value;
            $configs->{$orgKey} = $value;
        }

        # for the purpose of reload value in the config map, cut these code

        elsif ( exists( $config->{$key} ) ) {
            $temp = $config->{$key};
            if ( ref($temp) eq 'ARRAY' ) {
                push( @$temp, $2 );
            }
            else {
                my @mapArray = ( $config->{$key}, $value );
                $config->{$key}    = \@mapArray;
                $config->{$orgKey} = \@mapArray;
            }
        }
        else {
            $config->{$key}    = ($value);
            $config->{$orgKey} = ($value);
        }
    }
    else {
        print STDERR ("WARNING: Config file exists broken line: $line");
    }

    return $configName;
}

sub dump {
    my $self = shift @_;

    my $configs = $self->{config};

    foreach my $configName ( keys(%$configs) ) {
        my $config = $configs->{$configName};

        if ( ref($config) ne 'HASH' ) {
            print("$configName=$config\n");
        }
        else {
            print("[$configName]\n");

            foreach my $key ( keys(%$config) ) {
                my $tempArray;
                if ( ref( $config->{$key} ) eq 'ARRAY' ) {
                    $tempArray = $config->{$key};
                }
                else {
                    @$tempArray = ( $config->{$key} );
                }

                foreach my $value (@$tempArray) {
                    if ( ref($value) eq 'HASH' ) {
                        my $subKey;
                        print("$key={");
                        foreach $subKey ( keys(%$value) ) {
                            print( "$subKey=", $value->{$subKey}, "," );
                        }
                        print( '}', "\n" );
                    }
                    else {
                        print( "$key=", $value, "\n" );
                    }
                }
            }
        }
    }
}

1;

