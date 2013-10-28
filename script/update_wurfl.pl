#!/usr/bin/perl -w
# vim:filetype=perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Mobile::Wurfl::UpdateScript;

my %opts;

Mobile::Wurfl::UpdateScript->run(\%opts, \@ARGV);

1;
