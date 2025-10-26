#!/usr/bin/env bash
set -euo pipefail

ROLE=${1:-server}
# The private IP of the node must be passed as the second argument
NODE_IP=${2:?NODE_IP is required as the second argument}
# The Tailscale IP is the third, optional argument (only used for the server)
TLS_SAN_IP=${3:-}
K3S_VERSION=${K3S_VERSION:-"v1.30.4+k3s1"}

K3S_ARGS="--flannel-iface=enp7s0 --node-ip=${NODE_IP}"

if [ "$ROLE" = "server" ]; then
  CMD="server"
  K3S_ARGS="${K3S_ARGS} --disable traefik --disable metrics-server --bind-address=0.0.0.0"
  if [ -n "$TLS_SAN_IP" ]; then
    K3S_ARGS="${K3S_ARGS} --tls-san=${TLS_SAN_IP}"
  fi
else
  CMD="agent"
  K3S_ARGS="${K3S_ARGS} --server $K3S_URL --token $K3S_TOKEN"
fi

# Execute the installer
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION sh -s - ${CMD} ${K3S_ARGS}

echo "k3s $ROLE installed on node with IP ${NODE_IP}"

