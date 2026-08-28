# @summary A class to assign from the GUI, not from site.pp.
#
# Nothing in this repository declares it. Give it to a node from
# Classification & Code > Classification (through a group or on the node
# itself), optionally with a content parameter, run the agent, and the file
# appears: the compiler asked the console, the console answered, and both
# a class and a parameter travelled back.
#
# @param content
#   Text written to the marker file.
class profile::enc_marker (
  String[1] $content = 'classified-by-the-gui',
) {
  file { '/etc/openvox-gui-lab-enc-marker':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "${content}\n",
  }
}
