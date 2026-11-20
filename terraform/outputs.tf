output "vm_ips" {
  description = "IP of each VM (handy for the Ansible inventory)"
  value       = module.proxmox.vm_ips
}
