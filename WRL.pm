package WRL;

use Sys::Syslog;
use IPT;

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
	    $record->{'client'}->block("blocked for querying blocked query ($this->{'id'})");
	}
    }
}
    
sub block
{
    my ($this, $reason) = @_;

    return if ($this->{'blocked'});

    
    #IPT::block_query($main::iptables_block_chain, $this->{'id'}, $reason);

    for $query (@{$this->{'record_list'}}) {
	if (defined $query->{'client'}) {
	    $query->{'client'}->block("blocked for adding to blocked query ($this->{'id'})");
	}
    }

    $this->{'blocked'} = 1;
    $main::queries_block{$this->{'id'}} = 1;
}

package ClientWRL;
our @ISA = (WindowedRecordList);

sub block
{
    my ($this, $reason) = @_;
    my ($ipt_cmd) = @_;

    return if ($this->{'blocked'});

    IPT::block_host($this->{'id'}, $reason);

    $this->{'blocked'} = 1;
    $main::clients_block{$this->{'id'}} = 1;
}


return 1;
