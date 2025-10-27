#!/usr/bin/env bash
set -euo pipefail

# Delete a tenant from the observability platform

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ $# -lt 1 ]; then
  echo "Usage: $0 <tenant-id> [--force]"
  echo ""
  echo "Arguments:"
  echo "  tenant-id : ID of the tenant to delete"
  echo "  --force   : Skip confirmation prompt"
  exit 1
fi

TENANT_ID="$1"
FORCE="${2:-}"

# Check if tenant exists
TENANT_EXISTS=$(docker exec -i postgres psql -U tenants -d tenants -t -c \
  "SELECT COUNT(*) FROM tenants WHERE tenant_id = '${TENANT_ID}';" | tr -d ' ')

if [ "$TENANT_EXISTS" = "0" ]; then
  log_error "Tenant '${TENANT_ID}' not found"
  exit 1
fi

# Get tenant info
TENANT_INFO=$(docker exec -i postgres psql -U tenants -d tenants -t -A -F"," -c \
  "SELECT name, email FROM tenants WHERE tenant_id = '${TENANT_ID}';")

TENANT_NAME=$(echo "$TENANT_INFO" | cut -d',' -f1)
TENANT_EMAIL=$(echo "$TENANT_INFO" | cut -d',' -f2)

log_warn "You are about to delete the following tenant:"
echo ""
echo "  Tenant ID: $TENANT_ID"
echo "  Name:      $TENANT_NAME"
echo "  Email:     $TENANT_EMAIL"
echo ""
log_warn "This will:"
echo "  - Mark the tenant as inactive in the database"
echo "  - Revoke all API keys"
echo "  - Data in Loki/Mimir/Tempo will remain (manual cleanup required)"
echo "  - Grafana organization will remain (manual deletion required)"
echo ""

if [ "$FORCE" != "--force" ]; then
  read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    log_info "Deletion cancelled"
    exit 0
  fi
fi

# Deactivate tenant
log_info "Deactivating tenant..."
docker exec -i postgres psql -U tenants -d tenants <<EOF
UPDATE tenants SET is_active = false WHERE tenant_id = '${TENANT_ID}';
UPDATE api_keys SET is_active = false WHERE tenant_id = '${TENANT_ID}';
EOF

if [ $? -eq 0 ]; then
  log_info "Tenant '${TENANT_ID}' has been deactivated"
  echo ""
  log_warn "Manual cleanup required:"
  echo "  1. Delete Grafana organization (if exists)"
  echo "  2. Delete tenant data from Loki/Mimir/Tempo (if needed)"
  echo "  3. To permanently delete from database, run:"
  echo "     docker exec -i postgres psql -U tenants -d tenants -c \"DELETE FROM tenants WHERE tenant_id = '${TENANT_ID}';\""
else
  log_error "Failed to deactivate tenant"
  exit 1
fi

