
=head1 NAME

DJabberd::Gearman::Defaults - Pseudo-plugin for configuring default settings that apply to all plugins

=head1 SYNOPSIS

    <VHost example.com>
    
        <Plugin DJabberd::Gearman::Defaults>
            JobServers 127.0.0.1:3007
        </Plugin>
    
    </VHost>

=head1 DESCRIPTION

The configuration settings that apply to all plugins, as described
in L<DJabberd::Gearman>, can be set on a per-VHost rather than
per-Plugin basis using this pseudo-plugin.

It doesn't do anything by itself, but it does retain the values
of these properties on a per-VHost basis so that other
plugins in this suite can use them where no values are explictly
provided in their own declarations.

=cut

package DJabberd::Gearman::Defaults;

use strict;
use warnings;

use DJabberd::Gearman;
use base qw(DJabberd::Plugin);

my %vhost_defaults = ();

sub set_config_jobservers {
    my ($self, $servers) = @_;

    $self->{settings} ||= {};
    $self->{settings}{gearman_client} ||= DJabberd::Gearman->new_client();
    $self->{settings}{gearman_client}->set_job_servers(split(/\s+/, $servers));
}

sub register {
    my ($self, $vhost) = @_;

    my $domain = $vhost->server_name;
    $vhost_defaults{$domain} = $self->{settings};
}

sub settings_for_vhost {
    my ($class, $vhost) = @_;

    my $domain = $vhost->server_name;
    return $vhost_defaults{$domain};
}

1;
