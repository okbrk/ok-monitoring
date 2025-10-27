#!/usr/bin/env bash
set -euo pipefail

# Create a new tenant in the observability platform

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if required arguments are provided
if [ $# -lt 2 ]; then
  echo "Usage: $0 <tenant-name> <tenant-email> [tenant-id]"
  echo ""
  echo "Arguments:"
  echo "  tenant-name   : Display name for the tenant"
  echo "  tenant-email  : Contact email for the tenant"
  echo "  tenant-id     : (Optional) Custom tenant ID (auto-generated if not provided)"
  echo ""
  echo "Example:"
  echo "  $0 \"Acme Corp\" \"admin@acme.com\" acme"
  exit 1
fi

TENANT_NAME="$1"
TENANT_EMAIL="$2"
TENANT_ID="${3:-$(echo "$TENANT_NAME" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | tr -cd '[:alnum:]-')}"

# Generate a secure API key
API_KEY="obs_$(openssl rand -hex 32)"

log_info "Creating tenant: $TENANT_NAME (ID: $TENANT_ID)"

# Connect to PostgreSQL and create tenant
docker exec -i postgres psql -U tenants -d tenants <<EOF
INSERT INTO tenants (tenant_id, name, email, api_key)
VALUES ('${TENANT_ID}', '${TENANT_NAME}', '${TENANT_EMAIL}', '${API_KEY}')
ON CONFLICT (tenant_id) DO UPDATE
SET name = EXCLUDED.name, email = EXCLUDED.email, updated_at = CURRENT_TIMESTAMP;
EOF

if [ $? -eq 0 ]; then
  log_info "Tenant created successfully!"
  echo ""
  echo "========================================="
  echo "Tenant Information"
  echo "========================================="
  echo "Tenant ID:    $TENANT_ID"
  echo "Name:         $TENANT_NAME"
  echo "Email:        $TENANT_EMAIL"
  echo "API Key:      $API_KEY"
  echo ""
  echo "⚠️  IMPORTANT: Save this API key securely. It cannot be retrieved later."
  echo ""

  # Create Grafana organization for the tenant
  log_info "Creating Grafana organization..."

  GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
  GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"

  # Create organization
  ORG_RESPONSE=$(docker exec -i grafana curl -s -X POST \
    -H "Content-Type: application/json" \
    -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "http://localhost:3000/api/orgs" \
    -d "{\"name\":\"${TENANT_NAME}\"}")

  ORG_ID=$(echo "$ORG_RESPONSE" | grep -o '"orgId":[0-9]*' | grep -o '[0-9]*' || echo "")

  if [ -n "$ORG_ID" ]; then
    log_info "Grafana organization created (ID: $ORG_ID)"

    # Create service account token
    SA_RESPONSE=$(docker exec -i grafana curl -s -X POST \
      -H "Content-Type: application/json" \
      -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
      -H "X-Grafana-Org-Id: $ORG_ID" \
      "http://localhost:3000/api/serviceaccounts" \
      -d "{\"name\":\"${TENANT_ID}-api\",\"role\":\"Editor\"}")

    echo ""
    echo "Grafana Details:"
    echo "Organization ID: $ORG_ID"
    echo "Access URL:      https://\${DOMAIN}/grafana/"
  else
    log_warn "Failed to create Grafana organization. You may need to create it manually."
  fi

  # Save tenant info to file
  TENANT_FILE="$PROJECT_ROOT/tenants/${TENANT_ID}.json"
  mkdir -p "$PROJECT_ROOT/tenants"

  cat > "$TENANT_FILE" <<EOFJ
{
  "tenant_id": "${TENANT_ID}",
  "name": "${TENANT_NAME}",
  "email": "${TENANT_EMAIL}",
  "api_key": "${API_KEY}",
  "grafana_org_id": ${ORG_ID:-null},
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOFJ

  log_info "Tenant configuration saved to: $TENANT_FILE"

  # Generate customer onboarding guide
  ONBOARDING_FILE="$PROJECT_ROOT/tenants/${TENANT_ID}-onboarding.md"

  cat > "$ONBOARDING_FILE" <<'EOFMD'
# Observability Platform - Customer Onboarding Guide

## Your Credentials

- **Tenant ID**: ${TENANT_ID}
- **API Key**: ${API_KEY}
- **Grafana URL**: https://${DOMAIN}/grafana/

## Sending Data to the Platform

### 1. Metrics (Prometheus Remote Write)

Configure your Prometheus instance to send metrics:

```yaml
remote_write:
  - url: https://api.${DOMAIN}/api/v1/push
    headers:
      X-Scope-OrgID: ${TENANT_ID}
      Authorization: Bearer ${API_KEY}
```

### 2. Logs (via Promtail)

Configure Promtail to send logs to Loki:

```yaml
clients:
  - url: https://api.${DOMAIN}/loki/api/v1/push
    tenant_id: ${TENANT_ID}
    headers:
      Authorization: Bearer ${API_KEY}
```

### 3. Traces (OpenTelemetry)

Configure OTLP exporter in your application:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=https://api.${DOMAIN}
export OTEL_EXPORTER_OTLP_HEADERS="X-Scope-OrgID=${TENANT_ID},Authorization=Bearer ${API_KEY}"
```

Or using gRPC:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.${DOMAIN}:443
export OTEL_EXPORTER_OTLP_HEADERS="X-Scope-OrgID=${TENANT_ID},Authorization=Bearer ${API_KEY}"
```

## Example: Docker Compose Setup

```yaml
version: '3.8'

services:
  # Your application
  myapp:
    image: myapp:latest
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=https://api.${DOMAIN}
      - OTEL_EXPORTER_OTLP_HEADERS=X-Scope-OrgID=${TENANT_ID},Authorization=Bearer ${API_KEY}

  # Promtail for log shipping
  promtail:
    image: grafana/promtail:latest
    volumes:
      - /var/log:/var/log:ro
      - ./promtail-config.yaml:/etc/promtail/config.yaml:ro
    command: -config.file=/etc/promtail/config.yaml
```

## Support

For assistance, contact: support@example.com

EOFMD

  # Replace placeholders in onboarding guide
  sed -i.bak "s/\${TENANT_ID}/${TENANT_ID}/g" "$ONBOARDING_FILE"
  sed -i.bak "s/\${API_KEY}/${API_KEY}/g" "$ONBOARDING_FILE"
  sed -i.bak "s/\${DOMAIN}/\${DOMAIN}/g" "$ONBOARDING_FILE"
  rm -f "${ONBOARDING_FILE}.bak"

  log_info "Onboarding guide saved to: $ONBOARDING_FILE"

else
  log_error "Failed to create tenant in database"
  exit 1
fi

