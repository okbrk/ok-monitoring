#!/bin/bash
# Register a Prometheus metrics endpoint for a customer

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Help
if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ $# -lt 2 ]; then
  echo "Usage: $0 TENANT_ID ENDPOINT_URL [SCRAPE_INTERVAL_SECONDS]"
  echo ""
  echo "Register a Prometheus metrics endpoint for health check scraping."
  echo ""
  echo "Arguments:"
  echo "  TENANT_ID                   Customer tenant ID (e.g., 'okbrk')"
  echo "  ENDPOINT_URL                Full URL to metrics endpoint (e.g., 'https://app.okbrk.com/api/metrics')"
  echo "  SCRAPE_INTERVAL_SECONDS     Optional: Scrape interval in seconds (default: 30, min: 15, max: 300)"
  echo ""
  echo "Examples:"
  echo "  $0 okbrk https://app.okbrk.com/api/metrics"
  echo "  $0 okbrk https://app.okbrk.com/api/metrics 60"
  echo "  $0 acme http://localhost:8080/metrics 15"
  echo ""
  exit 0
fi

TENANT_ID=$1
ENDPOINT_URL=$2
SCRAPE_INTERVAL=${3:-30}

# Validate scrape interval
if [ "$SCRAPE_INTERVAL" -lt 15 ] || [ "$SCRAPE_INTERVAL" -gt 300 ]; then
  echo -e "${RED}Error: Scrape interval must be between 15 and 300 seconds${NC}"
  exit 1
fi

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

echo -e "${BLUE}Registering metrics endpoint${NC}"
echo "  Tenant ID: $TENANT_ID"
echo "  Endpoint: $ENDPOINT_URL"
echo "  Scrape Interval: ${SCRAPE_INTERVAL}s"
echo ""

# Check if tenant exists
TENANT_EXISTS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -c \
  "SELECT EXISTS(SELECT 1 FROM tenants WHERE tenant_id = '$TENANT_ID' AND is_active = true);" 2>/dev/null)

if [ "$TENANT_EXISTS" != "t" ]; then
  echo -e "${RED}Error: Tenant '$TENANT_ID' does not exist or is inactive${NC}"
  echo "Use: bash scripts/tenant-management/list-tenants.sh"
  exit 1
fi

# Validate URL format
if [[ ! $ENDPOINT_URL =~ ^https?:// ]]; then
  echo -e "${RED}Error: Endpoint URL must start with http:// or https://${NC}"
  exit 1
fi

# Insert endpoint into database
INSERT_QUERY="
INSERT INTO metrics_endpoints (tenant_id, endpoint_url, scrape_interval_seconds)
VALUES ('$TENANT_ID', '$ENDPOINT_URL', $SCRAPE_INTERVAL)
RETURNING id;
"

ENDPOINT_ID=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -c "$INSERT_QUERY" 2>&1)

if [ $? -ne 0 ]; then
  echo -e "${RED}Error: Failed to register endpoint${NC}"
  echo "$ENDPOINT_ID"
  exit 1
fi

echo -e "${GREEN}✓ Endpoint registered successfully (ID: $ENDPOINT_ID)${NC}"
echo ""

# Regenerate agent config
echo -e "${BLUE}Regenerating Grafana Agent configuration...${NC}"
bash scripts/tenant-management/generate-agent-config.sh

echo ""
echo -e "${GREEN}✓ Metrics endpoint registered and configuration updated${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Customer must expose the endpoint with API key authentication:"
echo "   - Endpoint: $ENDPOINT_URL"
echo "   - Expected header: Authorization: Bearer <customer_api_key>"
echo "   - Response format: Prometheus text format"
echo ""
echo "2. Deploy the updated configuration:"
echo "   scp config/grafana-agent/config.yaml ok-obs:/opt/observability/config/grafana-agent/"
echo "   ssh ok-obs 'cd /opt/observability && docker compose restart grafana-agent'"
echo ""
echo "3. Verify scraping:"
echo "   ssh ok-obs 'docker logs grafana-agent --tail 50'"
echo ""
echo "4. Check metrics in Grafana:"
echo "   Query: up{tenant_id=\"$TENANT_ID\"}"
echo ""

