# Security Architecture: VPN-Only Admin Access

This document explains the security model for the observability platform based on the separation of customer data ingestion (public) and admin tools (VPN-only).

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────┐
│                    INTERNET (PUBLIC)                            │
│                                                                  │
│  Customer Applications → https://api.yourdomain.com             │
│                       → https://otlp.yourdomain.com             │
│                                                                  │
│  ✓ Data Ingestion Endpoints (OTLP, Loki, Mimir)               │
│  ✓ API Key Authentication                                       │
│  ✓ Tenant Isolation via X-Scope-OrgID                          │
│  ✗ NO Admin Access                                             │
└────────────────────────────────────────────────────────────────┘
                              │
                              │ Firewall
                              ▼
┌────────────────────────────────────────────────────────────────┐
│                    HETZNER VM                                   │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │    Caddy     │  │     Loki     │  │    Mimir     │        │
│  │ (Public API) │  │    (Logs)    │  │  (Metrics)   │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │    Tempo     │  │  PostgreSQL  │  │ OTEL Collector│       │
│  │   (Traces)   │  │  (Tenants)   │  │   (Gateway)  │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
└────────────────────────────────────────────────────────────────┘
                              ▲
                              │ Tailscale VPN Only
                              │
┌────────────────────────────────────────────────────────────────┐
│                  TAILSCALE VPN (PRIVATE)                        │
│                                                                  │
│  Platform Admin → http://<tailscale-ip>:3000 (Grafana)        │
│  Platform Admin → http://<tailscale-ip>:3001 (Admin Dashboard) │
│                                                                  │
│  ✓ Full Access to Grafana                                     │
│  ✓ Access to Custom Admin Dashboard                           │
│  ✓ Direct Database Access (if needed)                         │
│  ✗ NOT Accessible from Public Internet                        │
└────────────────────────────────────────────────────────────────┘
```

## Why This Architecture?

### Security Benefits

1. **Zero Public Admin Access**
   - Grafana is never exposed to the internet
   - Reduces attack surface significantly
   - No brute force attempts on admin interface

2. **Principle of Least Privilege**
   - Customers only get API keys for data ingestion
   - Customers never see raw Grafana/tools
   - Only authorized admins access monitoring tools

3. **Separation of Concerns**
   - Customer data ingestion: Public with auth
   - Admin/analytics: Private VPN access
   - Custom dashboard: Can show curated data to customers

### Operational Benefits

1. **Custom Customer Experience**
   - Build a branded dashboard for customers
   - Show only relevant metrics
   - Hide infrastructure complexity

2. **Flexible Access Control**
   - Easily add/remove VPN users
   - No public login forms to secure
   - Audit trail via Tailscale

3. **Cost Effective**
   - Tailscale free tier: 100 devices
   - No need for complex auth on Grafana
   - Simpler firewall rules

## Access Patterns

### For Platform Admins (You & Your Team)

```bash
# 1. Connect to Tailscale
tailscale up

# 2. Access Grafana
http://<tailscale-ip>:3000
# Login: admin / your-password

# 3. Access Custom Admin Dashboard (when built)
http://<tailscale-ip>:3001

# 4. SSH to server (for maintenance)
ssh root@<public-ip>  # Or via Tailscale IP
```

### For Customers

```bash
# Customers ONLY use:
# 1. Data ingestion endpoints (public)
https://api.yourdomain.com/v1/traces
https://api.yourdomain.com/loki/api/v1/push
https://otlp.yourdomain.com

# 2. Custom dashboard you build for them
https://dashboard.yourdomain.com
# Shows curated data from their tenant
```

## Firewall Configuration

### Public Ports (Hetzner Firewall)
- Port 22: SSH (restricted to your IP)
- Port 80: HTTP (Let's Encrypt, redirects)
- Port 443: HTTPS (customer data ingestion)
- Port 41641: Tailscale UDP (VPN)

### Private Ports (Tailscale VPN only)
- Port 3000: Grafana
- Port 3001: Your custom admin dashboard
- Port 5432: PostgreSQL (direct access if needed)
- All other service ports

### Blocked (Not accessible from anywhere public)
- Port 3100: Loki internal
- Port 8080: Mimir internal
- Port 3200: Tempo internal
- Port 4317/4318: OTLP (only via Caddy proxy with auth)

## Tailscale Setup

### Initial Setup

1. **Create Tailscale account**: https://tailscale.com
2. **Generate auth key**: https://login.tailscale.com/admin/settings/keys
   - Set expiration to never (for server)
   - Mark as reusable (for multiple team members)
3. **Add to `.env`**:
   ```bash
   TAILSCALE_AUTHKEY=tskey-auth-xxxxx
   ```

### Adding Team Members

```bash
# Each team member:
1. Installs Tailscale: https://tailscale.com/download
2. Logs in with same Tailscale account
3. Automatically gets access to server

# Or use ACLs for more control:
# https://tailscale.com/kb/1018/acls/
```

### Accessing Admin Tools

```bash
# From any device on your Tailscale network:

# View Tailscale IP
tailscale status

# Access Grafana
open http://<tailscale-ip>:3000

# SSH via Tailscale (no public IP needed)
ssh root@<tailscale-ip>
```

## Customer Data Isolation

### How Tenant Isolation Works

1. **API Key → Tenant ID Mapping**
   ```
   PostgreSQL stores:
   tenant_id: "acme-corp"
   api_key: "obs_a1b2c3..."
   ```

2. **Request Flow**
   ```
   Customer → Caddy (validates API key)
           → OTEL Collector (adds X-Scope-OrgID header)
           → Loki/Mimir/Tempo (stores with tenant ID)
   ```

3. **Data Segregation**
   - Each tenant's data tagged with `X-Scope-OrgID`
   - Loki/Mimir/Tempo enforce tenant boundaries
   - Impossible for tenants to access each other's data

### Custom Dashboard Queries

When building your customer dashboard, always include tenant ID:

```typescript
// API route that queries Loki
const response = await fetch(`${LOKI_URL}/loki/api/v1/query_range?...`, {
  headers: {
    'X-Scope-OrgID': session.user.tenantId, // From your auth
  },
})
```

## Monitoring the Platform Itself

### Self-Monitoring

Create an `internal` tenant for platform metrics:

```bash
ssh root@<server-ip> 'cd /opt/observability && \
  bash scripts/tenant-management/create-tenant.sh "Internal Platform" "admin@yourdomain.com" internal'
```

Then monitor Docker containers:

```yaml
# docker-compose.yml - add this service
services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
      - OTEL_EXPORTER_OTLP_HEADERS=X-Scope-OrgID=internal
```

## Security Checklist

### Initial Setup
- [ ] Tailscale auth key generated and configured
- [ ] Firewall rules verified (only necessary ports open)
- [ ] Strong passwords set in `.env`
- [ ] DNS configured for customer endpoints
- [ ] SSH key authentication only (no password auth)

### Regular Maintenance
- [ ] Rotate API keys quarterly
- [ ] Review Tailscale access logs
- [ ] Monitor for unusual tenant usage
- [ ] Update Docker images monthly
- [ ] Backup PostgreSQL tenant database weekly

### Incident Response
- [ ] Revoke compromised API keys immediately
- [ ] Review logs for unauthorized access
- [ ] Notify affected customers
- [ ] Document incident and remediation

## Compliance Considerations

### Data Residency
- All data stored in Hetzner EU datacenter
- No data leaves your infrastructure
- Customer data isolated per tenant

### GDPR
- Customers own their data
- Can request data deletion
- Tenant deletion script provided
- Logs can be filtered by user ID

### Audit Trail
- All tenant operations logged in PostgreSQL
- API key usage tracked
- Last used timestamps recorded

## FAQ

### Q: Can customers access Grafana?
**A:** No. Grafana is only accessible via Tailscale VPN. Customers use your custom dashboard.

### Q: How do I add a new admin user?
**A:** Install Tailscale on their device and have them join your Tailscale network.

### Q: What if Tailscale goes down?
**A:** You can still access via SSH using the public IP. Grafana accessible via SSH tunnel: `ssh -L 3000:localhost:3000 root@<server-ip>`

### Q: Can I expose Grafana behind a login?
**A:** Not recommended. The current architecture is more secure. If needed, use Tailscale Funnel feature.

### Q: How do I backup the platform?
**A:** Use Hetzner volume snapshots + PostgreSQL dumps. See backup guide in main README.

## Next Steps

1. **Deploy the platform** using `scripts/setup.sh`
2. **Connect to Tailscale** and verify Grafana access
3. **Create test tenant** and send sample data
4. **Start building** custom admin dashboard (see ADMIN_DASHBOARD.md)
5. **Onboard first customer** with custom credentials

---

**Remember**: Admin tools are private, customer endpoints are public with API key auth. This separation keeps your platform secure while providing customers with seamless monitoring integration.

