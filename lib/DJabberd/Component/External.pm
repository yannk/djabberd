
package DJabberd::Component::External;

use base 'DJabberd::Component';
use strict;
use DJabberd::Log;
use DJabberd::Util qw(exml);
use DJabberd::Component::External::Connection;
use IO::Socket::UNIX;
use IO::Socket::INET;
use Socket qw(IPPROTO_TCP TCP_NODELAY SOL_SOCKET SOCK_STREAM);

our $logger = DJabberd::Log->get_logger();

sub set_config_listenport {
    my ($self, $port) = @_;
    
    $self->{listenport} = $port;
}

sub set_config_secret {
    my ($self, $secret) = @_;
    
    $self->{secret} = $secret;
}

sub set_config_listenaddr {
    my ($self, $addr) = @_;
    
    $self->{listenaddr} = $addr;
}

sub finalize {
    my ($self) = @_;
    
    # If the address starts with a slash, it's a unix domain socket
    if ($self->{listenaddr} =~ m!^/!) {
        $logger->logdie("Can't specify ListenPort for external component on a UNIX domain socket") if $self->{listenport};
    }
    else {
        $logger->logdie("No ListenPort specified for external component") unless $self->{listenport};
        $self->{listenaddr} ||= "127.0.0.1";
    }

    $logger->logdie("No Secret specified for external component") unless $self->{secret};
    
    $self->SUPER::finalize;
}

sub register {
    my ($self, $vhost) = @_;
    
    $self->SUPER::register($vhost);

    $self->_start_listener();

}

sub secret {
    return $_[0]->{secret};
}

sub handle_component_disconnect {
    my ($self, $connection) = @_;
    
    if ($connection != $self->{connection}) {
        $logger->warn("Got disconnection for the wrong connection. Something's screwy.");
        return 0;
    }

    $logger->info("Component ".$self->domain." disconnected.");

    $self->{connection} = undef;
    $self->_start_listener();  # Re-open the listen port so the component can re-connect.
    return 1;
}

# Stanza from the server to the component
sub handle_stanza {
    my ($self, $vhost, $stanza) = @_;
    
    # If the component is not connected, return Service Unavailable
    unless ($self->{connection} && $self->{connection}->is_authenticated) {
        $stanza->make_error_response('503', 'cancel', 'service-unavailable')->deliver($vhost);
        return;
    }
    
    $self->{connection}->send_stanza($stanza);
}

# Stanza from the component to the server
sub handle_component_stanza {
    my ($self, $stanza) = @_;
    
    if ($stanza->from_jid && $stanza->from_jid->domain eq $self->domain) {
        $stanza->deliver($self->vhost);
    }
    else {
        $logger->warn("External component ".$self->domain." used bogus from address. Discarding stanza.");
    }
}

sub _start_listener {
    my ($self) = @_;
    my $vhost = $self->vhost;
    
    my $bindaddr = $self->{listenaddr};

    # FIXME: Maybe shouldn't duplicate all of this code out of DJabberd.pm.
    
    my $server;
    my $not_tcp = 0;
    if ($bindaddr =~ m!^/!) {
        $not_tcp = 1;
        $server = IO::Socket::UNIX->new(
            Type   => SOCK_STREAM,
            Local  => $bindaddr,
            Listen => 10
        );
        $logger->logdie("Error creating UNIX domain socket $bindaddr: $@") unless $server;
        $logger->info("Started listener for component ".$self->domain." on UNIX domain socket $bindaddr");
    } else {
        my $localaddr = $bindaddr.":".$self->{listenport};

        $server = IO::Socket::INET->new(
            LocalAddr => $localaddr,
            Type      => SOCK_STREAM,
            Proto     => IPPROTO_TCP,
            Blocking  => 0,
            Reuse     => 1,
            Listen    => 10
        );
        $logger->logdie("Error creating listen socket for <$localaddr>: $@") unless $server;
        $logger->info("Started listener for component ".$self->domain." on TCP socket <$localaddr>");
    }

    # Brad thinks this is necessary under Perl 5.6, and who am I to argue?
    IO::Handle::blocking($server, 0);
    
    $self->{listener} = $server;

    my $accept_handler = sub {
        my $csock = $server->accept;
        return unless $csock;
        
        $logger->debug("Accepting connection from component ".$self->domain);

        IO::Handle::blocking($csock, 0);
        unless ($not_tcp) {
            setsockopt($csock, IPPROTO_TCP, TCP_NODELAY, pack("l", 1)) or $logger->logdie("Couldn't set TCP_NODELAY");
        }

        my $connection = DJabberd::Component::External::Connection->new($csock, $vhost->server, $self);
        $connection->watch_read(1);
        $self->{connection} = $connection;

        # We only need to support one connection at a time, so
        # shut down the listen socket now to save resources.
        $self->_stop_listener($self);
    };
    
    Danga::Socket->AddOtherFds(fileno($server) => $accept_handler);
}

sub _stop_listener {
    my ($self) = @_;
    
    return unless $self->{listener};
    $logger->info("Shutting down listener for component ".$self->domain);
    $self->{listener} = undef if $self->{listener}->close();
    return $self->{listener} == undef;
}

1;
