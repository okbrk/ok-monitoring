# Multi-Tenant Observability Platform

A simplified, production-ready observability platform for monitoring SaaS applications and customer workloads.

## Quick Start

```bash
# 1. Configure your environment
cp env.example .env
# Edit .env with your values

# 2. Deploy the platform
bash scripts/setup.sh

# 3. Configure DNS (as instructed by the script)

# 4. Access Grafana
# https://your-domain.com/grafana/
```

## Features

- **Multi-Tenant**: Isolated data per customer with API key authentication
- **Complete Observability**: Logs (Loki), Metrics (Mimir), Traces (Tempo)
- **Self-Monitoring**: Built-in infrastructure monitoring with Prometheus, Alertmanager, and dashboards
- **Automated Alerts**: Email and webhook notifications for critical issues
- **Simple Deployment**: Docker Compose on Hetzner Cloud
- **Automatic HTTPS**: Caddy with Let's Encrypt
- **Remote Collection**: OTLP, Prometheus Remote Write, Loki API
- **Cost Effective**: ~$15/month for <50 tenants

## Documentation

- **[Full Documentation](docs/README.md)** - Complete setup and operations guide
- **[Customer Guide](docs/CUSTOMER_GUIDE.md)** - Integration guide for customers
- **[Prometheus Integration](docs/PROMETHEUS_INTEGRATION.md)** - Configure Prometheus targets and remote_write

## Architecture

```
Customer Apps → OTLP/Remote Write → Your Platform
                                    ├─ Grafana (UI)
                                    ├─ Loki (Logs)
                                    ├─ Mimir (Metrics)
                                    └─ Tempo (Traces)
```

## Requirements

- Hetzner Cloud account
- Domain name with DNS access
- Terraform, jq, SSH

## Support

For issues and questions, see [docs/README.md](docs/README.md#troubleshooting).

## License

MIT

