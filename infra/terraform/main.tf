terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.123.1" # x-release-please-version
    }
  }

  backend "s3" {
    bucket = "homelab-tfstate"
    region = "auto"
    endpoints = {
      s3 = "https://<CLOUDFLARE_ACCOUNT_ID>.r2.cloudflarestorage.com"
    }
    key = "terraform.tfstate"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
    use_lockfile                = true # remove this line if R2 rejects locking
  }
}

# Providers are configured once here and inherited by the child modules.
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true # Proxmox uses a self-signed certificate

  # A few provider features use SSH to the host. Uses your local ssh-agent key.
  ssh {
    agent    = true
    username = "root"

    # By default the provider SSHes to the node's LAN IP as reported by Proxmox,
    # which is unreachable off the home network. Reuse the endpoint's host instead.
    node {
      name    = var.node_name
      address = regex("^https?://([^:/]+)", var.proxmox_endpoint)[0]
    }
  }
}

module "proxmox" {
  source = "./proxmox"

  node_name       = var.node_name
  vm_datastore    = var.vm_datastore
  image_datastore = var.image_datastore
  bridge          = var.bridge
  gateway         = var.gateway
  dns_servers     = var.dns_servers
  ssh_public_key  = var.ssh_public_key
  vm_password     = var.vm_password
  vms             = var.vms
}

# module "tailscale" {
#   source = "./tailscale"
# }
