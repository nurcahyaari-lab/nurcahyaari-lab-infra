
proxmox_endpoint = "https://100.116.185.117:8006/" # Tailscale IP of the Proxmox host; works on or off the home LAN

node_name       = "homelab"
vm_datastore    = "local-lvm"
image_datastore = "local"
bridge          = "vmbr0"

gateway        = "192.168.1.1"
ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICP7UI4GRHg0Rh+ekWIkPo0TJTjTwbwTntMAQGNd5ecX homelab"

# Pick IPs OUTSIDE router's DHCP range.
vms = {
  # Control Plane VM
  "k8s-cp" = {
    vm_id   = 201
    cores   = 2
    memory  = 4096
    disk_gb = 40
    ip      = "192.168.1.21/24"
  }
  # Worker Node VM
  "k8s-worker" = {
    vm_id   = 202
    cores   = 6
    memory  = 16384
    disk_gb = 128
    ip      = "192.168.1.22/24"
  }
  # Monitoring VM
  "monitoring" = {
    vm_id   = 203
    cores   = 1
    memory  = 2048
    disk_gb = 40
    ip      = "192.168.1.23/24"
  }
}
