#!/usr/bin/perl
#
# DJabberd Web Admin interface
# using Perlbal as its HTTP server
#
# This is really just a proof-of-concept at the moment, and doesn't do anything particularly useful
#
# Copyright 2007 Martin Atkins <mart@degeneration.co.uk>
# This package and any part thereof may be freely distributed, modified, and used in other products.
#

package DJabberd::WebAdmin;

use strict;
use Perlbal;
use Perlbal::Plugin::Cgilike;

use base qw(DJabberd::Plugin);

our $logger = DJabberd::Log->get_logger();

my $server = undef;

sub finalize {
    my ($self) = @_;
    
    # Configure a new service in Perlbal
    my $ctx = Perlbal::CommandContext->new;
    my $writer = sub {
        $logger->info($_[0]);
    };
    
    my $c = sub {
        my ($line) = @_;
        my $success = Perlbal::run_manage_command($line, $writer, $ctx);
        
        unless ($success) {
            $logger->logdie("Error configuring Perlbal service when running ".$line);
        }
    };
    
    $c->("LOAD cgilike");
    $c->("CREATE SERVICE djabberdadmin");
    $c->("SET listen = 127.0.0.1:8045");
    $c->("SET role = web_server");
    $c->("SET plugins = cgilike");
    $c->("PERLHANDLER = DJabberd::WebAdmin::handle_web_request");
    $c->("ENABLE djabberdadmin");
    
    # Now for a bit of yuck.
    # Perlbal's not really designed to run in someone else's event loop,
    # so we have to fake it out a bit and do some of the stuff it would
    # otherwise have done in its main run() function.
    # TODO: Make a nicer API for embedding Perlbal
    
    $Perlbal::run_started = 1;
    Perlbal::run_global_hook("pre_event_loop");
    
    # Hopefully by this point Perlbal's screwed around enough with Danga::Socket
    # that it'll just work!
    
    return 1;
}

sub register {
    my ($self, $vhost) = @_;
    
    unless ($server) {
        $server = $vhost->server;
    }
    else {
        $logger->logdie("Can't load DJabberd::WebAdmin into more than one VHost");
    }

}

sub handle_web_request {
    my ($r) = @_;

    # All valid paths end with a slash
    # (because it makes it easier to construct relative links)
    my $path = $r->path;
    if (substr($path, -1) ne '/') {
        $r->response_status_code(302);
        $r->response_header('Location' => $path.'/');
        print "...";
        return Perlbal::Plugin::Cgilike::HANDLED;
    }

    my $page = determine_page_for_request($r);
    
    if ($page) {
        output_page($r, $page);
        return Perlbal::Plugin::Cgilike::HANDLED;
    }
    else {
        return 404;
    }

    return Perlbal::Plugin::Cgilike::HANDLED;
}

sub determine_page_for_request {
    my ($r) = @_;
    
    my @pathbits = $r->path_segments;
    pop @pathbits; # Zzap mpty string on the end because of our trailing slash
    
    if (scalar(@pathbits) == 0) {
        return DJabberd::WebAdmin::Page::Home->new();
    }
    
    my $vhost_name = shift @pathbits;
    
    my $vhost = $server->lookup_vhost($vhost_name);
    
    return undef unless $vhost;
    
    if (scalar(@pathbits) == 0) {
        return DJabberd::WebAdmin::Page::VHostSummary->new($vhost);
    }
    
    return undef;
}

# Just a debugging function
sub dump_object_html {
    print "<pre>".DJabberd::Util::exml(Data::Dumper::Dumper(@_))."</pre>";
}

*ehtml = \&DJabberd::Util::exml;

sub output_page {
    my ($r, $page) = @_;
    
    my $title = $page->title;
    print q{<html><head><title>}.($title ? ehtml($title)." - " : '').q{DJabberd Web Admin</title><body>};
    
    print "<h1>".ehtml($title)."</h1>";

    print "<div id='body'>";
    $page->print_body;
    print "</div>";

    print "<div id='vhostselector'>";
    print "<h1>Configured VHosts</h1>";
    print "<ul>";

    $server->foreach_vhost(sub {
        my $vhost = shift;
        my $name = $vhost->server_name;
        print "<li><a href='/".ehtml($name)."/'>".ehtml($name)."</a></li>";
    });

    print "</ul>";
    print "</div>";

    print q{</body></html>};
}

package DJabberd::WebAdmin::Page;

# Abstract subclass for standalone pages

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub title {
    my ($self, $r) = @_;
    return "";
}

sub print_body {
    my ($self, $r) = @_;

}

# Borrow the ehtml function
*ehtml = \&DJabberd::WebAdmin::ehtml;

package DJabberd::WebAdmin::Page::WithVHost;

# Abstract subclass for pages which are about a specific vhost
# (which is most of them)

use base qw(DJabberd::WebAdmin::Page);

sub new {
    my ($class, $vhost) = @_;
    return bless { vhost => $vhost }, $class;
}

sub vhost {
    return $_[0]->{vhost};
}

package DJabberd::WebAdmin::Page::Home;

use base qw(DJabberd::WebAdmin::Page);

sub title {
    return "Home";
}

sub print_body {
    my ($self, $r) = @_;

    print "<p>Welcome to the DJabberd Web Admin interface</p>";

}

package DJabberd::WebAdmin::Page::VHostSummary;

use base qw(DJabberd::WebAdmin::Page::WithVHost);

sub title {
    my ($self) = @_;
    return $self->vhost->server_name;
}

sub print_body {
    my ($self, $r) = @_;

    my $vhost = $self->vhost;

    # FIXME: Should add some accessors to DJabberd::VHost to get this stuff, rather than
    #    grovelling around inside.
    print "<h2>Client Sessions</h2>";
    print "<ul>";
    foreach my $jid (keys %{$vhost->{jid2sock}}) {
        my $conn = $vhost->{jid2sock}{$jid};
        print "<li>" . DJabberd::WebAdmin::Page::ehtml($jid) . " " . DJabberd::WebAdmin::Page::ehtml($conn->{peer_ip}) . " " . ($conn->{ssl} ? ' (SSL)' : '') . "</li>";
    }
    print "</ul>";
    
    print "<h2>Plugins Loaded</h2>";
    print "<ul>";
    foreach my $class (keys %{$vhost->{plugin_types}}) {
        print "<li>" . DJabberd::WebAdmin::Page::ehtml($class) . "</li>";
    }
    print "</ul>";

    #DJabberd::WebAdmin::dump_object_html($self->vhost);

}

1;
