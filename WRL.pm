package WRL;

use Sys::Syslog;

$debug = 0;

sub set_debug
{
    ($WRL::debug) = @_;
}

package Record;
sub new
{
    my ($cls, $ts) = @_;

    my $this = {'ts' => $ts};

    return bless $this, $cls;
}

package QueryRecord;
## records the client as well
#  we'll be blocking clients participating in a query that's > threshold
our @ISA = (Record);
sub new
{
    my ($cls, $query_str, $client, $ts) = @_;

    my $this = {'query_str' => $query_str,
		'client'    => $client,
		'ts'        => $ts};

    return bless $this, $cls;
}

package ClientRecord;
## for now this is just a copy of Record
our @ISA = (Record);

package WindowedRecordList;

sub new
{
    my ($cls, $id, $record, $window) = @_;

    my $this = {'id' => $id, 
		'record_list' => [$record],
		'window'      => $window,
		'last_update' => $record->{'ts'},
		'rate'        => 0,
		'blocked'     => 0,
    };

    bless $this, $cls;

    return $this;
}

sub add_record
{
    my ($this, $record) = @_;

    push @{$this->{'record_list'}}, $record;
    $this->{'last_update'} = $record->{'ts'};
}

sub calc_rate
{
    my ($this, $now) = @_;

    my $start_ts = $now - $this->{'window'};

    @{$this->{'record_list'}} = grep { $_->{'ts'} >= $start_ts } @{$this->{'record_list'}};

    $this->{'rate'} = scalar(@{$this->{'record_list'}}) / $this->{'window'};
}

package QueryWRL;
our @ISA = (WindowedRecordList);

sub add_record
{
    my ($this, $record) = @_;

    push @{$this->{'record_list'}}, $record;
    $this->{'last_update'} = $record->{'ts'};
    
    ## querying a blocked query gets you blocked
    if ($this->{'blocked'}) {
	if (!$record->{'client'}->{'blocked'}) {
	    $record->{'client'}->block();
	}
    }
}
    
sub block
{
    my ($this) = @_;
    my ($query, $hex_query, $ipt_cmd);

    return if ($this->{'blocked'});

    #$hex_query = unpack('H*', $this->{'id'});
    #$ipt_cmd = sprintf('iptables -A INPUT -p udp --dport 53 -m string --hex-string "|%s|" --algo bm -j DROP', $hex_query);

    if ($WRL::debug) {
	print "$ipt_cmd\n";
    } else {
	#system($ipt_cmd);
	Sys::Syslog::syslog('warning', "blocked query %s (%s)", $this->{'id'}, $ipt_cmd);
    }

    for $query (@{$this->{'record_list'}}) {
	$query->{'client'}->block();
    }

    $this->{'blocked'} = 1;
}

package ClientWRL;
our @ISA = (WindowedRecordList);

sub block
{
    my ($this) = @_;
    my ($ipt_cmd) = @_;

    return if ($this->{'blocked'});

    $ipt_cmd = sprintf('iptables -A INPUT -p udp --dport 53 -s "%s" -j DROP', $this->{'id'});

    if ($WRL::debug) {
	print "$ipt_cmd\n";
    } else {
	system($ipt_cmd);
	Sys::Syslog::syslog('warning', "blocked client %s (%s)", $this->{'id'}, $ipt_cmd);
    }

    $this->{'blocked'} = 1;
}


return 1;
