# Multi-Tenant Observability Platform

A simplified, production-ready observability platform for monitoring SaaS applications. Built on Grafana, Loki, Mimir, and Tempo with Docker Compose for easy deployment and management.

## Overview

This platform provides a complete observability stack for multi-tenant SaaS environments, allowing you to collect and analyze logs, metrics, and traces from customer applications deployed anywhere.

### Key Features

- **Multi-Tenancy**: Isolated data per tenant with API key authentication
- **Full Observability**: Logs (Loki), Metrics (Mimir), Traces (Tempo)
- **Simple Deployment**: Docker Compose on a single VM (scalable to multiple VMs)
- **Automatic HTTPS**: Caddy with Let's Encrypt certificate management
- **Remote Collection**: Customers send data via OTLP, Prometheus Remote Write, or Loki API
- **Self-Hosted**: Complete control over your data on Hetzner Cloud VMs
- **Tenant Management**: Automated scripts for tenant provisioning and management

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Customer Applications                 │
│         (Deployed anywhere - send data remotely)         │
└──────────────┬──────────────────────┬───────────────────┘
               │                      │
               │ OTLP/Remote Write   │ API Calls
               │                      │
┌──────────────▼──────────────────────▼───────────────────┐
│              Hetzner Cloud VM (cpx31)                    │
│  ┌────────────────────────────────────────────────────┐ │
│  │  Caddy (Reverse Proxy + HTTPS)                     │ │
│  └───┬────────────────────────────────────────────────┘ │
│      │                                                   │
│  ┌───▼──────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ OpenTelemetry│  │   Grafana    │  │  PostgreSQL  │  │
│  │  Collector   │  │  (Frontend)  │  │  (Tenants)   │  │
│  └───┬──────────┘  └──────────────┘  └──────────────┘  │
│      │                                                   │
│  ┌───▼──────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │     Loki     │  │    Mimir     │  │    Tempo     │  │
│  │    (Logs)    │  │  (Metrics)   │  │   (Traces)   │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                           │
│  ┌────────────────────────────────────────────────────┐ │
│  │  Block Storage Volume (100GB)                      │ │
│  │  /opt/observability-data                           │ │
│  └────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────┘
```

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Configuration](#configuration)
4. [Deployment](#deployment)
5. [Tenant Management](#tenant-management)
6. [Customer Onboarding](#customer-onboarding)
7. [Monitoring and Maintenance](#monitoring-and-maintenance)
8. [Scaling](#scaling)
9. [Backup and Recovery](#backup-and-recovery)
10. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools

Install the following on your local machine:

- [Terraform](https://www.terraform.io/downloads) (>= 1.6)
- [jq](https://stedolan.github.io/jq/download/)
- SSH client
- A domain name with DNS management access

### Accounts and Access

- **Hetzner Cloud Account**: [Sign up here](https://www.hetzner.com/cloud)
- **SSH Key**: Upload your public key to Hetzner Cloud console

### Estimated Costs

For <50 tenants with moderate usage:
- **Hetzner CPX32** (4 vCPU, 8GB RAM, 160GB SSD): ~€13.30/month
- **100GB Block Storage**: ~€4/month
- **Traffic**: Included (20TB)
- **Total**: ~€17.30/month (~$19/month)

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/ok-monitoring.git
cd ok-monitoring
```

### 2. Configure Environment

Copy the example environment file and customize it:

```bash
cp env.example .env
```

Edit `.env` with your values:

```bash
# Required
DOMAIN=obs.example.com
HCLOUD_TOKEN=your_hetzner_api_token
SSH_KEY_NAME=your_ssh_key_name
MY_IP_CIDR=1.2.3.4/32

# Credentials (change these!)
GRAFANA_ADMIN_PASSWORD=strong_password_here
POSTGRES_PASSWORD=another_strong_password

# Optional
LOCATION=nbg1  # Hetzner datacenter (nbg1, fsn1, hel1)
```

### 3. Deploy Infrastructure

Run the automated setup script:

```bash
bash scripts/setup.sh
```

This script will:
1. Provision a Hetzner VM with Terraform
2. Install Docker and dependencies via cloud-init
3. Deploy the Docker Compose stack
4. Create the admin tenant
5. Provide you with access credentials

### 4. Configure DNS

Point your domain to the server IP (provided by the setup script):

```
obs.example.com       A    <SERVER_IP>
api.obs.example.com   A    <SERVER_IP>
otlp.obs.example.com  A    <SERVER_IP>
```

Wait 2-3 minutes for DNS propagation and Let's Encrypt certificate issuance.

### 5. Access Grafana

Open your browser and navigate to:

```
https://obs.example.com/grafana/
```

Log in with the credentials from the setup script output.

## Configuration

### Environment Variables

#### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DOMAIN` | Your platform domain | `obs.example.com` |
| `HCLOUD_TOKEN` | Hetzner Cloud API token | Get from Hetzner console |
| `SSH_KEY_NAME` | SSH key name in Hetzner | `my-ssh-key` |
| `MY_IP_CIDR` | Your IP for SSH access | `1.2.3.4/32` |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password | Use a strong password |
| `POSTGRES_PASSWORD` | PostgreSQL password | Use a strong password |

#### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LOCATION` | Hetzner datacenter | `nbg1` |
| `DATA_DIR` | Data directory path | `/opt/observability-data` |
| `GRAFANA_ADMIN_USER` | Grafana admin username | `admin` |

### Service Configuration

Advanced configuration can be modified in:

- `config/loki/loki.yaml` - Loki configuration (retention, limits)
- `config/mimir/mimir.yaml` - Mimir configuration (storage, compaction)
- `config/tempo/tempo.yaml` - Tempo configuration (trace retention)
- `config/grafana/datasources.yaml` - Grafana data sources
- `config/caddy/Caddyfile` - Reverse proxy and routing
- `config/otel-collector/config.yaml` - OpenTelemetry Collector pipeline

After modifying configuration files, restart the affected services:

```bash
ssh root@<SERVER_IP> "cd /opt/observability && docker compose restart <service-name>"
```

## Deployment

### Automated Deployment

The recommended deployment method is the automated setup script:

```bash
bash scripts/setup.sh
```

### Manual Deployment

If you need more control, follow these steps:

#### 1. Provision Infrastructure

```bash
cd infra/terraform
terraform init
terraform apply \
  -var "hcloud_token=$HCLOUD_TOKEN" \
  -var "ssh_key_name=$SSH_KEY_NAME" \
  -var "my_ip_cidr=$MY_IP_CIDR"
```

#### 2. Get Server IP

```bash
SERVER_IP=$(terraform output -raw server_public_ip)
```

#### 3. Deploy Application

```bash
cd ../..
tar czf /tmp/obs-stack.tar.gz docker-compose.yml config/ scripts/
scp /tmp/obs-stack.tar.gz root@$SERVER_IP:/opt/observability/
ssh root@$SERVER_IP "cd /opt/observability && tar xzf obs-stack.tar.gz && rm obs-stack.tar.gz"
```

#### 4. Create .env File on Server

```bash
ssh root@$SERVER_IP "cat > /opt/observability/.env" <<EOF
DOMAIN=${DOMAIN}
DATA_DIR=/opt/observability-data
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
EOF
```

#### 5. Start Services

```bash
ssh root@$SERVER_IP "cd /opt/observability && docker compose up -d"
```

### Verify Deployment

Run the smoke test script:

```bash
bash scripts/smoke-test.sh
```

## Tenant Management

### Creating a New Tenant

```bash
ssh root@<SERVER_IP> 'cd /opt/observability && \
  bash scripts/tenant-management/create-tenant.sh "Customer Name" "customer@example.com" customer-id'
```

This will:
- Generate a unique API key
- Create a Grafana organization
- Output customer onboarding instructions
- Save tenant configuration to `/opt/observability/tenants/`

### Listing Tenants

```bash
ssh root@<SERVER_IP> 'cd /opt/observability && \
  bash scripts/tenant-management/list-tenants.sh'
```

### Rotating API Keys

```bash
ssh root@<SERVER_IP> 'cd /opt/observability && \
  bash scripts/tenant-management/rotate-api-key.sh customer-id'
```

### Deactivating a Tenant

```bash
ssh root@<SERVER_IP> 'cd /opt/observability && \
  bash scripts/tenant-management/delete-tenant.sh customer-id'
```

Note: This marks the tenant as inactive but does not delete historical data.

## Customer Onboarding

### Onboarding Process

1. **Create tenant account** using the create-tenant script
2. **Send credentials** to customer (tenant ID and API key)
3. **Provide documentation**: Share the [Customer Guide](CUSTOMER_GUIDE.md)
4. **Assist with integration** if needed

### Example Customer Configuration

#### Prometheus Remote Write

```yaml
remote_write:
  - url: https://api.obs.example.com/api/v1/push
    headers:
      X-Scope-OrgID: customer-id
      Authorization: Bearer obs_xxxxx
```

#### OTLP Configuration

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.obs.example.com
export OTEL_EXPORTER_OTLP_HEADERS="X-Scope-OrgID=customer-id,Authorization=Bearer obs_xxxxx"
```

#### Loki (Promtail)

```yaml
clients:
  - url: https://api.obs.example.com/loki/api/v1/push
    tenant_id: customer-id
    headers:
      Authorization: Bearer obs_xxxxx
```

For complete integration examples, see [Customer Guide](CUSTOMER_GUIDE.md).

## Monitoring and Maintenance

### Viewing Logs

```bash
# All services
ssh root@<SERVER_IP> 'cd /opt/observability && docker compose logs -f'

# Specific service
ssh root@<SERVER_IP> 'cd /opt/observability && docker compose logs -f grafana'
```

### Checking Service Health

```bash
ssh root@<SERVER_IP> 'cd /opt/observability && docker compose ps'
```

### Restarting Services

```bash
# All services
ssh root@<SERVER_IP> 'cd /opt/observability && docker compose restart'

# Specific service
ssh root@<SERVER_IP> 'cd /opt/observability && docker compose restart loki'
```

### Updating Services

```bash
ssh root@<SERVER_IP> 'cd /opt/observability && \
  docker compose pull && \
  docker compose up -d'
```

### Resource Usage

Check disk usage:

```bash
ssh root@<SERVER_IP> 'df -h /opt/observability-data'
```

Check Docker stats:

```bash
ssh root@<SERVER_IP> 'docker stats --no-stream'
```

## Scaling

### When to Scale

Consider scaling when:
- CPU usage consistently >70%
- Memory usage >80%
- Disk I/O is bottleneck
- Supporting >50 active tenants
- Data retention needs increase

### Vertical Scaling

Upgrade to a larger VM:

```bash
# In infra/terraform/variables.tf, change:
default = "cpx41"  # 8 vCPU, 16GB RAM

# Apply changes
cd infra/terraform
terraform apply -var "hcloud_token=$HCLOUD_TOKEN" ...
```

Downtime: ~5 minutes during resize.

### Horizontal Scaling

For >100 tenants or high availability:

1. **Deploy multiple VMs** - modify Terraform to create 2-3 VMs
2. **Add load balancer** - Hetzner Load Balancer or Caddy in proxy mode
3. **Shared storage** - Use S3-compatible storage (Wasabi) for Loki/Mimir/Tempo
4. **Distributed mode** - Run Mimir/Loki in microservices mode

Refer to official Grafana docs for distributed deployment patterns.

### Storage Scaling

Increase block storage volume:

```bash
# In infra/terraform/variables.tf, increase:
default = 200  # from 100GB to 200GB

cd infra/terraform
terraform apply -var "hcloud_token=$HCLOUD_TOKEN" ...

# Resize filesystem on server
ssh root@<SERVER_IP> 'resize2fs /dev/disk/by-id/scsi-0HC_Volume_*'
```

## Backup and Recovery

### Automated Backups

Enable Hetzner volume snapshots:

```bash
# Via Hetzner Cloud Console or API
# Schedule daily snapshots of the block storage volume
```

### Manual Backup

```bash
# Backup PostgreSQL database
ssh root@<SERVER_IP> 'docker exec postgres pg_dump -U tenants tenants' > backup-$(date +%Y%m%d).sql

# Backup tenant configurations
scp -r root@<SERVER_IP>:/opt/observability/tenants/ ./tenants-backup-$(date +%Y%m%d)/
```

### Disaster Recovery

1. **Provision new infrastructure** using Terraform
2. **Restore volume snapshot** or copy data to new volume
3. **Deploy application stack** using setup script
4. **Restore PostgreSQL** database:

```bash
cat backup-20240101.sql | ssh root@<NEW_SERVER_IP> 'docker exec -i postgres psql -U tenants tenants'
```

5. **Update DNS** to point to new server

## Troubleshooting

### Services Not Starting

```bash
# Check logs
ssh root@<SERVER_IP> 'cd /opt/observability && docker compose logs'

# Check Docker daemon
ssh root@<SERVER_IP> 'systemctl status docker'

# Restart stack
ssh root@<SERVER_IP> 'cd /opt/observability && docker compose down && docker compose up -d'
```

### HTTPS Certificate Issues

```bash
# Check Caddy logs
ssh root@<SERVER_IP> 'docker compose logs caddy'

# Verify DNS resolution
dig obs.example.com

# Force certificate renewal
ssh root@<SERVER_IP> 'docker compose restart caddy'
```

### Data Not Appearing in Grafana

1. Verify tenant is using correct API key and tenant ID
2. Check Loki/Mimir/Tempo logs for ingestion errors
3. Verify customer firewall allows outbound HTTPS/gRPC
4. Test connectivity from customer network

### High Resource Usage

```bash
# Identify resource-heavy containers
ssh root@<SERVER_IP> 'docker stats --no-stream'

# Check data retention settings
ssh root@<SERVER_IP> 'cat /opt/observability/config/loki/loki.yaml | grep retention'

# Consider scaling up or optimizing retention policies
```

### PostgreSQL Issues

```bash
# Check PostgreSQL health
ssh root@<SERVER_IP> 'docker exec postgres pg_isready -U tenants'

# Access PostgreSQL CLI
ssh root@<SERVER_IP> 'docker exec -it postgres psql -U tenants -d tenants'

# View tenants
ssh root@<SERVER_IP> 'docker exec postgres psql -U tenants -d tenants -c "SELECT * FROM tenants;"'
```

## Security Considerations

- **Firewall**: Only necessary ports are exposed (22, 80, 443, 4317, 4318)
- **SSH Access**: Restricted to your IP via `MY_IP_CIDR`
- **API Keys**: Generated using cryptographically secure random
- **HTTPS**: Automatic Let's Encrypt certificates with Caddy
- **Tenant Isolation**: Data isolated via `X-Scope-OrgID` header
- **Regular Updates**: Keep Docker images updated monthly
- **Backup**: Enable automated snapshots for data protection

### Security Best Practices

1. Use strong passwords for admin accounts
2. Rotate API keys periodically
3. Monitor for unusual usage patterns
4. Keep system and Docker updated
5. Use SSH key authentication only
6. Enable 2FA for Grafana if possible
7. Review access logs regularly

## Migration from k3s Setup

If migrating from the previous k3s-based setup:

1. **Deploy new infrastructure** following this guide
2. **No data migration needed** - fresh start recommended
3. **Recreate tenants** and provide new credentials
4. **Decommission old cluster** using `terraform destroy` in old setup

The new architecture is significantly simpler and more maintainable.

## Contributing

Contributions are welcome! Please open an issue or pull request.

## License

MIT License - see LICENSE file for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/ok-monitoring/issues)
- **Documentation**: This README and [Customer Guide](CUSTOMER_GUIDE.md)
- **Examples**: See `examples/` directory for sample configurations

## Acknowledgments

Built with:
- [Grafana](https://grafana.com/) - Visualization
- [Loki](https://grafana.com/oss/loki/) - Log aggregation
- [Mimir](https://grafana.com/oss/mimir/) - Metrics storage
- [Tempo](https://grafana.com/oss/tempo/) - Distributed tracing
- [Caddy](https://caddyserver.com/) - Web server and reverse proxy
- [OpenTelemetry](https://opentelemetry.io/) - Telemetry collection
- [Hetzner Cloud](https://www.hetzner.com/cloud) - Infrastructure
