# @summary The dedicated OpenVox GUI console.
#
# Agent only — no puppetserver, no CA, no control repo. The GUI talks to
# the compiler for catalogs and environments, to OpenVoxDB by its
# round-robin name, and to the CA by its round-robin name over the CA HTTP
# API; it reaches the compiler for Stage/Activate and runs over Bolt as
# the bolt user. All of that is what "clustered" means in OpenVox GUI 3.12.
#
# The installer's Bolt step (configure_bolt) creates the console's bolt user
# and SSH key; the key's public half is then reported as a fact and every
# target, this node included, collects it (profile::bolt_target).
#
# Cluster mode is set once from here, through the GUI's own Settings >
# Cluster > Save (deployment_mode clustered, the compiler, OpenVoxDB and CA
# members, the round-robin names to hide from the fleet), so that what an
# operator's Save does - seeding the ENC infrastructure groups, running
# the migration helpers - happens here too. The GUI owns the result
# afterwards; Puppet only steps in while the GUI is not yet clustered.
#
# The GUI's own database is PostgreSQL on the primary, reached as
# ovdb.example.com: clustered mode requires it (Settings > Cluster refuses
# to save on SQLite), and the installer provisions role, database and
# schema itself through its bootstrap-openvox-gui-db.sh, given a superuser
# DSN and the app password.
#
# @param gui_version
#   OpenVox GUI release to install.
# @param admin_password
#   Initial admin password.
# @param gui_db_password
#   Password of the openvox_gui database role the installer creates.
# @param gui_db_admin_password
#   Password of the superuser the installer connects as to create it.
# @param gui_db_admin_user
#   That superuser's name.
# @param compiler
#   Catalog compiler the GUI treats as its OpenVox Server.
# @param puppetdb_host
#   OpenVoxDB name the GUI queries (a DNS round-robin name here).
# @param ca_host
#   CA name the GUI uses for the CA HTTP API (a DNS round-robin name here).
# @param puppetdb_nodes
#   OpenVoxDB member FQDNs, for per-member health.
# @param ca_nodes
#   CA member FQDNs, for per-member health.
class profile::console (
  String[1] $gui_version,
  String[1] $admin_password,
  String[1] $gui_db_password,
  String[1] $gui_db_admin_password,
  String[1] $gui_db_admin_user = 'openvox_gui_admin',
  Stdlib::Host $compiler = 'compiler01.example.com',
  Stdlib::Host $puppetdb_host = 'ovdb.example.com',
  Stdlib::Host $ca_host = 'ovca.example.com',
  Array[Stdlib::Host] $puppetdb_nodes = ['puppet.example.com'],
  Array[Stdlib::Host] $ca_nodes = ['puppet.example.com'],
) {
  include profile::base
  include profile::bolt_target

  # EL9's default nodejs is 16; the frontend build needs 18+. The AppStream
  # nodejs:20 stream supplies both nodejs and npm, so the module's own nodejs
  # package is dropped from its dependency list and provided here.
  package { 'nodejs':
    ensure   => '20',
    provider => 'dnfmodule',
  }

  # The installer's OpenBolt step installs it too; being explicit keeps the
  # dependency visible. python3.12: EL9's python3 is 3.9, below the backend's
  # floor, so the installer is pointed at the AppStream 3.12.
  package { ['openbolt', 'python3.12']:
    ensure => installed,
  }

  # The installer's database bootstrap runs psql from here.
  package { 'postgresql':
    ensure => installed,
  }

  class { 'openvox_gui':
    version             => $gui_version,
    admin_password      => Sensitive($admin_password),
    puppet_server_host  => $compiler,
    puppetdb_host       => $puppetdb_host,
    configure_bolt      => true,
    dependency_packages => ['git', 'npm', 'diffutils', 'curl', 'openssh-clients'],
    extra_settings      => {
      'PUPPET_CA_HOST'              => $ca_host,
      'PYTHON_BIN'                  => '/usr/bin/python3.12',
      'OPENVOX_GUI_DB_BACKEND'      => 'postgresql',
      'OPENVOX_GUI_DB_ADMIN_DSN'    => "postgresql://${gui_db_admin_user}:${gui_db_admin_password}@${puppetdb_host}:5432/postgres",
      'OPENVOX_GUI_DB_APP_PASSWORD' => $gui_db_password,
    },
    require             => Package['nodejs', 'openbolt', 'python3.12', 'postgresql'],
  }

  $cluster = {
    'deployment_mode'             => 'clustered',
    'compilers'                   => [$compiler],
    'code_deploy_targets'         => [$compiler],
    'puppetdb_nodes'              => $puppetdb_nodes,
    'ca_nodes'                    => $ca_nodes,
    'ca_vips'                     => [$ca_host],
    'dns_rr_vips'                 => [$puppetdb_host],
    'consoles'                    => [$facts['networking']['fqdn']],
    'database_backend'            => 'postgresql',
    'seed_infrastructure_groups'  => true,
  }

  $seed = '/usr/local/sbin/openvox-gui-seed-cluster'
  $seed_payload = '/opt/openvox-gui/config/cluster-seed.json'
  $seed_login = '/opt/openvox-gui/config/cluster-seed-login.json'
  $cluster_config = '/opt/openvox-gui/data/cluster_config.json'

  file { $seed_payload:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => stdlib::to_json_pretty($cluster),
  }

  file { $seed_login:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => stdlib::to_json({ 'username' => 'admin', 'password' => $admin_password }),
  }

  file { $seed:
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/profile/openvox-gui-seed-cluster',
  }

  # Runs while the GUI is not yet clustered; afterwards the GUI owns the file.
  $is_clustered = "import json, sys; sys.exit(0 if json.load(open('${cluster_config}')).get('deployment_mode') == 'clustered' else 1)"

  exec { 'openvox-gui seed cluster':
    command   => "${seed} ${seed_login} ${seed_payload}",
    unless    => "/usr/bin/python3 -c \"${is_clustered}\"",
    logoutput => true,
    require   => [Class['openvox_gui'], File[$seed, $seed_login, $seed_payload]],
  }
}
