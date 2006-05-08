#!/usr/bin/perl

use strict;
use lib 'lib';
use Test::More 'no_plan';
use DJabberd;
use DJabberd::Authen::AllowedUsers;
use DJabberd::Authen::StaticPassword;
use DJabberd::TestSAXHandler;
use DJabberd::RosterStorage::SQLite;
use DJabberd::RosterStorage::Dummy;
use DJabberd::RosterStorage::LiveJournal;

use FindBin qw($Bin);

my $roster = "$Bin/test-roster.dat";
unlink($roster);

my $vhost = DJabberd::VHost->new(
                                 server_name => 'jabber.example.com',
                                 s2s         => 0,
                                 plugins   => [
                                               DJabberd::Authen::AllowedUsers->new(policy => "deny",
                                                                                   allowed => [qw(tester)]),
                                               DJabberd::Authen::StaticPassword->new(password => "password"),
                                               DJabberd::PresenceChecker::Local->new(),
                                               DJabberd::Delivery::Local->new(),
                                               DJabberd::Delivery::S2S->new(),
                                               DJabberd::RosterStorage::SQLite->new($roster),
                                               ],
                                 );

my $server = DJabberd->new;
$server->add_vhost($vhost);

my $childpid = fork;
if (!$childpid) {
    $0 = "[djabberd]";
    $server->run;
    exit 0;
}

$SIG{INT} = sub { kill 9, $childpid; exit 0; };

use IO::Socket::INET;
my $conn;

foreach (1..3) {
    print "Connecting...\n";
    $conn = IO::Socket::INET->new(PeerAddr => "127.0.0.1:5222", Timeout => 1);
    last if $conn;
    sleep 1;
}

my $err = sub {
    kill 9, $childpid;
    die $_[0];
};

$err->("Can't connect to server") unless $conn;

my @events;
my ($handler, $p);
my $new_parser = sub {
    @events = ();
    $handler = DJabberd::TestSAXHandler->new(\@events);
    $p = XML::SAX::Expat::Incremental->new( Handler => $handler );
};
$new_parser->();

my $get_event = sub {
    while (! @events) {
        my $byte;
        my $rv = sysread($conn, $byte, 1);
        $p->parse_more($byte);
    }

    return shift @events;
};

my $get_stream_start = sub {
    my $ev = $get_event->();
    die unless $ev && $ev->isa("DJabberd::StreamStart");
    return $ev;
};


$conn->close;
for (1..2500) {
    print "connect $_/500\n";
    $conn = IO::Socket::INET->new(PeerAddr => "127.0.0.1:5222", Timeout => 1);
    $new_parser->();
    print $conn qq{
        <stream:stream
          xmlns:stream='http://etherx.jabber.org/streams' to='jabber.example.com'
          xmlns='jabber:client'>
    };

    my $ss = $get_stream_start->();
    print "got a streamstart: $ss\n";

    ok($ss, "got a stream back");
    ok($ss->id, "got a stream id back");

    $conn->close;
}

print "Sleeping for 50....\n";
sleep 50;
