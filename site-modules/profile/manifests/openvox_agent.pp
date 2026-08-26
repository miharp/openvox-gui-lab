# @summary Pins the agent package version.
#
# @param version
#   The openvox-agent version to hold every node at.
class profile::openvox_agent (
  String[1] $version,
) {
  package { 'openvox-agent':
    ensure => $version,
  }
}
