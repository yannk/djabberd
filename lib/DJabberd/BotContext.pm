package DJabberd::BotContext;
use strict;
use fields (
            # expire times,
            # start time,
            # history of chat...
            # etc, etc
            'vhost',
            'method',
            'fromjid',
            'myjid',
            );
use warnings;

sub new {
    my ($class, $vhost, $method, $fromjid, $myjid) = @_;
    my $self = fields::new($class);
    $self->{vhost}   = $vhost;
    $self->{method}  = $method;
    $self->{fromjid} = $fromjid;
    $self->{myjid}   = $myjid;
    return $self;
}

sub reply {
    my ($self, $text, $html) = @_;
    return unless $text || $html;

    my $body = "";
    if ($text) {
        $body .= "<body>". DJabberd::Util::exml($text) . "</body>";
    }
    if ($html) {
        $body .= qr{<html xmlns='http://jabber.org/protocol/xhtml-im'><body xmlns='http://www.w3.org/1999/xhtml'>$html</body></html>};
    }

    my $reply = DJabberd::Message->new('jabber:client', 'message', {
        '{}type' => 'chat',
        '{}to'   => $self->{fromjid}->as_string,
        '{}from' => $self->{myjid}->as_string,
    }, []);
    $reply->set_raw($body);
    $reply->deliver($self->{vhost});
}

1;
