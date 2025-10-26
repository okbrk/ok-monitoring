#!/usr/bin/env bash
set -euo pipefail

ROLE=${1:-server}
K3S_VERSION=${K3S_VERSION:-"v1.30.4+k3s1"}

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION sh -s - \
  $( [ "$ROLE" = "server" ] && echo "server --disable traefik" || echo "agent --server $K3S_URL --token $K3S_TOKEN" )

echo "k3s $ROLE installed"

