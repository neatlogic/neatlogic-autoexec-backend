#!/usr/bin/perl
use strict;

package TagentGetLog;

use FindBin;
use File::Glob qw(bsd_glob);
use TagentClient;

my $MAX_SIZE       = 65536;
my $TAIL_INIT_SIZE = 16384;

sub new {
    my ( $pkg, $osType, $host, $port, $user, $pass, $timeout ) = @_;
    my $self = {};

    $self->{ostype} = $osType;

    my $tagent = new TagentClient( $host, $port, $pass );

    $self->{tagent} = $tagent;

    bless( $self, $pkg );

    return $self;
}

sub getPath {
    my ( $self, $insInfo ) = @_;
    my $tagent     = $self->{tagent};
    my $logPattern = $insInfo->{logPatterns};
    if ( defined($logPattern) or $logPattern ne '' ) {
        my @logPatterns = split( /\s*,\s*/, $logPattern );
        my $cmd = "use File::Glob qw(bsd_glob);";
        foreach my $pattern (@logPatterns) {
            $cmd = $cmd . 'print(join("\n", bsd_glob("' . $pattern . '")), "\n");';
        }

        if ( $self->{ostype} eq 'windows' ) {
            $cmd =~ s/"/\\"/g;
            $cmd = qq{perl -e "$cmd"};
        }
        else {
            $cmd = qq{perl -e '$cmd'};
        }

        $tagent->execCmd( 'none', $cmd, 1 );
    }
}

sub tailLog {
    my ( $self, $logPath, $startPos ) = @_;

    my $tagent = $self->{tagent};
    $startPos = -1 if ( not defined($startPos) );
    my $perlCmd = qq{
    use IO::File;
    my \$fh = new IO::File("$logPath","r");
    my \$start = $startPos;
    my \$fSize = (-s "$logPath");
    \$start = \$fSize - $TAIL_INIT_SIZE if (\$start eq -1);
    \$start = 0 if(\$start < 0);
    \$fh->seek( \$start, 0 );
    my \$size = 0;
    my \$line;
    \$line = \$fh->getline() if (\$start eq -1); 
    while(\$line=\$fh->getline()){
        print(\$line);
        \$size = \$size + length(\$line);
        last if(\$size > $MAX_SIZE);
    }
    print(\$start, ",", \$fh->tell() . "\\n");
    };

    $perlCmd =~ s/\n/ /g;
    $perlCmd =~ s/\s+/ /g;

    if ( $self->{ostype} eq 'windows' ) {
        $perlCmd =~ s/"/\\"/g;
        $perlCmd = qq{perl -e "$perlCmd"};
    }
    else {
        $perlCmd = qq{perl -e '$perlCmd'};
    }

    $tagent->execCmd( 'none', $perlCmd, 1 );
}

sub headLog {
    my ( $self, $logPath, $startPos ) = @_;

    my $tagent = $self->{tagent};
    $startPos = 0 if ( not defined($startPos) );
    my $perlCmd = qq{
    use IO::File;
    my \$fh = new IO::File("$logPath","r");
    my \$start = $startPos - $TAIL_INIT_SIZE;
    my \$end   = $startPos;
    \$start = 0 if (\$start < 0);
    my \$lStart = \$start;
    my \$cur   = \$start;
    \$fh->seek( \$start, 0 );
    my \$line;
    if(\$start > 0){
        \$line = \$fh->getline();
        \$cur = \$cur + length(\$line);
        \$lStart = \$cur;
    };
    while(\$line=\$fh->getline()){
        print(\$line);
        \$cur = \$cur + length(\$line);
        
        last if(\$cur >= \$end);
    }
    print(\$lStart . "," . \$cur . "\\n");
    };

    $perlCmd =~ s/\n/ /g;
    $perlCmd =~ s/\s+/ /g;

    if ( $self->{ostype} eq 'windows' ) {
        $perlCmd =~ s/"/\\"/g;
        $perlCmd = qq{perl -e "$perlCmd"};
    }
    else {
        $perlCmd = qq{perl -e '$perlCmd'};
    }

    $tagent->execCmd( 'none', $perlCmd, 1 );
}

sub downLog {
    my ( $self, $logPath ) = @_;

    my $tagent = $self->{tagent};

    my $perlCmd = qq{
    use IO::File; 
    my \$fh=new IO::File("$logPath","r"); 
    my \$line;
    while(\$line=\$fh->getline()){ print \$line;}
    close(\$fh);
    };

    $perlCmd =~ s/\n/ /g;
    $perlCmd =~ s/\s+/ /g;
    if ( $self->{ostype} eq 'windows' ) {
        $perlCmd =~ s/"/\\"/g;
        $perlCmd = qq{perl -e "$perlCmd"};
    }
    else {
        $perlCmd = qq{perl -e '$perlCmd'};
    }

    $tagent->execCmd( 'none', $perlCmd, 1 );

    #if ( $self->{ostype} eq 'windows' ) {
    #    $tagent->execCmd( 'none', "type $logPath", 1 );
    #}
    #else {
    #    $tagent->execCmd( 'none', "cat $logPath", 1 );
    #}
}

1;
