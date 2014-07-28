#!/usr/bin/perl
# nbt, 28.7.2014

# Interpret a hash of lists of editions pointing to the same work, keyed by oclc_number.

use strict;
use warnings;

use Carp;
use Data::Dumper;
use File::Slurp;
use JSON;
use Readonly;
use REST::Client;

Readonly my $SET_SIZE => 10000;
Readonly my $OCLC_NUMBER_LIST_FN => 'econbiz_oclc_numbers_' . $SET_SIZE . '.lst';
Readonly my $RESULT_FN => 'all_oclc_editions_' . $SET_SIZE . '.json';
Readonly my $ECONBIZ_RESULT_FN => 'econbiz_editions_' . $SET_SIZE . '.json';
Readonly my $ALL_ECONBIZ_OCLC_FREQ_FN => 'all_econbiz_oclc_freq.json';

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
}
write_file($ECONBIZ_RESULT_FN, encode_json $edition_econbiz_ref);

my $econbiz_count = scalar(keys %$all_econbiz_ref);

print "\nResults from $SET_SIZE example oclc numbers re. $econbiz_count oclc numbers in Econis/EconBiz\n\n";
interpret_result($edition_econbiz_ref);

# debugging
foreach my $oclc_number (246996241, 251028375)  {
#  print "\n", Dumper $oclc_number, $$edition_ref{$oclc_number}, $$edition_econbiz_ref{$oclc_number};
}


#############################

sub interpret_result {
  my $edition_ref = shift || croak "param missing\n";

  my ($count, $nowork_count, $single_count, %multi_count, %bucket_count);
  my %bucket_def = (3 => 5, 6 => 10, 11 => 50, 51 => 100, 101 => 9999);

  foreach my $oclc_number (sort {$a <=> $b} keys %$edition_ref) {
    my @editions = @{$$edition_ref{$oclc_number}};
    my $found = scalar(@editions);

    # some work records don't link back to the actual edition
    if (scalar(@editions) gt 0 and !grep(/$oclc_number/, @editions)) {
      warn "$oclc_number not in list: " . Dumper \@editions;
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
    }
    $count++;
  }

  print "$single_count oclc numbers which's work has only the current edition\n";
  foreach my $from (sort {$a <=> $b} keys %bucket_def) {
    print $bucket_count{$from} . " oclc numbers with $from to $bucket_def{$from} editions\n"
  }
  print "$nowork_count oclc numbers without a work id\n";
  ##print "detailed results: " . Dumper \%multi_count;
}
