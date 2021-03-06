# == Class: role::labs::wdq-mm
# Role class for setting up an instance of
# Magnus' WDQ on labs
class role::labs::wdq-mm {
    include misc::labsdebrepo

    include labs_lvm
    labs_lvm::volume { 'instance-storage':
        mountat => '/srv',
        size    => '80%FREE',
    }

    class { '::wdq-mm':
        require => [
            Class['misc::labsdebrepo'],
            Labs_lvm::Volume['instance-storage'],
        ]
    }
}

# == Class: role::labs::wdq-mm::lb
# Load balancer for balancing across multiple instances
# of role::labs::wdq-mm
class role::labs::wdq-mm::lb {
    class { '::wdq-mm::lb':
    }
}
