output "vm_ips" {
  description = "IP of each VM (handy for the Ansible inventory)"
  value       = { for name, vm in var.vms : name => split("/", vm.ip)[0] }
}
