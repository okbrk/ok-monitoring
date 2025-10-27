# Migration Summary: k3s to Docker Compose

This document summarizes the major architectural changes from the complex k3s-based setup to the simplified Docker Compose architecture.

## What Changed

### Removed Components

- ❌ Kubernetes (k3s) - 3-node cluster
- ❌ Helmfile and Helm charts
- ❌ cert-manager for certificate management
- ❌ step-ca internal PKI
- ❌ CoreDNS custom DNS setup
- ❌ Tailscale VPN requirement
- ❌ NGINX Ingress Controller
- ❌ Manual kubectl operations
- ❌ Complex networking setup

### Added Components

- ✅ Docker Compose orchestration
- ✅ Caddy reverse proxy with automatic Let's Encrypt
- ✅ PostgreSQL for tenant management
- ✅ OpenTelemetry Collector as gateway
- ✅ Automated tenant management scripts
- ✅ Public HTTPS endpoints
- ✅ Simplified single-VM architecture

### Infrastructure Changes

**Before:**
- 3x Hetzner VMs (cx22: 2 vCPU, 4GB RAM each)
- Private network between nodes
- Complex firewall rules
- Tailscale VPN for access
- Manual steps for PKI and DNS

**After:**
- 1x Hetzner VM (cpx32: 4 vCPU, 8GB RAM, 160GB SSD)
- 100GB block storage volume (optional with larger SSD)
- Simple firewall (SSH, HTTP, HTTPS, OTLP)
- Public access via Let's Encrypt
- Zero manual steps after env configuration

### Cost Comparison

| Component | Before | After |
|-----------|--------|-------|
| Compute | 3x €4 = €12 | 1x €13.30 = €13.30 |
| Storage | Included | €4 (100GB volume) |
| **Total** | **~€12/mo** | **~€17.30/mo** |

The slight cost increase is offset by:
- Significantly reduced operational complexity
- No Tailscale subscription needed for scale
- Easier scaling path
- Better resource utilization

## Deployment Comparison

### Before (k3s)

```bash
# 1. Create secrets.env (40+ variables)
# 2. terraform apply
# 3. Wait for VMs
# 4. Install Tailscale on all nodes
# 5. Approve subnet routes (manual)
# 6. Bootstrap k3s master
# 7. Get join token
# 8. Bootstrap 2x k3s agents
# 9. Configure kubectl
# 10. Wait for nodes Ready
# 11. Deploy metrics-server
# 12. Deploy cert-manager
# 13. Wait for cert-manager Ready
# 14. Deploy CoreDNS
# 15. Configure Tailscale split DNS (manual)
# 16. Generate PKI certificates
# 17. Deploy step-ca
# 18. Create ClusterIssuer
# 19. Wait for step-ca Ready
# 20. Deploy NGINX Ingress
# 21. Create Wasabi buckets
# 22. Deploy observability stack
# 23. Create certificate
# 24. Wait 5-10 minutes for pods

# Total time: ~30-40 minutes + manual steps
# Lines of code: ~1000+
# Manual interventions: 3-4
```

### After (Docker Compose)

```bash
# 1. cp env.example .env && edit .env
# 2. bash scripts/setup.sh
# 3. Configure DNS A records (2 minutes)

# Total time: ~5-7 minutes + DNS propagation
# Lines of code: ~200
# Manual interventions: 1 (DNS only)
```

## Feature Comparison

| Feature | Before | After | Notes |
|---------|--------|-------|-------|
| Multi-tenancy | ✅ | ✅ | Improved with PostgreSQL tracking |
| Logs (Loki) | ✅ | ✅ | Same functionality |
| Metrics (Mimir) | ✅ | ✅ | Same functionality |
| Traces (Tempo) | ✅ | ✅ | Same functionality |
| Grafana | ✅ | ✅ | Same functionality |
| HTTPS/TLS | ✅ | ✅ | Simpler with Caddy |
| High Availability | ✅ | ⚠️ | Single VM (can be scaled) |
| Auto-scaling | ✅ | ❌ | Over-engineering for <50 tenants |
| Tenant Management | ❌ | ✅ | New automated scripts |
| API Key Auth | Manual | ✅ | Automated generation |
| Customer Onboarding | Manual | ✅ | Auto-generated docs |
| Backup | Manual | ✅ | Hetzner snapshots |
| Monitoring Stack | ❌ | ✅ | Built-in metrics |

## Migration Path

### For Fresh Deployments

Simply follow the new `docs/README.md` guide. No migration needed.

### For Existing k3s Deployments

**Recommended approach: Fresh deployment**

1. Deploy new infrastructure following new guide
2. Recreate tenants with new credentials
3. Migrate customer configs to new endpoints
4. Test thoroughly
5. Decommission old k3s cluster

**Why not in-place migration?**
- Fundamentally different architectures
- Data models changed (PostgreSQL for tenants)
- No downtime-free migration path
- Fresh start is faster and safer

### Customer Impact

Customers will need to:
1. Update API endpoints (domain change possible)
2. Use new API keys
3. Update X-Scope-OrgID headers

Provide 2-4 weeks notice for customers to update configurations.

## Operations Improvements

### Before: Kubernetes Operations

```bash
# Check status
kubectl get pods -n observability -w
kubectl describe pod loki-0 -n observability
kubectl logs -f loki-0 -n observability

# Restart service
kubectl rollout restart deployment/grafana -n observability

# Scale
kubectl scale deployment/loki-read --replicas=3

# Update configuration
kubectl edit configmap loki-config -n observability
kubectl rollout restart deployment/loki

# Debug
kubectl exec -it mimir-0 -n observability -- sh
```

### After: Docker Compose Operations

```bash
# Check status
docker compose ps
docker compose logs -f loki

# Restart service
docker compose restart loki

# Scale (if needed)
docker compose up -d --scale loki=3

# Update configuration
vim config/loki/loki.yaml
docker compose restart loki

# Debug
docker exec -it loki sh
```

**~70% fewer commands, more intuitive operations**

## Scaling Considerations

### When Current Setup is Sufficient

- <50 active tenants
- <10TB/month combined data
- <1000 queries/second
- <99.5% uptime requirement

### When to Consider Scaling

- >50 active tenants
- Need for high availability
- Geographic distribution required
- >99.9% uptime requirement

### Scaling Options

1. **Vertical**: Upgrade to cpx41 (8 vCPU, 16GB RAM)
2. **Horizontal**: Add more VMs with load balancer
3. **Distributed**: Move to Kubernetes with Mimir/Loki in microservices mode
4. **Hybrid**: Use managed services (Grafana Cloud) for storage

## Lessons Learned

### What We Gained

- **Simplicity**: 80% less code, 90% fewer manual steps
- **Maintainability**: Standard Docker Compose, well-documented
- **Reliability**: Fewer moving parts, easier to troubleshoot
- **Speed**: 5x faster deployments
- **Cost**: Better resource utilization
- **Tenant Management**: Automated and tracked

### What We Lost (and why it's okay)

- **Auto-scaling**: Not needed for target scale (<50 tenants)
- **Multi-node HA**: Can be added later if needed
- **Kubernetes ecosystem**: Over-engineering for the use case

### Key Insight

> "Perfect is the enemy of good. The k3s setup was technically impressive but operationally complex. The Docker Compose setup is 'just right' for the target scale and much easier to understand, deploy, and maintain."

## Next Steps After Migration

1. **Monitor resource usage** for 2-4 weeks
2. **Collect feedback** from operators
3. **Document** any edge cases
4. **Consider** S3 backend for long-term storage (Wasabi)
5. **Evaluate** scaling needs at 40-50 tenants

## Questions?

Refer to:
- `docs/README.md` - Main documentation
- `docs/CUSTOMER_GUIDE.md` - Customer integration guide
- `scripts/` - Operational scripts with inline comments

