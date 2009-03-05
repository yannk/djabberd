
=head1 NAME

DJabberd::Gearman::BasePlugin - Abstract base plugin for this suite

=cut

package DJabberd::Gearman::BasePlugin;

use strict;
use warnings;
use base qw(DJabberd::Plugin);
use DJabberd::Log;
use Gearman::Task;
use DJabberd::Callback;

my $logger = DJabberd::Log->get_logger();

sub set_config_jobservers {
    my ($self, $servers) = @_;

    $self->{gearman_client} ||= DJabberd::Gearman->new_client();
    $self->{gearman_client}->set_job_servers(split(/\s+/, $servers));
}

sub configure_defaults {
    my ($self, $vhost) = @_;

    my $defaults = DJabberd::Gearman::Defaults->settings_for_vhost($vhost);

    if ($defaults) {
        foreach my $k (keys %$defaults) {
            $self->{$k} ||= $defaults->{$k};
        }
    }

    # We should definitely have a Gearman client by this point.
    $logger->logdie("No JobServers configured for $self in ".$vhost->server_name) unless $self->{gearman_client};
}

sub gearman_client {
    return $_[0]->{gearman_client};
}

# This gets overridden by the abstract plugin classes
# that some of our plugins also inherit. In such cases,
# the plugin must duplicate this method to cause
# configure_defaults to be called.
sub register {
    my ($self, $vhost) = @_;

    $self->configure_defaults($vhost);
    return $self->SUPER::register($vhost);
}

sub call_gearman_func {
    my ($self, $func_name, $args, $cb) = @_;

    my $client = $self->gearman_client;
    my $arg = ref($args) ? DJabberd::Gearman->json_encode($args) : $args;

    $cb = DJabberd::Callback->new($cb);

    my $task = Gearman::Task->new($func_name, \$arg, {
        on_complete => sub {
            my ($result_json) = @_;

            my $result_obj;
            eval {
                $result_obj = DJabberd::Gearman->json_decode($result_json);
            };
            if ($@) {
                $cb->fail('JSON Parse Error');
            }
            else {
                $cb->complete($result_obj);
            }
        },
        on_fail => sub {
            $cb->fail('Gearman call failed');
        },
    });

    print STDERR "Calling $func_name($arg)\n";

    $client->add_task($task);

}

sub declare_gearman_func {
    my ($self, $func_name, $callback) = @_;



}

sub declare_gearman_func_raw {
    my ($self, $func_name, $callback) = @_;

}

sub make_configurable_funcs {
    my ($class, @funcs) = @_;

    no strict 'refs';

    foreach my $func (@funcs) {
        my $config_name = $func.'_func';
        my $set_config_name = "set_config_".$func."func";
        *{$class."::".$set_config_name} = sub {
            my ($self, $name) = @_;
            $self->$config_name($name);
        };

        *{$class."::".$config_name} = sub {
            my $self = shift;

            if (@_) {
                $self->{$config_name} = shift;
                $self->{$config_name} =~ s/^\s*//g;
                $self->{$config_name} =~ s/\s*$//g;
            }
            else {
                return $self->{$config_name};
            }
        };
    }
}

1;

