package DJabberd::IQ;
use strict;
use base qw(DJabberd::Stanza);
use fields (
            'connection',   # Store the connection the IQ came in on so we can respond.  may be undef, as it's a weakref.
            );

# DO NOT OVERRIDE THIS
sub process {
    my DJabberd::IQ $self = shift;
    my $conn = shift;

    $self->{connection} = $conn;
    Scalar::Util::weaken($self->{connection});

    my $handler = {
        'get-{jabber:iq:roster}query' => \&process_iq_getroster,
        'get-{jabber:iq:auth}query' => \&process_iq_getauth,
        'set-{jabber:iq:auth}query' => \&process_iq_setauth,
    };

    $conn->run_hook_chain(phase    => "c2s-iq",
                          args     => [ $self ],
                          fallback => sub {
                              my $sig = $self->signature;
                              my $meth = $handler->{$sig};
                              unless ($meth) {
                                  warn "Unknown IQ packet: $sig";
                                  return;
                              }
                              $meth->($conn, $self);
                          });
}

sub signature {
    my $iq = shift;
    my $fc = $iq->first_child;
    # FIXME: should signature ever get called on a bogus IQ packet?
    return $iq->type . "-" . ($fc ? $fc->element : "(BOGUS)");
}

sub send_result_nodes {
}

# caller must send well-formed XML (but we do the wrapping element)
sub send_result_raw {
    my DJabberd::IQ $self = shift;
    my $raw = shift;

    my $conn = $self->{connection}
        or return;

    my $id = $self->id;
    my $to = $conn->bound_jid->as_string;
    my $xml = qq{<iq to='$to' type='result' id='$id'>$raw</iq>};
    warn "About to send IQ reply: $xml\n";
    $conn->write(\$xml);
}

sub process_iq_getroster {
    my ($conn, $iq) = @_;
    $conn->set_requested_roster(1);

    my $send_roster = sub {
        my $roster = shift;
        # TODO: walk roster and add presence subscriptions for everybody
        $iq->send_result_raw($roster->as_xml);
    };

    $conn->run_hook_chain(phase => "RosterGet",
                          methods => {
                              set_roster => sub {
                                  my ($self, $roster) = @_;
                                  $send_roster->($roster);
                              },
                          },
                          fallback => sub {
                              $send_roster->(DJabberd::Roster->new()),
                          });
    return 1;
}

sub process_iq_getauth {
    my ($conn, $iq) = @_;
    # <iq type='get' id='gaimf46fbc1e'><query xmlns='jabber:iq:auth'><username>brad</username></query></iq>

    my $child = $iq->query->first_element
        or return;

    return 0 unless $child->element eq "{jabber:iq:auth}username";

    my $username = $child->first_child;
    die "Element in username field?" if ref $username;

    my $id = $iq->id;

    $conn->write("<iq id='$id' type='result'><query xmlns='jabber:iq:auth'><username>$username</username><digest/><resource/></query></iq>");

    return 1;
}

sub process_iq_setauth {
    my ($conn, $iq) = @_;
    # <iq type='set' id='gaimbb822399'><query xmlns='jabber:iq:auth'><username>brad</username><resource>work</resource><digest>ab2459dc7506d56247e2dc684f6e3b0a5951a808</digest></query></iq>
    my $id = $iq->id;

    my $query = $iq->query
        or die;
    my @children = $query->children;

    my $get = sub {
        my $lname = shift;
        foreach my $c (@children) {
            next unless ref $c && $c->element eq "{jabber:iq:auth}$lname";
            my $text = $c->first_child;
            return undef if ref $text;
            return $text;
        }
        return undef;
    };

    my $username = $get->("username");
    my $resource = $get->("resource");
    my $digest   = $get->("digest");

    return unless $username =~ /^\w+$/;

    my $accept = sub {
        $conn->{authed}   = 1;
        $conn->{username} = $username;
        $conn->{resource} = $resource;

        # register
        my $sname = $conn->server->name;
        my $jid = DJabberd::JID->new("$username\@$sname/$resource");

        $conn->server->register_jid($jid, $conn);
        $conn->set_bound_jid($jid);

        # FIXME: escape, or make $iq->send_good_result, or something
        $conn->write(qq{<iq id='$id' type='result' />});
        return;
    };

    my $reject = sub {
        warn " BAD LOGIN!\n";
        # FIXME: FAIL
        return 1;
    };

    $conn->run_hook_chain(phase => "Auth",
                          args  => [ { username => $username, resource => $resource, digest => $digest } ],
                          methods => {
                              accept => $accept,
                              reject => $reject,
                          },
                          fallback => $reject);

    return 1;  # signal that we've handled it
}


sub id {
    return $_[0]->attr("{jabber:client}id");
}

sub type {
    return $_[0]->attr("{jabber:client}type");
}

sub query {
    my $self = shift;
    my $child = $self->first_element
        or return;
    my $ele = $child->element
        or return;
    return undef unless $child->element =~ /\}query$/;
    return $child;
}

1;
