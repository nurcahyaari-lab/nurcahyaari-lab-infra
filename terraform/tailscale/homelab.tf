data "tailscale_device" "homelab" {
  hostname = "homelab"
}

resource "tailscale_device_subnet_routes" "homelab" {
  device_id = data.tailscale_device.homelab.node_id
  routes    = var.routes
}

resource "tailscale_device_key" "homelab" {
  device_id           = data.tailscale_device.homelab.node_id
  key_expiry_disabled = true
}
