# Copyright (c) 2013 Sebastian Haas
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY.

# See the LICENSE file for more details.

package IPT;
use strict;

use CFG;

sub do_system
{
    my ($cmd) = @_;

    return system($cmd);

}

sub init_firewall
{
    do_system(sprintf('iptables -N %s', $CFG::iptables_block_chain));
    do_system(sprintf('iptables -F %s', $CFG::iptables_block_chain));

    for my $rule (@IPT::default_rules) {
	do_system(sprintf('iptables -A %s %s', $CFG::iptables_block_chain, $rule));
    }
}

sub block_host
{
    my ($host, $reason) = @_;

    my $ipt_cmd = sprintf('iptables -A %s -p udp --dport 53 -s "%s"', $CFG::iptables_block_chain, $host);
    
    if ($reason) {
	#$ipt_cmd .= sprintf(' -m comment --comment "%s"', $reason);
    }

    $ipt_cmd .= ' -j DROP';

    do_system($ipt_cmd);
    Sys::Syslog::syslog('warning', "blocked client %s (%s)", $host, $ipt_cmd);
}

sub encode_name_part
{
    my ($name_part) = @_;

    return sprintf('%02x%s', length($name_part), unpack('H*', $name_part));
}

sub encode_hex_query
{
    my ($query_str) = @_;

    my ($query_host, @query_flags) = split(/\s+/, $query_str);
    my (@name_parts) = split(/\./, $query_host);

    my $hex_query = join('', map { encode_name_part($_) } (@name_parts, '')); # add the 0 byte root label as ''

    return $hex_query;
}

sub block_query
{
    my ($query_str, $reason) = @_;

    my $hex_query = encode_hex_query($query_str);
    my $ipt_cmd = sprintf('iptables -A %s -p udp --dport 53 -m string --hex-string "|%s|" --algo bm', $CFG::iptables_block_chain, $hex_query);

    if ($reason) {
	#$ipt_cmd .= sprintf(' -m comment --comment "%s"', $reason);
    }

    $ipt_cmd .= ' -j DROP';

    do_system($ipt_cmd);
    Sys::Syslog::syslog('warning', "blocked query %s (%s)", $query_str, $ipt_cmd);
}

1;
