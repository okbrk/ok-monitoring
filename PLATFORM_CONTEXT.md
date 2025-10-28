# Platform Context - Multi-Tenant Observability Infrastructure

Quick reference document for managing the observability platform across different sessions.

## 🏗️ Infrastructure Overview

### Server Details
- **Provider**: Hetzner Cloud
- **Server Type**: CPX32 (4 vCPU, 8GB RAM, 160GB NVMe SSD)
- **Public IP**: `91.99.16.221`
- **Tailscale IP**: `100.87.121.71` (VPN access)
- **Domain**: `obs.okbrk.com`
- **Location**: Nuremberg, Germany (nbg1)
- **Cost**: ~€13.30/month + €6.99 Wasabi S3 = ~€20/month

### Architecture
```
Customer Apps (Anywhere)
    ↓
HTTPS Public Endpoints:
  - https://api.obs.okbrk.com (OTLP HTTP, Loki, Mimir)
  - https://otlp.obs.okbrk.com (OTLP gRPC)
    ↓
Hetzner CPX32 (91.99.16.221)
  ├─ Caddy (reverse proxy + Let's Encrypt)
  ├─ OpenTelemetry Collector (gateway)
  ├─ Loki (logs) - auth_enabled: false
  ├─ Mimir (metrics) - multitenancy: false
  ├─ Tempo (traces) - multitenancy: false
  ├─ Grafana (admin UI) - VPN-only @ 100.87.121.71:3000
  ├─ Grafana Agent (Prometheus scraper)
  ├─ PostgreSQL (tenant management)
  └─ Infrastructure Monitoring:
      ├─ Prometheus (metrics collection)
      ├─ Alertmanager (alert routing)
      ├─ Node Exporter (host metrics)
      ├─ cAdvisor (container metrics)
      └─ Postgres Exporter (DB metrics)

Storage: 160GB local SSD + Wasabi S3 buckets (future)
```

### Security Model
- **Public**: Customer data ingestion endpoints (API key required)
- **Private**: Admin tools (Grafana, SSH) via Tailscale VPN only
- **Isolation**: Label-based (service_name, not strict multi-tenancy)
- **Firewall**: Disabled (relying on Hetzner network security)

---

## 🔑 Access & Credentials

### SSH Access
```bash
# SSH config alias (already configured in ~/.ssh/config)
ssh ok-obs

# Full command
ssh -i ~/.ssh/id_ed25519 root@91.99.16.221
```

### Grafana Access (VPN-Only)
```
URL: http://100.87.121.71:3000
Username: admin
Password: [from your .env file - GRAFANA_ADMIN_PASSWORD]
```

**Note**: Must be connected to Tailscale VPN to access Grafana.

### Admin Tenant
```
Tenant ID: admin
API Key: obs_421c9fddc3d80a3d720675a73c8a6cf75d63c2b54dd18adc143a58d75673bbfe
```

### Customer Example
```
Tenant ID: okbrk
API Key: obs_f07962fbc30f4e469250d0ca8aafdf76edcfaeb6e961a4912a46a999287b5308
Email: burak@okbrk.com
```

---

## 🚀 Key Commands

### Service Management

```bash
# View all services
ssh ok-obs 'cd /opt/observability && docker compose ps'

# View logs
ssh ok-obs 'cd /opt/observability && docker compose logs -f [service-name]'

# Restart services
ssh ok-obs 'cd /opt/observability && docker compose restart'

# Restart specific service
ssh ok-obs 'cd /opt/observability && docker compose restart loki'

# Update services
ssh ok-obs 'cd /opt/observability && docker compose pull && docker compose up -d'
```

### Tenant Management

```bash
# Create new customer
ssh ok-obs 'cd /opt/observability && \
  bash scripts/tenant-management/create-tenant.sh "Company Name" "email@example.com" "tenant-id"'

# List all tenants
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/list-tenants.sh'

# Rotate API key
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/rotate-api-key.sh tenant-id'

# Deactivate tenant
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/delete-tenant.sh tenant-id'
```

### Prometheus Metrics Management

```bash
# Register customer metrics endpoint
ssh ok-obs 'cd /opt/observability && \
  bash scripts/tenant-management/register-metrics-endpoint.sh tenant-id https://app.com/api/metrics 30'

# List registered endpoints
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/list-metrics-endpoints.sh'

# Remove endpoint
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/remove-metrics-endpoint.sh ENDPOINT_ID'

# Regenerate Grafana Agent config
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/generate-agent-config.sh'
```

### Configuration Updates

```bash
# Update any config file locally, then:
cd /Users/burak/projects/ok/apps/ok-monitoring

# Copy to server
scp config/loki/loki.yaml ok-obs:/opt/observability/config/loki/

# Restart affected service
ssh ok-obs 'cd /opt/observability && docker compose restart loki'
```

---

## 📊 Data Flow

### How Customers Send Data

**Logs (via Loki API):**
```bash
curl -X POST https://api.obs.okbrk.com/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: tenant-id" \
  -H "Authorization: Bearer obs_api_key" \
  -d '{...}'
```

**Metrics (via OTLP):**
```bash
# OTLP HTTP
POST https://api.obs.okbrk.com/v1/metrics
Headers: X-Scope-OrgID, Authorization

# OTLP gRPC
grpc://otlp.obs.okbrk.com:443
```

**Metrics (via Prometheus Endpoint - Health Check Style):**
```bash
# Customer exposes authenticated endpoint
GET https://customer-app.com/api/metrics
Header: Authorization: Bearer obs_api_key

# Platform scrapes it every 15-30s via Grafana Agent
# See: docs/PROMETHEUS_INTEGRATION.md
```

**Traces (via OTLP):**
```bash
POST https://api.obs.okbrk.com/v1/traces
Headers: X-Scope-OrgID, Authorization
```

### Data Routing

```
Customer → Caddy (HTTPS) → OTEL Collector → Loki/Mimir/Tempo
                                           ↓
                                        Grafana (queries)
```

Customers send to **public HTTPS endpoints**, data flows through OTEL Collector, stored in respective backends, queryable via Grafana (VPN-only).

---

## 🧪 Testing & Verification

### Test Loki (Logs)

```bash
# Send test log
curl -X POST https://api.obs.okbrk.com/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: okbrk" \
  -H "Authorization: Bearer obs_f07962fbc30f4e469250d0ca8aafdf76edcfaeb6e961a4912a46a999287b5308" \
  -d '{
    "streams": [{
      "stream": {"job": "test", "service_name": "okbrk", "level": "info"},
      "values": [["'$(date +%s)'000000000", "Test at '$(date)'"]]
    }]
  }'

# Query directly
ssh ok-obs 'curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode "query={service_name=\"okbrk\"}" \
  --data-urlencode "start='$(($(date +%s) - 600))'000000000" \
  --data-urlencode "end='$(date +%s)'000000000" \
  | jq ".data.result[].values | length"'

# In Grafana Explore (Loki):
{service_name="okbrk"}
```

### Test Mimir (Metrics)

```bash
# Check Mimir is responding
ssh ok-obs "curl -s http://localhost:8080/prometheus/api/v1/query?query=up"

# Send test metric via OTLP
curl -X POST https://api.obs.okbrk.com/v1/metrics \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: okbrk" \
  -d '{...OTLP format...}'

# In Grafana Explore (Mimir):
up
# Or: test_requests_total
```

### Test Tempo (Traces)

```bash
# Check Tempo is ready
ssh ok-obs "curl -s http://localhost:3200/ready"

# Send test trace via OTLP
curl -X POST https://api.obs.okbrk.com/v1/traces \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: okbrk" \
  -d '{...OTLP format...}'

# In Grafana Explore (Tempo):
# Search by service.name = okbrk
```

### Health Check

```bash
# Public endpoint
curl https://api.obs.okbrk.com/health
# Returns: OK

# All services status
ssh ok-obs 'cd /opt/observability && docker compose ps'

# Disk usage
ssh ok-obs 'df -h /opt/observability-data'
```

---

## 🗂️ File Locations

### On Server (`91.99.16.221`)

```
/opt/observability/
├── docker-compose.yml          # Service definitions
├── config/                     # Service configurations
│   ├── loki/loki.yaml
│   ├── mimir/mimir.yaml
│   ├── tempo/tempo.yaml
│   ├── grafana/datasources.yaml
│   ├── grafana-agent/config.yaml
│   ├── caddy/Caddyfile
│   ├── otel-collector/config.yaml
│   └── postgres/init.sql
├── scripts/
│   └── tenant-management/      # Tenant CRUD scripts
│       ├── create-tenant.sh
│       ├── list-tenants.sh
│       ├── delete-tenant.sh
│       ├── rotate-api-key.sh
│       ├── register-metrics-endpoint.sh
│       ├── list-metrics-endpoints.sh
│       ├── remove-metrics-endpoint.sh
│       └── generate-agent-config.sh
├── tenants/                    # Tenant configs (generated)
│   ├── okbrk.json
│   └── okbrk-onboarding.md
└── .env                        # Environment variables

/opt/observability-data/        # Persistent data
├── grafana/
├── grafana-agent/
├── loki/
├── mimir/
├── tempo/
├── postgres/
└── caddy/
```

### On Local Machine

```
/Users/burak/projects/ok/apps/ok-monitoring/
├── docker-compose.yml          # Source files
├── config/                     # Config templates
├── scripts/
│   ├── setup.sh               # Automated deployment
│   ├── smoke-test.sh          # Health checks
│   └── tenant-management/     # Tenant management
├── dashboards/                # Grafana dashboards (5 pre-built)
├── docs/
│   ├── README.md              # Platform documentation
│   ├── ADMIN_GUIDE.md         # Admin operations
│   ├── CUSTOMER_GUIDE.md      # Customer integration
│   ├── PROMETHEUS_INTEGRATION.md  # Prometheus metrics setup
│   └── ADMIN_DASHBOARD.md     # Build custom dashboard
├── infra/terraform/           # Infrastructure as code
├── .env                       # Your credentials (gitignored)
└── env.example                # Template
```

---

## ⚙️ Current Configuration

### Multi-Tenancy
- **Status**: **Disabled** (auth_enabled: false)
- **Why**: Easier admin access, still isolated by labels
- **Customer Isolation**: Via `service_name` label, not strict tenant IDs
- **Grafana**: Can query all tenants, filter by labels

### Data Retention
- **Logs (Loki)**: 31 days (744h)
- **Metrics (Mimir)**: 30 days (720h)
- **Traces (Tempo)**: 30 days (720h)

### Storage Backend
- **Current**: Local filesystem (160GB SSD)
- **Future**: Wasabi S3 (buckets created, not yet configured)
  - `obs-okbrk-com-loki-logs`
  - `obs-okbrk-com-mimir-metrics`
  - `obs-okbrk-com-tempo-traces`

### Datasources in Grafana
- **Loki**: `http://loki:3100` (no X-Scope-OrgID needed)
- **Mimir**: `http://mimir:8080/prometheus` (no X-Scope-OrgID needed)
- **Tempo**: `http://tempo:3200` (no X-Scope-OrgID needed)

### Ports & Endpoints

**Public (via Caddy):**
- 80/tcp: HTTP (redirects to HTTPS)
- 443/tcp: HTTPS (Let's Encrypt certificates)
  - `api.obs.okbrk.com` → OTEL Collector, Loki push, Mimir push
  - `otlp.obs.okbrk.com` → OTEL Collector gRPC

**VPN-Only (Tailscale):**
- 3000/tcp: Grafana UI
- 9090/tcp: Prometheus UI
- 9093/tcp: Alertmanager UI
- 8081/tcp: cAdvisor UI
- 5432/tcp: PostgreSQL (if needed)
- 3100/tcp: Loki (internal)
- 8080/tcp: Mimir (internal)
- 3200/tcp: Tempo (internal)
- 9100/tcp: Node Exporter (internal)
- 9187/tcp: Postgres Exporter (internal)
- 12345/tcp: Grafana Agent (internal)

**SSH:**
- 22/tcp: Restricted to your IP (`MY_IP_CIDR` in .env)

---

## 📋 Common Workflows

### Deploy from Scratch

```bash
cd /Users/burak/projects/ok/apps/ok-monitoring

# 1. Configure
cp env.example .env
# Edit .env with your values

# 2. Deploy everything
bash scripts/setup.sh

# 3. Configure DNS
# api.obs.okbrk.com → 91.99.16.221
# otlp.obs.okbrk.com → 91.99.16.221

# 4. Access Grafana via Tailscale
# http://100.87.121.71:3000
```

### Add New Customer

```bash
# Create tenant
ssh ok-obs 'cd /opt/observability && \
  bash scripts/tenant-management/create-tenant.sh \
  "Customer Name" "email@example.com" "customer-slug"'

# Save the API key from output
# Send credentials + docs/CUSTOMER_GUIDE.md to customer
```

### Update Configuration

```bash
# 1. Edit config locally
vim config/loki/loki.yaml

# 2. Copy to server
scp config/loki/loki.yaml ok-obs:/opt/observability/config/loki/

# 3. Restart service
ssh ok-obs 'cd /opt/observability && docker compose restart loki'

# 4. Verify
ssh ok-obs 'docker logs loki --tail 20'
```

### Monitor Platform Health

```bash
# Service status
ssh ok-obs 'cd /opt/observability && docker compose ps'

# Resource usage
ssh ok-obs 'docker stats --no-stream'

# Disk space
ssh ok-obs 'df -h /opt/observability-data'

# View logs
ssh ok-obs 'cd /opt/observability && docker compose logs -f'

# Check monitoring stack health
ssh ok-obs 'curl -s http://localhost:9090/-/healthy' # Prometheus
ssh ok-obs 'curl -s http://localhost:9093/-/healthy' # Alertmanager

# View active alerts
ssh ok-obs 'curl -s http://localhost:9090/api/v1/alerts'

# Access monitoring UIs (via Tailscale VPN):
# - Grafana:      http://100.87.121.71:3000
# - Prometheus:   http://100.87.121.71:9090
# - Alertmanager: http://100.87.121.71:9093
# - cAdvisor:     http://100.87.121.71:8081
```

---

## 🐛 Debugging

### Check if Services are Running

```bash
ssh ok-obs 'cd /opt/observability && docker compose ps'
```

Expected output:
```
grafana        Up       3000/tcp
loki           Up       3100/tcp
mimir          Up       8080/tcp
tempo          Up       3200/tcp
otel-collector Up       4317-4318/tcp, 8888/tcp
grafana-agent  Up       12345/tcp
caddy          Up       80/tcp, 443/tcp
postgres       Up       5432/tcp
```

### Test Data Ingestion

**Test Logs:**
```bash
curl -X POST https://api.obs.okbrk.com/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: okbrk" \
  -H "Authorization: Bearer obs_f07962fbc30f4e469250d0ca8aafdf76edcfaeb6e961a4912a46a999287b5308" \
  -d '{
    "streams": [{
      "stream": {"job": "test", "service_name": "okbrk"},
      "values": [["'$(date +%s)'000000000", "Test log"]]
    }]
  }'

# Should return: HTTP/2 204 (success)
```

**Query Logs Directly:**
```bash
ssh ok-obs 'curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode "query={service_name=\"okbrk\"}" \
  --data-urlencode "start='$(($(date +%s) - 3600))'000000000" \
  --data-urlencode "end='$(date +%s)'000000000" \
  | jq ".data.result | length"'

# Should return: number > 0 if logs exist
```

### Check Grafana Datasources

```bash
# Test Loki datasource from Grafana container
ssh ok-obs 'docker exec grafana curl -s "http://loki:3100/ready"'
# Returns: ready

# Test Mimir datasource
ssh ok-obs 'docker exec grafana curl -s "http://mimir:8080/ready"'
# Returns: ready

# Test Tempo datasource
ssh ok-obs 'docker exec grafana curl -s "http://tempo:3200/ready"'
# Returns: ready
```

### View Service Logs

```bash
# Loki
ssh ok-obs 'docker logs loki --tail 100'

# Mimir
ssh ok-obs 'docker logs mimir --tail 100'

# Tempo
ssh ok-obs 'docker logs tempo --tail 100'

# Grafana
ssh ok-obs 'docker logs grafana --tail 100'

# OTEL Collector
ssh ok-obs 'docker logs otel-collector --tail 100'

# Caddy
ssh ok-obs 'docker logs caddy --tail 100'
```

---

## 📁 Important Files

### Configuration Files
- **Loki**: `config/loki/loki.yaml` (auth_enabled: false)
- **Mimir**: `config/mimir/mimir.yaml` (multitenancy: false)
- **Tempo**: `config/tempo/tempo.yaml` (multitenancy: false)
- **Grafana Datasources**: `config/grafana/datasources.yaml`
- **Caddy Routing**: `config/caddy/Caddyfile`
- **OTEL Collector**: `config/otel-collector/config.yaml`

### Scripts
- **Deployment**: `scripts/setup.sh`
- **Create Tenant**: `scripts/tenant-management/create-tenant.sh`
- **List Tenants**: `scripts/tenant-management/list-tenants.sh`
- **Rotate Key**: `scripts/tenant-management/rotate-api-key.sh`
- **Delete Tenant**: `scripts/tenant-management/delete-tenant.sh`
- **Health Check**: `scripts/smoke-test.sh`

### Documentation
- **Main README**: `docs/README.md`
- **Admin Operations**: `docs/ADMIN_GUIDE.md`
- **Customer Integration**: `docs/CUSTOMER_GUIDE.md`
- **Custom Dashboard**: `docs/ADMIN_DASHBOARD.md`
- **Security Model**: `SECURITY_ARCHITECTURE.md`

### Dashboards
- `dashboards/customer-overview.json`
- `dashboards/web-performance.json`
- `dashboards/web-vitals.json`
- `dashboards/ecommerce-tracking.json`
- `dashboards/logs-overview.json`

---

## 🔧 Key Configurations

### Environment Variables (.env)

```bash
# Domain & endpoints
DOMAIN=obs.okbrk.com

# Tailscale VPN
TAILSCALE_AUTHKEY=tskey-auth-xxxxx
TAILSCALE_IP=100.87.121.71

# Credentials
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=[secure-password]
POSTGRES_PASSWORD=[secure-password]

# Hetzner
HCLOUD_TOKEN=[api-token]
SSH_KEY_NAME=burak@okbrk.com
SSH_KEY_FILE=~/.ssh/id_ed25519
MY_IP_CIDR=[your-ip]/32

# Wasabi S3
WASABI_REGION=eu-central-1
WASABI_ENDPOINT=https://s3.eu-central-1.wasabisys.com
S3_LOKI_BUCKET=obs-okbrk-com-loki-logs
S3_MIMIR_BUCKET=obs-okbrk-com-mimir-metrics
S3_TEMPO_BUCKET=obs-okbrk-com-tempo-traces
```

### Terraform State

Located at: `infra/terraform/terraform.tfstate`

**Important**: Keep this file - contains infrastructure state.

---

## 📡 Network & DNS

### DNS Records (Configured)
```
api.obs.okbrk.com    A    91.99.16.221
otlp.obs.okbrk.com   A    91.99.16.221
```

### SSL Certificates
- **Provider**: Let's Encrypt (via Caddy)
- **Auto-renewal**: Yes
- **Expires**: ~90 days (auto-renewed at 30 days)

### Firewall
- **Hetzner Cloud Firewall**: Disabled (had outbound connectivity issues)
- **Security**: Relying on Hetzner network isolation + Tailscale VPN for admin

---

## 🎯 Quick Reference: Filtering Customers

Since multi-tenancy is disabled (for easier admin access), filter by **labels**:

### In Grafana Explore (Loki):
```logql
# All logs
{job=~".+"}

# Specific customer
{service_name="okbrk"}

# Multiple customers
{service_name=~"okbrk|customer2|customer3"}

# Customer + filter
{service_name="okbrk", level="error"}
```

### In Grafana Explore (Mimir):
```promql
# All metrics
{__name__=~".+"}

# Specific customer
http_requests_total{service_name="okbrk"}

# Aggregate by customer
sum by (service_name) (rate(http_requests_total[5m]))
```

---

## 🚨 Known Issues & Workarounds

### Issue: No Labels in Grafana Explore

**Cause**: No data sent yet, or time range too narrow

**Fix**:
1. Send test data (curl commands above)
2. Set time range to "Last 1 hour" or wider
3. Use code mode: `{service_name="okbrk"}`

### Issue: Grafana Shows "No data"

**Cause**: Datasource not configured with correct URL

**Fix**:
- Loki URL should be: `http://loki:3100` (not public API)
- Mimir URL should be: `http://mimir:8080/prometheus`
- Tempo URL should be: `http://tempo:3200`

### Issue: Can't Access Public Endpoints

**Cause**: DNS not propagated or browser cache

**Fix**:
1. Clear browser cache / use incognito
2. Test with curl first: `curl https://api.obs.okbrk.com/health`
3. Wait 5-10 minutes for DNS propagation

### Issue: Docker Can't Pull Images

**Cause**: systemd-resolved DNS issues

**Fix**: Already applied in cloud-init (configures DNS to use 8.8.8.8)

---

## 💡 Pro Tips

1. **Always use `ssh ok-obs`** - SSH config alias already set up
2. **Grafana accessible only via VPN** - connect to Tailscale first
3. **Test with curl before Grafana** - easier to debug
4. **Check service logs** if something breaks - `docker logs [service]`
5. **Time ranges matter** in Grafana - default is 6 hours
6. **Label-based filtering** is more flexible than strict multi-tenancy
7. **Keep API keys secure** - store in password manager

---

## 🔄 If Something Goes Wrong

### Nuclear Option: Restart Everything

```bash
ssh ok-obs 'cd /opt/observability && docker compose down'
sleep 5
ssh ok-obs 'cd /opt/observability && docker compose up -d'
sleep 30
ssh ok-obs 'cd /opt/observability && docker compose ps'
```

### Re-deploy from Scratch

```bash
cd /Users/burak/projects/ok/apps/ok-monitoring

# Destroy infrastructure
cd infra/terraform
terraform destroy -auto-approve \
  -var "hcloud_token=$HCLOUD_TOKEN" \
  -var "ssh_key_name=$SSH_KEY_NAME" \
  -var "my_ip_cidr=$MY_IP_CIDR"

# Re-deploy
cd ../..
bash scripts/setup.sh
```

**Data will be lost** - only do this if absolutely necessary!

---

## 📞 Quick Support Checklist

When asking for help, provide:

```bash
# Platform status
ssh ok-obs 'cd /opt/observability && docker compose ps'

# Service logs (last 50 lines)
ssh ok-obs 'docker logs [service] --tail 50'

# Disk space
ssh ok-obs 'df -h'

# Test endpoints
curl https://api.obs.okbrk.com/health

# What you're trying to do
# What error you're seeing
# What you've already tried
```

---

## 🎯 Current State

**Platform Status**: ✅ Operational
**Services**: 14/14 Running (includes infrastructure monitoring stack)
**Tenants**: 2 (admin, okbrk)
**Data Received**: Logs only (7 log entries from okbrk tenant)
**Metrics**: None yet (no apps instrumented)
**Traces**: None yet (no apps instrumented)
**Dashboards**: 6 ready to use (5 customer + 1 infrastructure)
**Public Endpoints**: ✅ Working with Let's Encrypt
**Admin Access**: ✅ Via Tailscale VPN
**Prometheus Scraping**: ✅ Ready (customers can register metrics endpoints)
**Infrastructure Monitoring**: ✅ Complete (Prometheus + Alertmanager + exporters)
**Alerting**: ✅ Configured (email + webhook support)

---

**Last Updated**: October 27, 2025
**Platform Version**: Docker Compose v1.0
**Location**: `/Users/burak/projects/ok/apps/ok-monitoring`

---

## 📌 Quick Copy-Paste Commands

```bash
# SSH to server
ssh ok-obs

# View services
ssh ok-obs 'cd /opt/observability && docker compose ps'

# Send test log
curl -X POST https://api.obs.okbrk.com/loki/api/v1/push -H "Content-Type: application/json" -H "X-Scope-OrgID: okbrk" -H "Authorization: Bearer obs_f07962fbc30f4e469250d0ca8aafdf76edcfaeb6e961a4912a46a999287b5308" -d '{"streams":[{"stream":{"job":"test","service_name":"okbrk"},"values":[["'$(date +%s)'000000000","Test"]]}]}'

# Query logs
ssh ok-obs 'curl -s -G "http://localhost:3100/loki/api/v1/query_range" --data-urlencode "query={service_name=\"okbrk\"}" --data-urlencode "start='$(($(date +%s)-3600))'000000000" --data-urlencode "end='$(date +%s)'000000000" | jq ".data.result | length"'

# Access Grafana
# http://100.87.121.71:3000 (Tailscale VPN required)

# Create customer
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/create-tenant.sh "Name" "email" "id"'

# List customers
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/list-tenants.sh'

# Register Prometheus endpoint
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/register-metrics-endpoint.sh tenant-id https://app.com/api/metrics 30'

# List metrics endpoints
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/list-metrics-endpoints.sh'

# Check infrastructure monitoring health
ssh ok-obs 'curl -s http://localhost:9090/-/healthy && echo " - Prometheus OK"'
ssh ok-obs 'curl -s http://localhost:9093/-/healthy && echo " - Alertmanager OK"'

# View active alerts
ssh ok-obs 'curl -s http://localhost:9090/api/v1/alerts | jq ".data.alerts[] | {alertname, state}"'

# Check platform resource usage
ssh ok-obs 'docker stats --no-stream'
```

---

**Save this document for future reference across different chat sessions!**

