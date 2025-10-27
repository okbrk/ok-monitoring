#!/usr/bin/env bash
set -euo pipefail

# Rotate API key for a tenant

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [ $# -lt 1 ]; then
  echo "Usage: $0 <tenant-id>"
  echo ""
  echo "Arguments:"
  echo "  tenant-id : ID of the tenant"
  exit 1
fi

TENANT_ID="$1"

# Check if tenant exists
TENANT_EXISTS=$(docker exec -i postgres psql -U tenants -d tenants -t -c \
  "SELECT COUNT(*) FROM tenants WHERE tenant_id = '${TENANT_ID}' AND is_active = true;" | tr -d ' ')

if [ "$TENANT_EXISTS" = "0" ]; then
  log_error "Tenant '${TENANT_ID}' not found or inactive"
  exit 1
fi

# Generate new API key
NEW_API_KEY="obs_$(openssl rand -hex 32)"

log_info "Generating new API key for tenant: $TENANT_ID"

# Update primary API key in tenants table
docker exec -i postgres psql -U tenants -d tenants <<EOF
UPDATE tenants
SET api_key = '${NEW_API_KEY}', updated_at = CURRENT_TIMESTAMP
WHERE tenant_id = '${TENANT_ID}';

-- Archive old key to api_keys table for audit
INSERT INTO api_keys (tenant_id, api_key, description, is_active)
SELECT tenant_id, api_key, 'Rotated key', false
FROM tenants
WHERE tenant_id = '${TENANT_ID}';
EOF

if [ $? -eq 0 ]; then
  log_info "API key rotated successfully!"
  echo ""
  echo "========================================="
  echo "New API Key"
  echo "========================================="
  echo "Tenant ID: $TENANT_ID"
  echo "API Key:   $NEW_API_KEY"
  echo ""
  log_warn "Update this key in your customer's configuration"
  echo ""

  # Update tenant config file if it exists
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  TENANT_FILE="$PROJECT_ROOT/tenants/${TENANT_ID}.json"

  if [ -f "$TENANT_FILE" ]; then
    # Update the API key in the JSON file
    if command -v jq &> /dev/null; then
      jq --arg key "$NEW_API_KEY" '.api_key = $key | .updated_at = now | .key_rotated_at = now' "$TENANT_FILE" > "${TENANT_FILE}.tmp"
      mv "${TENANT_FILE}.tmp" "$TENANT_FILE"
      log_info "Updated tenant configuration file: $TENANT_FILE"
    else
      log_warn "jq not installed. Please manually update $TENANT_FILE"
    fi
  fi
else
  log_error "Failed to rotate API key"
  exit 1
fi

