# @summary Baseline every node in the lab gets.
#
# Deliberately thin: the agent at a pinned version and a marker file whose
# content comes from Hiera, so a code change can be watched travelling from
# a commit through Stage/Activate to an applied resource.
#
# @param marker_content
#   Text written to the marker file.
class profile::base (
  String[1] $marker_content = 'default',
) {
  include profile::openvox_agent

  file { '/etc/openvox-gui-lab-marker':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "${marker_content}\n",
  }
}
