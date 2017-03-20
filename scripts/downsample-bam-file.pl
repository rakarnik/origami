#!/usr/bin/perl

use strict;
use List::Util qw/shuffle/;

die "Syntax: <BAM file> <number of pairs> <tmp file> " unless scalar(@ARGV)>=3;

my ($bamfile,$npairs,$tmpfile) = @ARGV;


die "Cannot find $bamfile" unless -e $bamfile;
die "Number of pairs has to be non-negative" unless $npairs > 0;

my @pairs;

open(B,"samtools view -h $bamfile |") or die "Cannot read BAM file $bamfile: $!";
open(O,">","$tmpfile") or die "Cannot write to $tmpfile: $!";

while(<B>) {
  if( /^@/ ) {
    print O;
    next;
  }
  
  my $p1 = $_;
  my $p2 = <B>;
  
  my ($r1) = split /\t/, $p1;
  my ($r2) = split /\t/, $p2;
  
  die "BAM file does not look paired, saw $r1 and $r2" unless $r1 eq $r2;
  
  push @pairs, [$p1,$p2];
}

close(B);

die "No paired-end reads found in BAM file!" if scalar(@pairs)==0;

@pairs = shuffle @pairs;

for( my $i = 0; $i < $npairs; $i++ ) {
  print O for(@{$pairs[$i]});
}

close(O);

