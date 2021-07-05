#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package TOMCATCollector;

use strict;
use parent 'BASECollector';

use File::Basename;

sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo = $self->{procInfo};
    my $appInfo  = {};

    my $confPath;
    if ( $procInfo->{COMMAND} =~ /-Dcatalina.base=(\S+)\s+/ ) {
        $confPath                 = $1;
        $appInfo->{CATALINA_BASE} = $confPath;
        $appInfo->{SERVICE_NAME}  = basename($confPath);

        my $confFile = "$confPath/conf/server.xml";
        my $fh       = IO::File->new("<$confFile");
        if ( defined($fh) ) {
            my $fSize = -s $confFile;
            my $xml;
            $fh->read( $xml, $fSize );

            my @ports = ();
            my $port;
            if ( $xml =~ /<Connector\b.*?\bHTTP\b.*?\/>/ ) {
                my $matchContent = $&;
                if ( $matchContent =~ /port="(.*?)"/ ) {
                    $port = $1;
                    if ( $port =~ /^\d+$/ ) {
                        $appInfo->{HTTP_PORT} = $port;
                    }
                    elsif ( $port =~ /\$\{(.*?)\}/ ) {
                        my $optName = $1;
                        if ( $procInfo->{COMMAND} =~ /-D$optName=(\d+)/ ) {
                            $port = $1;
                            $appInfo->{HTTP_PORT} = $port;
                            push( @ports, $port );
                        }
                    }
                }
            }

            if ( $xml =~ /<Connector\b.*?\bSSLEnabled\b.*?\/>/ ) {
                my $matchContent = $&;
                if ( $matchContent =~ /port="(.*?)"/ ) {
                    $port = $1;
                    if ( $port =~ /^\d+$/ ) {
                        $appInfo->{HTTPS_PORT} = $port;
                    }
                    elsif ( $port =~ /\$\{(.*?)\}/ ) {
                        my $optName = $1;
                        if ( $procInfo->{COMMAND} =~ /-D$optName=(\d+)/ ) {
                            $port = $1;
                            $appInfo->{HTTPS_PORT} = $port;
                            push( @ports, $port );
                        }
                    }
                }
            }

            $appInfo->{PORTS} = \@ports;
        }
    }
    else {
        $appInfo->{SERVICE_NAME} = 'tomcat';
    }

    my $installPath;
    if ( $procInfo->{COMMAND} =~ /-Dcatalina.home=(\S+)\s+/ ) {
        $installPath = $1;
        $appInfo->{CATALINA_HOME} = $installPath;
    }

    my $binPath = "$installPath/bin";
    my $verCmd  = "sh $binPath/version.sh";
    if ( $procInfo->{OS_TYPE} eq 'Windows' ) {
        $verCmd = `cmd /c $binPath/version.bat`;
    }
    my @verOut = `$verCmd`;
    foreach my $line (@verOut) {
        if ( $line =~ /Server number:\s*(.*?)\s*/ ) {
            $appInfo->{VERSION} = $1;
        }
        elsif ( $line =~ /JVM Vendor:\s*(.*?)\s*/ ) {
            $appInfo->{JVM_VENDER} = $1;
        }
        elsif ( $line =~ /JRE_HOME:\s*(.*?)\s*/ ) {
            $appInfo->{JRE_HOME} = $1;
        }
        elsif ( $line =~ /JVM Version:\s*(.*?)\s*/ ) {
            $appInfo->{JVM_VERSION} = $1;
        }
    }

    #获取-X的java扩展参数，TODO: 确实是否有用
    my $jvmExtendOpts = '';
    my @cmdOpts = split( /\s+/, $procInfo->{COMMAND} );
    foreach my $cmdOpt (@cmdOpts) {
        if ( $cmdOpt =~ /^-X/ ) {
            $jvmExtendOpts = $jvmExtendOpts . ' ' . $cmdOpt;
        }
    }
    chomp($jvmExtendOpts);
    $appInfo->{JVM_EXTEND_OPT} = $jvmExtendOpts;

    return $appInfo;
}

1;
