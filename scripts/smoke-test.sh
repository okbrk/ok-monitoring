#!/usr/bin/env bash
set -euo pipefail

# Smoke test script for observability platform

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

passed=0
failed=0

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((passed++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    ((failed++))
}

test_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo "======================================"
echo "Observability Platform Smoke Tests"
echo "======================================"
echo ""

# Load environment
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
else
    test_fail ".env file not found"
    exit 1
fi

# Get server IP from Terraform
cd "$PROJECT_ROOT/infra/terraform"
if [ -f "terraform.tfstate" ]; then
    SERVER_IP=$(terraform output -raw server_public_ip 2>/dev/null || echo "")
    if [ -n "$SERVER_IP" ]; then
        test_pass "Server IP retrieved: $SERVER_IP"
    else
        test_fail "Could not retrieve server IP from Terraform"
        exit 1
    fi
else
    test_fail "Terraform state not found. Run setup.sh first"
    exit 1
fi

cd "$PROJECT_ROOT"

echo ""
echo "Testing Server Connectivity..."
echo "------------------------------"

# Test SSH connectivity
if ssh -o ConnectTimeout=5 -o BatchMode=yes root@"$SERVER_IP" "echo 'SSH OK'" &>/dev/null; then
    test_pass "SSH connection successful"
else
    test_fail "SSH connection failed"
fi

# Test Docker
if ssh root@"$SERVER_IP" "docker --version" &>/dev/null; then
    test_pass "Docker is installed"
else
    test_fail "Docker is not installed"
fi

echo ""
echo "Testing Docker Services..."
echo "--------------------------"

# Check if Docker Compose stack is running
RUNNING_SERVICES=$(ssh root@"$SERVER_IP" "cd /opt/observability && docker compose ps --services --filter 'status=running'" 2>/dev/null || echo "")

if [ -n "$RUNNING_SERVICES" ]; then
    test_pass "Docker Compose stack is running"

    # Check individual services
    for service in grafana loki mimir tempo otel-collector caddy postgres; do
        if echo "$RUNNING_SERVICES" | grep -q "^${service}$"; then
            test_pass "Service '$service' is running"
        else
            test_fail "Service '$service' is not running"
        fi
    done
else
    test_fail "Docker Compose stack is not running"
fi

echo ""
echo "Testing Service Health..."
echo "-------------------------"

# Test internal service endpoints (via SSH tunnel)
services_to_test=(
    "grafana:3000:/api/health:Grafana"
    "loki:3100:/ready:Loki"
    "mimir:8080:/ready:Mimir"
    "tempo:3200:/ready:Tempo"
)

for service_test in "${services_to_test[@]}"; do
    IFS=':' read -r service port path name <<< "$service_test"
    if ssh root@"$SERVER_IP" "docker exec $service wget -q -O- http://localhost:${port}${path}" &>/dev/null; then
        test_pass "$name health check passed"
    else
        test_warn "$name health check failed (service may still be starting)"
    fi
done

echo ""
echo "Testing PostgreSQL..."
echo "---------------------"

# Test PostgreSQL
if ssh root@"$SERVER_IP" "docker exec postgres pg_isready -U tenants" &>/dev/null; then
    test_pass "PostgreSQL is ready"

    # Check if admin tenant exists
    TENANT_COUNT=$(ssh root@"$SERVER_IP" "docker exec postgres psql -U tenants -d tenants -t -c \"SELECT COUNT(*) FROM tenants;\"" 2>/dev/null | tr -d ' ' || echo "0")
    if [ "$TENANT_COUNT" -gt 0 ]; then
        test_pass "Tenants table populated ($TENANT_COUNT tenants)"
    else
        test_warn "No tenants found in database"
    fi
else
    test_fail "PostgreSQL is not ready"
fi

echo ""
echo "Testing External Access..."
echo "--------------------------"

# Test HTTP/HTTPS ports
if nc -z -w5 "$SERVER_IP" 80 &>/dev/null; then
    test_pass "Port 80 (HTTP) is open"
else
    test_fail "Port 80 (HTTP) is not accessible"
fi

if nc -z -w5 "$SERVER_IP" 443 &>/dev/null; then
    test_pass "Port 443 (HTTPS) is open"
else
    test_fail "Port 443 (HTTPS) is not accessible"
fi

# Test OTLP ports
if nc -z -w5 "$SERVER_IP" 4317 &>/dev/null; then
    test_pass "Port 4317 (OTLP gRPC) is open"
else
    test_warn "Port 4317 (OTLP gRPC) is not accessible"
fi

if nc -z -w5 "$SERVER_IP" 4318 &>/dev/null; then
    test_pass "Port 4318 (OTLP HTTP) is open"
else
    test_warn "Port 4318 (OTLP HTTP) is not accessible"
fi

echo ""
echo "Testing DNS and HTTPS..."
echo "------------------------"

# Test if domain resolves
if host "$DOMAIN" &>/dev/null; then
    RESOLVED_IP=$(host "$DOMAIN" | grep "has address" | awk '{print $4}' | head -1)
    if [ "$RESOLVED_IP" = "$SERVER_IP" ]; then
        test_pass "Domain $DOMAIN resolves correctly to $SERVER_IP"

        # Test HTTPS
        if curl -sf -o /dev/null "https://${DOMAIN}/health" 2>/dev/null; then
            test_pass "HTTPS is working with valid certificate"
        else
            test_warn "HTTPS not yet available (DNS may need time to propagate, or Let's Encrypt needs to issue cert)"
        fi
    else
        test_warn "Domain $DOMAIN resolves to $RESOLVED_IP but server is at $SERVER_IP"
    fi
else
    test_warn "Domain $DOMAIN does not resolve yet"
fi

echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"
echo -e "${GREEN}Passed:${NC} $passed"
if [ $failed -gt 0 ]; then
    echo -e "${RED}Failed:${NC} $failed"
fi
echo ""

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All critical tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please investigate.${NC}"
    exit 1
fi
