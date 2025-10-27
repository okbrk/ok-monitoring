#!/usr/bin/env bash
set -euo pipefail

if [ -z "${WASABI_ENDPOINT:-}" ]; then
  echo "WASABI_ENDPOINT required" >&2
  exit 1
fi

if [ -z "${DOMAIN:-}" ]; then
  echo "DOMAIN required for unique bucket naming" >&2
  exit 1
fi

# Create unique bucket names using domain (replace dots with dashes)
BUCKET_PREFIX=$(echo "${DOMAIN}" | tr '.' '-')

BUCKETS=(
  "${BUCKET_PREFIX}-loki-logs"
  "${BUCKET_PREFIX}-tempo-traces"
  "${BUCKET_PREFIX}-mimir-metrics"
  "${BUCKET_PREFIX}-grafana-backups"
)

echo "Creating S3 buckets with prefix: ${BUCKET_PREFIX}"

for b in "${BUCKETS[@]}"; do
  if ! aws --endpoint-url "$WASABI_ENDPOINT" --region "$WASABI_REGION" s3api head-bucket --bucket "${b}" >/dev/null 2>&1; then
    echo "Bucket ${b} not found. Creating..."
    aws --endpoint-url "$WASABI_ENDPOINT" --region "$WASABI_REGION" s3 mb "s3://${b}"
    echo "✓ Created bucket: ${b}"
  else
    echo "✓ Bucket ${b} already exists."
  fi
done

# Apply lifecycle policies
echo "Applying lifecycle policies..."

cat > /tmp/lifecycle-logs.json <<EOF
{"Rules":[{"ID":"expire-logs","Status":"Enabled","Expiration":{"Days":30}}]}
EOF
aws --endpoint-url "$WASABI_ENDPOINT" --region "$WASABI_REGION" s3api put-bucket-lifecycle-configuration \
  --bucket "${BUCKET_PREFIX}-loki-logs" \
  --lifecycle-configuration file:///tmp/lifecycle-logs.json
echo "✓ Loki logs retention: 30 days"

cat > /tmp/lifecycle-traces.json <<EOF
{"Rules":[{"ID":"expire-traces","Status":"Enabled","Expiration":{"Days":14}}]}
EOF
aws --endpoint-url "$WASABI_ENDPOINT" --region "$WASABI_REGION" s3api put-bucket-lifecycle-configuration \
  --bucket "${BUCKET_PREFIX}-tempo-traces" \
  --lifecycle-configuration file:///tmp/lifecycle-traces.json
echo "✓ Tempo traces retention: 14 days"

cat > /tmp/lifecycle-metrics.json <<EOF
{"Rules":[{"ID":"expire-metrics","Status":"Enabled","Expiration":{"Days":90}}]}
EOF
aws --endpoint-url "$WASABI_ENDPOINT" --region "$WASABI_REGION" s3api put-bucket-lifecycle-configuration \
  --bucket "${BUCKET_PREFIX}-mimir-metrics" \
  --lifecycle-configuration file:///tmp/lifecycle-metrics.json
echo "✓ Mimir metrics retention: 90 days"

echo ""
echo "S3 Buckets created successfully!"
echo "Bucket names:"
echo "  Loki:    ${BUCKET_PREFIX}-loki-logs"
echo "  Mimir:   ${BUCKET_PREFIX}-mimir-metrics"
echo "  Tempo:   ${BUCKET_PREFIX}-tempo-traces"
echo "  Grafana: ${BUCKET_PREFIX}-grafana-backups"

