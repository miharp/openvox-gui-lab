# @summary Installs OpenVox Server, on the primary and on the compiler.
#
# A compiler runs the same package as the primary; what differs is that its
# CA service is disabled and it enrols against the primary's CA, and that
# split is set up during provisioning because it has to precede the node
# holding a certificate.
#
# The GUI probes every server's /status (member health) and /metrics
# (dashboard JVM metrics) with its agent certificate, and the stock auth.conf
# allows neither, so both are opened to the console certnames here.
#
# @param version
#   The openvox-server version to install.
# @param console_certnames
#   Certnames of the OpenVox GUI console(s) allowed on /status and /metrics.
# @param auth_conf
#   Path of puppetserver's auth.conf.
class profile::openvox_server (
  String[1] $version,
  Array[String[1]] $console_certnames = [],
  Stdlib::Absolutepath $auth_conf = '/etc/puppetlabs/puppetserver/conf.d/auth.conf',
) {
  $package_version = $facts['os']['family'] ? {
    'RedHat' => "${version}-1.el${facts['os']['release']['major']}",
    default  => $version,
  }

  package { 'openvox-server':
    ensure => $package_version,
  }

  service { 'puppetserver':
    ensure  => running,
    enable  => true,
    require => Package['openvox-server'],
  }

  unless $console_certnames.empty {
    # sort_order 200 beats the stock rules (500) for the same paths.
    puppet_authorization::rule { 'openvox-gui status':
      path                 => $auth_conf,
      match_request_path   => '/status',
      match_request_type   => 'path',
      match_request_method => 'get',
      allow                => $console_certnames,
      sort_order           => 200,
      require              => Package['openvox-server'],
      notify               => Service['puppetserver'],
    }

    puppet_authorization::rule { 'openvox-gui metrics':
      path                 => $auth_conf,
      match_request_path   => '/metrics',
      match_request_type   => 'path',
      match_request_method => ['get', 'post'],
      allow                => $console_certnames,
      sort_order           => 200,
      require              => Package['openvox-server'],
      notify               => Service['puppetserver'],
    }
  }
}
