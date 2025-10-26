variable "hcloud_token" {
  type        = string
  description = "Hetzner Cloud API token"
  sensitive   = true
}

variable "ssh_key_name" {
  type        = string
  description = "Existing SSH key name in Hetzner Cloud"
}

variable "location" {
  type        = string
  description = "Hetzner DC location (hel1|nbg1)"
  default     = "nbg1"
}

variable "my_ip_cidr" {
  type        = string
  description = "Your IP in CIDR for SSH allow-list (e.g., 1.2.3.4/32)"
}

variable "server_type" {
  type        = string
  description = "Hetzner server type"
  default     = "cax11"
}

variable "image" {
  type        = string
  description = "Base image name"
  default     = "ubuntu-24.04"
}


