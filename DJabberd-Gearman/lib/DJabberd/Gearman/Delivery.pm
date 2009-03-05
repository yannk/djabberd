
=head1 NAME

DJabberd::Gearman::Delivery - Delivers incoming stanzas to Gearman workers

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

package DJabberd::Gearman::Delivery;

use DJabberd::Gearman;
use base qw(DJabberd::Gearman::BasePlugin);
use DJabberd::Log;
my $logger = DJabberd::Log->get_logger();

__PACKAGE__->make_configurable_funcs(qw(receive transmit));

sub register {
    my ($self, $vhost) = @_;

    $self->configure_defaults($vhost);

    my $client = $self->gearman_client;

    if ($self->receive_func) {
        $vhost->register_hook('deliver', sub {
            $self->handle_received_stanza(@_);
        });
    }
}

sub handle_received_stanza {
    my ($self, $vhost, $cb, $stanza) = @_;

    my $func = $self->receive_func;
    my $stanza_xml = $stanza->as_xml;

    $logger->debug("Sending stanza to $func function");

    $self->call_gearman_func($func, $stanza_xml, {
        complete => sub {
            my ($dummy, $result) = @_;

            my $callback = $result{'result'};
            my $value = $result{'value'};

            $cb->$callback(defined $value ? ($value) : ());
        },
        fail => sub {
            $cb->error('Delivery service failed to respond');
        },
    });
}

1;

=head1 CONFIGURATION OPTIONS

The following configuration options are supported for this plugin.

=head2 ReceiveFunc

This gives the name of the Gearman function that will
receive all incoming stanzas.

If this option is not set, the plugin will decline
all incoming stanzas, allowing them to pass through
to any other delivery plugins defined in this VHost.

=head2 TransmitFunc

This gives the name of the Gearman function that this
plugin will expose (as a Gearman worker) to allow
callers to transmit XMPP stanzas into this VHost.

Note that for this to be useful you'll need to have
some other delivery plugin available in the VHost
or else the stanza will just get delivered back into
your defined ReceiveFunc.

If this option is not set, the plugin will not expose
any such function and the transmit functionality will
not be available.

=head1 FUNCTIONS

This plugin uses Gearman functions with the following
conventions:

=head2 receive

Named as defined by the ReceiveFunc configuration option,
this Gearman function will be invoked with its argument
set to a string of XML representing the incoming Stanza.

The function must return a JSON-encoded object with
a single property called "result". This property
can have the value "delivered" to indicate successful
delivery, "declined" to indicate that the worker doesn't
wish to handle this particular stanza, or "error"
if there was a delivery error.

In the case where the result is "error", the function may
include an additional "value" property whose value is
a string describing the error.

If the call to this function fails for some reason,
the plugin will signal error. For this reason, it's
generally best to put this delivery plugin last in
your delivery chain and not rely on the facility
to decline stanzas in the worker.

=head2 transmit

Named as defined by the TransmitFunc configuration option,
this Gearman function will be handled by DJabberd itself,
acting as a Gearman worker.

It expects as its argument a string of XML representing
the Stanza to be delivered.

Currently this function will always return a JSON-encoded
object containing a single property called "result" whose
value is "delivered", since there is no way to determine
whether the stanza was actually delivered at this point.
However, if delivery I<does> fail, in most cases a
delivery failure stanza will be generated and delivered
to the JID identified as the sender of the original
stanza, allowing you to handle errors in the receive function
if required.




