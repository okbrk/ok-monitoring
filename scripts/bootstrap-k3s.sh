#!/usr/bin/env bash
set -euo pipefail

ROLE=${1:-server}
# The private IP of the node must be passed as the second argument
NODE_IP=${2:?NODE_IP is required as the second argument}
K3S_VERSION=${K3S_VERSION:-"v1.30.4+k3s1"}

# Base flags for both server and agent to ensure private networking
INSTALL_K3S_EXEC="--flannel-iface=enp7s0 --node-ip=${NODE_IP}"

if [ "$ROLE" = "server" ]; then
  # Server-specific flags
  INSTALL_K3S_EXEC="server --disable traefik --disable metrics-server --bind-address=${NODE_IP} ${INSTALL_K3S_EXEC}"
else
  # Agent-specific flags
  INSTALL_K3S_EXEC="agent --server $K3S_URL --token $K3S_TOKEN ${INSTALL_K3S_EXEC}"
fi

# Execute the installer
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION sh -s - ${INSTALL_K3S_EXEC}

echo "k3s $ROLE installed on node with IP ${NODE_IP}"

