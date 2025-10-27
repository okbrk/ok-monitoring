resource "hcloud_firewall" "observability" {
  name = "ok-obs-fw"

  # SSH access from maintainer
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = [var.my_ip_cidr]
    description = "SSH from maintainer IP"
  }

  # HTTP/HTTPS for Caddy (Let's Encrypt + customer data ingestion)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "HTTP for Let's Encrypt and redirects"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "HTTPS for public API endpoints"
  }

  # Tailscale UDP for VPN access to admin tools
  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "41641"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Tailscale UDP for VPN"
  }

  # ICMP for health checks
  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "ICMP ping"
  }

  # Allow all outbound traffic
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "All TCP outbound"
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "All UDP outbound"
  }
}


