# @summary A plain managed node, and an orchestration target.
class role::agent {
  include profile::base
  include profile::bolt_target
}
