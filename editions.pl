#!/usr/bin/perl
# nbt, 10.6.2014

# Starting from an OCLC number, get the OCLC numbers of all editions of the same work

use strict;
use warnings;

use Data::Dumper;
use File::Slurp;
use JSON;
use Readonly;
use REST::Client;

Readonly my $EDITION_URL_BASE => 'http://www.worldcat.org/oclc/';
Readonly my $WORK_URL_BASE => 'http://worldcat.org/entity/work/id/';
Readonly my $SET_SIZE => 100000;
Readonly my $OCLC_NUMBER_LIST_FN => 'econbiz_oclc_numbers_' . $SET_SIZE . '.lst';
Readonly my $RESULT_FN => 'all_oclc_editions_' . $SET_SIZE . '.json';

our $client = REST::Client->new();
$client->addHeader( 'Accept', 'application/ld+json' );
$client->setFollow(1);

# read the oclc numbers from file
my @oclc_number_list = read_file($OCLC_NUMBER_LIST_FN);

# iteratate over the numbers and store the result a hash, with
# key is the source edition number and value is a reference to a list of all
# editions of the work (if any)
my %edition;
foreach my $oclc_number (@oclc_number_list) {
  chomp($oclc_number);
  my $editions_ref = get_edtions_via_work_for($oclc_number);
  $edition{$oclc_number} = $editions_ref;
}

write_file($RESULT_FN, encode_json \%edition);


#################################

sub get_edtions_via_work_for {
  my $oclc_number = shift || die "missing param\n";
  my $edition_uri =  $EDITION_URL_BASE . $oclc_number;
 
  my @oclc_numbers;
  
  # look up the edition's work id 
  if (my $work_uri = fetch_jsonld_property($edition_uri, 'exampleOfWork')) {

    # look up the work's editions
    if (my $editions_ref = fetch_jsonld_property($work_uri, 'workExample')) {

      # change single string value from fetch to array_ref
      if (ref($editions_ref) ne 'ARRAY') {
        $editions_ref = [ $editions_ref ];
      }
      
      # extract the OCLC number (last element of the edition uri)
      foreach my $uri (@$editions_ref) {
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
  return unless $client->responseCode() == 200;
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

