output "server_public_ip" {
  description = "Public IP of the observability server"
  value       = hcloud_server.observability.ipv4_address
}

output "server_name" {
  description = "Name of the observability server"
  value       = hcloud_server.observability.name
}

output "firewall_id" {
  description = "Firewall ID"
  value       = hcloud_firewall.observability.id
}


