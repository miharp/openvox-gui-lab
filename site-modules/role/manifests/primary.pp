# @summary The primary: CA, OpenVoxDB, DNS for the estate, and an
#   orchestration target like every other node the GUI can see.
class role::primary {
  include profile::primary
  include profile::bolt_target
}
