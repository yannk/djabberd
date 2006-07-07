
package DJabberd::Bot::Admin;
# abstract base class
use strict;
use warnings;
use base 'DJabberd::Bot';
use Chatbot::Eliza;


our $logger = DJabberd::Log->get_logger();

sub finalize {
    my ($self) = @_;
    $self->{nodename} ||= "admin";
    $self->SUPER::finalize();
}

sub set_config_users {
    my ($self, $users) = @_;
    my @users = split /\s+/, $users;
    $self->{users}->{$_}++ foreach @users;
}

sub handle_message {
    my ($self, $stanza) = @_;


    my $body;
    foreach my $child ($stanza->children_elements) {
        if($child->{element} eq 'body') {
            $body = $child;
            last;
        }
    }
    $logger->logdie("Can't find a body in incoming message") unless $body;
    my $command = $body->first_child;

    return if ($self->{users} && !$self->{users}->{$stanza->from_jid->node});

    my $can = DJabberd::Connection::Admin->can("CMD_$command");
    $self->{buffer} = "";

    if ($can) {
        $can->($self);
    } else {
        $self->{buffer} = "Unknown command '$command'";
    }




    my $reply = DJabberd::Message->new('jabber:client', 'message', { '{}type' => 'chat', '{}to' => $stanza->from, '{}from' => $self->{jid} }, []);
    $reply->set_raw(qq{<body>$self->{buffer}</body>});
    undef $self->{buffer};
    $reply->deliver($self->{vhost});
}


sub write {
    my ($self, $data) = @_;
    $self->{buffer} .= $data . "\n";
}

sub end {

}

1;


