#!/usr/bin/env bash
set -euo pipefail

# List all tenants in the observability platform

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }

log_info "Retrieving tenant list..."

# Query PostgreSQL for tenant list
docker exec -i postgres psql -U tenants -d tenants -t -A -F"," <<'EOF'
SELECT
    tenant_id,
    name,
    email,
    is_active,
    created_at,
    (SELECT COUNT(*) FROM api_keys WHERE api_keys.tenant_id = tenants.tenant_id AND is_active = true) as active_keys
FROM tenants
ORDER BY created_at DESC;
EOF

echo ""
log_info "Tenant Statistics:"

# Get usage stats for the last 7 days
docker exec -i postgres psql -U tenants -d tenants <<'EOF'
SELECT
    t.tenant_id,
    t.name,
    COALESCE(SUM(u.logs_ingested_bytes), 0) / 1024 / 1024 as logs_mb,
    COALESCE(SUM(u.metrics_ingested_count), 0) as metrics_count,
    COALESCE(SUM(u.traces_ingested_count), 0) as traces_count,
    COALESCE(SUM(u.queries_executed), 0) as queries
FROM tenants t
LEFT JOIN usage_stats u ON t.tenant_id = u.tenant_id
    AND u.date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY t.tenant_id, t.name
ORDER BY logs_mb DESC;
EOF

echo ""
log_info "Total tenants: $(docker exec -i postgres psql -U tenants -d tenants -t -c "SELECT COUNT(*) FROM tenants WHERE is_active = true;")"

