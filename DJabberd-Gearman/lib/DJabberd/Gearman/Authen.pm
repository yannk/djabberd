
=head1 NAME

DJabberd::Gearman::Authen - Authenticate with a Gearman worker

=head1 DESCRIPTION

This is the lowest-level plugin provided by the L<DJabberd::Gearman>
suite, and allows a Gearman worker to receive all incoming stanzas
for a VHost. (Or, at least, those that weren't handled by an
earlier Delivery plugin.)

=head1 SYNOPSIS

    <VHost example.com>
    
        <Plugin DJabberd::Delivery::Gearman>
            ReceiveFunc receive_xmpp_stanza
            TransmitFunc transmit_xmpp_stanza
        </Plugin>
    
    </VHost>

=cut

package DJabberd::Gearman::Authen;

use DJabberd::Gearman;
use base qw(DJabberd::Authen DJabberd::Gearman::BasePlugin);

__PACKAGE__->make_configurable_funcs(qw(get_password check_digest check_cleartext check_jid register_jid unregister_jid));

sub finalize {
    my ($self) = @_;

    die "A CheckJID function is required" unless $self->check_jid_func;
    die "A CheckCleartext function is required" unless $self->check_cleartext_func;

}

sub can_register_jids {
    my ($self) = @_;
    return $self->register_jid_func ? 1 : 0;
}

sub can_unregister_jids {
    my ($self) = @_;
    return $self->unregister_jid_func ? 1 : 0;
}

sub can_retrieve_cleartext {
    my ($self) = @_;
    return $self->get_password_func ? 1 : 0;
}

sub can_check_digest {
    my ($self) = @_;
    return $self->check_digest_func ? 1 : 0;
}

sub check_jid {
    my ($self, $cb, %args) = @_;

    my $username = $args{username};

    my $gearman_args = {
        username => $username,
    };

    $self->call_gearman_func($func, $gearman_args, {
        complete => sub {
            my ($dummy, $result) = @_;

            my $callback = $result{'result'};
            my $value = $result{'value'};

            $cb->$callback(defined $value ? ($value) : ());
        },
        fail => sub {
            $cb->error('Authentication service failed to respond');
        },
    });
}

sub check_cleartext {
    my ($self, $cb, %args) = @_;

    print STDERR Data::Dumper::Dumper($args);

    my $gearman_args = {
        username => $args{username},
        password => $args{password},
    };

    $self->call_gearman_func($func, $gearman_args, {
        complete => sub {
            my ($dummy, $result) = @_;

            my $callback = $result{'result'};
            my $value = $result{'value'};

            $cb->$callback(defined $value ? ($value) : ());
        },
        fail => sub {
            $cb->error('Authentication service failed to respond');
        },
    });
}


1;

