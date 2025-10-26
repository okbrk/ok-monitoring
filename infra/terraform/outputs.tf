output "node_public_ips" {
  description = "Public IPv4 of nodes"
  value       = [for s in hcloud_server.nodes : s.ipv4_address]
}

output "node_private_ips" {
  description = "Private IPv4 of nodes"
  value       = [for a in hcloud_server_network.nodes_net : a.ip]
}

output "network_id" {
  description = "Hetzner network ID"
  value       = hcloud_network.main.id
}


