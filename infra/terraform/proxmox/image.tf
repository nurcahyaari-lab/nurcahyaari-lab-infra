resource "proxmox_download_file" "ubuntu_noble" {
  file_name    = "noble-server-cloudimg-amd64.img"
  node_name    = var.node_name
  datastore_id = var.image_datastore
  content_type = "iso"

  url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}