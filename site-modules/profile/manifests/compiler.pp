# @summary A catalog compiler and orchestration target.
#
# Same package as the primary, CA disabled during provisioning. Stores
# facts, catalogs and reports in OpenVoxDB at ovdb.example.com (the GUI's
# fleet view follows OpenVoxDB, so a compiler not wired to it hides every
# node it serves). Carries r10k and an r10k.yaml because the GUI's
# Stage/Activate runs r10k here, over Bolt, as root. The bolt user itself
# comes from profile::bolt_target once the console has reported its key.
#
# Classification from the GUI happens here too: puppetserver runs the GUI's
# enc.py at compile time, which asks the console. Every console allowed on
# this server's status endpoints (profile::openvox_server::console_certnames)
# is one the classifier may ask. enc.py answers with an empty classification
# when no console responds, so the compiler carries this from its first run,
# before the console exists; until then each compile waits out the request
# timeout, and site.pp's classification is all a node gets.
#
# @param puppetdb_server
#   OpenVoxDB host the termini talk to.
# @param control_repo_remote
#   Git remote r10k deploys from. The default is the read-only synced copy
#   of this repository's own .git.
# @param console_port
#   Port the console(s) serve the GUI on.
class profile::compiler (
  Stdlib::Host $puppetdb_server = 'ovdb.example.com',
  String[1] $control_repo_remote = 'file:///vagrant-src/.git',
  Stdlib::Port $console_port = 4567,
) {
  include profile::base
  include profile::openvox_server
  include profile::bolt_target

  $consoles = $profile::openvox_server::console_certnames
  unless $consoles.empty {
    class { 'openvox_gui::enc':
      api_base => $consoles.map |$c| { "https://${c}:${console_port}" },
      require  => Package['openvox-server'],
    }
  }

  class { 'openvoxdb::master::config':
    puppetdb_server         => $puppetdb_server,
    manage_report_processor => true,
    enable_reports          => true,
  }

  package { 'git':
    ensure => installed,
  }

  exec { 'install r10k':
    command => '/opt/puppetlabs/puppet/bin/gem install r10k --no-document',
    unless  => '/opt/puppetlabs/puppet/bin/gem list -i r10k',
    require => Package['openvox-server'],
  }

  file { '/etc/puppetlabs/r10k':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { '/etc/puppetlabs/r10k/r10k.yaml':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => @("YAML"),
      ---
      cachedir: '/var/cache/r10k'

      sources:
        control:
          remote: '${control_repo_remote}'
          basedir: '/etc/puppetlabs/code/environments'
      | YAML
  }
}
