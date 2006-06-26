package DJabberd::Connection::ServerIn;
use strict;
use base 'DJabberd::Connection';
use fields
    ('announced_dialback',
     'verified_remote_domain',  # once we know it
     );

use DJabberd::Stanza::DialbackResult;

sub set_vhost {
    my ($self, $vhost) = @_;
    return 0 unless $vhost->{s2s};
    return $self->SUPER::set_vhost($vhost);
}

sub peer_domain {
    my $self = shift;
    return $self->{verified_remote_domain};
}

sub on_stream_start {
    my ($self, $ss) = @_;
    $self->{in_stream} = 1;
    return $self->close unless $ss->xmlns eq $self->namespace; # FIXME: should be stream error

    if ($ss->announced_dialback) {
        $self->{announced_dialback} = 1;
        $self->start_stream_back($ss,
                                 extra_attr => "xmlns:db='jabber:server:dialback'",
                                 namespace  => 'jabber:server');
    } else {
        $self->start_stream_back($ss,
                                 namespace  => 'jabber:server');
    }
}

sub on_stanza_received {
    my ($self, $node) = @_;

    if ($self->xmllog->is_info) {
        $self->log_incoming_data($node);
    }

    my %class = (
                   "{jabber:server:dialback}result" => "DJabberd::Stanza::DialbackResult",
                   "{jabber:server:dialback}verify" => "DJabberd::Stanza::DialbackVerify",
                   "{jabber:server}iq"       => 'DJabberd::IQ',
                   "{jabber:server}message"  => 'DJabberd::Message',
                   "{jabber:server}presence" => 'DJabberd::Presence',
                   "{http://etherx.jabber.org/streams}features" => 'DJabberd::Stanza::StreamFeatures',
                   );

    my $class = $class{$node->element} or
        return $self->stream_error("unsupported-stanza-type", $node->element);

    # same variable as $node, but down(specific)-classed.
    my $stanza = $class->downbless($node, $self);

    $self->run_hook_chain(phase => "filter_incoming_server",
                          deprecated => 1,  # yes, we know this is deprecated, but we don't have a vhost always during dialback.
                          args  => [ $stanza ],
                          methods => {
                              reject => sub { },  # just stops the chain
                          },
                          fallback => sub {
                              $self->filter_incoming_server_builtin($stanza);
                          });
}

sub filter_incoming_server_builtin {
    my ($self, $stanza) = @_;

    unless ($stanza->acceptable_from_server($self)) {
        # FIXME: who knows.  send something else.
        $self->log->error("Stansa of type '$stanza' not acceptable");
        $self->stream_error;
        return 0;
    }

    $self->run_hook_chain(phase => "switch_incoming_server",
                          deprecated => 1,  # yes, we know this is deprecated, but we don't have a vhost always during dialback.
                          args  => [ $stanza ],
                          methods => {
                              process => sub { $stanza->process($self) },
                              deliver => sub { $stanza->deliver($self) },
                          },
                          fallback => sub {
                              $stanza->on_recv_from_server($self);
                          });
}

sub is_server { 1 }

sub namespace {
    return "jabber:server";
}

sub dialback_verify_valid {
    my $self = shift;
    my %opts = @_;

    # according to page 45 of the spec we have to send the ID back
    my $res = qq{<db:verify from='$opts{recv_server}' to='$opts{orig_server}' id='$opts{id}' type='valid'/>};

    $self->log->debug("Dialback verify valid for connection $self->{id}.  from=$opts{recv_server}, to=$opts{orig_server}: $res\n");
    $self->write($res);
}

sub dialback_verify_invalid {
    my ($self, $reason) = @_;
    warn "Dialback verify invalid for $self, reason: $reason\n";
    $self->close_stream;
}

sub dialback_result_valid {
    my $self = shift;
    my %opts = @_;

    my $res = qq{<db:result from='$opts{recv_server}' to='$opts{orig_server}' type='valid'/>};
    $self->{verified_remote_domain} = $opts{orig_server};

    $self->log->debug("Dialback result valid for connection $self->{id}.  from=$opts{recv_server}, to=$opts{orig_server}: $res\n");
    $self->write($res);
}

sub dialback_result_invalid {
    my ($self, $reason) = @_;
    $self->log->warn("Dialback result invalid for $self, reason: $reason");
    $self->close_stream;
}


1;
