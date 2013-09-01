#!/usr/bin/perl -w

## standrd perl modules
use NDBM_File;
use Fcntl;
use Data::Dumper;
use Sys::Syslog;
use Date::Parse;
use Data::Dumper;
use POSIX;

## custom perl modules 
use WRL; # implementation of query and client windowed record lists
use BS; # utilities 
use IPT; # iptables stuff

# WRL::set_debug(1);

## threshold / time config
$threshold_query_ps      =  5; # if this many same query per second
$threshold_query_window  = 10; # over this period of time => block
$threshold_client_ps     =  5; # if the same client per second
$threshold_client_window = 10; # over this period of time => block

$log_check_sleepy_time =  1; # if no new log entries, sleep for this many seconds
$print_count_interval  = 30; # every this many seconds update the html count page

$query_ttl  = 3600;
$client_ttl = 3600;
$cleanup_interval = 1800;

## files config
$queries_log = "/var/log/named/queries.log";

$queries_db  = "/var/log/named/queries.db";
$metadata_db = "/var/log/named/metadata.db";
$queries_block_db  = "/var/log/named/queries_block.db";
$clients_block_db  = "/var/log/named/clients_block.db";

$print_stats_file = "/var/www/blinkenlicht/stats/bind.html";

## misc config
$html_eol = "<br />\n";

## Let's do it

($now, $today) = BS::now();

tie(%queries_per_day, 'NDBM_File', $queries_db, O_CREAT|O_RDWR, 0644)     or do_quit(-1, "queries db $!\n", $now);
tie(%metadata, 'NDBM_File', $metadata_db, O_CREAT|O_RDWR, 0644)           or do_quit(-1, "metadata db $!\n", $now);
tie(%queries_block, 'NDBM_File', $queries_block_db, O_CREAT|O_RDWR, 0644) or do_quit(-1, "queries block db $!\n", $now);
tie(%clients_block, 'NDBM_File', $clients_block_db, O_CREAT|O_RDWR, 0644) or do_quit(-1, "clients block db $!\n", $now);

## main loop control var
$done = 0;

## install signals
sub dump_db
{
    syslog('info', "Recorded queries blocked:\n");
    syslog('info', Dumper(\%queries_block));
    syslog('info', "Recorded clients blocked:\n");
    syslog('info', Dumper(\%clients_block));
}
$sigusr1_action = POSIX::SigAction->new(\&dump_db);
POSIX::sigaction(SIGUSR1, $sigusr1_action);

sub sig_quit
{
    $done = 1;
    syslog('info', 'exiting on user signal');
}
$sighup_action = POSIX::SigAction->new(\&sig_quit);
POSIX::sigaction(SIGHUP, $sighup_action);

$day_queries = $queries_per_day{$today};

print_count();
$print_count_ts = $now;
$cleanup_ts = $now;

openlog("bindstats.pl", "nofatal", "local0");
open($LOG, '<', $queries_log,) or do_quit(-1, "log $!\n", $now, $LOG);

syslog('info', 'Restarting');
($query_records, $client_records) = init_blocks(\%queries_block, \%clients_block, $threshold_query_window, $threshold_client_window);

while (!$done) {
    $log_line = <$LOG>;
    if (!defined($log_line)) {
	sleep $log_check_sleepy_time;
	next;
    }

    ## take apart the log line
    ($valid, $datetime, $date, $query_str, $client_ip) = BS::parse_log_line($log_line);
    if (!$valid) {
	next;
    }
	
    $old_today = $today;
    ($now, $today) = BS::now();

    ## reset day_queries if it's now tomorrow
    # record yesterday's total count
    if ($today != $old_today) {
	$queries_per_day{$old_today} = $day_queries;
	$day_queries = 1;
    } else {
	++$day_queries;
    }
    $queries_per_day{$today} = $day_queries;

    ## create a new client_record and add it to the WRL
    $client_record = ClientRecord->new($datetime);

    if (defined($client_records->{$client_ip})) {
	$client_records->{$client_ip}->add_record($client_record);
    } else {
	$client_records->{$client_ip} = ClientWRL->new($client_ip, $client_record, $threshold_client_window);
    }
    $client_wrl = $client_records->{$client_ip};

    ## create a new query record, linked to the client_wrl, and add it to the WRL
    $query_record = QueryRecord->new($query_str, $client_wrl, $datetime);
    if (defined($query_records->{$query_str})) {
	$query_records->{$query_str}->add_record($query_record);
    } else {
	$query_records->{$query_str} = QueryWRL->new($query_str, $query_record, $threshold_query_window);
    }
    $query_wrl = $query_records->{$query_str};

    ## calculate rates and (potentialy) block
    $query_wrl->calc_rate($now);
    if ($query_wrl->{'rate'} >= $threshold_query_ps) {
	$query_wrl->block();
	$queries_block{$query_str} = 1;
    }

    $client_wrl->calc_rate($now);
    if ($client_wrl->{'rate'} >= $threshold_client_ps) {
	$client_wrl->block();
	$clients_block{$client_ip} = 1;
    }	
    
    if (($now - $cleanup_ts) >= $cleanup_interval) {
	cleanup(\$query_records, $query_ttl, \$client_records, $client_ttl);
	$cleanup_ts = $now;
    }

    if (($now - $print_count_ts) >= $print_count_interval) {
	print_count();
	$print_count_ts = $now;
    }
}

do_quit(0, "normal exit", $now, $LOG);

sub cleanup
{
    my ($query_records, $query_ttl, $client_records, $client_ttl) = @_;
    my (@delete_queries, @delete_clients);
    my ($now, $today) = BS::now();

    my $query_cutoff  = $now - $query_ttl;
    my $client_cutoff = $now - $client_ttl;

    while (($query_str, $query_wrl) = each %$$query_records) {
	if ($query_wrl->{'last_update'} <= $query_cutoff) {
	    delete $$$query_records{$query_str};
	    Sys::Syslog::syslog('info', "forgot about query %s", $query_str);
	}
    }

    while (($client_ip, $client_wrl) = each %$$client_records) {
	if ($client_wrl->{'last_update'} <= $client_cutoff) {
	    delete $$$client_records{$client_ip};
	    Sys::Syslog::syslog('info', "forgot about client %s", $client_ip);
	}
    }
}

sub init_blocks
{
    my ($queries_block, $clients_block, $query_window, $client_window) = @_;
    my ($query, $client);

    my $qrs = {};
    my $crs = {};

    IPT::init_iptables();

    while ($query_str = each %$queries_block) {
	$query_record = QueryRecord->new($query_str, undef, 0);
	$qrs->{$query_str} = QueryWRL->new($query_str, $query_record, $query_window);
	$qrs->{$query_str}->block();
    }
    
    while ($client_ip = each %$clients_block) {
	$client_record = ClientRecord->new(0);
	$crs->{$client_ip} = ClientWRL->new($client_ip, $client_record, $client_window);
	$crs->{$client_ip}->block();
    }

    return ($qrs, $crs);
}

sub print_count
{
    my ($date, @strings);
    open(BINDSTATS, '>', $print_stats_file);
    
    $months = { 0 => "Jan",  1 => "Feb",  2 => "Mar",  3 => "Apr",
		4 => "May",  5 => "Jun",  6 => "Jul",  7 => "Aug",
		8 => "Sep",  9 => "Oct", 10 => "Nov", 11 => "Dec"};

    my @keys = sort { $b <=> $a} (keys(%queries_per_day));
    @keys = splice @keys, 0, 7;
    for $date (@keys) {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($date);
	my $human_date = sprintf("%d-%s-%d", $mday, $months->{$mon}, $year+1900);
	push @strings, "$human_date: $queries_per_day{$date}";
    }
    print BINDSTATS join($html_eol, @strings);

    close(BINDSTATS);
}

sub do_quit
{ 
    my ($ec, $reason, $now, $LOG) = @_;

    close($LOG) if ($LOG);

    $metadata{'last_seen'} = $now if (%metadata);

    untie(%queries_per_day) if (%queries_per_day);
    untie(%metadata)        if (%metadata);
    untie(%clients_block)   if (%clients_block);
    untie(%queries_block)   if (%queries_block);

    closelog();

    exit($ec);
}
