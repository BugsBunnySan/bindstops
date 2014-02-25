#!/usr/bin/perl -w

use Test::More qw(no_plan);

use_ok('Time::HiRes');

use_ok('BS');
require_ok('BS');

my ($now, $today) = BS::now();

$delta = $now - Time::HiRes::time();
ok($delta <= 1, "now reports the time corretly");

my $qname = BS::encode_query('wiki.blinkenlicht.de IN A');
print "$qname\n";
