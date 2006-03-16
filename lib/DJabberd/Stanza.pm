package DJabberd::Stanza;
use strict;
use base qw(DJabberd::XMLElement);

sub process {
    my ($self, $conn) = @_;
    warn "$self ->process not implemented\n";
}

# at this point, it's assumed the stanza has passed filtering checks,
# and should be delivered.
sub deliver {
    my ($stanza, $conn) = @_;

    $conn->run_hook_chain(phase => "deliver",
                          args  => [ $stanza ],
                          methods => {
                              finished => sub { },
                              # FIXME: in future, this should note deliver was
                              # complete and the next message to this jid should be dequeued and
                              # subsequently delivered.  (in order deliver)
                          },
                          fallback => sub {
                              $stanza->delivery_failure($conn);
                          });
}

# by default, stanzas need to and from coming from a server
sub acceptable_from_server {
    my ($self, $conn) = @_;  # where $conn is a serverin connection
    my ($to, $from) = ($self->to_jid, $self->from_jid);
    return 0 unless $to && $from;
    return 0 unless $from->domain eq $conn->peer_domain;
    return 1;
}

sub delivery_failure {
    my ($self, $conn) = @_;
    warn "$self has no ->delivery_failure method implemented\n";
}

sub to {
    my $self = shift;
    my $ns = $self->namespace;
    return $self->attr("{$ns}to");
}

sub from {
    my $self = shift;
    my $ns = $self->namespace;
    return $self->attr("{$ns}from");
}

sub set_from {
    my ($self, $fromstr) = @_;
    my $ns = $self->namespace;
    return $self->set_attr("{$ns}from", $fromstr);
}

sub to_jid {
    my $self = shift;
    my $to = $self->to;
    return $to ? DJabberd::JID->new($to) : undef;
}

sub from_jid {
    my $self = shift;
    my $from = $self->from;
    return $from ? DJabberd::JID->new($from) : undef;
}

1;
