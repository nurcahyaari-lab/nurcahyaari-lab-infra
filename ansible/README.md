# ansible

This sets up the VMs that [terraform](../terraform/readme.md) made. Terraform gives you empty Ubuntu machines, this turns them into a kubernetes cluster.

Right now it does:

- hostname and `/etc/hosts` on all machines, so they can find each other by name
- kernel modules and network settings kubernetes needs
- containerd (the thing that actually runs containers)
- kubeadm, kubelet, kubectl
- creates the cluster on `k8s-cp`, installs Calico for pod networking, and joins `k8s-worker`
- makes `pve` a Tailscale subnet router so I can reach the LAN from outside
- monitoring on the `monitoring` VM: Prometheus, Alertmanager (sends to Telegram), Grafana, and pve-exporter for Proxmox numbers. `monitoring` and `pve` also get node_exporter

## Getting ansible to run

You need ansible-core with **python 3.13 or newer** on your laptop. If you get an error like `Ansible requires Python 3.13`, your ansible is running on an older python.

I run ansible from a git clone in `~/Documents/projects/tools/ansible`, so every new terminal I do:

```sh
source ~/Documents/projects/tools/ansible/venv/bin/activate
source ~/Documents/projects/tools/ansible/hacking/env-setup -q
```

If you installed ansible some other way (pip, pipx, brew), skip that.

Then install the extra collections once:

```sh
ansible-galaxy collection install -r requirements.yaml
```

If that fails with `~/.netrc access too permissive`, run `chmod 600 ~/.netrc` and try again.

**Always run commands from this folder.** That's how ansible finds `ansible.cfg`, and without it it won't know where the inventory is.

## How ssh works here

You can't reach the VMs directly, so ansible jumps through the Proxmox host. It's the same as:

```sh
ssh -J pve ubuntu@192.168.1.21
```

That's set in `inventory/group_vars/all.yaml`. With Tailscale up the jump isn't really needed anymore, but I keep it so ansible still works when Tailscale is down. If `ansible all -m ping` fails, try that ssh command by hand first. If that doesn't work either, it's an ssh problem not an ansible problem.

## Folders

```
ansible.cfg              settings, points to the inventory
requirements.yaml        extra collections we need
inventory/
  hosts.ini              the machines and their groups
  group_vars/all.yaml    settings for every machine (ssh user, key, jump host)
  group_vars/k8s.yaml    kubernetes settings (version, pod ip range, calico version)
  group_vars/monitoring/  monitoring.yaml (versions, memory limits) + monitoring-vault.yml (secrets)
  group_vars/proxmox.yaml     pve settings (no jump host, tailscale routes)
playbooks/               which roles run on which machines
roles/                   the actual steps
```

Quick way to think about it:

- **inventory** = which machines
- **roles** = how to do a job
- **playbooks** = which job on which machines

`group_vars/<name>.yaml` gets loaded automatically for the group with that name. So `k8s.yaml` only applies to machines in `[k8s]`. Don't rename the folder to `group-vars`, ansible only looks for `group_vars`.

Every task in the roles has a `Manual:` comment above it with the shell command that does the same thing by hand. Handy when something breaks and you want to try it yourself.

## Playbooks

They run in this order (`site.yaml` runs all of them):

| playbook | runs on | what it does |
| --- | --- | --- |
| `common.yaml` | all | hostname, /etc/hosts, basic packages |
| `k8s_prerequisite.yaml` | k8s | kernel modules + sysctl |
| `container_runtime.yaml` | k8s | containerd |
| `k8s_init.yaml` | k8s | installs kubeadm, kubelet, kubectl |
| `k8s_cluster.yaml` | control_plane, then worker | kubeadm init, calico, kubeadm join |
| `tailscale_subnetting.yaml` | proxmox | ip forwarding + advertise the LAN route |
| `monitoring.yaml` | monitoring + proxmox | node_exporter, then prometheus, alertmanager, grafana, pve-exporter |

`k8s_cluster.yaml` has to run as a whole. The control plane makes a join command and the worker uses it in the same run, so if you `--limit` to only the worker it'll fail.

## Monitoring

Everything runs on the `monitoring` VM (192.168.1.23) as plain systemd services. Prometheus and Alertmanager come from the GitHub release tarball (checksum checked), Grafana from Grafana's apt repo, pve-exporter from pip in a venv. Versions are pinned in `group_vars/monitoring/monitoring.yaml`. To upgrade, I just bump the version there and run the playbook again.

| service | port | what it is |
| --- | --- | --- |
| prometheus | 9090 | collects the metrics |
| alertmanager | 9093 | sends alerts to Telegram |
| grafana | 3000 | dashboards, login is `admin` + the vault password |
| pve-exporter | 9221 (localhost only) | asks the Proxmox API for VM/storage numbers |
| node_exporter | 9100 | on `monitoring` and `pve`, machine CPU/mem/disk |

Before running `monitoring.yaml` I need a few things ready:

1. **Secrets in Ansible Vault.** `group_vars/monitoring/monitoring.yaml` reads `vault_grafana_admin_password`, `vault_telegram_bot_token` and `vault_pve_token_value`. I put them in a vault file next to it:

   ```sh
   mkdir -p inventory/group_vars/monitoring
   mv inventory/group_vars/monitoring.yaml inventory/group_vars/monitoring/monitoring.yaml
   ansible-vault create inventory/group_vars/monitoring/monitoring-vault.yml
   ```

   Then run the playbooks with `--ask-vault-pass`.

2. **A read-only Proxmox token** for pve-exporter. On pve:

   ```sh
   pveum user add prometheus@pve
   pveum acl modify / --users prometheus@pve --roles PVEAuditor
   pveum user token add prometheus@pve monitoring --privsep 0
   ```

   The last one prints the token value once. That goes in vault as `vault_pve_token_value`.

3. **The kubernetes token for Prometheus.** Prometheus scrapes the cluster from outside, so it needs a service account token. Ansible reads it with `kubectl` on my laptop (context `homelab`), from the `external-prometheus-token` secret in the `monitoring` namespace. So that secret has to exist in the cluster first, and my kubeconfig needs the `homelab` context.

4. **The config files** live in the manifests repo, in `nurcahyaari-lab-manifests/monitoring/config/`: `prometheus/prometheus.yml`, `prometheus/rules/`, `alertmanager/alertmanager.yml`, `grafana/datasource.yml`. By default Ansible looks for that repo next to this one. If you cloned it somewhere else, set `MONITORING_CONFIG_DIR` to its `monitoring/config` folder (for example `export MONITORING_CONFIG_DIR=~/code/nurcahyaari-lab-manifests/monitoring/config`). The path is `monitoring_config_dir` in `group_vars/monitoring/monitoring.yaml`. `prometheus.yml` and `alertmanager.yml` get checked with promtool/amtool before they're installed, so a broken config won't replace the working one.

Then:

```sh
ansible-playbook playbooks/monitoring.yaml --ask-vault-pass
```

If I only changed a config file, the services get a reload, not a restart. Prometheus keeps its data either way.

## Running it

```sh
ansible all -m ping                              # can we reach everything?
ansible-playbook playbooks/site.yaml --syntax-check
ansible-playbook playbooks/site.yaml             # do everything
```

Or one at a time, which is nicer the first time:

```sh
ansible-playbook playbooks/common.yaml
ansible-playbook playbooks/k8s_prerequisite.yaml
ansible-playbook playbooks/container_runtime.yaml
ansible-playbook playbooks/k8s_init.yaml
ansible-playbook playbooks/k8s_cluster.yaml
ansible-playbook playbooks/tailscale_subnetting.yaml
ansible-playbook playbooks/monitoring.yaml --ask-vault-pass
```

Some useful flags:

- `--check --diff` shows what would change without changing it. Works ok for `common` and `k8s_prerequisite`, but later playbooks give fake errors because each step needs the one before it to actually happen.
- `--limit k8s-cp` only runs on one machine
- `-v` or `-vvv` for more output when something's weird

It's fine to run things again. Stuff that's already done just shows `ok`. If a second run shows `changed=0` everywhere, all good.

## Checking it worked

```sh
ansible k8s -b -a "grep SystemdCgroup /etc/containerd/config.toml"   # should be true
ansible k8s -a "kubeadm version -o short"
ansible k8s-cp -a "kubectl get nodes"        # both nodes Ready (give it a minute or two)
ansible k8s-cp -a "kubectl get pods -A"      # calico + coredns should be Running
```

For monitoring:

```sh
ansible monitoring -a "systemctl is-active prometheus alertmanager grafana-server pve-exporter prometheus-node-exporter"   # all active
ansible monitoring -a "curl -s localhost:9090/-/ready"         # Prometheus is Ready
ansible monitoring -a "curl -s localhost:9093/-/ready"         # OK
ansible monitoring -a "curl -s localhost:3000/api/health"      # "database": "ok"
ansible monitoring -a "curl -s 'localhost:9221/pve?target=192.168.1.5'" | grep pve_up   # should be 1
```

Then open http://192.168.1.23:9090/targets, everything should be UP. Grafana is at http://192.168.1.23:3000.

To use kubectl from your laptop:

```sh
scp -J pve ubuntu@192.168.1.21:.kube/config ~/.kube/homelab
KUBECONFIG=~/.kube/homelab kubectl get nodes
```

(this needs the laptop to reach 192.168.1.21:6443. From home it just works, from outside it goes through Tailscale, see [../readme.md](../readme.md#reaching-the-lan-with-tailscale). The jump host doesn't help here, it's only for ssh)

## When things break

- **kubeadm init failed halfway**: run `sudo kubeadm reset -f` on k8s-cp before trying again, otherwise it complains things already exist. Or just roll back the Proxmox snapshot.
- **nodes stay NotReady**: look at `kubectl get pods -n kube-system`. Usually calico isn't up yet or is crashing.
- **pods keep restarting right after init**: check containerd has `SystemdCgroup = true` and was restarted after.
- **`Unsupported parameters` error**: a typo in a module option. The error lists the real names.
- **`couldn't resolve module/action`**: either a typo in the module name or a collection that isn't installed.
- **monitoring playbook fails on `Read the Kubernetes token secret`**: that's `kubectl` on the laptop. Try `kubectl --context homelab -n monitoring get secret external-prometheus-token` by hand.
- **`'vault_...' is undefined`**: forgot `--ask-vault-pass`, or the vault file doesn't have that key.
- **a service won't start**: `journalctl -u <service> -n 50` on the monitoring VM. If it got killed, check `MemoryMax` in `group_vars/monitoring/monitoring.yaml`.
- **`pve_up` is 0**: the token is wrong or doesn't have `PVEAuditor`. Test it with `curl -k -H 'Authorization: PVEAPIToken=prometheus@pve!monitoring=TOKEN' https://192.168.1.5:8006/api2/json/nodes`.

## Adding stuff

**A new machine:** make it with terraform first, then add it to `inventory/hosts.ini` under the right group(s), same name and ip as in terraform. Run the playbooks. A new worker just needs to go under `[k8s]` and `[worker]` and then `k8s_cluster.yaml` will join it.

**A new job** (like setting up monitoring):

1. make `roles/<name>/tasks/main.yaml` with the steps
2. if it needs to restart a service after a config change, put that in `roles/<name>/handlers/main.yaml` and use `notify`
3. make `playbooks/<name>.yaml` that says which group gets the role
4. settings go in `inventory/group_vars/<group>.yaml`
5. add the playbook to `site.yaml`
