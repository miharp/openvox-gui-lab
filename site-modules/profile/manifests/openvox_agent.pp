# @summary Pins the agent package version and keeps the agent service running.
#
# The agent runs as a service on every node, on a fixed interval, so the
# estate keeps converging on its own between deliberate runs (a Stage/Activate
# from the GUI shows up within one interval; scripts/converge is for when you
# do not want to wait). The interval is set in puppet.conf rather than left at
# the 30-minute package default so that it is visible and changeable here.
#
# @param version
#   The openvox-agent version to hold every node at.
# @param runinterval
#   How often the agent service applies the catalog (puppet.conf runinterval).
# @param service_ensure
#   State of the puppet service.
# @param service_enable
#   Whether the puppet service starts at boot.
class profile::openvox_agent (
  String[1] $version,
  String[1] $runinterval = '30m',
  Stdlib::Ensure::Service $service_ensure = 'running',
  Boolean $service_enable = true,
) {
  package { 'openvox-agent':
    ensure => $version,
  }

  ini_setting { 'puppet agent runinterval':
    ensure  => present,
    path    => '/etc/puppetlabs/puppet/puppet.conf',
    section => 'agent',
    setting => 'runinterval',
    value   => $runinterval,
    require => Package['openvox-agent'],
  }

  service { 'puppet':
    ensure    => $service_ensure,
    enable    => $service_enable,
    subscribe => Ini_setting['puppet agent runinterval'],
  }
}
