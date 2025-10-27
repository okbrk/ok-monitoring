resource "hcloud_server" "observability" {
  name        = "ok-obs-01"
  image       = local.image
  server_type = local.server_type
  location    = local.location

  ssh_keys = [data.hcloud_ssh_key.main.id]

  # Temporarily disable firewall to debug connectivity issues
  # TODO: Re-enable after fixing outbound rules
  # firewall_ids = [hcloud_firewall.observability.id]

  user_data = templatefile("${path.module}/cloud-init.yaml", {
    ssh_pub_key = data.hcloud_ssh_key.main.public_key
  })

  labels = {
    role = "observability"
    env  = "prod"
  }
}

# Note: Block volume removed - using Wasabi S3 for storage
# Local CPX32's 160GB SSD used for cache and temporary data


