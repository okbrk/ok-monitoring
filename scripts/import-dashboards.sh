#!/usr/bin/env bash
set -euo pipefail

# Import all dashboards into Grafana

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Check if Grafana is accessible
if ! ssh ok-obs "docker exec grafana curl -s http://localhost:3000/api/health" &>/dev/null; then
    log_warn "Grafana is not accessible. Make sure it's running."
    exit 1
fi

# Get admin credentials from .env
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
else
    log_warn ".env file not found"
    exit 1
fi

GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_PASS="${GRAFANA_ADMIN_PASSWORD}"

log_info "Importing dashboards to Grafana..."

# Copy dashboards to server
scp -r "$PROJECT_ROOT/dashboards" ok-obs:/tmp/

# Import each dashboard
for dashboard_file in "$PROJECT_ROOT"/dashboards/*.json; do
    dashboard_name=$(basename "$dashboard_file" .json)
    log_info "Importing dashboard: $dashboard_name"

    # Import dashboard via Grafana API
    ssh ok-obs "docker exec grafana curl -s -X POST \
        -H 'Content-Type: application/json' \
        -u '${GRAFANA_USER}:${GRAFANA_PASS}' \
        '${GRAFANA_URL}/api/dashboards/db' \
        -d @/tmp/dashboards/\$(basename '$dashboard_file')" | grep -q 'success' && echo '✓ Imported' || echo '✗ Failed'
done

# Cleanup
ssh ok-obs "rm -rf /tmp/dashboards"

log_info "Dashboard import complete!"
log_info "Access Grafana at: http://\$TAILSCALE_IP:3000"

