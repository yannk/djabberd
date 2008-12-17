package DJabberd::DNS;
use strict;
use base 'Danga::Socket';
use fields (
            'hostname',
            'callback',
            'srv',
            'port',
            'recurse_count',
            'became_readable',  # bool
            'timed_out',        # bool
            );
use Carp qw(croak);

use DJabberd::Log;
our $logger = DJabberd::Log->get_logger();

use Net::DNS;
my $resolver    = Net::DNS::Resolver->new;

sub srv {
    my ($class, %opts) = @_;

    foreach (qw(callback domain service)) {
        croak("No '$_' field") unless $opts{$_};
    }

    my $hostname = delete $opts{'domain'};
    my $callback = delete $opts{'callback'};
    my $service  = delete $opts{'service'};
    my $port     = delete $opts{'port'};
    my $recurse_count = delete($opts{'recurse_count'}) || 0;
    croak "unknown opts" if %opts;

    # default port for s2s
    $port ||= 5269 if $service eq "_xmpp-server._tcp";
    croak("No specified 'port'") unless $port;

    # testing support
    if ($service eq "_xmpp-server._tcp") {
        my $endpt = DJabberd->fake_s2s_peer($hostname);
        if ($endpt) {
            $callback->($endpt);
            return;
        }
    }

    my $pkt = Net::DNS::Packet->new("$service.$hostname", "SRV", "IN");

    $logger->debug("pkt = $pkt");
    my $sock = $resolver->bgsend($pkt);
    $logger->debug("sock = $sock");
    my $self = $class->SUPER::new($sock);

    $self->{hostname} = $hostname;
    $self->{callback} = $callback;
    $self->{srv}      = $service;
    $self->{port}     = $port;
    $self->{recurse_count} = $recurse_count;

    $self->{became_readable} = 0;
    $self->{timed_out}       = 0;

    # TODO: make DNS timeout configurable
    Danga::Socket->AddTimer(5.0, sub {
        return if $self->{became_readable};
        $self->{timed_out} = 1;
        $logger->debug("DNS 'SRV' lookup for '$hostname' timed out");
        $callback->();
        $self->close;
    });

    $self->watch_read(1);
}

sub new {
    my ($class, %opts) = @_;

    foreach (qw(hostname callback port)) {
        croak("No '$_' field") unless $opts{$_};
    }

    my $hostname = delete $opts{'hostname'};
    my $callback = delete $opts{'callback'};
    my $port     = delete $opts{'port'};
    my $recurse_count = delete($opts{'recurse_count'}) || 0;
    croak "unknown opts" if %opts;

    if ($hostname =~/^\d+\.\d+\.\d+\.\d+$/) {
        # we already have the IP, lets not looking it up
        $logger->debug("Skipping lookup for '$hostname', it is already the IP");
        $callback->(DJabberd::IPEndPoint->new($hostname, $port));
        return;
    }


    my $sock = $resolver->bgsend($hostname);
    my $self = $class->SUPER::new($sock);

    $self->{hostname} = $hostname;
    $self->{callback} = $callback;
    $self->{port}     = $port;
    $self->{recurse_count} = $recurse_count;

    $self->{became_readable} = 0;
    $self->{timed_out}       = 0;

    # TODO: make DNS timeout configurable, remove duplicate code
    Danga::Socket->AddTimer(5.0, sub {
        return if $self->{became_readable};
        $self->{timed_out} = 1;
        $logger->debug("DNS 'A' lookup for '$hostname' timed out");
        $callback->();
        $self->close;
    });

    $self->watch_read(1);
}

# TODO: verify response is for correct thing?  or maybe Net::DNS does that?
# TODO: lots of other stuff.
sub event_read {
    my $self = shift;

    if ($self->{timed_out}) {
        $self->close;
        return;
    }
    $self->{became_readable} = 1;

    if ($self->{srv}) {
        $logger->debug("DNS socket $self->{sock} became readable for 'srv'");
        return $self->event_read_srv;
    } else {
        $logger->debug("DNS socket $self->{sock} became readable for 'a'");
        return $self->event_read_a;
    }
}

sub event_read_a {
    my $self = shift;

    my $sock = $self->{sock};
    my $cb   = $self->{callback};

    my $packet = $resolver->bgread($sock);

    my @ans = $packet->answer;

    for my $ans (@ans) {
        my $rv = eval {
            if ($ans->isa('Net::DNS::RR::CNAME')) {
                if ($self->{recurse_count} < 5) {
                    $self->close;
                    DJabberd::DNS->new(hostname => $ans->cname,
                                       port     => $self->{port},
                                       callback => $cb,
                                       recurse_count => $self->{recurse_count}+1);
                }
                else {
                    # Too much recursion
                    $logger->warn("Too much CNAME recursion while resolving ".$self->{hostname});
                    $self->close;
                    $cb->();
                }
            } elsif ($ans->isa("Net::DNS::RR::PTR")) {
                $logger->debug("Ignoring RR response for $self->{hostname}");
            }
            else {
                $cb->(DJabberd::IPEndPoint->new($ans->address, $self->{port}));
            }
            $self->close;
            1;
        };
        if ($@) {
            $self->close;
            die "ERROR in DNS world: [$@]\n";
        }
        return if $rv;
    }

    # no result
    $self->close;
    $cb->();
}

sub event_read_srv {
    my $self = shift;

    my $sock = $self->{sock};
    my $cb   = $self->{callback};

    my $packet = $resolver->bgread($sock);
    my @ans = $packet->answer;

    # FIXME: is this right?  right order and direction?
    my @targets = sort {
        $a->priority <=> $b->priority ||
        $a->weight   <=> $b->weight
    } grep { ref $_ eq "Net::DNS::RR::SRV" && $_->port } @ans;

    unless (@targets) {
        # no result, fallback to an A lookup
        $self->close;
        $logger->debug("DNS socket $sock for 'srv' had nothing, falling back to 'a' lookup");
        DJabberd::DNS->new(hostname => $self->{hostname},
                           port     => $self->{port},
                           callback => $cb);
        return;
    }

    # FIXME:  we only do the first target now.  should do a chain.
    $logger->debug("DNS socket $sock for 'srv' found stuff, now doing hostname lookup on " . $targets[0]->target);
    DJabberd::DNS->new(hostname => $targets[0]->target,
                       port     => $targets[0]->port,
                       callback => $cb);
    $self->close;
}

package DJabberd::IPEndPoint;
sub new {
    my ($class, $addr, $port) = @_;
    return bless { addr => $addr, port => $port };
}

sub addr { $_[0]{addr} }
sub port { $_[0]{port} }

1;
