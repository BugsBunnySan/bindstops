package BS;

use Date::Parse qw(str2time);
use Time::HiRes qw(time);
use Sys::Syslog;

use CFG;

sub now
{
    my ($time, $months, $today, $now);

    $time = time;
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);
    $today = str2time(sprintf("%d-%s-%d", $mday, $CFG::months->{$mon}, $year+1900)); # normalize to day

    return ($time, $today);
}

sub parse_log_line
{
    my ($log_line) = @_;
    my ($valid, $date, $time, $client_ip, $query_str);

    chomp($log_line);

    if ($log_line =~ m/$CFG::query_regex/) {
	$valid = 1;
	($date, $time, $client_ip, $query_str) = ($1, $2, $3, $4, $5);
	$dt   = str2time("$date $time");
	$date = str2time($date);
    } else {
	$valid = 0;
	syslog('info', "Couldn't parse logline: $log_line");
    }

    return ($valid, $dt, $date, $query_str, $client_ip);
}

sub encode_query
{
    my ($query) = @_;
    my (@parts, $pack_string, @pack_values, $length, $qname);

    chomp($query);
    $query =~ m/^([\w\.]+)\s.+$/;
    $name = $1;

    @parts = split(/\./, $name);

    $pack_string = '';
    foreach $part (@parts) {
	$length = length($part);
	$pack_string .= sprintf('C A%d ', $length);
	push @pack_values, ($length, $part);
    }
    $pack_string .= 'C';
    push @pack_values, 0;

    $qname = pack($pack_string, @pack_values);

    return $qname;
}

return 1;
