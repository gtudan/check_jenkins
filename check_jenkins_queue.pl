#!/usr/bin/perl
#
# This Nagios plugin checks the number of jobs in the jenkins build queue
# It can check that the queue length will not exeed the WARNING and CRITICAL thresholds.
# Performance data are:
# queue=<count>;<warn>;<crit> busy_executors=<count>
#
# Author: Eric Blanchard, Gregor Tudan
#
use strict;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON::Parse 'parse_json';
use Getopt::Long
  qw(GetOptions HelpMessage VersionMessage :config no_ignore_case bundling);
use Pod::Usage qw(pod2usage);
use POSIX;

# Nagios return values
use constant {
    OK       => 0,
    WARNING  => 1,
    CRITICAL => 2,
    UNKNOWN  => 3,
};
use constant API_SUFFIX => "/overallLoad/api/json";
our $VERSION = '1.7';
my %args;
my $ciMasterUrl;
my $queue_warn   = -1;
my $queue_crit   = -1;
my $debug        = 0;
my $status_line  = '';
my $exit_code    = UNKNOWN;
my $timeout      = 10;

# Functions prototypes
sub trace(@);

# Main
GetOptions(
    \%args,
    'version|v' => sub { VersionMessage( { '-exitval' => UNKNOWN } ) },
    'help|h'    => sub { HelpMessage(    { '-exitval' => UNKNOWN } ) },
    'man' => sub { pod2usage( { '-verbose' => 2, '-exitval' => UNKNOWN } ) },
    'debug|d'     => \$debug,
    'timeout|t=i' => \$timeout,
    'proxy=s',
    'user|u=s',
    'password|p=s',
    'noproxy',
    'noperfdata',
    'warning|w=i'  => \$queue_warn,
    'critical|c=i' => \$queue_crit,
  )
  or pod2usage( { '-exitval' => UNKNOWN } );
HelpMessage(
    { '-msg' => 'Missing Jenkins url parameter', '-exitval' => UNKNOWN } )
  if scalar(@ARGV) != 1;
$ciMasterUrl = $ARGV[0];
$ciMasterUrl =~ s/\/$//;

# Master API request
my $ua = LWP::UserAgent->new();
$ua->timeout($timeout);
if ( defined( $args{proxy} ) ) {
    $ua->proxy( 'http', $args{proxy} );
}
else {
    if ( !defined( $args{noproxy} ) ) {

        # Use HTTP_PROXY environment variable
        $ua->env_proxy;
    }
}
my $url = $ciMasterUrl . API_SUFFIX . '?tree=busyExecutors[min[latest]],queueLength[min[latest]]';
my $req = HTTP::Request->new( GET => $url );
if ( defined( $args{user} and defined ($args{password}) ) ) {
    $req->authorization_basic( $args{user}, $args{password} );
}
trace("GET $url ...\n");
my $res = $ua->request($req);
if ( !$res->is_success ) {
    print "Failed retrieving $url ($res->{status_line})";
    exit UNKNOWN;
}
my $obj          = parse_json( $res->content );
my $executors    = $obj->{'busyExecutors'};                   # ref to array
my $busy_count   = $executors->{min}->{latest};
my $queue        = $obj->{'queueLength'};                   # ref to array
my $queue_length = $queue->{min}->{latest};
trace( "Found " . $queue_length . " jobs in waiting queue\n" );

my $perfdata     = '';
if ( !defined( $args{noperfdata} ) ) {
    $perfdata = 'queue='
      . $queue_length . ';'
      . ( $queue_warn == -1 ? '' : $queue_warn ) . ';'
      . ( $queue_crit == -1 ? '' : $queue_crit );
    $perfdata .= ' busy_executors=' . $busy_count;
}

if ( $queue_crit != -1 && $queue_length > $queue_crit ) {
    print "CRITICAL: queue length ", $queue_length, " exeeds critical threshold: ",
      $queue_crit, "\n";
    if ( !defined( $args{noperfdata} ) ) {
        print( '|', $perfdata, "\n" );
    }
    exit CRITICAL;
}
if ( $queue_warn != -1 && $queue_length > $queue_warn ) {
    print "WARNING: queue length ", $queue_length, " exeeds warning threshold: ",
      $queue_warn, "\n";
    if ( !defined( $args{noperfdata} ) ) {
        print( '|', $perfdata, "\n" );
    }
    exit WARNING;
}

print( 'OK: queue length: ', $queue_length );
if ( !defined( $args{noperfdata} ) ) {
    print( '|', $perfdata, "\n" );
}
exit OK;

sub trace(@) {
    if ($debug) {
        print @_;
    }
}
__END__

=head1 NAME

check_jenkins - A Nagios plugin that count the number of jobs of a Jenkins instance (throuh HTTP request)

=head1 SYNOPSIS


check_jenkins.pl --version

check_jenkins.pl --help

check_jenkins.pl --man

check_jenkins.pl [options] <jenkins-url>

    Options:
      -d --debug               turns on debug traces
      -t --timeout=<timeout>   the timeout in seconds to wait for the
                               request (default 30)
         --proxy=<url>         the http proxy url (default from
                               HTTP_PROXY env)
         --noproxy             do not use HTTP_PROXY env
      -u --user                username for authentication
      -p --password            password or api-key for authentication
         --noperfdata          do not output perdata
      -w --warning=<count>     the maximum queue length for WARNING threshold
      -c --critical=<count>    the maximum queue length for CRITICAL threshold
       
=head1 OPTIONS

=over 8

=item B<--help>

    Print a brief help message and exits.
    
=item B<--version>

    Prints the version of this tool and exits.
    
=item B<--man>

    Prints manual and exits.

=item B<-d> B<--debug>

    Turns on debug traces

=item B<-t> B<--timeout=>timeout

    The timeout in seconds to wait for the request (default 30)
    
=item B<--proxy=>url

    The http proxy url (default from HTTP_PROXY env)

=item B<--noproxy>

    Do not use HTTP_PROXY env

=item B<-u> B<--user=>user

    Username for authentication

=item B<-p> B<--password=>password

    Password or API-Key for authentication

=item B<--noperfdata>

    Do not output perdata

=item B<-w> B<--warning=>count

    The maximum queue length for WARNING threshold

=item B<-c> B<--critical=>count

    The maximum queue length for CRITICAL threshold
    
=back

=head1 DESCRIPTION

B<check_jenkins_queue.pl> is an Nagios plugin that checks the number of jobs in the jenkins build queue
It can check that the queue length will not exeed the WARNING and CRITICAL thresholds.
    
=cut
