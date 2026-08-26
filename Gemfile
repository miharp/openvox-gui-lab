source 'https://rubygems.org'

# Control-repo-wide testing. Onceover compiles every role against a node
# factset, so a role that cannot compile is caught before a VM is built.
#
#   bundle install
#   bundle exec onceover run spec
group :test do
  # openvox, not puppet: this is an OpenVox estate, and the gems diverge.
  gem 'openvox', ENV.fetch('PUPPET_GEM_VERSION', '~> 8.0'), require: false

  gem 'onceover', '~> 5.0', require: false
end
