
package DJabberd::Component::MUC::Room;

use base qw(DJabberd::Component::Node);
use DJabberd::Util qw(exml);
use strict;
use warnings;
use DJabberd::Log;
use DJabberd::Component::MUC::Participant;

our $logger = DJabberd::Log->get_logger();

sub finalize {
    my ($self) = @_;
    $self->{component_muc_room_participants} = {};
    $self->SUPER::finalize;
}

sub handle_presence {
    my ($self, $vhost, $stanza) = @_;
    
    my $to = $stanza->to_jid;
    my $from = $stanza->from_jid;
    
    unless ($to->resource) {
        $stanza->make_error_response('400', 'modify', 'jid-malformed')->deliver($vhost);
        return;
    }
    
    my $nickname = $to->resource;
    return $stanza->make_error_response('403', 'cancel', 'forbidden')->deliver($vhost) unless $self->jid_can_join($from, $nickname);
    
    $logger->debug("Adding new participant ".$from->as_string." as $nickname");
    
    my $participant = new DJabberd::Component::MUC::Participant(
        component => $self->component,
        nodename => $self->nodename,
        room => $self,
        nickname => $nickname,
        jid => $from,
    );
    
    $self->add_participant($participant);
    
    return;
}

sub participants {
    my ($self) = @_;
    
    return $self->{component_muc_room_participants};
}

sub add_participant {
    my ($self, $participant) = @_;
    
    $logger->logdie("Participant room mismatch (".$participant->room." != $self)") unless $participant->room == $self;
    
    my $oldcount = scalar(keys(%{$self->{component_muc_room_participants}}));
    $self->{component_muc_room_participants}{$participant->nickname} = $participant;
    
    # TODO: Send presence to all current participants
    #     and *of* all current participants.
    
    $participant->send_presence($participant->real_jid);

}

# FIXME: This needs to be able to distingish somehow the cases of
#   "membership required", "need password" or just "you aren't allowed"
sub jid_can_join {
    my ($self, $jid, $nickname) = @_;
    
    return 1;
}

sub features {
    my ($self) = @_;
    
    return [
        "http://jabber.org/protocol/muc",
        @{$self->SUPER::features}
    ];
}

sub send_stanza {
    my ($self, $stanza) = @_;
    $self->component->send_stanza($stanza);
}

1;
