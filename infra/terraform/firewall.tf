resource "hcloud_firewall" "nodes" {
  name = "ok-nodes-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.my_ip_cidr]
    description = "SSH from maintainer IP"
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "41641"
    source_ips = ["0.0.0.0/0", "::/0"]
    description = "Tailscale UDP"
  }

  rule {
    direction  = "out"
    protocol   = "tcp"
    port       = "443"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description = "DERP over HTTPS outbound"
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
    description = "ICMP ping"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "6443"
    source_ips  = [hcloud_network.main.ip_range]
    description = "k3s API server from private network"
  }

  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "8472"
    source_ips  = [hcloud_network.main.ip_range]
    description = "k3s flannel networking"
  }
}


