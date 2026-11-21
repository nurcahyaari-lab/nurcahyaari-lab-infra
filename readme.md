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

The VMs are on the home network (`192.168.1.x`). From outside, I reach them through Tailscale, so ssh and kubectl work directly, no `-J pve` needed:

```sh
ssh ubuntu@192.168.1.21
kubectl get nodes
```

The jump way still works if Tailscale is down:

```sh
ssh -J pve ubuntu@192.168.1.21
```

(`pve` is in `~/.ssh/config`)

## Reaching the LAN with Tailscale

Only the Proxmox host (`pve`) has Tailscale. The VMs don't. So pve acts as a subnet router: it tells my tailnet "send traffic for `192.168.1.x` to me", and then forwards it to the LAN.

There's 3 steps, and the order matters:

1. **Install Tailscale on pve, by hand.** This one stays manual. pve has no public ip, so ansible reaches it through Tailscale. No Tailscale = no ansible. Chicken and egg. Do this from home, on pve as root:

   ```sh
   curl -fsSL https://tailscale.com/install.sh | sh
   tailscale up
   ```

2. **Ansible** turns on ip forwarding and advertises `192.168.1.0/24`:

   ```sh
   cd ansible
   ansible-playbook playbooks/tailscale_subnetting.yaml
   ```

3. **Terraform** approves the route in the Tailscale admin console, and turns off key expiry for pve:

   ```sh
   cd terraform
   tofu apply
   ```

   Advertising alone isn't enough, the route stays pending until it's approved. And key expiry matters, without disabling it pve logs out of Tailscale after 180 days and I lose remote access to everything.

   Terraform needs a Tailscale OAuth client for this (admin console > Settings > OAuth clients, scopes `devices:core` and `devices:routes` write). Put it in `terraform/.env` as `TAILSCALE_OAUTH_CLIENT_ID` and `TAILSCALE_OAUTH_CLIENT_SECRET`.

The subnet is written in 2 places, `tailscale_routes` in `terraform/variables.tf` and `tailscale_advertise_routes` in `ansible/inventory/group_vars/proxmox.yaml`. Keep them the same.

Also, terraform sets the **full** list of approved routes for pve. If I approve something else by hand later (like an exit node), the next `tofu apply` removes it. Add it to `tailscale_routes` instead.

On the laptop, mac accepts routes by default. On linux you need `tailscale set --accept-routes`.

Check it:

```sh
ping 192.168.1.21
ssh ubuntu@192.168.1.21
```

If ping doesn't work, it's usually the route isn't approved yet, or ip forwarding is off on pve (`sysctl net.ipv4.ip_forward` should say `1`).

Heads up, this exposes the whole `192.168.1.0/24` to my tailnet, not only the VMs. So router, NAS, everything on the LAN. Fine for me since it's only my devices, but keep it in mind before sharing the tailnet with someone.

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
