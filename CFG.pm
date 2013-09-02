package CFG;
use strict; 

use Fcntl;

## threshold / time config
our $threshold_query_ps      =  5; # if this many same query per second
our $threshold_query_window  = 10; # over this period of time => block
our $threshold_client_ps     =  5; # if the same client per second
our $threshold_client_window = 10; # over this period of time => block

our $log_check_sleepy_time =  1; # if no new log entries, sleep for this many seconds
our $print_count_interval  = 30; # every this many seconds update the html count page

our $query_ttl  = 3600;
our $client_ttl = 3600;
our $cleanup_interval = 1800;

## files config
our $queries_log = "/var/log/named/queries.log";

our $queries_db  = "/var/log/named/queries.db";
our $metadata_db = "/var/log/named/metadata.db";
our $queries_block_db  = "/var/log/named/queries_block.db";
our $clients_block_db  = "/var/log/named/clients_block.db";

our $print_stats_file = "/var/www/blinkenlicht/stats/bind.html";

## misc config
our $html_eol = "<br />\n";

## firewall config
# the iptables chain we're adding our filter rules to
our $iptables_block_chain = 'DNS_BLOCK';

# this blocks ANY type queries
our @default_rules = ('-p udp -m udp --dport 53 -m string --hex-string "|0000ff0001|" --algo bm --to 65535 -j DROP');

# 21-Aug-2013 03:40:20.579 queries: info: client 184.72.178.83#766: query: bfhmm.com IN TXT +E (109.73.52.34)
our $query_regex = '^(\d\d-...-\d\d\d\d) (\d\d:\d\d:\d\d.\d\d\d) .* client ([0-9\.]+)#\d+: query: ([^\(]+) \(';

our $months = { 0 => "Jan",  1 => "Feb",  2 => "Mar",  3 => "Apr",
		4 => "May",  5 => "Jun",  6 => "Jul",  7 => "Aug",
		8 => "Sep",  9 => "Oct", 10 => "Nov", 11 => "Dec"};

our (%queries_per_day, %metadata, %queries_block, %clients_block);

sub init_db
{
    my ($now, $quit_func) = @_;

    tie(%queries_per_day, 'NDBM_File', $queries_db, O_CREAT|O_RDWR, 0644)     or $quit_func->(-1, "queries db $!\n", $now);
    tie(%metadata, 'NDBM_File', $metadata_db, O_CREAT|O_RDWR, 0644)           or $quit_func->(-1, "metadata db $!\n", $now);
    tie(%queries_block, 'NDBM_File', $queries_block_db, O_CREAT|O_RDWR, 0644) or $quit_func->(-1, "queries block db $!\n", $now);
    tie(%clients_block, 'NDBM_File', $clients_block_db, O_CREAT|O_RDWR, 0644) or $quit_func->(-1, "clients block db $!\n", $now);
}

sub close_db
{
    my ($now) = @_;

    $metadata{'last_seen'} = $now if (%metadata);

    untie(%queries_per_day) if (%queries_per_day);
    untie(%metadata)        if (%metadata);
    untie(%clients_block)   if (%clients_block);
    untie(%queries_block)   if (%queries_block);
}

1;
