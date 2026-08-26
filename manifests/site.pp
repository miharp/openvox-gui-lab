## site.pp ##
#
# Node definitions here must agree with spec/onceover.yaml: Onceover proves a
# role compiles, never that a node is classified into it.

File { backup => false }

# Anything unclassified gets the baseline only. Reaching this is a sign a node
# definition is missing.
node default {
  include profile::base
}

node 'puppet.example.com' {
  include role::primary
}

node 'compiler01.example.com' {
  include role::compiler
}

node 'console.example.com' {
  include role::console
}

node 'agent01.example.com' {
  include role::agent
}
