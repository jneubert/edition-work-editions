#!/usr/bin/perl
# nbt, 28.7.2014

# Interpret a hash of lists of editions pointing to the same work, keyed by oclc_number.

use strict;
use warnings;

use Carp;
use Data::Dumper;
use File::Slurp;
use File::Tee qw(tee);
use JSON;
use Readonly;
use REST::Client;

Readonly my $SET_SIZE => 100000;
Readonly my $OCLC_NUMBER_LIST_FN => 'econbiz_oclc_numbers_' . $SET_SIZE . '.lst';
Readonly my $RESULT_FN => 'all_oclc_editions_' . $SET_SIZE . '.json';
Readonly my $ECONBIZ_RESULT_FN => 'econbiz_editions_' . $SET_SIZE . '.json';
Readonly my $ALL_ECONBIZ_OCLC_FREQ_FN => 'all_econbiz_oclc_freq.json';
Readonly my $LARGE_LIST_SIZE => 50;

# open output files
tee(STDOUT, '>', "result_$SET_SIZE.txt");
tee(STDERR, '>', "error_$SET_SIZE.txt");

$Data::Dumper::Sortkeys = sub {
  no warnings 'numeric';
    [ sort { $a <=> $b } keys %{$_[0]} ]
  };

my $edition_ref = decode_json read_file($RESULT_FN);

print "\nResults from $SET_SIZE example oclc numbers re. all oclc numbers\n\n";
interpret_result($edition_ref);

my $edition_econbiz_ref = {};
my $all_econbiz_ref = decode_json read_file($ALL_ECONBIZ_OCLC_FREQ_FN);

# map result to oclc numbers existing in econis/econbiz
my $econbiz_instance_count = 0;
my $large_ref;
foreach my $oclc_number (keys %$edition_ref) {
  $$edition_econbiz_ref{$oclc_number} = [];
  my @editions = @{$$edition_ref{$oclc_number}};

  # fix missing actual edition in oclc data
  if (scalar(@editions) gt 0 and !grep(/$oclc_number/, @editions)) {
    push(@{$$edition_econbiz_ref{$oclc_number}}, $oclc_number);
  }

  # add to econbiz editions only when oclc_number exists in econbiz
  foreach my $edition (@editions) {
    next unless defined $$all_econbiz_ref{$edition};
    push(@{$$edition_econbiz_ref{$oclc_number}}, $edition);
  }

  # log very large sets
  if (scalar(@{$$edition_econbiz_ref{$oclc_number}} > $LARGE_LIST_SIZE)) {
    $$large_ref{$oclc_number} = scalar(@{$$edition_econbiz_ref{$oclc_number}});
  }

  # sometimes multiple econbiz instances per oclc number exist
  $econbiz_instance_count += $$all_econbiz_ref{$oclc_number};
}
write_file($ECONBIZ_RESULT_FN, encode_json $edition_econbiz_ref);

my $econbiz_count = scalar(keys %$all_econbiz_ref);

print "\nResults from $SET_SIZE example oclc numbers re. $econbiz_count oclc numbers in Econis/EconBiz\n\n";
interpret_result($edition_econbiz_ref);

print "\n\n" . ($econbiz_instance_count / $SET_SIZE) . " econbiz instances per oclc number\n\n";

print "oclc numbers with particular large sets of other editions: ", Dumper $large_ref;

# debugging
foreach my $oclc_number (246996241, 251028375)  {
#  print "\n", Dumper $oclc_number, $$edition_ref{$oclc_number}, $$edition_econbiz_ref{$oclc_number};
}

#############################

sub interpret_result {
  my $edition_ref = shift || croak "param missing\n";

  # initialize counters and buckets for counting
  my $count = 0;
  my $nowork_count = 0;
  my $single_count = 0;
  my $linkerror_count = 0;
  my (%multi_count, %bucket_count, %multi_occurences);
  my %bucket_def = (2 => 2, 3 => 5, 6 => 10, 11 => 50, 51 => 100, 101 => 9999);
  foreach my $from (keys %bucket_def) {
    $bucket_count{$from} = 0;
  }

  foreach my $oclc_number (sort {$a <=> $b} keys %$edition_ref) {
    my @editions = @{$$edition_ref{$oclc_number}};
    my $found = scalar(@editions);

    # some work records don't link back to the actual edition
    if (scalar(@editions) gt 0 and !grep(/$oclc_number/, @editions)) {
      warn "$oclc_number not in list: " . Dumper \@editions;
      $linkerror_count++;
    }

    if ($found eq 0) {
      $nowork_count++;
    }
    elsif ($found eq 1) {
      $single_count++;
      if ($oclc_number ne $editions[0]) {
        warn "$oclc_number and $editions[0] should be the same\n";
      }
    }
    else {
      $multi_count{$found}++;
      foreach my $from (keys %bucket_def) {
        if ($found >= $from and $found <= $bucket_def{$from}) {
          $bucket_count{$from}++;
        }
      }
      foreach my $edition (@editions) {
        $multi_occurences{$edition}++;
      }
    }
    $count++;
  }

  my $total_multiple = $SET_SIZE - ($single_count + $nowork_count);
  my $total_occurences = scalar(keys %multi_occurences);

  printf "%6d oclc numbers which's work has only the current edition\n", $single_count;
  foreach my $from (sort {$a <=> $b} keys %bucket_def) {
    if ($from eq $bucket_def{$from}) {
      printf "%6d oclc numbers with $from editions\n", $bucket_count{$from};
    }
    else {
      printf "%6d oclc numbers with $from to $bucket_def{$from} editions\n", $bucket_count{$from};
    }
  }
  printf "%6d oclc numbers without a work id\n", $nowork_count;
  printf "%6d missing backlinks to the oclc number\n", $linkerror_count;
  printf "%6d oclc numbers (%.1f %%) point to works with multiple editions, with $total_occurences total edtions\n", $total_multiple, ($total_multiple/$SET_SIZE)*100;

  ##print "detailed results: " . Dumper \%multi_count;
}
