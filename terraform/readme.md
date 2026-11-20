# terraform

This makes the VMs on Proxmox. It's written for OpenTofu (`tofu`), but `terraform` works the same.

It does 3 things:

- downloads the Ubuntu 24.04 cloud image to Proxmox (`proxmox/image.tf`)
- creates a VM for each entry in `vms` (`proxmox/vms.tf`)
- sets up each VM with cloud-init: static ip, dns, the `ubuntu` user, your ssh key and a password

It does **not** install anything inside the VMs. That's ansible's job, see [../ansible](../ansible/README.md).

## Files

```
main.tf                    provider, state backend, calls the proxmox module
variables.tf               all the inputs
outputs.tf                 prints the vm ips after apply
terraform.tfvars           your real values (not in git)
terraform.tfvars.example   copy this to start
.env                       secrets (not in git)
.env.example               copy this to start
proxmox/                   the module that actually makes the VMs
```

## First time setup

You need a few things first:

1. **A Proxmox API token.** In the Proxmox UI go to Datacenter > Permissions > API Tokens and make one. It looks like `user@pve!tokenid=xxxxxxxx-...`

2. **Your ssh key on the Proxmox host.** Some parts of the provider ssh into Proxmox as root, using your ssh-agent. Check that `ssh root@<proxmox ip>` works without a password.

3. **Bucket credentials for the state.** State is stored in a Cloudflare R2 bucket (`homelab-tfstate`), not on your laptop. You need an R2 access key for it.

Then copy the example files and fill them in:

```sh
cp terraform.tfvars.example terraform.tfvars
cp .env.example .env
```

In `.env` put the R2 keys (as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, R2 speaks the S3 api), the R2 endpoint (`AWS_ENDPOINT_URL_S3`, it has your Cloudflare account id in it), the Proxmox token and the VM password.

In `terraform.tfvars` put the Proxmox url, gateway, your ssh public key and the VM list.

## Running it

Load the secrets first, otherwise tofu can't reach the state bucket:

```sh
set -a; source .env; set +a

tofu init      # only first time, or after changing providers
tofu plan      # see what it will do
tofu apply     # do it
```

After apply it prints the ips of the VMs.

## Adding or changing a VM

Just edit the `vms` map in `terraform.tfvars`:

```hcl
vms = {
  "k8s-cp" = {
    vm_id   = 201
    cores   = 2
    memory  = 4096   # MB
    disk_gb = 40
    ip      = "192.168.1.21/24"
  }
  ...
}
```

Pick ips outside your router's dhcp range, so nothing else grabs them.

Then `tofu plan` and `tofu apply`. Don't forget to add the new VM to the ansible inventory too.

## Watch out

- **Always read the plan.** Some changes (like disk or cloud-init stuff) can make tofu **replace** the VM instead of updating it. Replace = the VM is deleted and made again, everything inside is gone. If the plan says `must be replaced` on a VM you care about, stop and think.
- **Don't commit `terraform.tfvars` or `.env`.** They have secrets in them. `.gitignore` already skips them, just don't force add them.
- The VM password is only for the Proxmox console (when ssh is broken). Ssh is key only.
