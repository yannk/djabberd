# this isn't meant to be used in production, but just for weird
# internal uses.  maybe you'll use it in production anyway.

package DJabberd::Connection::SimpleIn;
use strict;
use base 'DJabberd::Connection';
use fields (
            'read_buf',
            );

sub new {
    my ($class, $sock, $vhost) = @_;
    my $self = $class->SUPER::new($sock);

    warn "Vhost = $vhost\n";

    $self->{vhost}   = $vhost;
    Scalar::Util::weaken($self->{vhost});

    $self->{read_buf} = '';

    warn "CONNECTION from " . $self->peer_ip_string . " == $self\n";

    return $self;
}

sub event_write {
    my $self = shift;
    $self->watch_write(0) if $self->write(undef);
}

# DJabberd::Connection::SimpleIn
sub event_read {
    my DJabberd::Connection::SimpleIn $self = shift;

    my $bref = $self->read(1024);
    return $self->close unless defined $bref;
    $self->{read_buf} .= $$bref;

    if ($self->{read_buf} =~ s/^(.+?)\r?\n//) {
        my $line = $1;
        $self->process_line( $line );
    }
}

sub process_line {
    my DJabberd::Connection::SimpleIn $self = shift;
    my $line = shift;

    if ($line =~ /^(\d+)\s+(.*)/) {
        my ($to, $msg) = ($1, $2);
        warn "message to: $to, msg: $msg, server = $self->{vhost}\n";
        return;
    }

    return $self->close;
}

# DJabberd::Connection::SimpleIn
sub event_err { my $self = shift; $self->close; }
sub event_hup { my $self = shift; $self->close; }




1;
