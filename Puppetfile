forge 'https://forge.puppet.com'

# Kept small. Everything here is either needed by a component module or used
# by a profile in this lab; r10k does not resolve dependencies, so component
# module dependencies are listed explicitly.
mod 'puppetlabs/stdlib',       '9.7.0'
mod 'puppetlabs/concat',       '9.1.0'
mod 'puppetlabs/inifile',      '6.4.1'
mod 'puppetlabs/vcsrepo',      '7.0.0'

# OpenVoxDB on the primary and the termini on the compiler. firewall is a
# declared dependency of openvoxdb (unused: openvoxdb::manage_firewall is
# false, ports are opened during provisioning), systemd is used by its DLO
# cleanup timer.
mod 'puppet/openvoxdb',        '9.1.1'
mod 'puppetlabs/postgresql',   '10.6.3'
mod 'puppetlabs/firewall',     '8.5.0'
mod 'puppet/systemd',          '8.3.1'

# auth.conf rules that let the console reach the CA API and the compilers'
# status endpoints.
mod 'puppetlabs/hocon',                '2.0.0'
mod 'puppetlabs/puppet_authorization', '1.0.1'

# yumrepo left Puppet core. Real nodes get it with openvox-agent; a
# compile-only environment (Onceover) has to declare it.
mod 'puppetlabs/yumrepo_core', '3.0.1'

# Not on the Forge; pinned by tag. Installs the GUI on the console and
# prepares Bolt targets (openvox_gui::bolt_target) everywhere else.
mod 'openvox_gui',
  git: 'https://github.com/miharp/puppet-openvox_gui.git',
  ref: 'v0.2.0'
