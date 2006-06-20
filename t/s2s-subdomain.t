#!/usr/bin/perl
use strict;
use Test::More tests => 3;
use lib 't/lib';
BEGIN { $ENV{LOGLEVEL} ||= "OFF" };
require 'djabberd-test.pl';

$SIG{'ALRM'} = sub { die "alarm reached" };

use_ok('DJabberd::Plugin::SubdomainAlias');

@Test::DJabberd::Server::SUBDOMAINS = qw();
@Test::DJabberd::Server::SUBDOMAINS = qw(subdomain);

undef $Test::DJabberd::Server::PLUGIN_CB;
$Test::DJabberd::Server::PLUGIN_CB = sub {
    my $self = shift;
    my $plugins = $self->standard_plugins();
    push @$plugins, DJabberd::Plugin::SubdomainAlias->new(subdomain => 'subdomain');
    push @$plugins, DJabberd::Delivery::Local->new, DJabberd::Delivery::S2S->new; # these don't get pushed if someone else touches deliver
    return $plugins;
};

two_parties_s2s(sub {
    my ($pa, $pb) = @_;
    #very much fake subdomain issue
    $pa->login;
    $pb->login;
    $pa->send_xml("<presence/>");
    $pb->send_xml("<presence/>");

    # PA to PB
    $pa->server->{hostname} = 'subdomain.' . $pa->server->hostname;

    $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
    like($pb->recv_xml, qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb got pa's message");

    # PB to PA
    $pb->send_xml("<message type='chat' to='$pa'>Hello back!</message>");
    like($pa->recv_xml(3.0), qr/Hello back/, "pa got pb's message");
});


