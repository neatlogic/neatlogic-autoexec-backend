#!/usr/bin/perl
use strict;

package SonarQubeAdapter;

use FindBin;
use IO::File;
use REST::Client;
use File::Path;
use JSON qw(to_json from_json);
use MIME::Base64;
use Cwd;

use DeployUtils;

my $SYSTEM_CONF;
my $SYSINFO_MAP  = {};
my $APPCONF_MAP  = {};
my $AUTHCONF_MAP = {};
my $PLAYBOOK_MAP = {};
my $INS_MAP      = {};
my $PASS_MAP     = {};

sub getAuthToken {
    my ( $username, $password ) = @_;

    my $authToken = 'Basic ' . MIME::Base64::encode( $username . ':' . $password );
    return $authToken;
}

sub convCharSet {
    my ( $client, $content ) = @_;
    my $contentEncoding = 'utf-8';
    my $contentType     = $client->responseHeader('Content-Type');
    $contentEncoding = $1 if ( $contentType =~ /charset=(.*)$/ );

    my $lang = $ENV{LANG};
    my $encoding = lc( substr( $lang, rindex( $lang, '.' ) + 1 ) );
    $encoding = 'utf-8' if ( $encoding eq 'utf8' );
    if ( $encoding ne $contentEncoding ) {
        $content = Encode::encode( $encoding, Encode::decode( $contentEncoding, $content ) );
    }
    return $content;
}

# Get information on Compute Engine tasks
# https://sonarcloud.io/web_api/api/ce
sub isCeFinish {
    my ( $client, $ceUrl, $baseUrl ) = @_;

    $client->GET($ceUrl);
    if ( $client->responseCode() ne 200 ) {
        die("ERROR: get Compute Engine status failed.\n");
    }

    my $content = convCharSet( $client, $client->responseContent() );
    my $ceJson = from_json($content);

    #print("DEBUG: Compute Engine status is $content\n");
    if ( $ceJson->{'pending'} gt 0 or $ceJson->{'inProgress'} gt 0 ) {
        print("INFO: waiting sonarqube compute engine finish task...\n");
        return 0;
    }

    if ( $ceJson->{'failing'} gt 0 ) {

        #get task id
        $client->GET("$baseUrl/api/ce/activity?status=FAILED");
        if ( $client->responseCode() ne 200 ) {
            die("ERROR: search for tasks failed.\n");
        }
        $content = convCharSet( $client, $client->responseContent() );
        $ceJson = from_json($content);
        my $tasks = $ceJson->{'tasks'};
        foreach my $task (@$tasks) {
            my $id = $task->{'id'};

            #get error message by task id && print it
            $client->GET("$baseUrl/api/ce/task?id=$id");
            if ( $client->responseCode() ne 200 ) {
                die("ERROR: get Compute Engine task details failed.\n");
            }
            $content = convCharSet( $client, $client->responseContent() );
            $ceJson = from_json($content);
            my $errorMessage    = $ceJson->{'task'}->{'errorMessage'};
            my $errorStacktrace = $ceJson->{'task'}->{'errorStacktrace'};
            print("$errorMessage\n$errorStacktrace\n");
        }
        die("ERROR: Compute Engine failed.\n");
    }

    return 1;
}

sub getMeasures {
    my ( $projectKey, $baseUrl, $username, $password, $level, $threshold ) = @_;

    my $authToken = getAuthToken( $username, $password );

    my $componentId;

    my $url = "$baseUrl/api/components/show?key=$projectKey";

    my $client = REST::Client->new();
    $client->getUseragent()->ssl_opts( verify_hostname => 0 );
    $client->getUseragent()->ssl_opts( SSL_verify_mode => 'SSL_VERIFY_NONE' );
    $client->addHeader( 'Authorization', $authToken );

    $client->GET($url);
    if ( $client->responseCode() eq 200 ) {
        my $content = convCharSet( $client, $client->responseContent() );
        my $rcJson = from_json($content);

        if ( $rcJson->{'errors'} ) {
            my $errMsg;
            my $errors = $rcJson->{'errors'};
            foreach my $error (@$errors) {
                $errMsg = $errMsg . $error->{'msg'} . "\n";
            }
            die($errMsg);
        }
        else {
            $componentId = $rcJson->{'component'}->{'id'};
        }
    }
    else {
        my $errMsg = $client->responseContent();
        die("ERROR: Get compnent failed, cause by:$errMsg\n");
    }

    if ( not defined($componentId) ) {
        die("ERROR: Get compnentId failed.\n");
    }

    #print("DEBUG: componentId is: $componentId\n");
    my $isFinish = 0;
    while ( !$isFinish ) {
        sleep 2;
        $isFinish = isCeFinish( $client, "$baseUrl/api/ce/activity_status?componentId=$componentId", $baseUrl );
    }

    my $measureKeyMap = {
        files                 => 'files',
        classes               => 'classes',
        lines                 => 'lines',
        ncloc                 => 'ncloc',
        functions             => 'functions',
        statements            => 'statements',
        complexity            => 'complexity',
        file_complexity       => 'fileComplexity',
        class_complexity      => 'classComplexity',
        function_complexity   => 'functionComplexity',
        violations            => 'violations',
        blocker_violations    => 'blockerViolations',
        critical_violations   => 'criticalViolations',
        major_violations      => 'majorViolations',
        minor_violations      => 'minorViolations',
        bugs                  => 'bugs',
        vulnerabilities       => 'vulnerabilities',
        code_smells           => 'code_smells',
        executable_lines_data => 'executableLinesData',

        #        it_conditions_to_cover        => 'itConditionsToCover',
        #        it_branch_coverage            => 'itVranchCoverage',
        #        it_conditions_by_line         => 'itConditionsByLine',
        #        it_coverage                   => 'itCoverage',
        #        it_coverage_line_hits_data    => 'itCoverageLineHitsData',
        #        it_covered_conditions_by_line => 'itCoveredConditionsByLine',
        #        it_line_coverage              => 'itLineCoverage',
        #        it_lines_to_cover             => 'itLinesToCover',
        #        conditions_to_cover        => 'itConditionsToCover',
        #        branch_coverage            => 'itVranchCoverage',
        #        conditions_by_line         => 'itConditionsByLine',
        #        coverage                   => 'itCoverage',
        #        coverage_line_hits_data    => 'itCoverageLineHitsData',
        #        covered_conditions_by_line => 'itCoveredConditionsByLine',
        #        line_coverage              => 'itLineCoverage',
        #        lines_to_cover             => 'itLinesToCover',
########

        comment_lines_density         => 'commentLinesDensity',
        public_documented_api_density => 'publicDocumentedApiDensity',
        duplicated_files              => 'duplicatedFiles',
        duplicated_lines              => 'duplicatedLines',
        duplicated_lines_density      => 'duplicatedLinesDensity',
        new_duplicated_lines          => 'newDuplicatedLines',
        new_duplicated_lines_density  => 'newDuplicatedLinesDensity',
        duplicated_blocks             => 'duplicatedBlocks',
        new_duplicated_blocks         => 'newDuplicatedBlocks',

        #单元测试指标
        tests                => 'tests',
        test_success_density => 'testSuccessDensity',
        test_errors          => 'testErrors',
        branch_coverage      => 'branchCoverage',
        new_branch_coverage  => 'newBranchCoverage',
        line_coverage        => 'lineCoverage',
        new_line_coverage    => 'newLineCoverage'
    };

    my @measureVals;

    if ( defined($componentId) ) {
        my @measures = keys(%$measureKeyMap);

        $url = "$baseUrl/api/measures/component?componentId=$componentId\&metricKeys=" . join( ',', @measures );

        #print("$url\n");
        $client->GET($url);

        if ( $client->responseCode() eq 200 ) {
            my $content = convCharSet( $client, $client->responseContent() );
            my $rcJson = from_json($content);

            if ( $rcJson->{'errors'} ) {
                my $errMsg;
                my $errors = $rcJson->{'errors'};
                foreach my $error (@$errors) {
                    $errMsg = $errMsg . $error->{'msg'} . "\n";
                }
                die($errMsg);
            }
            else {
                my $rcMeasureVals = $rcJson->{'component'}->{'measures'};
                push( @measureVals, @$rcMeasureVals );
            }
        }
        else {
            my $errMsg = $client->responseContent();
            die("ERROR: Get measures failed, cause by:$errMsg\n");
        }
    }

    my $hasError = 0;
    my %measuresMap;

    foreach my $measureVal (@measureVals) {

        #if( $measureVal->{'metric'} eq "$level".'_violations'){
        #    print ('阻断违规 Blocker violations', ':' , $measureVal->{'value'}, "\n");
        #}

        #if($measureVal->{'metric'}  eq 'critical_violations'){
        #    print ('严重违规 Critical violations', ':' , $measureVal->{'value'}, "\n");
        #}
        #if($measureVal->{'metric'}  eq 'info_violations'){
        #    print ('提示违规 Info violationd', ':' , $mea
        #}

        if ( $measureVal->{'value'} ne '' ) {
            if ( defined($level) and defined($threshold) ) {
                if ( $measureVal->{'metric'} eq "$level" . '_violations' ) {
                    my $violations = $measureVal->{'value'};
                    if ( $violations >= $threshold ) {
                        $hasError = $hasError + 1;
                        print("ERROR: Number of code violations($violations) is above the threshold value: $threshold \n");
                    }
                }
            }
            $measuresMap{ $measureKeyMap->{ $measureVal->{'metric'} } } =
                $measureVal->{'value'};

            #print( $measureKeyMap->{ $measureVal->{'metric'} }, ':', $measureVal->{'value'}, "\n" );
        }
    }

    $url = "$baseUrl/api/qualitygates/project_status?projectKey=$projectKey";

    #print("$url\n");
    $client->GET($url);
    if ( $client->responseCode() ne 200 ) {
        die("ERROR: get Project Quality Gate Status failed.\n");
    }
    my $content           = convCharSet( $client, $client->responseContent() );
    my $ceJson            = from_json($content);
    my $projectStatus     = $ceJson->{'projectStatus'}->{'status'};
    my @projectConditions = @{ $ceJson->{'projectStatus'}->{'conditions'} };
    foreach my $condition (@projectConditions) {

        print("Quality Gate> metric: $condition->{metricKey} => $condition->{actualValue} \n");
        if ( $condition->{status} ne "OK" ) {
            print("====================================================================================\n");
            print( "ERROR: Quality Gate Failed: " . $condition->{metricKey} . " " . $condition->{comparator} . " " . $condition->{errorThreshold} . "\n" );
            print("====================================================================================\n");
        }
    }

    if ( $projectStatus ne "OK" ) {
        $hasError = $hasError + 1;
        print("ERROR: project status returned from sonarqube is $projectStatus\n");
    }

    if ( $hasError > 0 ) {
        die("ERROR: Get measures from sonarqube failed.\n");
    }
    return \%measuresMap;
}

#getMeasures( 'DEMOA', 'DEMOASUB', 'http://192.168.0.24:9000', 'admin', 'admin' );

1;

