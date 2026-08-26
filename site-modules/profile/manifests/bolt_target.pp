# @summary Makes this node an OpenVox GUI orchestration target.
#
# Wraps openvox_gui::bolt_target (the bolt user, its upload directory, its
# authorized keys) and adds the half the module leaves to the operator:
# passwordless sudo for that user, which the GUI's privileged runs and
# Stage/Activate depend on.
#
# Keys come from Hiera when set. Otherwise every console's key is collected
# from OpenVoxDB through the openvox_gui_bolt_pubkey fact, so a rebuilt
# console converges on the next agent runs without anyone copying a key.
# Onceover has no OpenVoxDB: when puppetdb_query is unavailable the lookup is
# skipped, and with no keys nothing is declared — which is also what a target
# sees until the console has reported its key.
#
# @param authorized_keys
#   Explicit authorized_keys lines for the bolt user. Overrides the lookup.
class profile::bolt_target (
  Array[String[1]] $authorized_keys = [],
) {
  if $authorized_keys.empty and stdlib::has_function('puppetdb_query') {
    $keys = puppetdb_query('facts[value] { name = "openvox_gui_bolt_pubkey" }').map |$fact| { $fact['value'] }.unique.sort
  } else {
    $keys = $authorized_keys
  }

  unless $keys.empty {
    class { 'openvox_gui::bolt_target':
      authorized_keys => $keys,
    }

    file { '/etc/sudoers.d/bolt':
      ensure       => file,
      owner        => 'root',
      group        => 'root',
      mode         => '0440',
      content      => "bolt ALL=(ALL) NOPASSWD: ALL\n",
      validate_cmd => '/usr/sbin/visudo -cf %',
    }
  }
}
