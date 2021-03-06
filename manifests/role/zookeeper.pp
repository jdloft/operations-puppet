# role/zookeeper.pp
#
# Classes for Zookeeper nodes.
# These role classes will configure Zookeeper properly in either
# the labs or production environments.
#
# Usage:
#
# If you only need Zookeeper client configs to talk to Zookeeper servers:
#   include role::zookeeper::client
#
# If you want to set up a Zookeeper server:
#   include role::zookeeper::server
#
#
# You need to include the hiera variable 'zookeeper_hosts' as a
# assoc array with key being name of node and value being zookeeper id
# for the client / server roles to work.

# == Class role::zookeeper::client
#
class role::zookeeper::client {

    $version = $::lsbdistcodename ? {
        'trusty'  => '3.4.5+dfsg-1',
        'precise' => '3.3.5+dfsg1-1ubuntu1',
    }

    $hosts = hiera('zookeeper_hosts')

    class { '::zookeeper':
        hosts   => $hosts,
        version => $version,
        # Default tick_time is 2000ms, this should allow a max
        # of 16 seconds of latency for Zookeeper client sessions.
        # See comments in role::analytics::kafka::server for more info.
        sync_limit => 8,
    }
}

# == Class role::zookeeper::server
#
class role::zookeeper::server {
    system::role { 'role::zookeeper::server':
        description => 'Analytics Cluster Zookeeper Server'
    }

    include role::zookeeper::client

    class { '::zookeeper::server': }

    if hiera('has_ganglia', true) {
        # TODO: use variables from new ganglia module once it is finished.
        $ganglia_host = '239.192.1.32'
        $ganglia_port = 8649

        # Only allow hosts in the Analytics Cluster to
        # connect to the Zookeeper admin client port.
        #
        # We don't include base::firewall yet, but do
        # want to restrict access to administrative
        # services.  We need defs.erb to be rendered
        # so we can reference defined networks in rules.
        # NOTE:  This should be removed if we get a useable
        # base::firewall class.
        include ferm
        include network::constants
        ferm::conf { 'defs':
            # defs can always be present.
            # They don't actually do firewalling.
            ensure  => 'present',
            prio    => '00',
            content => template('base/firewall/defs.erb')
        }

        ferm::service { 'zookeeper':
            proto  => 'tcp',
            # Zookeeper client, protocol, and jmx listen ports.
            port   => "(2181 2182 2183 ${$::zookeeper::server::jmx_port})",
            srange => '($ANALYTICS_NETWORKS)',
        }
        # Use jmxtrans for sending metrics to ganglia
        class { 'zookeeper::jmxtrans':
            ganglia => "${ganglia_host}:${ganglia_port}",
        }
    }
}
