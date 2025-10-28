#!/bin/bash
# Remove or deactivate a Prometheus metrics endpoint

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Help
if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ $# -lt 1 ]; then
  echo "Usage: $0 ENDPOINT_ID [--delete]"
  echo ""
  echo "Remove or deactivate a Prometheus metrics endpoint."
  echo ""
  echo "Arguments:"
  echo "  ENDPOINT_ID    The ID of the endpoint to remove"
  echo "  --delete       Permanently delete instead of deactivating (optional)"
  echo ""
  echo "Examples:"
  echo "  $0 1              # Deactivate endpoint ID 1"
  echo "  $0 1 --delete     # Permanently delete endpoint ID 1"
  echo ""
  echo "Use 'bash scripts/tenant-management/list-metrics-endpoints.sh' to see endpoint IDs"
  echo ""
  exit 0
fi

ENDPOINT_ID=$1
DELETE_FLAG=$2

# Database connection
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-tenants}
DB_USER=${DB_USER:-tenants}
DB_PASSWORD=${POSTGRES_PASSWORD}

if [ -z "$DB_PASSWORD" ]; then
  echo -e "${RED}Error: POSTGRES_PASSWORD environment variable not set${NC}"
  exit 1
fi

# Validate endpoint ID is a number
if ! [[ "$ENDPOINT_ID" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}Error: ENDPOINT_ID must be a number${NC}"
  exit 1
fi

# Check if endpoint exists
ENDPOINT_INFO=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -F'|' -c \
  "SELECT tenant_id, endpoint_url, is_active FROM metrics_endpoints WHERE id = $ENDPOINT_ID;" 2>/dev/null)

if [ -z "$ENDPOINT_INFO" ]; then
  echo -e "${RED}Error: Endpoint ID $ENDPOINT_ID not found${NC}"
  echo "Use: bash scripts/tenant-management/list-metrics-endpoints.sh"
  exit 1
fi

IFS='|' read -r tenant_id endpoint_url is_active <<< "$ENDPOINT_INFO"

echo -e "${BLUE}Endpoint Details${NC}"
echo "  ID: $ENDPOINT_ID"
echo "  Tenant: $tenant_id"
echo "  Endpoint: $endpoint_url"
echo "  Current Status: $([ "$is_active" == "t" ] && echo "Active" || echo "Inactive")"
echo ""

# Perform action
if [ "$DELETE_FLAG" == "--delete" ]; then
  # Permanently delete
  echo -e "${YELLOW}Permanently deleting endpoint...${NC}"

  DELETE_QUERY="DELETE FROM metrics_endpoints WHERE id = $ENDPOINT_ID;"

  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "$DELETE_QUERY" > /dev/null 2>&1

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Endpoint permanently deleted${NC}"
  else
    echo -e "${RED}Error: Failed to delete endpoint${NC}"
    exit 1
  fi
else
  # Deactivate
  if [ "$is_active" == "f" ]; then
    echo -e "${YELLOW}Warning: Endpoint is already inactive${NC}"
    echo ""
    read -p "Continue anyway? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
      echo "Cancelled"
      exit 0
    fi
  fi

  echo -e "${YELLOW}Deactivating endpoint...${NC}"

  UPDATE_QUERY="UPDATE metrics_endpoints SET is_active = false, updated_at = CURRENT_TIMESTAMP WHERE id = $ENDPOINT_ID;"

  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "$UPDATE_QUERY" > /dev/null 2>&1

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Endpoint deactivated${NC}"
  else
    echo -e "${RED}Error: Failed to deactivate endpoint${NC}"
    exit 1
  fi
fi

echo ""

# Regenerate agent config
echo -e "${BLUE}Regenerating Grafana Agent configuration...${NC}"
bash scripts/tenant-management/generate-agent-config.sh

echo ""
echo -e "${GREEN}✓ Endpoint removed and configuration updated${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "Deploy the updated configuration:"
echo "  scp config/grafana-agent/config.yaml ok-obs:/opt/observability/config/grafana-agent/"
echo "  ssh ok-obs 'cd /opt/observability && docker compose restart grafana-agent'"
echo ""

