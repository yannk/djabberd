
=head1 NAME

DJabberd::Gearman - Various DJabberd plugins that send tasks to Gearman workers

=head1 DESCRIPTION

This package provides a selection of DJabberd plugins that
implement DJabberd hooks but do not actually handle them
directly. Instead, a L<Gearman> job with a predefined calling
convention is used to handle each hook.

You (the user) just need to provide a gearman job server (L<gearmand>)
and a worker that can support the defined calling convention.

To allow for workers in languages other than Perl, this suite
of modules (in most cases) uses JSON for communication with workers.
Most languages have straightforward JSON libraries at this point.
If you're writing workers in Perl, check out L<JSON::Any>.

Some of the plugins expect workers to be able to handle raw stanzas
given as strings of XML, depending on the level they operate at.
If this upsets you then be sure to use only the higher-level
plugins that hide the details of the underlying XML.

Some plugins may also themselves expose workers, allowing Gearman
client apps to call into them and request that work be done.

=head1 COMMON CONFIGURATION OPTIONS

The following configuration options are common to all
plugins provided in this suite.

=head2 JobServers

Sets the Gearman job servers that will be used by the plugin.
Given as a space-separated string of ipaddr:port pairs.

It is expected (and required) that all of the functions used
by a given plugin will use the same job servers.

If you want to use the same job servers for all plugins
in a given VHost (which is probably the common case)
then you can set a default value which will apply
to all plugins that do not explicitly override
this setting. This is done using the special
L<DJabberd::Gearman::Defaults> plugin, which doesn't
actually do anything itself but acts as a container
for default values.

    <Plugin DJabberd::Gearman::Defaults>
        JobServers 127.0.0.1:3007
    </Plugin>

=cut

package DJabberd::Gearman;

use strict;
use warnings;

use Gearman::Client::Async;
use JSON::Any ();

my $json = JSON::Any->new();

sub new_client {
    my ($class) = @_;

    return Gearman::Client::Async->new();
}

sub json_encode {
    my ($class, $value) = @_;

    return $json->encode($value);
}
sub json_decode {
    my ($class, $value) = @_;

    return $json->decode($value);
}

1;
