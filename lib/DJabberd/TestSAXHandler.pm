package DJabberd::TestSAXHandler;
use strict;
use base qw(XML::SAX::Base);
use DJabberd::SAXHandler;
use DJabberd::XMLElement;
use DJabberd::StreamStart;

sub new {
    my ($class, $listref) = @_;
    my $self = $class->SUPER::new;
    $self->{"listref"} = $listref;
    $self->{"capture_depth"} = 0;  # on transition from 1 to 0, stop capturing
    $self->{"on_end_capture"} = undef;  # undef or $subref->($doc)
    $self->{"events"} = [];  # capturing events
    return $self;
}

use constant EVT_START_ELEMENT => 1;
use constant EVT_END_ELEMENT   => 2;
use constant EVT_CHARS         => 3;

sub start_element {
    my $self = shift;
    my $data = shift;

    if ($self->{capture_depth}) {
        push @{$self->{events}}, [EVT_START_ELEMENT, $data];
        $self->{capture_depth}++;
        return;
    }

    if ($data->{LocalName} eq "djab-noop") {
        return;
    }

    # {=xml-stream}
    if ($data->{NamespaceURI} eq "http://etherx.jabber.org/streams" &&
        $data->{LocalName} eq "stream") {

        my $ss = DJabberd::StreamStart->new($data);
        push @{$self->{listref}}, $ss;
        return;
    }

    my $start_capturing = sub {
        my $cb = shift;

        $self->{"events"} = [];  # capturing events
        $self->{capture_depth} = 1;

        # capture via saving SAX events
        push @{$self->{events}}, [EVT_START_ELEMENT, $data];

        $self->{on_end_capture} = $cb;
        return 1;
    };

    return $start_capturing->(sub {
        my ($doc, $events) = @_;
        my $nodes = _nodes_from_events($events);
        # {=xml-stanza}
        push @{$self->{listref}}, $nodes->[0];
    });

}

sub characters {
    my ($self, $data) = @_;

    if ($self->{capture_depth}) {
        push @{$self->{events}}, [EVT_CHARS, $data];
    }
}

sub end_element {
    my ($self, $data) = @_;

    if ($data->{NamespaceURI} eq "http://etherx.jabber.org/streams" &&
        $data->{LocalName} eq "stream") {
        push @{$self->{listref}}, "end-stream";
        return;
    }

    if ($self->{capture_depth}) {
        push @{$self->{events}}, [EVT_END_ELEMENT, $data];
        $self->{capture_depth}--;
        return if $self->{capture_depth};
        my $doc = undef;
        if (my $cb = $self->{on_end_capture}) {
            $cb->($doc, $self->{events});
        }
        return;
    }
}

*_nodes_from_events = \&DJabberd::SAXHandler::_nodes_from_events;

1;
