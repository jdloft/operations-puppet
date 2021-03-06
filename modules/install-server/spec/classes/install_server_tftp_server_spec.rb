require 'spec_helper'

describe 'install-server::tftp-server', :type => :class do

    it { should contain_package('atftpd').with_ensure('present') }

    it do
        should contain_file('/etc/default/atftpd').with({
            'mode'   => '0444',
            'owner'  => 'root',
            'group'  => 'root',
        })
    end

    it do
        should contain_file('/srv/tftpboot').with({
            'mode'   => '0444',
            'owner'  => 'root',
            'group'  => 'root',
            'recurse'  => 'remote',
        })
    end
end
