variable "proxmox_endpoint" {
  description = "Proxmox API URL, e.g. https://192.168.1.10:8006/ (or the Tailscale IP)"
  type        = string
}

variable "proxmox_api_token" {
  description = "API token in the form user@pve!tokenid=secret"
  type        = string
  sensitive   = true
}

variable "node_name" {
  description = "Proxmox node name (shown in the left tree of the web UI)"
  type        = string
  default     = "pve"
}

variable "vm_datastore" {
  description = "Storage for VM disks (Datacenter -> Storage). Often local-lvm, or your ZFS pool"
  type        = string
  default     = "local-lvm"
}

variable "image_datastore" {
  description = "Storage that can hold ISO images (usually local)"
  type        = string
  default     = "local"
}

variable "bridge" {
  description = "Network bridge the VMs attach to"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "LAN gateway (your router), e.g. 192.168.1.1"
  type        = string
}

variable "dns_servers" {
  description = "DNS servers for the VMs"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "ssh_public_key" {
  description = "Public key put on every VM so you and Ansible can SSH in"
  type        = string
}

variable "vms" {
  description = "VM spec sheet. Add an entry here to create another VM."
  type = map(object({
    vm_id   = number
    cores   = number
    memory  = number # MB
    disk_gb = number
    ip      = string # CIDR, e.g. 192.168.1.21/24
  }))
}