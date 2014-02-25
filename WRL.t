#!/usr/bin/perl -w

use Test::More qw(no_plan);

use_ok('BS');
require_ok('BS');

use_ok('WRL');
require_ok('WRL');

use_ok('IPT');
require_ok('IPT');

IPT::set_debug(1);

my ($now, $today) = BS::now();
my $query_str = 'tar.blinkenlicht.de';
my $client1_ip = '127.0.0.1';
my $client2_ip = '127.0.0.2';
my $window    = 10;
my $expected_rate = 5/10;

my $record = Record->new($now);
isa_ok($record, 'Record');
ok($record->{'ts'} == $now, "Record has correct 'ts' field");

my $wrl = WindowedRecordList->new('test', $record, $window);
isa_ok($wrl, 'WindowedRecordList');
ok($wrl->{'rate'} == 0, "WRL initial rate is 0");
ok($wrl->{'blocked'} == 0, "WRL initialiy unblocked");
$wrl->add_record($record);
$wrl->add_record($record);
$wrl->add_record($record);
$wrl->add_record($record);
my $n_records = scalar(@{$wrl->{'record_list'}});
ok($n_records == 5, "records in WRL ($n_records) is 5 as expected");
$wrl->calc_rate($now);
ok($wrl->{'rate'} == $expected_rate, "WRL rate ($wrl->{'rate'}) is as expected ($expected_rate)");

my $client_record = ClientRecord->new($now);
isa_ok($client_record, 'ClientRecord');
ok($client_record->{'ts'} == $now, "Client record has correct 'ts' field");

my $cwrl1 = ClientWRL->new($client1_ip, $client_record, $window);
isa_ok($cwrl1, 'ClientWRL');
ok($cwrl1->{'rate'} == 0, "ClientWRL initial rate is 0");
ok($cwrl1->{'blocked'} == 0, "ClientWRL initialiy unblocked");

my $query_record1 = QueryRecord->new($cwrl1, $now);
isa_ok($query_record1, 'QueryRecord');
ok($query_record1->{'ts'} == $now, "Query record has correct 'ts' field");
ok($query_record1->{'client'}->{'id'} eq $cwrl1->{'id'}, "Client added correctly to the query record");

my $cwrl2 = ClientWRL->new($client2_ip, $client_record, $window);
my $query_record2 = QueryRecord->new($cwrl2, $now);

my $qwrl = QueryWRL->new('test', $query_record1, $window);
$qwrl->add_record($query_record1);
ok(!$cwrl1->{'blocked'}, "Record added to Query WRL didn't block client");
$qwrl->block();
ok($qwrl->{'blocked'}, "Blocking a query sets it to blocked");
$qwrl->add_record($query_record2);
ok($cwrl2->{'blocked'}, "Record added to blocked Query WRL blocked the client");
