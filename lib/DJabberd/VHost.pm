package DJabberd::VHost;
use strict;
use Carp qw(croak);
use DJabberd::Util qw(tsub);
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger();
our $hook_logger = DJabberd::Log->get_logger("DJabberd::VHost");

sub new {
    my ($class, %opts) = @_;

    my $self = {
        'server_name' => lc(delete $opts{server_name} || ""),
        'require_ssl' => delete $opts{require_ssl},
        'hooks'       => {},
        'server'      => undef,  # set when added to a server
    };

    my $plugins = delete $opts{plugins};
    die "unknown opts" if %opts; #FIXME: better

    bless $self, $class;

    $logger->info("Addding plugins...");
    foreach my $pl (@{ $plugins || [] }) {
        $logger->info("  ... adding plugin: $pl");
        $self->add_plugin($pl);
    }

    return $self;
}

sub server {
    my $self = shift;
    return $self->{server};
}

sub set_server {
    my ($self, $server) = @_;
    $self->{server} = $server;
}

sub run_hook_chain {
    my $self = shift;
    my %opts = @_;

    my $phase    = delete $opts{'phase'};
    my $methods  = delete $opts{'methods'} || {};
    my $args     = delete $opts{'args'}    || [];
    my $fallback = delete $opts{'fallback'};
    die if %opts;

    # make phase into an arrayref;
    $phase = [ $phase ] unless ref $phase;

    my @hooks;
    foreach my $ph (@$phase) {
        $logger->logcroak("Undocumented hook phase: '$ph'") unless
            $DJabberd::HookDocs::hook{$ph};
        push @hooks, @{ $self->{hooks}->{$ph} || [] };
    }
    push @hooks, $fallback if $fallback;

    my $try_another;
    my $stopper = tsub {
        $try_another = undef;
    };
    $try_another = tsub {

        my $hk = shift @hooks
            or return;

        $hk->($self,
              DJabberd::Callback->new(
                                      decline    => $try_another,
                                      declined   => $try_another,
                                      stop_chain => $stopper,
                                      _post_fire => sub {
                                          # when somebody fires this callback, we know
                                          # we're done (unless it was decline/declined)
                                          # and we need to clean up circular references
                                          my $fired = shift;
                                          unless ($fired =~ /^decline/) {
                                              $try_another = undef;
                                          }
                                      },
                                      %$methods,
                                      ),
              @$args);
    };

    $try_another->();
}

# return the version of the spec we implement
sub spec_version {
    my $self = shift;
    return $self->{_spec_version} ||= DJabberd::StreamVersion->new("1.0");
}

sub name {
    my $self = shift;
    return $self->{server_name} || die "No server name configured.";
    # FIXME: try to determine it
}

# vhost method
sub add_plugin {
    my ($self, $plugin) = @_;
    $plugin->register($self);
}

*requires_ssl = \&require_ssl;  # english
sub require_ssl {
    my $self = shift;
    return $self->{require_ssl};
}

sub are_hooks {
    my ($self, $phase) = @_;
    return scalar @{ $self->{hooks}{$phase} || [] } ? 1 : 0;
}

sub register_hook {
    my ($self, $phase, $subref) = @_;
    # TODO: die if bogus phase
    push @{ $self->{hooks}{$phase} ||= [] }, $subref;
}

# local connections
my %jid2sock;  # bob@207.7.148.210/rez -> DJabberd::Connection
               # bob@207.7.148.210     -> DJabberd::Connection
my %bare2fulls; # barejids -> { fulljid -> 1 }

sub find_jid {
    my ($self, $jid) = @_;
    if (ref $jid) {
        return $self->find_jid($jid->as_string) ||
               $self->find_jid($jid->as_bare_string);
    }
    my $sock = $jid2sock{$jid} or return undef;
    return undef if $sock->{closed};
    return $sock;
}

sub register_jid {
    my ($self, $jid, $sock) = @_;
    $logger->info("Registering '$jid' to connection '$sock->{id}'");

    my $barestr = $jid->as_bare_string;
    my $fullstr = $jid->as_string;
    $jid2sock{$fullstr} = $sock;
    $jid2sock{$barestr} = $sock;
    ($bare2fulls{$barestr} ||= {})->{$fullstr} = 1;
}

# given a bare jid, find all local connections
sub find_conns_of_bare {
    my ($self, $jid) = @_;
    my $barestr = $jid->as_bare_string;
    my @conns;
    foreach my $fullstr (keys %{ $bare2fulls{$barestr} || {} }) {
        my $conn = $self->find_jid($fullstr)
            or next;
        push @conns, $conn;
    }

    return @conns;
}

# returns true if given jid is recognized as "for the server"
sub uses_jid {
    my ($self, $jid) = @_;
    return 0 unless $jid;
    # FIXME: this does no canonicalization of server_name, for one
    return $jid->as_string eq $self->{server_name};
}

# returns true if given jid is controlled by this vhost
sub handles_jid {
    my ($self, $jid) = @_;
    return 0 unless $jid;
    # FIXME: this does no canonicalization of server_name, for one
    return $jid->domain eq $self->{server_name};
}

sub roster_push {
    my ($self, $jid, $ritem) = @_;
    croak("no ritem") unless $ritem;

    # FIXME: single-server roster push only.   need to use a hook
    # to go across the cluster

    my $xml = "<query xmlns='jabber:iq:roster'>";
    $xml .= $ritem->as_xml;
    $xml .= "</query>";

    my @conns = $self->find_conns_of_bare($jid);
    foreach my $c (@conns) {
        #TODO:  next unless $c->is_available;
        my $id = $c->new_iq_id;
        my $iq = "<iq to='" . $c->bound_jid->as_string . "' type='set' id='$id'>$xml</iq>";
        $c->xmllog->info($iq);
        $c->write(\$iq);
    }
}

sub debug {
    my $self = shift;
    return unless $self->{debug};
    printf STDERR @_;
}


# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:

1;
