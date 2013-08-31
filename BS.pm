package BS;

use Date::Parse qw(str2time);
use Time::HiRes qw(time);

# 21-Aug-2013 03:40:20.579 queries: info: client 184.72.178.83#766: query: bfhmm.com IN TXT +E (109.73.52.34)
$query_regex = '^(\d\d-...-\d\d\d\d) (\d\d:\d\d:\d\d.\d\d\d) .* client ([0-9\.]+)#\d+: query: ([^\(]+) \(';

sub now
{
    my ($time, $months, $today, $now);

    $months = { 0 => "Jan",  1 => "Feb",  2 => "Mar",  3 => "Apr",
		4 => "May",  5 => "Jun",  6 => "Jul",  7 => "Aug",
		8 => "Sep",  9 => "Oct", 10 => "Nov", 11 => "Dec"};

    $time = time;
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);
    $today = str2time(sprintf("%d-%s-%d", $mday, $months->{$mon}, $year+1900)); # normalize to day

    return ($time, $today);
}

sub parse_log_line
{
    my ($log_line) = @_;

    chomp($log_line);

    $log_line =~ m/$query_regex/;
    my ($date, $time, $client_ip, $query_str) = ($1, $2, $3, $4, $5);
    $dt   = str2time("$date $time");
    $date = str2time($date);

    return ($dt, $date, $query_str, $client_ip);
}

return 1;
