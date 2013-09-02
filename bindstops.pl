#!/usr/bin/perl -w
use strict;

# BindStops
# stops bind attacks using firewall rules
#
# Copyright (c) 2013 Sebastian Haas
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY.

# See the LICENSE file for more details.


## standrd perl modules
use NDBM_File;
use Sys::Syslog;
use Date::Parse;
use Data::Dumper;
use POSIX;

## custom perl modules 
use WRL; # implementation of query and client windowed record lists
use BS; # utilities 
use IPT; # iptables stuff
use CFG; # configuration

# WRL::set_debug(1);

## Let's do it
our ($now, $today) = BS::now();
CFG::init_db($now, \&do_quit);

init_signals();

## main loop control var
our $loop_ctrl = 1;

our $day_queries = $CFG::queries_per_day{$today};

our $print_count_ts = $now;
our $cleanup_ts = $now;

openlog("bindstops.pl", "nofatal", "local0");
syslog('info', 'Starting');

if ($CFG::print_count_interval >= 0) {
    print_count($CFG::print_stats_file, \%CFG::queries_per_day);
}

open(our $LOG, '<', $CFG::queries_log,) or do_quit(-1, "log $!\n", $now, $LOG);

our ($query_records, $client_records) = init_blocks(\%CFG::queries_block, \%CFG::clients_block, $CFG::threshold_query_window, $CFG::threshold_client_window);

while ($loop_ctrl) {
    my $log_line = <$LOG>;
    if (!defined($log_line)) { # => we're at EOF, wait a bit and try again
	sleep $CFG::log_check_sleepy_time;
	next;
    }

    ## take apart the log line
    my ($valid, $datetime, $date, $query_str, $client_ip) = BS::parse_log_line($log_line);
    if (!$valid) {
	next;
    }
	
    my $old_today = $today;
    ($now, $today) = BS::now();

    ## reset day_queries if it's now tomorrow
    # record yesterday's total count
    if ($today != $old_today) {
	$CFG::queries_per_day{$old_today} = $day_queries;
	$day_queries = 1;
    } else {
	++$day_queries;
    }
    $CFG::queries_per_day{$today} = $day_queries;

    ## create a new client_record and add it to the WRL
    my $client_record = ClientRecord->new($datetime);

    if (defined($client_records->{$client_ip})) {
	$client_records->{$client_ip}->add_record($client_record);
    } else {
	$client_records->{$client_ip} = ClientWRL->new($client_ip, $client_record, $CFG::threshold_client_window);
    }
    my $client_wrl = $client_records->{$client_ip};

    ## create a new query record, linked to the client_wrl, and add it to the WRL
    my $query_record = QueryRecord->new($client_wrl, $datetime);
    if (defined($query_records->{$query_str})) {
	$query_records->{$query_str}->add_record($query_record);
    } else {
	$query_records->{$query_str} = QueryWRL->new($query_str, $query_record, $CFG::threshold_query_window);
    }
    my $query_wrl = $query_records->{$query_str};

    ## calculate rates and (potentialy) block
    if (!$CFG::queries_block{$query_str}) {
	$query_wrl->calc_rate($now);
	if ($query_wrl->{'rate'} >= $CFG::threshold_query_ps) {
	    $query_wrl->block();
	    $CFG::queries_block{$query_str} = 1;
	}
    }
    if (!$CFG::clients_block{$client_ip}) {
	$client_wrl->calc_rate($now);
	if ($client_wrl->{'rate'} >= $CFG::threshold_client_ps) {
	    $client_wrl->block();
	    $CFG::clients_block{$client_ip} = 1;
	}	
    }
    
    if (($now - $cleanup_ts) >= $CFG::cleanup_interval) {
	cleanup(\$query_records, $CFG::query_ttl, \$client_records, $CFG::client_ttl);
	$cleanup_ts = $now;
    }

    if (($CFG::print_count_interval >= 0) && 
	(($now - $print_count_ts) >= $CFG::print_count_interval)) {
	print_count($CFG::print_stats_file, \%CFG::queries_per_day);
	$print_count_ts = $now;
    }
}

do_quit(0, "normal exit", $now, $LOG);

sub cleanup
{
    ## removes wrl's to conserv memory, doesn't touch the clients/queries _block register

    my ($query_records, $query_ttl, $client_records, $client_ttl) = @_;
    my ($now, $today) = BS::now();

    my $query_cutoff  = $now - $query_ttl;
    my $client_cutoff = $now - $client_ttl;

    while (my ($query_str, $query_wrl) = each %$$query_records) {
	if ($query_wrl->{'last_update'} <= $query_cutoff) {
	    delete $$$query_records{$query_str};
	    #Sys::Syslog::syslog('info', "forgot about query %s", $query_str);
	}
    }

    while (my ($client_ip, $client_wrl) = each %$$client_records) {
	if ($client_wrl->{'last_update'} <= $client_cutoff) {
	    delete $$$client_records{$client_ip};
	    #Sys::Syslog::syslog('info', "forgot about client %s", $client_ip);
	}
    }
}

sub init_signals
{
    sub dump_db
    {
	syslog('info', "Recorded queries blocked:\n");
	syslog('info', Dumper(\%CFG::queries_block));
	syslog('info', "Recorded clients blocked:\n");
	syslog('info', Dumper(\%CFG::clients_block));
    }

    sub sig_quit {
	$main::loop_ctrl = 0;
	syslog('info', 'exiting on user signal');
    }

    my $sigusr1_action = POSIX::SigAction->new(\&dump_db);
    POSIX::sigaction(SIGUSR1, $sigusr1_action);

    my $sighup_action = POSIX::SigAction->new(\&sig_quit);
    POSIX::sigaction(SIGHUP, $sighup_action);
}

sub init_blocks
{
    my ($queries_block, $clients_block, $query_window, $client_window) = @_;
    my ($query, $client);

    my $qrs = {};
    my $crs = {};

    IPT::init_firewall();

    while (my $query_str = each %$queries_block) {
	my $query_record = QueryRecord->new(undef, 0);
	$qrs->{$query_str} = QueryWRL->new($query_str, $query_record, $query_window);
	$qrs->{$query_str}->block();
    }
    
    while (my $client_ip = each %$clients_block) {
	my $client_record = ClientRecord->new(0);
	$crs->{$client_ip} = ClientWRL->new($client_ip, $client_record, $client_window);
	$crs->{$client_ip}->block();
    }

    return ($qrs, $crs);
}

sub print_count
{
    my ($stats_file, $queries_per_day) = @_;

    my ($date, @strings);
    open(BINDSTATS, '>', $stats_file);
    
    my @keys = sort { $b <=> $a} (keys(%$queries_per_day));
    @keys = splice @keys, 0, 7;
    for $date (@keys) {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($date);
	my $human_date = sprintf("%d-%s-%d", $mday, $CFG::months->{$mon}, $year+1900);
	push @strings, "$human_date: $queries_per_day->{$date}";
    }
    print BINDSTATS join($CFG::html_eol, @strings);

    close(BINDSTATS);
}

sub do_quit
{ 
    my ($ec, $reason, $now, $LOG) = @_;

    close($LOG) if ($LOG);

    CFG::close_db($now);

    closelog();

    exit($ec);
}
