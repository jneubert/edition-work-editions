#!/usr/bin/perl
# nbt, 10.6.2014

# Starting from an OCLC number, get the OCLC numbers of all editions of the same work

use strict;
use warnings;

use Data::Dumper;
use File::Slurp;
use File::Tee qw(tee);
use JSON;
use Readonly;
use REST::Client;

Readonly my $EDITION_URL_BASE => 'http://www.worldcat.org/oclc/';
Readonly my $WORK_URL_BASE => 'http://worldcat.org/entity/work/id/';
Readonly my $SET_SIZE => 100000;
Readonly my $LOG_STEP_SIZE => 1000;
Readonly my $OCLC_NUMBER_LIST_FN => 'econbiz_oclc_numbers_' . $SET_SIZE . '.lst';
Readonly my $RESULT_FN => 'all_oclc_editions_' . $SET_SIZE . '.json';
Readonly my $RESULT_EDITION_FN => 'edition_work_' . $SET_SIZE . '.json';
Readonly my $RESULT_WORK_FN => 'work_editions_' . $SET_SIZE . '.json';

tee(STDOUT, '>', "run_$SET_SIZE.log");

my (%edition_work, %work_editions);

# configure REST client
my $client = REST::Client->new();
$client->addHeader( 'Accept', 'application/ld+json' );
$client->setFollow(1);

# read the oclc numbers from file
my @oclc_number_list = read_file($OCLC_NUMBER_LIST_FN);

# iteratate over the numbers and store the result a hash, with
# key is the source edition number and value is a reference to a list of all
# editions of the work (if any)
my %edition;
my $count;
print localtime() . " start\n";
foreach my $oclc_number (@oclc_number_list) {
  chomp($oclc_number);
  my $oclc_numbers_ref = get_edtions_via_work_for($oclc_number);
  $edition{$oclc_number} = $oclc_numbers_ref;
  $count++;
  if ($count % $LOG_STEP_SIZE == 0) {
    print localtime() . " $count checked\n";
    # save intermediate results
    save_results();
  }
}

# save final results
save_results();

print localtime() . " finish\n";


#################################

sub get_edtions_via_work_for {
  my $oclc_number = shift || die "missing param\n";
  my $edition_uri =  $EDITION_URL_BASE . $oclc_number;
 
  my $oclc_numbers_ref = [];
  my ($work_id, $work_uri);
  
  # look up the edition's work id 
  if (!defined($edition_work{$oclc_number})) {
    $work_uri = fetch_jsonld_property($edition_uri, 'exampleOfWork');
    if ($work_uri) {
      my @elements = split('/', $work_uri);
      $work_id = $elements[-1];
      $edition_work{$oclc_number} = $work_id;
    }
  }

  if ($work_id) {
    # look up the work's editions
    if (!defined($work_editions{$work_id})) {
      my $editions_ref = fetch_jsonld_property($work_uri, 'workExample');
      if ($editions_ref) {
        # change single string value from fetch to array_ref
        if (ref($editions_ref) ne 'ARRAY') {
          $editions_ref = [ $editions_ref ];
        }

        # extract the OCLC number (last element of the edition uri)
        foreach my $uri (@$editions_ref) {
          my @elements = split('/', $uri);
          my $other_oclc_number = $elements[-1];
          push(@{$oclc_numbers_ref}, $other_oclc_number);

          # cache for future lookups
          $edition_work{$other_oclc_number} = $work_id;
        }
        $work_editions{$work_id} = $oclc_numbers_ref;
      }
    }
  }
  return $oclc_numbers_ref;
}

sub fetch_jsonld_property {
  my $resource = shift || die "missing param\n";
  my $property = shift || die "missing param\n";

  # look up the  data 
  $client->GET($resource);
  if ($client->responseCode() != 200) {
    print localtime() . " Could not look up $resource (repsonse code " . $client->responseCode() . ")\n";
    # TODO collect ids for later repetition of lookup
    return;
  }

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

sub save_results {

  # save result used for evaluation
  write_file($RESULT_FN, encode_json \%edition);

  # save additional result hashes (currently used only for caching)
  write_file($RESULT_EDITION_FN, encode_json \%edition_work);
  write_file($RESULT_WORK_FN, encode_json \%work_editions);
}
