resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name      = each.key
  node_name = var.node_name
  vm_id     = each.value.vm_id
  on_boot   = true # start automatically when the host boots

  agent {
    enabled = false
  }
  stop_on_destroy = true

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  operating_system {
    type = "l26"
  }

  disk {
    datastore_id = var.vm_datastore
    file_id      = proxmox_download_file.ubuntu_noble.id
    interface    = "virtio0"
    size         = each.value.disk_gb
    discard      = "on"
  }

  network_device {
    bridge = var.bridge
  }

  serial_device {}

  initialization {
    datastore_id = var.vm_datastore

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = "ubuntu"
      keys     = [trimspace(var.ssh_public_key)]
      password = var.vm_password
    }
  }

}