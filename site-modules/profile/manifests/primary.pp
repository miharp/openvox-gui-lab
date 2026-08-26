# @summary The primary: certificate authority and OpenVoxDB.
#
# It compiles its own catalog and the compiler's; every other node gets
# catalogs from the compiler. OpenVoxDB (with the EL9 PostgreSQL) lives here
# and is reached as ovdb.example.com; this host's certificate carries that
# name as a SAN (set during provisioning) so OpenVoxDB can present it.
#
# The console is not the CA, so the GUI manages certificates through the CA
# HTTP API (certificate_status and friends) with its agent certificate. The
# stock auth.conf allows nobody there; the console certnames are allowed
# ahead of the stock rule.
#
# @param console_certnames
#   Certnames of the OpenVox GUI console(s) allowed to use the CA API.
# @param auth_conf
#   Path of puppetserver's auth.conf.
class profile::primary (
  Array[String[1]] $console_certnames = [],
  Stdlib::Absolutepath $auth_conf = '/etc/puppetlabs/puppetserver/conf.d/auth.conf',
) {
  include profile::base
  include profile::openvox_server

  # Settings (PostgreSQL version, listen address, heap) come from Hiera.
  class { 'openvoxdb': }

  # Termini and report processor on the primary itself. The module creates
  # Service['puppetserver'] only when it is not already declared, which
  # profile::openvox_server does.
  class { 'openvoxdb::master::config':
    manage_report_processor => true,
    enable_reports          => true,
    require                 => Class['openvoxdb'],
  }

  unless $console_certnames.empty {
    puppet_authorization::rule { 'openvox-gui certificate authority':
      path                 => $auth_conf,
      match_request_path   => '^/puppet-ca/v1/(certificate_status|certificate_statuses|clean|expirations)(/|$)',
      match_request_type   => 'regex',
      match_request_method => ['get', 'put', 'delete'],
      allow                => $console_certnames,
      sort_order           => 200,
      require              => Package['openvox-server'],
      notify               => Service['puppetserver'],
    }
  }
}
