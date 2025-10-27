# Grafana Dashboards for SaaS Monitoring

This directory contains pre-built Grafana dashboards for monitoring your customers' applications.

## Available Dashboards

### 1. Web Application Performance (`web-performance.json`)

**Purpose**: Monitor overall application health and performance

**Key Metrics**:
- Request rate (requests per second)
- Error rates (4xx and 5xx)
- Response time percentiles (P50, P95)
- Active requests
- Total requests in 24h
- Status code distribution
- Top endpoints by traffic

**Best For**: All web applications

**Variables**:
- `$service` - Filter by specific service/customer

---

### 2. Core Web Vitals & UX (`web-vitals.json`)

**Purpose**: Track user experience metrics from real browsers

**Key Metrics**:
- **LCP** (Largest Contentful Paint) - Loading performance
- **FID** (First Input Delay) - Interactivity
- **CLS** (Cumulative Layout Shift) - Visual stability
- **FCP** (First Contentful Paint) - Perceived load speed
- Page views
- Client-side JavaScript errors

**Best For**: Next.js, React, and frontend-heavy apps

**Thresholds** (Google's recommendations):
- LCP: Good < 2.5s, Poor > 4s
- FID: Good < 100ms, Poor > 300ms
- CLS: Good < 0.1, Poor > 0.25

---

### 3. Customer Overview (`customer-overview.json`)

**Purpose**: High-level view of all customers and their health

**Key Metrics**:
- Total active customers
- Total requests across all services
- Active services count
- Total errors in 24h
- Requests by customer (timeseries)
- Customer health matrix (requests/sec, error %, P95 latency)

**Best For**: Platform administrators monitoring multiple tenants

**Use Case**: Daily health checks, identifying problematic customers

---

### 4. E-Commerce & Conversion Tracking (`ecommerce-tracking.json`)

**Purpose**: Monitor e-commerce funnels and revenue

**Key Metrics**:
- Checkout completions
- Cart additions
- Revenue (24h)
- Conversion rate
- Checkout funnel (product view → add to cart → checkout → complete)
- Revenue by customer
- Cart abandonment rate
- Top products added to cart

**Best For**: Shopify, WooCommerce, and e-commerce sites

**Tracked Events** (must be instrumented):
- `cart_add_item_total`
- `checkout_started_total`
- `checkout_completed_total`
- `order_total_sum`

---

### 5. Logs Overview (`logs-overview.json`)

**Purpose**: Centralized log viewing and analysis

**Key Metrics**:
- Log volume by level (error, warn, info, debug)
- Logs by service
- Recent logs viewer (all services)
- Error logs filter

**Best For**: Debugging and troubleshooting

**Variables**:
- `$service` - Filter logs by service
- `$level` - Filter by log level

---

## Importing Dashboards

### Option A: Automated Import

```bash
cd /Users/burak/projects/ok/apps/ok-monitoring
bash scripts/import-dashboards.sh
```

### Option B: Manual Import via UI

1. Login to Grafana: `http://100.87.121.71:3000`
2. Navigate to **Dashboards** → **New** → **Import**
3. Click **Upload JSON file**
4. Select a dashboard file from this directory
5. Configure datasources:
   - Prometheus/Mimir: Select "Mimir"
   - Loki: Select "Loki"
   - Tempo: Select "Tempo"
6. Click **Import**

### Option C: Copy to Server and Import

```bash
# Copy dashboards to server
scp -r dashboards ok-obs:/opt/observability/

# Import via Grafana API
ssh ok-obs "cd /opt/observability && \
  for f in dashboards/*.json; do \
    docker exec grafana curl -X POST \
      -H 'Content-Type: application/json' \
      -u 'admin:YOUR_PASSWORD' \
      'http://localhost:3000/api/dashboards/db' \
      -d @\$f; \
  done"
```

---

## Required Instrumentation

For dashboards to work, your customers' applications need to send these metrics:

### HTTP Metrics (Standard)
```
http_server_requests_total{service_name, status_code, http_route}
http_server_duration_milliseconds_bucket{service_name, http_route, le}
http_server_active_requests{service_name}
```

### Web Vitals (Frontend)
```
web_vital_lcp{rating}
web_vital_fid{rating}
web_vital_cls{rating}
web_vital_fcp{rating}
```

### E-Commerce (Optional)
```
cart_add_item_total{service_name, product_id, product_name}
checkout_started_total{service_name}
checkout_completed_total{service_name}
order_total_sum{service_name}
page_view_total{service_name, page_template}
```

### Errors & Exceptions
```
exception_total{service_name, exception_type}
browser_error_total{service_name, error_type}
```

---

## Customization

Each dashboard can be customized after import:

1. **Thresholds**: Adjust based on your SLAs
2. **Time ranges**: Default is 6h-24h, change as needed
3. **Variables**: Add more filters (environment, region, etc.)
4. **Panels**: Add/remove based on your needs

---

## Dashboard Organization

Suggested folder structure in Grafana:

```
📁 General
  - Customer Overview

📁 Application Performance
  - Web Application Performance
  - Core Web Vitals & UX

📁 Business Metrics
  - E-Commerce & Conversion Tracking

📁 Debugging
  - Errors & Distributed Tracing
  - Logs Overview
```

---

## Next Steps

1. **Import all dashboards** using method above
2. **Send test data** from a customer application
3. **Verify metrics appear** in dashboards
4. **Customize alerts** for critical metrics
5. **Create customer-specific** dashboards as needed

---

## Metrics Naming Convention

These dashboards follow OpenTelemetry semantic conventions:

- `http.server.*` - Server-side HTTP metrics
- `http.client.*` - Client-side HTTP metrics
- `service.name` - Service identifier
- `deployment.environment` - Environment (prod/staging/dev)

For more info: https://opentelemetry.io/docs/specs/semconv/http/

