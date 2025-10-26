resource "hcloud_server" "nodes" {
  count       = 3
  name        = "ok-node-${count.index}"
  image       = local.image
  server_type = local.server_type
  location    = local.location

  ssh_keys = [data.hcloud_ssh_key.main.id]

  firewall_ids = [hcloud_firewall.nodes.id]

  user_data = templatefile("${path.module}/cloud-init.yaml", {
    ssh_pub_key = data.hcloud_ssh_key.main.public_key
    my_ip_cidr  = var.my_ip_cidr
    public_nic  = "ens3"
    private_nic = "ens10"
  })

  labels = {
    role = "observability"
    env  = "prod"
  }
}

resource "hcloud_server_network" "nodes_net" {
  count     = length(hcloud_server.nodes)
  server_id = hcloud_server.nodes[count.index].id
  subnet_id = hcloud_network_subnet.main.id
}


