#!/usr/bin/perl
# nbt, 25.7.2014

# Extract random oclc numbers from EconBiz 
# (from the output of the following query against an EconBiz test instance)
# wget -O econbiz_oclc.json "http://thorin:9070/solr/select/?wt=json&q=has:identifier_oclc&version=2.2&start=0&rows=10&indent=on&facet=true&facet.field=identifier_oclc&facet.limit=-1"

use strict;
use warnings;

use Data::Dumper;
use File::Slurp;
use JSON;
use Readonly;

# number of radom oclc numbers to select
Readonly my $TARGET_SIZE => 10000;
Readonly my $ECONBIZ_OUTPUT => 'econbiz_oclc.json';
Readonly my $TARGET_FN => 'econbiz_oclc_numbers_' . $TARGET_SIZE . '.lst';
Readonly my $ALL_OCLC_FREQ_FN => 'all_econbiz_oclc_freq.json';

my $econbiz_output = read_file($ECONBIZ_OUTPUT);
my $econbiz_json = decode_json($econbiz_output);

# create a hash with oclc_number as key and count of occurrences in econbiz as value
my %all_oclc = @{$$econbiz_json{'facet_counts'}{'facet_fields'}{'identifier_oclc'}};

# save file as json for further processing
write_file($ALL_OCLC_FREQ_FN, encode_json(\%all_oclc));

# set of all oclc numbers
my  @all_oclc_numbers = keys(%all_oclc);

# get and save the set of target oclc numbers
my $target_ref = get_random_entries(\@all_oclc_numbers, $TARGET_SIZE);
write_file($TARGET_FN, join("\n", @$target_ref));


#################################################

sub get_random_entries {
  my $source_ref = shift;
  my $target_size = shift;

  my $source_size = scalar(@$source_ref);

  # collect target numbers in a hash to filter out duplicates
  my %target;
  while (scalar(keys(%target)) < $target_size) {

    # get a random value between 0 and the size of the source array
    my $rand = int(rand($source_size));

    # select the oclc number at that position of the source array
    my $oclc_number = $$source_ref[$rand];

    # skip invalid values for oclc numbers (such as 'ocn')
    next unless $oclc_number =~ m/\d+/;

    $target{$oclc_number}++;
  }

  my @target_list = keys(%target);
  return \@target_list;
}

