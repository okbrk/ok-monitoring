# Administrator Guide - Multi-Tenant Observability Platform

Complete guide for platform administrators to manage customers, monitor the platform, and troubleshoot issues.

## Table of Contents

1. [Platform Access](#platform-access)
2. [Adding New Customers](#adding-new-customers)
3. [Managing Customers](#managing-customers)
4. [Monitoring the Platform](#monitoring-the-platform)
5. [Troubleshooting](#troubleshooting)
6. [Maintenance & Updates](#maintenance--updates)

---

## Platform Access

### Admin Tools (VPN-Only via Tailscale)

All admin tools are only accessible via Tailscale VPN:

**Grafana Dashboard:**
```
http://100.87.121.71:3000
```

**Login Credentials:**
- Username: `admin`
- Password: (from your `.env` file - `GRAFANA_ADMIN_PASSWORD`)

**SSH Access:**
```bash
# Via SSH config alias
ssh ok-obs

# View all services
ssh ok-obs 'cd /opt/observability && docker compose ps'

# View logs
ssh ok-obs 'cd /opt/observability && docker compose logs -f'
```

### Customer Data Ingestion Endpoints (Public)

Customers send data to these public HTTPS endpoints:

- **API Endpoint**: `https://api.obs.okbrk.com`
- **OTLP gRPC**: `https://otlp.obs.okbrk.com`
- **Health Check**: `https://api.obs.okbrk.com/health`

---

## Adding New Customers

### Step 1: Create Tenant Account

```bash
# SSH to the server
ssh ok-obs

# Navigate to observability directory
cd /opt/observability

# Create new tenant
bash scripts/tenant-management/create-tenant.sh "Customer Name" "customer@email.com" "customer-id"
```

**Example:**
```bash
bash scripts/tenant-management/create-tenant.sh "Acme Corp" "admin@acme.com" "acme"
```

**Output:**
```
=========================================
Tenant Information
=========================================
Tenant ID:    acme
Name:         Acme Corp
Email:        admin@acme.com
API Key:      obs_abc123...

⚠️  IMPORTANT: Save this API key securely. It cannot be retrieved later.
```

**Important**: Copy and save the API key immediately - you'll need to send this to the customer.

### Step 2: Prepare Customer Onboarding Package

The tenant creation script automatically generates:

1. **Tenant config file**: `/opt/observability/tenants/acme.json`
2. **Onboarding guide**: `/opt/observability/tenants/acme-onboarding.md`

Copy the onboarding guide to send to your customer:

```bash
ssh ok-obs "cat /opt/observability/tenants/acme-onboarding.md" > customer-onboarding-acme.md
```

### Step 3: Send Credentials to Customer

Email the customer with:

**Subject**: Your Observability Platform Access

**Body**:
```
Hi [Customer Name],

Your monitoring platform access is ready! Here are your credentials:

Tenant ID: acme
API Key: obs_abc123... (secure this - don't share publicly)

Integration Endpoints:
- API: https://api.obs.okbrk.com
- OTLP gRPC: https://otlp.obs.okbrk.com

Please see the attached integration guide for:
- Next.js / React setup
- WordPress / Shopify setup
- Testing your integration

Support: your-support-email@example.com

Best regards,
Your Team
```

**Attach**:
- Customer onboarding guide (generated file)
- Or link them to your `docs/CUSTOMER_GUIDE.md`

### Step 4: Verify Customer Integration

After the customer integrates:

1. **Check Data Ingestion** in Grafana:
   - Go to **Explore**
   - Select **Loki** datasource
   - Query: `{service_name="acme"}`
   - Should see their logs

2. **Check Metrics**:
   - Select **Mimir** datasource
   - Query: `http_server_requests_total{service_name="acme"}`

3. **Check Traces**:
   - Select **Tempo** datasource
   - Search for traces with tag `service.name=acme`

---

## Managing Customers

### List All Customers

```bash
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/list-tenants.sh'
```

**Output:**
```
tenant_id,name,email,is_active,created_at,active_keys
acme,Acme Corp,admin@acme.com,t,2025-10-27,1
globex,Globex Corp,admin@globex.com,t,2025-10-27,1
...

Tenant Statistics:
 tenant_id | name       | logs_mb | metrics_count | traces_count | queries
-----------+------------+---------+---------------+--------------+---------
 acme      | Acme Corp  | 1250    | 50000         | 1200         | 45
```

### View Customer Usage

```bash
# Connect to PostgreSQL
ssh ok-obs "docker exec -it postgres psql -U tenants -d tenants"

# Query usage stats
SELECT
    t.name,
    SUM(u.logs_ingested_bytes) / 1024 / 1024 as logs_mb,
    SUM(u.metrics_ingested_count) as metrics,
    SUM(u.traces_ingested_count) as traces
FROM tenants t
LEFT JOIN usage_stats u ON t.tenant_id = u.tenant_id
WHERE u.date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY t.name
ORDER BY logs_mb DESC;
```

### Rotate Customer API Key

If a customer's API key is compromised:

```bash
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/rotate-api-key.sh customer-id'
```

**Example:**
```bash
bash scripts/tenant-management/rotate-api-key.sh acme
```

**Output:**
```
New API Key
=========================================
Tenant ID: acme
API Key:   obs_new_key_xyz...

⚠️ Update this key in your customer's configuration
```

Send the new API key to the customer and have them update their configuration.

### Deactivate a Customer

To temporarily disable a customer (suspend service):

```bash
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/delete-tenant.sh customer-id'
```

**Example:**
```bash
bash scripts/tenant-management/delete-tenant.sh acme
```

This will:
- Mark tenant as inactive
- Revoke all API keys
- **Note**: Historical data remains (for compliance/records)

### Permanently Delete Customer Data

```bash
# Connect to PostgreSQL
ssh ok-obs "docker exec -it postgres psql -U tenants -d tenants"

# Permanently delete tenant
DELETE FROM tenants WHERE tenant_id = 'acme';
```

**Warning**: This only deletes the tenant record. Log/metric/trace data in Loki/Mimir/Tempo persists until retention policies expire (30 days default).

---

## Monitoring the Platform

### Platform Health Dashboard

Create a dashboard in Grafana to monitor the platform itself:

1. **Go to Dashboards** → **New** → **New Dashboard**
2. **Add panels for**:
   - Docker container CPU/Memory usage
   - Disk usage on `/opt/observability-data`
   - Request rates to ingestion endpoints
   - Error rates per tenant
   - Data ingestion volume

### Key Metrics to Monitor

**Platform Resources:**
```bash
# Check disk usage
ssh ok-obs "df -h /opt/observability-data"

# Check Docker resource usage
ssh ok-obs "docker stats --no-stream"

# Check service health
ssh ok-obs "cd /opt/observability && docker compose ps"
```

**Data Volume by Tenant:**

In Grafana Explore (Mimir):
```promql
# Top tenants by request volume
topk(10, sum by (X-Scope-OrgID) (rate(http_server_requests_total[1h])))
```

In Grafana Explore (Loki):
```logql
# Log volume by tenant
sum by (X-Scope-OrgID) (rate({job=~".+"}[5m]))
```

### Alerts to Configure

Set up alerts in Grafana for:

1. **Platform Health**:
   - Any service down for > 5 minutes
   - Disk usage > 80%
   - Memory usage > 85%

2. **Customer SLAs**:
   - Error rate > 5% for any customer
   - P95 latency > 1 second
   - No data received from customer in 1 hour

3. **Security**:
   - Failed authentication attempts > 100/hour
   - Unusual data volume from a tenant

---

## Troubleshooting

### Services Not Running

```bash
# Check status
ssh ok-obs "cd /opt/observability && docker compose ps"

# Restart specific service
ssh ok-obs "cd /opt/observability && docker compose restart loki"

# Restart all services
ssh ok-obs "cd /opt/observability && docker compose restart"

# View logs for errors
ssh ok-obs "cd /opt/observability && docker compose logs loki --tail 100"
```

### Customer Can't Send Data

**Check 1: Verify API Key**
```bash
# Query PostgreSQL
ssh ok-obs "docker exec postgres psql -U tenants -d tenants -c \"SELECT tenant_id, api_key, is_active FROM tenants WHERE tenant_id = 'acme';\""
```

**Check 2: Test Endpoint**
```bash
# From your machine
curl -X POST https://api.obs.okbrk.com/v1/traces \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: acme" \
  -H "Authorization: Bearer obs_customer_api_key" \
  -d '{}'

# Should return 200 or validation error (not 401)
```

**Check 3: Check Service Logs**
```bash
# Check OTEL collector logs for the customer
ssh ok-obs "docker logs otel-collector --tail 100 | grep acme"

# Check Loki for ingestion errors
ssh ok-obs "docker logs loki --tail 100 | grep acme"
```

### Grafana Can't Query Data

**Issue**: "No org ID" or 401 errors

**Fix**: Datasources need `X-Scope-OrgID` header

1. Go to **Connections** → **Data sources**
2. Click on **Mimir** (or Loki/Tempo)
3. Scroll to **Custom HTTP Headers**
4. Add header:
   - **Header**: `X-Scope-OrgID`
   - **Value**: `admin` (or specific tenant ID)
5. Click **Save & test**

### Disk Space Running Low

```bash
# Check current usage
ssh ok-obs "df -h /opt/observability-data"

# Check which service uses most space
ssh ok-obs "du -sh /opt/observability-data/*"

# Clean old data manually if needed
ssh ok-obs "find /opt/observability-data/loki/chunks -mtime +30 -delete"
ssh ok-obs "find /opt/observability-data/tempo/traces -mtime +14 -delete"
```

**Permanent Fix**: Adjust retention in configs or migrate to S3 storage.

### Let's Encrypt Certificate Issues

```bash
# Check Caddy logs
ssh ok-obs "docker logs caddy --tail 50"

# Force certificate renewal
ssh ok-obs "docker compose restart caddy"

# Verify DNS is correct
dig api.obs.okbrk.com +short
# Should return: 91.99.16.221
```

---

## Maintenance & Updates

### Daily Checks

```bash
# Quick health check script
ssh ok-obs '
cd /opt/observability
echo "=== Service Status ==="
docker compose ps

echo -e "\n=== Disk Usage ==="
df -h /opt/observability-data

echo -e "\n=== Active Tenants ==="
docker exec postgres psql -U tenants -d tenants -t -c "SELECT COUNT(*) FROM tenants WHERE is_active = true;"

echo -e "\n=== 24h Request Volume ==="
# Add Prometheus query here
'
```

### Weekly Maintenance

1. **Review customer usage** (identify high-volume tenants)
2. **Check for errors** in platform logs
3. **Verify backups** (if configured)
4. **Update dashboard** if needed

### Monthly Tasks

1. **Update Docker images**:
```bash
ssh ok-obs "cd /opt/observability && docker compose pull"
ssh ok-obs "cd /opt/observability && docker compose up -d"
```

2. **Review retention policies** (adjust if needed)

3. **Check S3 costs** (if using Wasabi)

4. **Rotate admin API keys**

### Backup Strategy

**Option 1: Hetzner Snapshots (Recommended)**

1. Go to Hetzner Cloud Console
2. Select your server (`ok-obs-01`)
3. Click **Actions** → **Create snapshot**
4. Name it: `obs-backup-2025-10-27`
5. Automate with Hetzner API or CLI

**Option 2: PostgreSQL Backup**

```bash
# Backup tenant database
ssh ok-obs "docker exec postgres pg_dump -U tenants tenants" > tenants-backup-$(date +%Y%m%d).sql

# Restore if needed
cat tenants-backup-20251027.sql | ssh ok-obs "docker exec -i postgres psql -U tenants tenants"
```

**Option 3: Configuration Backup**

```bash
# Backup configs and tenant data
ssh ok-obs "tar czf /tmp/obs-config-backup.tar.gz /opt/observability/config /opt/observability/tenants"
scp ok-obs:/tmp/obs-config-backup.tar.gz ./backups/obs-config-$(date +%Y%m%d).tar.gz
```

---

## Scaling

### When to Scale

Monitor these indicators:

| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU Usage | Consistently > 75% | Upgrade VM |
| Memory Usage | > 85% | Upgrade VM or add swap |
| Disk I/O Wait | > 30% | Add SSD or migrate to S3 |
| Tenants | > 50 active | Consider second VM |
| Disk Space | > 80% | Increase volume or add S3 |

### Vertical Scaling (Recommended First)

```bash
# Current: CPX32 (4 vCPU, 8GB RAM, 160GB SSD) - €13.30/month
# Upgrade to: CPX42 (8 vCPU, 16GB RAM, 320GB SSD) - €24.19/month

cd /Users/burak/projects/ok/apps/ok-monitoring

# Update .env
# Change: (edit manually or use sed)
# In infra/terraform/variables.tf, change default to "cpx42"

# Apply changes
cd infra/terraform
source ../../.env
terraform apply \
  -var "hcloud_token=$HCLOUD_TOKEN" \
  -var "ssh_key_name=$SSH_KEY_NAME" \
  -var "my_ip_cidr=$MY_IP_CIDR"

# Server will reboot (5-10 minute downtime)
```

### Migrate to S3 Storage

When local disk is insufficient (>100 tenants or long retention):

1. **Update configs** to use S3 (Wasabi)
2. **Copy updated configs** to server
3. **Restart services**
4. **Verify data** appears in S3 buckets

See `docs/README.md` section on S3 configuration.

---

## Customer Onboarding Workflow

### Complete Onboarding Checklist

- [ ] **Create tenant account** (generate API key)
- [ ] **Save credentials** securely
- [ ] **Prepare onboarding email** with credentials
- [ ] **Send integration guide** (CUSTOMER_GUIDE.md)
- [ ] **Schedule onboarding call** (optional, for complex setups)
- [ ] **Test data ingestion** (ask customer to send test event)
- [ ] **Verify data in Grafana** (check logs/metrics/traces)
- [ ] **Create custom dashboard** for customer (optional)
- [ ] **Set up alerts** for customer SLAs (optional)

### Sample Onboarding Email Template

```
Subject: Welcome to [Your Company] Observability Platform

Hi [Customer Name],

Welcome! Your monitoring platform is ready.

CREDENTIALS:
-----------
Tenant ID: [tenant-id]
API Key: [api-key]

ENDPOINTS:
----------
API: https://api.obs.okbrk.com
OTLP: https://otlp.obs.okbrk.com

NEXT STEPS:
-----------
1. Review the attached integration guide
2. Install OpenTelemetry in your application (see guide)
3. Configure with your credentials
4. Test by sending a sample trace/log
5. Reach out if you need help!

Your application type: [Next.js / WordPress / Shopify]
See section: [specific section in guide]

SUPPORT:
--------
Email: support@example.com
Response time: < 24 hours

Best regards,
[Your Team]
```

---

## Advanced Operations

### Query Tenant Data Directly

```bash
# View all tenants
ssh ok-obs "docker exec postgres psql -U tenants -d tenants -c 'SELECT * FROM tenants;'"

# Get specific tenant info
ssh ok-obs "docker exec postgres psql -U tenants -d tenants -c \"SELECT * FROM tenants WHERE tenant_id = 'acme';\""

# View API keys
ssh ok-obs "docker exec postgres psql -U tenants -d tenants -c \"SELECT tenant_id, api_key, is_active, created_at FROM api_keys;\""
```

### Manually Test Data Ingestion

```bash
# Test Loki ingestion
curl -X POST https://api.obs.okbrk.com/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: admin" \
  -d '{
    "streams": [{
      "stream": {"job": "test", "service_name": "test"},
      "values": [["'$(date +%s)'000000000", "Test log message"]]
    }]
  }'

# Test Mimir (Prometheus remote write)
# Requires protobuf format - use Prometheus client

# Test OTLP
grpcurl -v \
  -H "X-Scope-OrgID: admin" \
  -H "Authorization: Bearer obs_your_admin_key" \
  -d '{"resource_spans":[]}' \
  otlp.obs.okbrk.com:443 \
  opentelemetry.proto.collector.trace.v1.TraceService/Export
```

### Audit Log Access

```bash
# View tenant API key usage
ssh ok-obs "docker exec postgres psql -U tenants -d tenants -c \"
  SELECT tenant_id, last_used_at
  FROM api_keys
  WHERE is_active = true
  ORDER BY last_used_at DESC;
\""

# This shows when each tenant last sent data
```

### Update Platform Configuration

```bash
# Update any service config
cd /Users/burak/projects/ok/apps/ok-monitoring

# 1. Edit config file locally
vim config/loki/loki.yaml

# 2. Copy to server
scp config/loki/loki.yaml ok-obs:/opt/observability/config/loki/

# 3. Restart service
ssh ok-obs "cd /opt/observability && docker compose restart loki"

# 4. Verify
ssh ok-obs "docker logs loki --tail 20"
```

---

## Security Best Practices

### Regular Security Tasks

**Weekly:**
- [ ] Review failed auth attempts
- [ ] Check for unusual data volumes
- [ ] Verify all services are up to date

**Monthly:**
- [ ] Rotate admin passwords
- [ ] Review tenant access patterns
- [ ] Update Docker images
- [ ] Review firewall rules

**Quarterly:**
- [ ] Rotate tenant API keys (communicate with customers first)
- [ ] Review and update retention policies
- [ ] Audit user access logs
- [ ] Security patch review

### Access Control

**Who has access to what:**

| Role | Grafana | SSH | PostgreSQL | Customer Data |
|------|---------|-----|------------|---------------|
| **Platform Admin (You)** | ✅ Full | ✅ Yes | ✅ Yes | ✅ All tenants |
| **Team Member (Tailscale)** | ✅ Full | ✅ Yes | ❌ No | ✅ All tenants |
| **Customer** | ❌ No | ❌ No | ❌ No | ✅ Own data only (via custom dashboard) |

### Incident Response Plan

**If customer reports missing data:**

1. Check if service is running: `docker compose ps`
2. Check customer's API key is valid
3. Check service logs for ingestion errors
4. Test ingestion manually with their credentials
5. Check retention hasn't deleted their data

**If platform is down:**

1. SSH to server
2. Check Docker: `docker ps -a`
3. Check system resources: `htop`
4. Review logs: `docker compose logs`
5. Restart services if needed
6. Notify affected customers

**If data breach suspected:**

1. Immediately rotate all API keys
2. Review access logs
3. Check for unauthorized queries
4. Notify affected customers
5. Review and update security measures

---

## Platform Costs

### Current Setup

**Infrastructure:**
- Hetzner CPX32: €13.30/month
- Wasabi S3 (minimal): €6.99/month
- **Total**: ~€20/month (~$22/month)

**Cost per Tenant:**
- With 10 tenants: ~€2/tenant/month
- With 50 tenants: ~€0.40/tenant/month

### Cost Optimization

1. **Adjust retention**: Shorter = less storage
2. **Implement sampling**: For high-volume apps
3. **Use compression**: Already enabled in configs
4. **Monitor S3 usage**: Delete old data proactively

---

## Quick Reference Commands

### Service Management

```bash
# View all services
ssh ok-obs 'cd /opt/observability && docker compose ps'

# Restart all
ssh ok-obs 'cd /opt/observability && docker compose restart'

# View logs
ssh ok-obs 'cd /opt/observability && docker compose logs -f [service]'

# Update services
ssh ok-obs 'cd /opt/observability && docker compose pull && docker compose up -d'
```

### Tenant Management

```bash
# Create tenant
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/create-tenant.sh "Name" "email" "id"'

# List tenants
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/list-tenants.sh'

# Rotate key
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/rotate-api-key.sh tenant-id'

# Deactivate
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/delete-tenant.sh tenant-id'
```

### Platform Monitoring

```bash
# Disk usage
ssh ok-obs "df -h"

# Container stats
ssh ok-obs "docker stats --no-stream"

# Network connections
ssh ok-obs "netstat -an | grep ESTABLISHED | wc -l"

# Check Tailscale status
ssh ok-obs "tailscale status"
```

---

## Support Escalation

### Customer Support Tiers

**Tier 1** (You handle):
- Integration questions
- API key issues
- Basic troubleshooting

**Tier 2** (Requires investigation):
- Performance issues
- Data not appearing
- Complex queries

**Tier 3** (Platform issues):
- Service outages
- Data loss
- Security incidents

### Getting Help

- **Grafana Community**: https://community.grafana.com
- **Loki Docs**: https://grafana.com/docs/loki/
- **Mimir Docs**: https://grafana.com/docs/mimir/
- **Tempo Docs**: https://grafana.com/docs/tempo/
- **OpenTelemetry**: https://opentelemetry.io/docs/

---

## Appendix: Useful SQL Queries

### Tenant Analytics

```sql
-- Most active tenants (last 7 days)
SELECT
    t.name,
    COUNT(DISTINCT u.date) as active_days,
    SUM(u.queries_executed) as total_queries
FROM tenants t
LEFT JOIN usage_stats u ON t.tenant_id = u.tenant_id
WHERE u.date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY t.name
ORDER BY total_queries DESC
LIMIT 10;

-- Tenants with no activity
SELECT tenant_id, name, email, created_at
FROM tenants
WHERE tenant_id NOT IN (
    SELECT DISTINCT tenant_id
    FROM usage_stats
    WHERE date >= CURRENT_DATE - INTERVAL '7 days'
)
AND is_active = true;

-- Revenue potential (if tracking usage for billing)
SELECT
    t.name,
    SUM(u.logs_ingested_bytes) / 1024 / 1024 / 1024 as logs_gb,
    SUM(u.metrics_ingested_count) / 1000000 as metrics_millions
FROM tenants t
LEFT JOIN usage_stats u ON t.tenant_id = u.tenant_id
WHERE u.date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY t.name;
```

---

**Your observability platform is fully operational!** Use this guide for all customer onboarding and platform management tasks. 🎉

