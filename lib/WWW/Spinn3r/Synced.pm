package WWW::Spinn3r::Synced;

use WWW::Spinn3r;
use DateTime;
use DateTime::Duration;
use DateTime::Format::ISO8601;

use DB_File;
use Fcntl;
use File::Temp qw(tempfile);
use Storable qw(freeze thaw);

my $iso8601 = DateTime::Format::ISO8601->new;

sub new {
  my $p = shift;

  my %param = @_;
  exists $param{api} and die "don't pass api to WWW::Spinn3r::Synced, use WWW::Spinn3r instead if you want a specific api";
  delete $param{api};

  my $match_range = delete($param{match_range}) || 30;

  my %fparam = %param;
  my %pparam = %param;

  $fparam{params} = {%{$pparam{params}}}; # clone hash
  my $feed_after = $fparam{params}->{after}->clone;
  $feed_after -= DateTime::Duration->new(seconds => $match_range);
  $fparam{params}->{after} = $feed_after;

  my $self = bless {
    feed	=> WWW::Spinn3r->new(api => 'feed.getDelta', %fparam),
    permalink	=> WWW::Spinn3r->new(api => 'permalink.getDelta', %pparam),
    fi		=> { },
    last_ftime	=> undef,
    match_range	=> $match_range,
  }, $p;

  $self
}

sub feed_next {
  my $self = shift;
  $self->{feed}->next(@_);
}

sub permalink_next {
  my $self = shift;
  $self->{permalink}->next(@_);
}

sub next() {
  my $self = shift;
  my $fi = $self->{fi};
  my $match_range = $self->{match_range};

  my $pitem = $self->permalink_next;
  my $ptime = $pitem->{t} = $iso8601->parse_datetime($pitem->{'post:date_found'})->epoch;
  my $min_t = $ptime - $match_range;
  my $max_t = $ptime + $match_range;
  my $link = $$pitem{link};

  while ($self->{last_ftime} <= $max_t) {
    my $fitem = $self->feed_next;
    my $ftime = $fitem->{t} = $iso8601->parse_datetime($fitem->{'post:date_found'})->epoch;
    $$fi{$$fitem{link}} = $fitem;
    $self->{last_ftime} = $ftime;
  }

  # this feed item, if defined, goes with this permalink
  my $fitem = delete $$fi{$link};

  # remove feed items which don't refer to permalink items
  for my $flink (keys %$fi) {
    my $fitem = $$fi{$flink};
    my $ftime = $$fitem{t};
    $ftime < $min_t and delete $$fi{$flink};
  }

  [$pitem, $fitem]
}


1;

=head1 NAME 

WWW::Spinn3r::Synced - A interface that provides synced access to
permalink and feed APIs.

=head1 SYNOPOSIS 

 use WWW::Spinn3r::Synced;
 use DateTime;

 my $API = { 
    vendor          => 'acme',   # required
    limit           => 5, 
    after           => DateTime->now()->subtract(hours => 48),
 };

 my $spnr = new WWW::Spinn3r::Synced (params => $API, debug => 1);

 while(1) { 
     my ($p, $f) = @{ $spnr->next };
     if ($p and $f) { 
        print "both! $$p{link}\n"
     } else { 
        print "permalink only! $$p{link}\n"
     }
 }

=head1 DESCRIPTION

WWW::Spinn3r::Synced synchronizes the C<permalink.getDelta> and
C<feed.getDelta> APIs provided by Spinn3r such that next() returns both
the permalink and feed items associated with a link.

=head1 B<new()>

The same as new() in WWW::Spinn3r but doesn't accept an C<api> key, since 
both APIs are used internally by this module.

=head1 next()

Returns an arrayref, the first element is the permalink item and the 
second element is the feed item.  When a feed item is not available, 
the permalink is returned as first item, and the second item is set
to undef.

=head1 SEE ALSO 

examples/synced.pl, WWW::Spinn3r 

=head1 AUTHOR 

Dan Brumleve <opensource@slaant.com>

=cut
