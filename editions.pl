#!/usr/bin/perl
# nbt, 10.6.2014

# Starting from an OCLC number, get the OCLC numbers of all editions of the same work

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Readonly;
use REST::Client;

Readonly my $EDITION_URL_BASE => 'http://www.worldcat.org/oclc/';
Readonly my $WORK_URL_BASE => 'http://worldcat.org/entity/work/id/';

our $client = REST::Client->new();
$client->addHeader( 'Accept', 'application/ld+json' );
$client->setFollow(1);

my $oclc_number;
if (@ARGV) {
  $oclc_number = $ARGV[0];
} else {
  # example from
  # http://www.econbiz.de/Record/microeconomics-and-behavior-frank-robert/10010339515
  $oclc_number='863381506';
}

print Dumper get_edtions_via_work_for($oclc_number);


sub get_edtions_via_work_for {
  my $oclc_number = shift || die "missing param\n";
  my $edition_uri =  $EDITION_URL_BASE . $oclc_number;
 
  my @oclc_numbers;
  
  # look up the edition's work id 
  if (my $work_uri = fetch_jsonld_property($edition_uri, 'exampleOfWork')) {

    # look up the work's editions
    if (my $works_ref = fetch_jsonld_property($work_uri, 'workExample')) {
      
      # extract the OCLC number
      foreach my $uri (@$works_ref) {
        my @elements = split('/', $uri);
        push(@oclc_numbers, $elements[-1]);
      }
    }
  }
  return \@oclc_numbers;
}

sub fetch_jsonld_property {
  my $resource = shift || die "missing param\n";
  my $property = shift || die "missing param\n";

  # look up the  data 
  $client->GET($resource);
  my $result_ref = decode_json $client->responseContent();

  # q&d json-ld parsing
  my $result = undef;
  my $graph_ref = $$result_ref{'@graph'};
  foreach my $entry_ref (@$graph_ref) {
    next unless ($$entry_ref{'@id'} eq $resource);
    if ($$entry_ref{$property}) {
      $result = $$entry_ref{$property};
    }
  }
  return $result;
}

