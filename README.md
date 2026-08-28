# openvox-gui-lab

A control repo and Vagrant topology whose only job is to exercise
[OpenVox GUI](https://github.com/cvquesty/openvox-gui)'s **clustered mode** on
real OpenVox nodes — the dedicated-console layout that 3.12 is built around,
which until now had only ever run on its maintainer's estate.

It is laid out the way `INSTALL.md` ("Advanced Installations") describes and
the way the GUI's own `cluster-preflight.sh` checks for: a console that is
not the CA and runs no puppetserver, a compiler the console reaches over
Bolt, OpenVoxDB and the CA behind DNS round-robin names, and real DNS to
serve them.

## Why this exists separately

The dev control-repo runs the GUI **all-in-one** on the OpenVox Server, and
that is the right thing for it to test: it is what most installs look like.
The clustered code paths are different ones — CA over HTTP instead of a local
`puppetserver ca`, Bolt to compilers instead of local r10k, fleet membership
from OpenVoxDB with round-robin names filtered out — and none of them can be
reached from an all-in-one box. The GUI's own container install-test proves
`install.sh` works; this lab proves the estate around it does.

[codavox-lab](https://github.com/miharp/codavox-lab) is the model: one
purpose, EL9, sequential bring-up, roles and profiles, Onceover, `commit →
deploy` with a `file://` r10k remote, and a README that says what to try.

## Topology

All four nodes are EL9 (`bento/rockylinux-9`). Deliberately not EL10, for the
same reason codavox-lab gives: this lab exists to find GUI problems, and EL10's
module-ecosystem gaps surface as failures that look like GUI problems.

| node | IP | runs | `server` / `ca_server` |
|---|---|---|---|
| `puppet` | 192.168.58.10 | CA, OpenVoxDB + PostgreSQL (also the GUI's own database), dnsmasq, r10k, bolt user | itself |
| `compiler01` | 192.168.58.11 | catalog compiler, r10k, bolt user | `puppet` / `puppet` |
| `console` | 192.168.58.12 | OpenVox GUI, OpenBolt, bolt user | `compiler01` / `puppet` |
| `agent01` | 192.168.58.13 | agent, bolt user | `compiler01` / `puppet` |

Two names exist only in DNS, because the GUI treats them specially:
`ovdb.example.com` (OpenVoxDB) and `ovca.example.com` (CA), both resolving to
the primary. The console is configured with those names, they are seeded into
Settings → Cluster as `dns_rr_vips` / `ca_vips`, and the GUI hides them from
the Nodes list because a DNS name is not a computer.

**The primary runs real DNS.** `cluster-preflight.sh` fails when the PuppetDB
host is pinned in `/etc/hosts` (files beat DNS, so round-robin could never
work), so `/etc/hosts` entries for the estate exist only on the primary, where
dnsmasq serves them, and every other node resolves through it (NetworkManager
`global-dns`). External lookups still work: dnsmasq forwards upstream.

`192.168.58.x` so this lab, the `192.168.56.x` dev repo and the
`192.168.57.x` codavox-lab can all be up at once.

### Memory

About **7.9 GB** across the four VMs: 3072 for the primary (puppetserver,
OpenVoxDB, PostgreSQL), 2048 each for the compiler and the console, 768 for
the agent. puppetserver's heap is capped at 1 GB on both servers and
OpenVoxDB's at 512 MB — lab settings, not advice.

## Getting started

```console
vagrant up
```

Bring-up is sequential and takes a while: the console's first Puppet run
builds the GUI's frontend with npm and installs its Python dependencies.

Then:

```console
./scripts/converge     # one more agent run everywhere (see below)
./scripts/verify       # is the estate what the GUI expects?
```

and open <https://console.example.com:4567> (add `192.168.58.12
console.example.com` to your host's `/etc/hosts`, or use the IP). Log in as
`admin` with the password in `data/common.yaml`. Settings → Cluster is already
filled in — saved through the GUI's own API during the console's build, so
the ENC groups that Save seeds (`OpenVox Compiler`, `OpenVoxDB`) exist too.

**Why `converge` after `up`:** the compiler enrols before the console exists.
Its bolt user is created from the console's public key, collected from
OpenVoxDB through the `openvox_gui_bolt_pubkey` fact — and a node uploads
its facts at the *start* of a run, so the key reaches OpenVoxDB during the
console's run and the compiler can only see it on a run after that.
`converge` runs the agent on every node in that order (primary, console,
compiler, agent); it is also the way to apply any change you deploy.

## How the pieces fit

- **Console** — `profile::console`. Agent only. Installs the GUI (the
  3.12.1 dev train: 3.12.0's installer cannot use EL9's python3.12, see
  `data/common.yaml`) with the
  [miharp/openvox_gui](https://github.com/miharp/puppet-openvox_gui) module:
  `puppet_server_host` is the compiler, `puppetdb_host` is `ovdb.example.com`,
  `PUPPET_CA_HOST` is `ovca.example.com`. `configure_bolt` creates the
  console's bolt user and SSH key. The GUI's own database is PostgreSQL on
  the primary (`OPENVOX_GUI_DB_BACKEND`): the installer provisions role,
  database and schema itself with its `bootstrap-openvox-gui-db.sh`,
  connecting as a superuser the primary carries for that purpose. Cluster
  mode is set once by driving Settings → Cluster → Save
  (`openvox-gui-seed-cluster`, `PUT /api/config/cluster`) while the GUI is
  not yet clustered; the GUI owns the result afterwards.
- **Primary** — `profile::primary`. OpenVoxDB with the EL9 PostgreSQL, which
  also holds the GUI's `openvox_gui` database (the runbook's layout: one
  instance, two databases) and listens on the network for it. Its
  certificate carries `ovca`/`ovdb` SANs (set during provisioning) so the CA
  API and OpenVoxDB can be reached by those names. auth.conf rules allow the
  console's certname on the CA API (`certificate_status` and friends) — the
  stock rules allow nobody there.
- **Both servers** — `profile::openvox_server`. auth.conf rules allow the
  console on `/status` (member health) and `/metrics` (dashboard JVM data).
- **Compiler** — `profile::compiler`. OpenVoxDB termini pointed at
  `ovdb.example.com` (the GUI's fleet follows OpenVoxDB: a compiler not
  wired to it hides every node it serves), r10k and an `r10k.yaml` because
  Stage/Activate runs r10k *here*, over Bolt, and the GUI's classifier
  (`openvox_gui::enc`): puppetserver runs `enc.py` at compile time, which
  asks the console at `https://console.example.com:4567`. The console URLs
  are derived from the same `console_certnames` list that opens the
  status endpoints. `enc.py` answers with an empty classification when no
  console responds, so this is on from the compiler's first run: until
  the console exists, nodes get only what `site.pp` gives them (and each
  compile waits out one ten-second timeout while the console host is
  unreachable, none once it merely refuses).
- **Every target** — `profile::bolt_target`. Wraps
  `openvox_gui::bolt_target` and adds the sudoers rule the module leaves to
  the operator.

r10k deploys from `file:///vagrant-src/.git` on both servers, the codavox-lab
pattern: commit on the host, deploy, watch it land — no push. Uncommitted
changes are invisible to the fleet, which is the point.

## Things worth trying

### Stage, then Activate

Change `profile::base::marker_content` in `data/common.yaml`, commit, then in
the GUI: Code Deployment → **Stage** → **Activate**. That uploads
`r10k-stage-activate.sh` to the compiler's `/home/bolt/.bolt/tmp` over Bolt
and runs r10k there as root. Then:

```console
./scripts/converge agent01
vagrant ssh agent01 -c 'cat /etc/openvox-gui-lab-marker'
```

`./scripts/deploy` does the r10k part out of band if you want to compare.

### Run a command on the fleet

Nodes → pick `agent01` → Run Command → `sudo systemctl status puppet`. It
goes console → `bolt@agent01` → sudoers rule from `profile::bolt_target`.

### Classify a node from the GUI

`profile::enc_marker` is declared nowhere in this repository; it exists
to be handed out by the GUI. Classification & Code → Classification →
create a group (environment `production`) with class `profile::enc_marker`
and, if you like, parameter `content`, and add `agent01.example.com` to
it. Then:

```console
./scripts/converge agent01
vagrant ssh agent01 -c 'cat /etc/openvox-gui-lab-enc-marker'
```

`compiler01` and `puppet` are already classified, into the `OpenVox
Compiler` and `OpenVoxDB` groups that Settings → Cluster → Save seeds.
(Save refuses clustered mode on SQLite; the GUI's own database being
PostgreSQL is what makes it, and this whole page, work.)

What happened: the agent asked `compiler01` for a catalog, puppetserver
ran `/usr/local/bin/enc.py agent01.example.com`, the script asked the
console's `/api/enc/classify/agent01.example.com/yaml`, and the class
and parameter came back merged with what `site.pp` declares. The same
YAML, straight from either end:

```console
vagrant ssh compiler01 -c 'sudo sh -c "set -a; . /etc/sysconfig/openvox-enc; /usr/local/bin/enc.py agent01.example.com"'
vagrant ssh console -c 'curl -sk https://localhost:4567/api/enc/classify/agent01.example.com/yaml'
```

Stop the GUI (`vagrant ssh console -c 'sudo systemctl stop openvox-gui'`)
and converge again: the run still succeeds and the marker stays — the
ENC returns an empty classification, and Puppet leaves an unmanaged file
alone. A stopped service refuses instantly; only an unreachable console
*host* costs each compile the script's ten-second timeout.

### Member health by FQDN, not VIP

Settings → Services shows the compiler's `:8140`, OpenVoxDB's `:8081` and the
CA per member. Stop one and watch it go red:

```console
vagrant ssh compiler01 -c 'sudo systemctl stop puppetserver'
```

### The preflight that this lab was designed around

```console
vagrant ssh console -c 'sudo /opt/openvox-gui/scripts/cluster-preflight.sh'
```

Pin `ovdb.example.com` in the console's `/etc/hosts` and run it again to see
the check that made real DNS non-negotiable.

### CA from a console that has no CA

Certificates → the list comes from the CA HTTP API at `ovca.example.com`,
authenticated with the console's agent cert and allowed by the auth.conf rule
in `profile::primary`. Comment that rule out, `converge puppet`, and the page
goes empty — the failure mode `TROUBLESHOOTING.md` describes.

## Testing without VMs

```console
bundle install
bundle exec onceover run spec
```

Onceover compiles every role against a real EL9 factset (captured from
codavox-lab VMs; the console's is derived from the agent's). It proves a role
is *valid* — **not** that any node is classified into it. `manifests/site.pp`
owns that, and the two are kept in agreement by hand.

`profile::bolt_target` collects keys with `puppetdb_query`, which Onceover does
not have; it detects that and declares nothing, which is also what a real
target sees until the console has reported its key.

## What is deliberately not here (yet)

- **An HAProxy compiler frontend** (`ovcompilers.example.com`) and a second
  compiler. The GUI has specific rules for that name (it *is* a node, unlike
  the round-robin names) and coordinated cutover only means something with
  two compilers. The rest of phase 2 (the GUI's classifier on the compiler
  was the first half).
- **A second OpenVoxDB and the two Spock meshes** from
  `docs/CLUSTERED_SHARED_DB.txt`. The GUI's own database is already
  PostgreSQL (the first half of phase 3); replicating it and OpenVoxDB
  across sites is the rest — the runbook was written from a week of field
  failures, which is exactly what a lab should be able to reproduce on
  purpose.

## Layout

| path | what |
|---|---|
| `Vagrantfile` | the four nodes, DNS, and their provisioning |
| `Puppetfile` | component modules, including `openvox_gui` pinned by tag |
| `manifests/site.pp` | node definitions; keep in step with onceover |
| `data/` | Hiera; versions, credentials, OpenVoxDB and PostgreSQL settings |
| `site-modules/profile/` | `base`, `openvox_agent`, `openvox_server`, `primary`, `compiler`, `console`, `bolt_target`, `enc_marker` (assigned from the GUI only) |
| `site-modules/role/` | `primary`, `compiler`, `console`, `agent` |
| `scripts/converge` | run the agent on every node, in order |
| `scripts/verify` | GUI health, login, cluster mode, member health, database, fleet count, Bolt, ENC, preflight |
| `scripts/deploy` | r10k on both servers, out of band |
