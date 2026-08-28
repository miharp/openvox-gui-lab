# OpenVox GUI clustered-mode lab.
#
# A minimal estate laid out the way OpenVox GUI 3.12's clustered mode expects
# (INSTALL.md "Advanced Installations"): a dedicated console that is not the CA
# and runs no puppetserver, a catalog compiler the console reaches over Bolt,
# a primary that is the CA and hosts OpenVoxDB, and a plain agent. The GUI's
# clustered features — Settings > Cluster, per-FQDN member health, Bolt runs,
# Stage/Activate, cluster-preflight — have only ever been exercised on the
# maintainer's own estate; this lab exists so they can be exercised here.
#
#   Topology                          runs                               server / ca_server
#   -----------------------------------------------------------------------------------------
#   puppet       192.168.58.10        CA, OpenVoxDB + PostgreSQL, DNS     itself
#   compiler01   192.168.58.11        catalog compiler, r10k, bolt user   puppet / puppet
#   console      192.168.58.12        OpenVox GUI, OpenBolt, bolt user    compiler01 / puppet
#   agent01      192.168.58.13        agent, bolt user                    compiler01 / puppet
#
# The primary runs real DNS (dnsmasq) for example.com, including the round-robin
# names the GUI treats specially: ovdb.example.com (OpenVoxDB) and
# ovca.example.com (CA). The GUI's cluster-preflight refuses a PuppetDB host
# pinned in /etc/hosts, so /etc/hosts entries for the estate exist only on the
# primary, where dnsmasq serves them; every other node resolves through it.
#
# 192.168.58.x on purpose: the dev control-repo is 192.168.56.x and codavox-lab
# is 192.168.57.x, so all three can be up at once.

Vagrant.configure("2") do |config|
  # Sequential bring-up: compilers enrol against the primary's CA, the console
  # gets its catalog from the compiler, and the agent needs both.
  ENV['VAGRANT_NO_PARALLEL'] ||= '1'

  # Set OPENVOX_TEST_REPO=1 to install from the pre-release testing repository.
  openvox_test_repo = ENV['OPENVOX_TEST_REPO'] == '1'
  yum_release_base = openvox_test_repo \
    ? 'https://s3.osuosl.org/openvox-artifacts/repo_test/yum' \
    : 'https://yum.voxpupuli.org'

  # EL9, like codavox-lab and for the same reason: this lab exists to find
  # openvox-gui problems, and EL10 is far enough ahead of the module ecosystem
  # that its gaps show up as failures that look like GUI problems.
  config.vm.box = "bento/rockylinux-9"

  primary_ip = "192.168.58.10"

  # Served by dnsmasq on the primary. Only the primary gets these in /etc/hosts.
  hosts = <<~HOSTS
    192.168.58.10 puppet.example.com puppet
    192.168.58.11 compiler01.example.com compiler01
    192.168.58.12 console.example.com console
    192.168.58.13 agent01.example.com agent01
  HOSTS

  # What dnsmasq answers with: the estate plus the round-robin names the GUI
  # treats specially, ovdb.example.com (OpenVoxDB) and ovca.example.com (CA).
  lab_hosts = hosts.sub(/^192\.168\.58\.10 .*$/) { |l| "#{l} ovdb.example.com ovdb ovca.example.com ovca" }

  # Common to every node: clock, curl, OpenVox repo.
  common = <<-SHELL
    set -euo pipefail

    # Parallels VMs can boot with real clock skew, and a wrong clock when
    # puppetserver first starts bakes a bad timestamp into the CRL.
    systemctl stop chronyd 2>/dev/null || true
    chronyd -q 'pool pool.ntp.org iburst' || true
    systemctl start chronyd

    dnf install -y -q curl
    rpm -q openvox8-release >/dev/null 2>&1 || \
      rpm -Uvh #{yum_release_base}/openvox8-release-el-9.noarch.rpm
  SHELL

  # Every node except the primary resolves through the primary's dnsmasq.
  # NetworkManager's global-dns applies to all connections, including the
  # NAT one, so the primary must forward upstream (it does: dnsmasq reads the
  # primary's own resolv.conf, which NetworkManager still writes normally there).
  dns_client = <<-SHELL
    set -euo pipefail
    cat > /etc/NetworkManager/conf.d/90-lab-dns.conf <<'EOF'
[global-dns]
searches=example.com

[global-dns-domain-*]
servers=#{primary_ip}
EOF
    systemctl restart NetworkManager
    for _ in $(seq 1 30); do
      getent hosts puppet.example.com >/dev/null 2>&1 && break
      sleep 2
    done
    getent hosts ovdb.example.com >/dev/null || { echo "lab DNS on #{primary_ip} is not answering"; exit 1; }
  SHELL

  # puppetserver defaults to -Xms2g -Xmx2g, which fills a 2GB VM and gets the
  # JVM OOM-killed. A lab setting, not advice.
  puppetserver_heap = <<-SHELL
    set -euo pipefail
    install -d -m 0755 /etc/sysconfig
    sed -i 's/^JAVA_ARGS=.*/JAVA_ARGS="-Xms512m -Xmx1024m -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger"/' \
      /etc/sysconfig/puppetserver
    grep -q 'Xmx1024m' /etc/sysconfig/puppetserver || \
      echo 'JAVA_ARGS="-Xms512m -Xmx1024m"' >> /etc/sysconfig/puppetserver
  SHELL

  # pp_role is an X.509 extension fixed at issue time, so it has to be in
  # csr_attributes.yaml before the first check-in. The GUI surfaces trusted
  # facts, and it is the conventional way to tell estate roles apart.
  csr_attributes = lambda do |role|
    <<-SHELL
      install -d -m 0755 /etc/puppetlabs/puppet
      cat > /etc/puppetlabs/puppet/csr_attributes.yaml <<'EOF'
---
extension_requests:
  pp_role: #{role}
EOF
    SHELL
  end

  # r10k from a file:// remote against this repo's own .git, synced read-only
  # (the codavox-lab pattern): the loop is commit -> deploy, no push needed,
  # and r10k still deploys a real resolved tree from a committed branch.
  r10k_setup = <<-SHELL
    set -euo pipefail
    dnf install -y -q git
    /opt/puppetlabs/puppet/bin/gem list -i r10k >/dev/null 2>&1 || \
      /opt/puppetlabs/puppet/bin/gem install r10k --no-document
    install -d -m 0755 /etc/puppetlabs/r10k
    cat > /etc/puppetlabs/r10k/r10k.yaml <<'EOF'
---
cachedir: '/var/cache/r10k'

sources:
  control:
    remote: 'file:///vagrant-src/.git'
    basedir: '/etc/puppetlabs/code/environments'
EOF
    # git refuses file:// clones of a repo owned by another uid unless told
    # the path is trusted; the synced mount is owned by the host user.
    git config --global --add safe.directory /vagrant-src
    git config --global --add safe.directory /vagrant-src/.git
    /opt/puppetlabs/puppet/bin/r10k deploy environment -v -p
  SHELL

  # ---------------------------------------------------------------- primary ----
  config.vm.define "puppet" do |node|
    node.vm.hostname = "puppet.example.com"
    node.vm.network "private_network", ip: primary_ip

    node.vm.provider "parallels" do |prl|
      # puppetserver (1 GB heap) + OpenVoxDB JVM + PostgreSQL.
      prl.memory = 3072
      prl.cpus = 2
    end

    node.vm.synced_folder ".", "/vagrant-src", mount_options: ["ro"]

    node.vm.provision "shell", inline: common
    node.vm.provision "shell", inline: csr_attributes.call("openvox_server")
    node.vm.provision "shell", inline: <<-SHELL
      set -euo pipefail

      grep -q '# openvox-gui-lab' /etc/hosts || cat >> /etc/hosts <<'EOF'
# openvox-gui-lab
#{hosts}
EOF

      # DNS for the estate. dnsmasq serves an explicit hosts file — not
      # /etc/hosts, which carries Vagrant's own "127.0.1.1 puppet.example.com"
      # line and would tell every node the primary lives at loopback (on the
      # compiler that loopback address answers with the wrong certificate).
      # The file lives outside /etc/dnsmasq.d, which dnsmasq reads as config.
      # Upstream queries follow this node's own resolv.conf.
      dnf install -y -q dnsmasq
      cat > /etc/openvox-gui-lab.hosts <<'EOF'
#{lab_hosts}
EOF
      cat > /etc/dnsmasq.d/openvox-gui-lab.conf <<'EOF'
listen-address=#{primary_ip}
bind-interfaces
domain=example.com
no-hosts
addn-hosts=/etc/openvox-gui-lab.hosts
EOF
      systemctl enable --now dnsmasq

      dnf install -y -q openvox-server

      /opt/puppetlabs/bin/puppet config set --section main certname puppet.example.com
      /opt/puppetlabs/bin/puppet config set --section main server puppet.example.com
      # The CA certificate must be valid for the names the console uses:
      # ovca.example.com (CA HTTP API) and ovdb.example.com (OpenVoxDB reuses
      # this host's certificate).
      /opt/puppetlabs/bin/puppet config set --section server dns_alt_names \
        puppet,puppet.example.com,ovca,ovca.example.com,ovdb,ovdb.example.com

#{puppetserver_heap}

      # Only these certnames are autosigned; naming them keeps bring-up
      # non-interactive without accepting anything that asks.
      cat > /etc/puppetlabs/puppet/autosign.conf <<'EOF'
compiler01.example.com
console.example.com
agent01.example.com
EOF

      firewall-cmd --add-service=dns --permanent >/dev/null
      firewall-cmd --add-port=8140/tcp --permanent >/dev/null
      firewall-cmd --add-port=8081/tcp --permanent >/dev/null
      firewall-cmd --add-port=5432/tcp --permanent >/dev/null
      firewall-cmd --reload >/dev/null

      systemctl enable --now puppetserver
      for _ in $(seq 1 60); do
        curl -ks https://localhost:8140/status/v1/simple >/dev/null 2>&1 && break
        sleep 5
      done

#{r10k_setup}

      # First run installs OpenVoxDB + PostgreSQL, wires the termini into
      # puppetserver (restarting it), and opens the CA API to the console.
      # The second run converges what the restart interrupted.
      /opt/puppetlabs/bin/puppet agent -t --waitforlock 60 || true
      for _ in $(seq 1 60); do
        curl -ks https://localhost:8140/status/v1/simple >/dev/null 2>&1 && break
        sleep 5
      done
      /opt/puppetlabs/bin/puppet agent -t --waitforlock 60 || true

      echo "[primary] waiting for OpenVoxDB"
      for _ in $(seq 1 60); do
        curl -ks https://localhost:8081/status/v1/services/puppetdb-status >/dev/null 2>&1 && break
        sleep 5
      done
      systemctl is-active puppetdb || { journalctl -u puppetdb --no-pager -n 30; exit 1; }

      # The agent is left off on every node: this is a lab for watching
      # specific things happen. scripts/converge runs it on demand.
      systemctl disable --now puppet 2>/dev/null || true
    SHELL
  end

  # --------------------------------------------------------------- compiler ----
  config.vm.define "compiler01" do |node|
    node.vm.hostname = "compiler01.example.com"
    node.vm.network "private_network", ip: "192.168.58.11"

    node.vm.provider "parallels" do |prl|
      prl.memory = 2048
      prl.cpus = 2
    end

    # The compiler needs the control repo too: the GUI's Stage/Activate runs
    # r10k here, not on the console.
    node.vm.synced_folder ".", "/vagrant-src", mount_options: ["ro"]

    node.vm.provision "shell", inline: common
    node.vm.provision "shell", inline: dns_client
    node.vm.provision "shell", inline: csr_attributes.call("openvox_compiler")
    node.vm.provision "shell", inline: <<-SHELL
      set -euo pipefail

      dnf install -y -q openvox-server

      firewall-cmd --add-port=8140/tcp --permanent >/dev/null
      firewall-cmd --reload >/dev/null

#{puppetserver_heap}

      /opt/puppetlabs/bin/puppet config set --section main certname compiler01.example.com
      /opt/puppetlabs/bin/puppet config set --section main server puppet.example.com
      /opt/puppetlabs/bin/puppet config set --section main ca_server puppet.example.com

      # A compiler compiles catalogs; it does not issue certificates. This has
      # to happen before the node holds a certificate at all.
      install -d -m 0755 /etc/puppetlabs/puppetserver/services.d
      cat > /etc/puppetlabs/puppetserver/services.d/ca.cfg <<'EOF'
# This node defers certificate signing to the primary.
puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service
EOF

#{r10k_setup}

      # Enrol and converge: OpenVoxDB termini pointed at ovdb.example.com, the
      # console allowed on /status and /metrics, r10k.yaml under management.
      # The bolt user arrives on a later run, once the console has reported
      # its key to OpenVoxDB (scripts/converge).
      /opt/puppetlabs/bin/puppet agent -t --waitforlock 60 || true

      systemctl enable --now puppetserver
      systemctl restart puppetserver
      systemctl disable --now puppet 2>/dev/null || true

      # Do not return until puppetserver answers, or the console's first run
      # races a still-starting JVM.
      for _ in $(seq 1 60); do
        curl -ks https://localhost:8140/status/v1/simple >/dev/null 2>&1 && break
        sleep 5
      done
    SHELL
  end

  # ---------------------------------------------------------------- console ----
  config.vm.define "console" do |node|
    node.vm.hostname = "console.example.com"
    node.vm.network "private_network", ip: "192.168.58.12"

    node.vm.provider "parallels" do |prl|
      # uvicorn workers plus a one-time npm build of the frontend.
      prl.memory = 2048
      prl.cpus = 2
    end

    node.vm.provision "shell", inline: common
    node.vm.provision "shell", inline: dns_client
    node.vm.provision "shell", inline: csr_attributes.call("openvox_console")
    node.vm.provision "shell", inline: <<-SHELL
      set -euo pipefail

      # A dedicated console: agent only. No openvox-server here, on purpose —
      # the GUI reaches the CA over HTTP and the compiler over Bolt.
      dnf install -y -q openvox-agent

      /opt/puppetlabs/bin/puppet config set --section main certname console.example.com
      /opt/puppetlabs/bin/puppet config set --section main server compiler01.example.com
      /opt/puppetlabs/bin/puppet config set --section main ca_server puppet.example.com

      # The GUI runs as 'puppet' and serves TLS with this node's agent
      # certificate. Puppet gives the SSL directory to the puppet user and
      # group when they exist at the start of a run, so create them before
      # the first run rather than waiting for the module to do it a run late.
      getent group puppet >/dev/null || groupadd --system puppet
      id puppet >/dev/null 2>&1 || useradd --system --gid puppet --shell /sbin/nologin --home-dir /opt/openvox-gui puppet

      firewall-cmd --add-port=4567/tcp --permanent >/dev/null
      firewall-cmd --reload >/dev/null

      # First run: enrol, build the frontend, run the installer (which
      # provisions the GUI's database on the primary), then put the GUI into
      # clustered mode through its own API. Second run: this node has now
      # reported its Bolt public key, so it becomes its own orchestration
      # target.
      /opt/puppetlabs/bin/puppet agent -t --waitforlock 60 || true
      /opt/puppetlabs/bin/puppet agent -t --waitforlock 60 || true
      systemctl disable --now puppet 2>/dev/null || true

      for _ in $(seq 1 30); do
        curl -skf https://localhost:4567/health >/dev/null 2>&1 && break
        sleep 4
      done
      curl -skf https://localhost:4567/health || { journalctl -u openvox-gui --no-pager -n 30; exit 1; }
      echo
      echo "[console] https://console.example.com:4567 (admin / see data/common.yaml)"
    SHELL
  end

  # ------------------------------------------------------------------ agent ----
  config.vm.define "agent01" do |node|
    node.vm.hostname = "agent01.example.com"
    node.vm.network "private_network", ip: "192.168.58.13"

    node.vm.provider "parallels" do |prl|
      prl.memory = 768
      prl.cpus = 1
    end

    node.vm.provision "shell", inline: common
    node.vm.provision "shell", inline: dns_client
    node.vm.provision "shell", inline: csr_attributes.call("openvox_agent")
    node.vm.provision "shell", inline: <<-SHELL
      set -euo pipefail

      dnf install -y -q openvox-agent

      /opt/puppetlabs/bin/puppet config set --section main certname agent01.example.com
      /opt/puppetlabs/bin/puppet config set --section main server compiler01.example.com
      /opt/puppetlabs/bin/puppet config set --section main ca_server puppet.example.com

      /opt/puppetlabs/bin/puppet agent -t --waitforlock 60 || true
      systemctl disable --now puppet 2>/dev/null || true
    SHELL
  end
end
