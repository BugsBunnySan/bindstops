package IPT;

## firewall config
$iptables_block_chain = 'DNS_BLOCK'; # the iptables chain we're adding our filter rules to

@default_rules = ('-p udp -m udp --dport 53 -m string --hex-string "|0000ff0001|" --algo bm --to 65535 -j DROP');

sub do_system
{
    my ($cmd) = @_;

    return system($cmd);

}

sub init_iptables
{
    do_system(sprintf('iptables -F %s', $IPT::iptables_block_chain));

    for $rule (@IPT::default_rules) {
	do_system(sprintf('iptables -A %s %s', $IPT::iptables_block_chain, $rule));
    }
}

sub block_host
{
    my ($host, $reason) = @_;

    $ipt_cmd = sprintf('iptables -A %s -p udp --dport 53 -s "%s" -j DROP', $IPT::iptables_block_chain, $host);
    
    if ($reason) {
	#$ipt_cmd .= sprintf('-m comment --comment "%s"', $reason);
    }

    do_system($ipt_cmd);
    Sys::Syslog::syslog('warning', "blocked client %s (%s)", $host, $ipt_cmd);
}

sub block_query
{
    my ($query, $reason) = @_;

    $hex_query = unpack('H*', $query);
    $ipt_cmd = sprintf('iptables -A %s -p udp --dport 53 -m string --hex-string "|%s|" --algo bm -j DROP', $IPT::iptables_block_chain, $hex_query);

    if ($reason) {
	#$ipt_cmd .= sprintf('-m comment --comment "%s"', $reason);
    }

    do_system($ipt_cmd);
    Sys::Syslog::syslog('warning', "blocked query %s (%s)", $query, $ipt_cmd);
}
