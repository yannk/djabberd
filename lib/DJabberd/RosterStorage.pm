package DJabberd::RosterStorage;
# abstract base class
use strict;
use warnings;
use base 'DJabberd::Plugin';
use DJabberd::Roster;
use DJabberd::RosterItem;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

# don't override, or at least call SUPER to this if you do.
sub register {
    my ($self, $vhost) = @_;
    $vhost->register_hook("RosterGet", sub {
        my ($conn, $cb) = @_;
        my $jid = $conn->bound_jid;
        $self->get_roster($cb, $jid);
    });
    $vhost->register_hook("RosterAddUpdateItem", sub {
        my ($conn, $cb, $ritem) = @_;
        my $jid = $conn->bound_jid;
        $self->addupdate_roster_item($cb, $jid, $ritem);
    });
    $vhost->register_hook("RosterRemoveItem", sub {
        my ($conn, $cb, $ritem) = @_;
        my $jid = $conn->bound_jid;
        $self->delete_roster_item($cb, $jid, $ritem);
    });
    $vhost->register_hook("RosterSubscribe", sub {
        my ($conn, $cb, $target_jid) = @_;
        my $jid = $conn->bound_jid;

        # create a 'pass-through' callback, as we may go with
        # stricter typing on callbacks in the future, so I didn't
        # want to pass in our $cb to this unchanged.
        my $cb2 = DJabberd::Callback->new(
                                          done  => sub { $cb->done },
                                          error => sub { $cb->error($_[1]) },
                                          );

        $self->note_pending_out($cb2, $jid, $target_jid);
    });
    $vhost->register_hook("RosterLoadItem", sub {
        my ($conn, $cb, $user_jid, $contact_jid) = @_;
        # cb can 'set($data|undef)' and 'error($reason)'
        $self->load_roster_item($user_jid, $contact_jid, $cb);
    });

}

# override this.
sub get_roster {
    my ($self, $cb, $jid) = @_;
    $cb->declined;
}

# override this.
sub addupdate_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    $cb->declined;
}

# override this.  unlike addupdate, you should respect the subscription level
sub set_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    warn "SET ROSTER ITEM FAILED\n";
    $cb->error;
}

# override this.
sub delete_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    $cb->declined;
}

# override this.
sub load_roster_item {
    my ($self, $jid, $target_jid, $cb) = @_;
    $cb->error("load_roster_item not implemented");
}


# optionally override this, if you want to do this more efficiently.
# by default it loads the roster item, updates it (creating it if it
# doesn't exist), and sets it back.
sub note_pending_out {
    my ($self, $cb, $jid, $target_jid) = @_;

    my %set_meth = (
                    error => sub { $cb->error($_[1]) },
                    done  => sub { $cb->done  },
                    );

    my %load_meth = (
                     error => sub { $cb->error($_[1]) },
                     set => sub {
                         my ($cb, $ritem) = @_;
                         $ritem ||= DJabberd::RosterItem->new($target_jid);
                         $ritem->subscription->set_pending_out(1);
                         $self->set_roster_item(DJabberd::Callback->new(%set_meth),
                                                $jid, $ritem);
                         # TODO: roster push
                         # $vhost->roster_push($ritem);
                     }
                     );

    $self->load_roster_item($jid, $target_jid, DJabberd::Callback->new(%load_meth));
}

1;
