#!/usr/bin/env bash
set -euo pipefail

echo "Checking DNS for grafana.ok..."
dig +short grafana.ok || true

echo "Checking NodePort from tailnet (should succeed if on VPN)..."
NC_TARGET=${GRAFANA_NODE_TS_IP:-}
if [ -n "$NC_TARGET" ]; then
  nc -vz "$NC_TARGET" 30443 || true
fi

echo "Checking Wasabi buckets..."
if [ -n "${WASABI_ENDPOINT:-}" ]; then
  aws --endpoint-url "$WASABI_ENDPOINT" s3 ls || true
fi

echo "Done."

