#!/bin/bash
# List all registered Prometheus metrics endpoints

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Help
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
  echo "Usage: $0 [TENANT_ID]"
  echo ""
  echo "List all registered Prometheus metrics endpoints."
  echo ""
  echo "Arguments:"
  echo "  TENANT_ID    Optional: Filter by tenant ID"
  echo ""
  echo "Examples:"
  echo "  $0              # List all endpoints"
  echo "  $0 okbrk        # List endpoints for 'okbrk' tenant only"
  echo ""
  exit 0
fi

FILTER_TENANT=$1

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

# Build query
if [ -n "$FILTER_TENANT" ]; then
  QUERY="
SELECT
  me.id,
  me.tenant_id,
  t.name as tenant_name,
  me.endpoint_url,
  me.scrape_interval_seconds,
  me.is_active,
  me.last_scrape_at,
  me.last_scrape_status,
  me.created_at
FROM metrics_endpoints me
JOIN tenants t ON me.tenant_id = t.tenant_id
WHERE me.tenant_id = '$FILTER_TENANT'
ORDER BY me.created_at DESC;
"
else
  QUERY="
SELECT
  me.id,
  me.tenant_id,
  t.name as tenant_name,
  me.endpoint_url,
  me.scrape_interval_seconds,
  me.is_active,
  me.last_scrape_at,
  me.last_scrape_status,
  me.created_at
FROM metrics_endpoints me
JOIN tenants t ON me.tenant_id = t.tenant_id
ORDER BY me.created_at DESC;
"
fi

# Fetch data
ENDPOINTS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -F'|' -c "$QUERY" 2>/dev/null)

if [ $? -ne 0 ]; then
  echo -e "${RED}Error: Failed to query database${NC}"
  exit 1
fi

# Display header
echo ""
if [ -n "$FILTER_TENANT" ]; then
  echo -e "${BLUE}Metrics Endpoints for Tenant: $FILTER_TENANT${NC}"
else
  echo -e "${BLUE}All Registered Metrics Endpoints${NC}"
fi
echo ""

# Count endpoints
ENDPOINT_COUNT=0
ACTIVE_COUNT=0

# Display endpoints
if [ -z "$ENDPOINTS" ]; then
  echo -e "${GRAY}No metrics endpoints registered${NC}"
else
  while IFS='|' read -r id tenant_id tenant_name endpoint_url scrape_interval is_active last_scrape last_status created_at; do
    [ -z "$id" ] && continue

    ENDPOINT_COUNT=$((ENDPOINT_COUNT + 1))

    # Status indicator
    if [ "$is_active" == "t" ]; then
      STATUS="${GREEN}●${NC} Active"
      ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
    else
      STATUS="${GRAY}○${NC} Inactive"
    fi

    # Last scrape status
    if [ -n "$last_scrape" ] && [ "$last_scrape" != " " ]; then
      SCRAPE_INFO="${GRAY}Last scraped: $last_scrape${NC}"
      if [ -n "$last_status" ] && [ "$last_status" != " " ]; then
        SCRAPE_INFO="$SCRAPE_INFO ${GRAY}(${last_status})${NC}"
      fi
    else
      SCRAPE_INFO="${GRAY}Never scraped${NC}"
    fi

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "ID: ${YELLOW}$id${NC}  |  Status: $STATUS"
    echo -e "Tenant: ${YELLOW}$tenant_id${NC} ($tenant_name)"
    echo -e "Endpoint: $endpoint_url"
    echo -e "Interval: ${scrape_interval}s"
    echo -e "$SCRAPE_INFO"
    echo -e "Created: ${GRAY}$created_at${NC}"
    echo ""

  done <<< "$ENDPOINTS"

  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi

echo ""
echo -e "${BLUE}Summary:${NC} $ENDPOINT_COUNT total endpoint(s), $ACTIVE_COUNT active"
echo ""

# Show commands
if [ $ENDPOINT_COUNT -gt 0 ]; then
  echo -e "${GRAY}Commands:${NC}"
  echo "  Register new:  bash scripts/tenant-management/register-metrics-endpoint.sh TENANT_ID URL"
  echo "  Remove:        bash scripts/tenant-management/remove-metrics-endpoint.sh ENDPOINT_ID"
  echo "  Regenerate:    bash scripts/tenant-management/generate-agent-config.sh"
  echo ""
fi

