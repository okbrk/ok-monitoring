terraform {
  required_version = ">= 1.6.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.46.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

locals {
  node_count   = 3
  server_type  = var.server_type
  image        = var.image
  location     = var.location
  ssh_key_name = var.ssh_key_name
}

data "hcloud_ssh_key" "main" {
  name = local.ssh_key_name
}


