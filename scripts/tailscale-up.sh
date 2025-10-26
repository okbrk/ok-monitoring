#!/usr/bin/env bash
set -euo pipefail

if ! command -v tailscale >/dev/null; then
  echo "Installing Tailscale..."
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
  sudo apt-get update && sudo apt-get install -y tailscale
fi

sudo systemctl enable --now tailscaled

if [ -z "${TS_AUTHKEY:-}" ]; then
  echo "TS_AUTHKEY is required" >&2
  exit 1
fi

sudo tailscale up \
  --authkey "${TS_AUTHKEY}" \
  --ssh \
  --advertise-routes=10.42.0.0/16,10.43.0.0/16 \
  --accept-dns=false

IP=$(tailscale ip -4 | head -n1)
echo "Tailscale up. IPv4: $IP"

