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

# Need 5.8 because we use PerlIO
require 5.008;

use strict;
use Perlbal; # FIXME: Once a release of Perlbal with the new API has actually been made, require that version explicitly here
use Perlbal::Plugin::Cgilike;
use Symbol;
use Template;

use base qw(DJabberd::Plugin);

our $logger = DJabberd::Log->get_logger();

my $server = undef;

my $tt = Template->new({
    INCLUDE_PATH => 'templates',
    
    START_TAG => quotemeta("[["),
    END_TAG => quotemeta("]]"),
    PRE_CHOMP => 2, # CHOMP_COLLAPSE
    POST_CHOMP => 2, # CHOMP_COLLAPSE
    RECURSION => 1,
});

sub set_config_listenaddr {
    my ($self, $addr) = @_;
    
    $self->{listenaddr} = DJabberd::Util::as_bind_addr($addr);

    # We default to localhost if no interface is specified
    # User can explicitly say 0.0.0.0: to bind to everything.
    $self->{listenaddr} = "127.0.0.1:".$self->{listenaddr} if $self->{listenaddr} =~ /^\d+$/;
}

sub finalize {
    my ($self) = @_;

    $logger->logdie("No ListenAddr specified for WebAdmin") unless $self->{listenaddr};

    # We depend on the "cgilike" plugin
    # FIXME: Should add a nice API to Perlbal for this
    Perlbal::run_manage_command("LOAD cgilike", sub { $logger->info('[perlbal] '.$_[0]); });
    
    # Create an anonymous Perlbal service
    my $pbsvc = Perlbal->create_service();
    
    $pbsvc->set('listen', $self->{listenaddr});
    $pbsvc->set('role', 'web_server');
    $pbsvc->set('plugins', 'cgilike');
    
    # It'd be good if there was a nicer API to do this, but whatever
    $pbsvc->run_manage_command('PERLHANDLER = DJabberd::WebAdmin::handle_web_request');
    
    $pbsvc->enable();
    
    # Let Perlbal do any global initialization it needs to do.
    Perlbal::initialize();
    
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

    my $path = $r->path;

    # If the URL starts with /_/ then it's a static file request.
    if ($path =~ m!^/_/(\w+)$!) {
        my $resource_name = $1;
        return handle_static_resource($r, $resource_name);
    }
    # which we just let Perlbal handle itself.
    return Perlbal::Plugin::Cgilike::DECLINED if ($path =~ m!^/_/!);

    # All valid paths end with a slash
    # (because it makes it easier to construct relative links)
    if (substr($path, -1) ne '/') {
        $r->response_status_code(302);
        $r->response_header('Location' => $path.'/');
        print "...";
        return Perlbal::Plugin::Cgilike::HANDLED;
    }

    my $page = determine_page_for_request($r);
    
    unless (ref $page) {
        # It's a string containing a relative URL to redirect to
        $r->response_status_code(302);
        $r->response_header('Location' => $path.$page);
        print "...";
        return Perlbal::Plugin::Cgilike::HANDLED;
    }
    
    if ($page) {
        output_page($r, $page);
        return Perlbal::Plugin::Cgilike::HANDLED;
    }
    else {
        return 404;
    }

    return Perlbal::Plugin::Cgilike::HANDLED;
}

sub handle_static_resource {
    my ($r, $name) = @_;
    
    my $fn = undef;
    my $type = undef;
    
    if ($name eq 'style') {
        $fn = 'stat/style.css';
        $type = 'text/css';
    }
    else {
        $fn = 'stat/'.$name.'.png';
        $type = 'image/png';
    }

    return 404 unless defined($fn) && -f $fn;
    
    $r->response_header('Content-type' => $type);
    $r->send_response_header();
    
    # FIXME: Should really add an API to Cgilike's $r for this, which can then use sendfile
    # This is lame.
    
    return 404 unless open (STATFILE, '<', $fn);
    
    # FIXME: Really should to binmode() the fh underlying $r, but no nice API for this right now
    #    and DJabberd doesn't work on Windows anyway.
    binmode STATFILE;
    
    my $buf = "";
    while (read(STATFILE, $buf, 1024)) {
        print $buf;
    }
    
    close(STATFILE);
    
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
        return "summary/";
    }
    
    my $tabname = shift @pathbits;
    
    if ($tabname eq 'summary') {
        if (scalar(@pathbits) == 0) {
            return DJabberd::WebAdmin::Page::VHostSummary->new($vhost);
        }
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

    my @pathbits = $r->path_segments;

    my @tabs = (
        {
            caption => 'Summary',
            urlname => 'summary',
        },
        {
            caption => 'Client Sessions',
            urlname => 'clients',
        },
        {
            caption => 'Server Sessions',
            urlname => 'servers',
        },
    );

    $tt->process('page.tt', {
        section_title => $title ? $title : "DJabberd Web Admin",
        page_title => 'Summary',
        head_title => sub { ($title ? $title.' - ' : '')."DJabberd Web Admin"; },
        body => sub { return ${ capture_output(sub { $page->print_body; }) }; },
        tabs => [
            map {
                {
                    caption => $_->{caption},
                    url => '../'.$_->{urlname}.'/',
                    current => ($pathbits[1] eq $_->{urlname} ? 1 : 0),
                }
            } @tabs
        ],
        vhosts => sub {
            my @ret = ();
            $server->foreach_vhost(sub {
                my $vhost = shift;
                my $name = $vhost->server_name;
                push @ret, {
                    hostname => $name, # The real hostname
                    url => '/'.$name.'/summary/', # FIXME: should urlencode $name here
                    name => $name, # Some display name (just the hostname for now)
                    current => ($pathbits[0] eq $name ? 1 : 0),
                };
            });
            return [ sort { $a->{name} cmp $b->{name} } @ret ];
        },
        djabberd_version => $DJabberd::VERSION,
        perlbal_version => $Perlbal::VERSION,
    }, $r);

}

sub capture_output {
    my $sub = shift;
    
    my $fh = Symbol::gensym();
    my $ret = "";
    open($fh, '>', \$ret);
    
    my $oldfh = select($fh);
    
    $sub->(@_);
    
    select($oldfh);
    close($fh);
    
    return \$ret;
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
    print "<h3>Client Sessions</h3>";
    print "<ul>";
    foreach my $jid (keys %{$vhost->{jid2sock}}) {
        my $conn = $vhost->{jid2sock}{$jid};
        print "<li>" . DJabberd::WebAdmin::Page::ehtml($jid) . " " . DJabberd::WebAdmin::Page::ehtml($conn->{peer_ip}) . " " . ($conn->{ssl} ? ' (SSL)' : '') . "</li>";
    }
    print "</ul>";
    
    print "<h3>Plugins Loaded</h3>";
    print "<ul>";
    foreach my $class (keys %{$vhost->{plugin_types}}) {
        print "<li>" . DJabberd::WebAdmin::Page::ehtml($class) . "</li>";
    }
    print "</ul>";

    #DJabberd::WebAdmin::dump_object_html($self->vhost);

}

1;
