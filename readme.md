# infra

Everything to build the homelab lives here. There's two parts:

- `terraform/` sets the VMs on Proxmox (cpu, memory, disk, ip, ssh key)
- `ansible/` sets the configurations, or applications on the VMs (hostname, containerd, kubernetes, etc)

So yeah, terraform provisions the machine and ansible configures the machine

## The machines

| name       | ip           | what it's for            |
| ---------- | ------------ | ------------------------ |
| k8s-cp     | 192.168.1.21 | kubernetes control plane |
| k8s-worker | 192.168.1.22 | kubernetes worker        |
| monitoring | 192.168.1.23 | monitoring |

All of them run Ubuntu 24.04 and you log in as `ubuntu` with the `~/.ssh/homelab` key.

The VMs are only reachable from inside the home network, so from outside you jump through the Proxmox host:

```sh
ssh -J pve ubuntu@192.168.1.21
```

(`pve` is in `~/.ssh/config`)

## Building from zero

1. Make the VMs, see [terraform/readme.md](terraform/readme.md)

   ```sh
   cd terraform
   tofu apply
   ```

2. Set them up, see [ansible/README.md](ansible/README.md)

   ```sh
   cd ansible
   ansible-playbook playbooks/site.yaml
   ```

That's it, at the end you should have a 2 node kubernetes cluster.

## Adding a new VM

You need to touch both sides, they don't know about each other:

1. add it to `vms` in `terraform/terraform.tfvars` and run `tofu apply`
2. add it to `ansible/inventory/hosts.ini` with the same name and ip
3. run the playbooks again

Yeah the ip lives in 2 places right now. If they don't match ansible will try to ssh to the wrong machine, so double check.

## Before doing anything scary

Take a snapshot in Proxmox first. Rolling back a snapshot is way faster than fixing a broken VM or rebuilding it.

```sh
ssh pve
qm snapshot 201 before-something   # k8s-cp
qm snapshot 202 before-something   # k8s-worker
qm rollback 201 before-something   # if it went bad
```
