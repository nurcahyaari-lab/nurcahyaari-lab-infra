# ansible

This sets up the VMs that [terraform](../terraform/readme.md) made. Terraform gives you empty Ubuntu machines, this turns them into a kubernetes cluster.

Right now it does:

- hostname and `/etc/hosts` on all machines, so they can find each other by name
- kernel modules and network settings kubernetes needs
- containerd (the thing that actually runs containers)
- kubeadm, kubelet, kubectl
- creates the cluster on `k8s-cp`, installs Calico for pod networking, and joins `k8s-worker`

The `monitoring` VM only gets the basic setup for now.

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

`k8s_cluster.yaml` has to run as a whole. The control plane makes a join command and the worker uses it in the same run, so if you `--limit` to only the worker it'll fail.

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

## Adding stuff

**A new machine:** make it with terraform first, then add it to `inventory/hosts.ini` under the right group(s), same name and ip as in terraform. Run the playbooks. A new worker just needs to go under `[k8s]` and `[worker]` and then `k8s_cluster.yaml` will join it.

**A new job** (like setting up monitoring):

1. make `roles/<name>/tasks/main.yaml` with the steps
2. if it needs to restart a service after a config change, put that in `roles/<name>/handlers/main.yaml` and use `notify`
3. make `playbooks/<name>.yaml` that says which group gets the role
4. settings go in `inventory/group_vars/<group>.yaml`
5. add the playbook to `site.yaml`
