#!/usr/bin/env bash
set -euo pipefail

if [ -z "${WASABI_ENDPOINT:-}" ]; then
  echo "WASABI_ENDPOINT required" >&2
  exit 1
fi

BUCKETS=(loki-logs tempo-traces mimir-metrics grafana-backups)
for b in "${BUCKETS[@]}"; do
  if ! aws --endpoint-url "$WASABI_ENDPOINT" s3api head-bucket --bucket "${b}" >/dev/null 2>&1; then
    echo "Bucket ${b} not found. Creating..."
    aws --endpoint-url "$WASABI_ENDPOINT" s3 mb "s3://${b}"
  else
    echo "Bucket ${b} already exists."
  fi
done

# Simple lifecycle examples
cat > /tmp/lifecycle-logs.json <<EOF
{"Rules":[{"ID":"expire-logs","Status":"Enabled","Expiration":{"Days":120}}]}
EOF
aws --endpoint-url "$WASABI_ENDPOINT" s3api put-bucket-lifecycle-configuration --bucket loki-logs --lifecycle-configuration file:///tmp/lifecycle-logs.json

cat > /tmp/lifecycle-traces.json <<EOF
{"Rules":[{"ID":"expire-traces","Status":"Enabled","Expiration":{"Days":14}}]}
EOF
aws --endpoint-url "$WASABI_ENDPOINT" s3api put-bucket-lifecycle-configuration --bucket tempo-traces --lifecycle-configuration file:///tmp/lifecycle-traces.json

