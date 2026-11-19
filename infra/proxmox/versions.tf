# Child module: declares which provider it needs. The provider itself
# (endpoint, token, ssh) is configured in the root module (infra/main.tf).
terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}
