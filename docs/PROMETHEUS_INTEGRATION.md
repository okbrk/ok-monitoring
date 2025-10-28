# Prometheus Metrics Integration Guide

This guide explains how to expose Prometheus metrics from your application so our platform can scrape them as health checks.

## Overview

Instead of running your own Prometheus instance, simply expose a `/api/metrics` endpoint (or any path) from your application that:

1. Returns Prometheus-format metrics
2. Requires your API key in the `Authorization` header
3. Is accessible over HTTPS

Our platform will scrape your endpoint every 15-30 seconds and store metrics in our Mimir backend.

```
Your App → /api/metrics (authenticated) ← Platform scrapes every 30s
                                          ↓
                                        Mimir (storage)
                                          ↓
                                        Grafana (query)
```

---

## Quick Start

### 1. Expose Metrics Endpoint

Your application should expose a metrics endpoint protected by your API key.

**Node.js/Express Example:**

```javascript
const express = require('express');
const client = require('prom-client');

const app = express();
const register = new client.Registry();

// Collect default metrics (CPU, memory, etc.)
client.collectDefaultMetrics({ register });

// Custom metrics
const httpRequestCounter = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'path', 'status'],
  registers: [register]
});

// Track requests
app.use((req, res, next) => {
  res.on('finish', () => {
    httpRequestCounter.labels(req.method, req.path, res.statusCode).inc();
  });
  next();
});

// Metrics endpoint with authentication
app.get('/api/metrics', (req, res) => {
  const authHeader = req.headers.authorization;

  // Validate API key (replace with YOUR actual API key)
  if (authHeader !== 'Bearer obs_your_api_key_here') {
    return res.status(401).send('Unauthorized');
  }

  res.set('Content-Type', register.contentType);
  res.end(register.metrics());
});

app.listen(3000);
```

**Python/Flask Example:**

```python
from flask import Flask, request, Response, abort
from prometheus_client import Counter, Histogram, generate_latest, REGISTRY, CollectorRegistry
from prometheus_client import multiprocess, generate_latest

app = Flask(__name__)

# Custom metrics
request_count = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

request_duration = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint']
)

@app.route('/api/metrics')
def metrics():
    # Validate API key
    auth_header = request.headers.get('Authorization')
    if auth_header != 'Bearer obs_your_api_key_here':
        abort(401)

    # Return metrics
    return Response(generate_latest(REGISTRY), mimetype='text/plain')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

**Next.js API Route Example:**

```typescript
// pages/api/metrics.ts
import { NextApiRequest, NextApiResponse } from 'next';
import client from 'prom-client';

// Create registry
const register = new client.Registry();

// Collect default metrics
client.collectDefaultMetrics({ register });

// Custom metrics
const pageViews = new client.Counter({
  name: 'page_views_total',
  help: 'Total page views',
  labelNames: ['page'],
  registers: [register]
});

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  // Validate API key
  const authHeader = req.headers.authorization;

  if (authHeader !== `Bearer ${process.env.METRICS_API_KEY}`) {
    return res.status(401).send('Unauthorized');
  }

  // Return metrics
  res.setHeader('Content-Type', register.contentType);
  res.send(await register.metrics());
}
```

### 2. Test Your Endpoint

```bash
# Test locally
curl -H "Authorization: Bearer obs_your_api_key" http://localhost:3000/api/metrics

# Should return Prometheus format:
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
# http_requests_total{method="GET",path="/",status="200"} 42
```

### 3. Register with Platform

Contact your platform admin to register your endpoint, or use the registration script:

```bash
ssh ok-obs 'cd /opt/observability && \
  bash scripts/tenant-management/register-metrics-endpoint.sh \
  your-tenant-id \
  https://your-app.com/api/metrics \
  30'
```

**Arguments:**
- `your-tenant-id`: Your tenant identifier (e.g., `okbrk`)
- Endpoint URL: Full HTTPS URL to your metrics endpoint
- Scrape interval: Seconds between scrapes (15-300, default: 30)

### 4. Verify in Grafana

After a few minutes, metrics will appear in Grafana:

```promql
# Check scraping is working
up{tenant_id="your-tenant-id"}

# Query your custom metrics
http_requests_total{tenant_id="your-tenant-id"}

# Request rate over 5 minutes
rate(http_requests_total{tenant_id="your-tenant-id"}[5m])
```

---

## Common Metrics Libraries

### Node.js: prom-client

```bash
npm install prom-client
```

**Documentation:** https://github.com/siimon/prom-client

**Common metrics:**
```javascript
const client = require('prom-client');
const register = new client.Registry();

// Default system metrics
client.collectDefaultMetrics({ register });

// Counter - things that only increase
const requests = new client.Counter({
  name: 'api_requests_total',
  help: 'Total API requests',
  labelNames: ['method', 'endpoint', 'status'],
  registers: [register]
});

// Gauge - values that go up and down
const activeUsers = new client.Gauge({
  name: 'active_users',
  help: 'Number of active users',
  registers: [register]
});

// Histogram - measure distributions (latency, size, etc.)
const requestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request latency',
  labelNames: ['method', 'route'],
  registers: [register]
});
```

### Python: prometheus_client

```bash
pip install prometheus-client
```

**Documentation:** https://github.com/prometheus/client_python

**Common metrics:**
```python
from prometheus_client import Counter, Gauge, Histogram, Summary

# Counter
requests_total = Counter(
    'api_requests_total',
    'Total API requests',
    ['method', 'endpoint', 'status']
)

# Gauge
active_connections = Gauge(
    'active_connections',
    'Number of active connections'
)

# Histogram
request_latency = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint']
)

# Usage
requests_total.labels(method='GET', endpoint='/api', status=200).inc()
active_connections.set(42)

with request_latency.labels(method='GET', endpoint='/api').time():
    # Your code here
    pass
```

### Go: prometheus/client_golang

```bash
go get github.com/prometheus/client_golang/prometheus
go get github.com/prometheus/client_golang/prometheus/promhttp
```

**Example:**
```go
package main

import (
    "net/http"
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    requests = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "api_requests_total",
            Help: "Total API requests",
        },
        []string{"method", "endpoint", "status"},
    )
)

func init() {
    prometheus.MustRegister(requests)
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
    // Validate API key
    if r.Header.Get("Authorization") != "Bearer obs_your_api_key" {
        http.Error(w, "Unauthorized", http.StatusUnauthorized)
        return
    }

    promhttp.Handler().ServeHTTP(w, r)
}

func main() {
    http.HandleFunc("/api/metrics", metricsHandler)
    http.ListenAndServe(":8080", nil)
}
```

---

## Best Practices

### 1. Security

- **Always validate the API key** before returning metrics
- **Use HTTPS** in production (HTTP allowed for localhost testing)
- **Don't expose sensitive data** in metric labels
- Store API key in environment variables, not in code

```javascript
// ✅ Good - from environment
const API_KEY = process.env.METRICS_API_KEY;

// ❌ Bad - hardcoded
const API_KEY = 'obs_abc123';
```

### 2. Metric Naming

Follow Prometheus naming conventions:

- **Snake case:** `http_requests_total` not `httpRequestsTotal`
- **Units as suffix:** `_seconds`, `_bytes`, `_total`
- **Descriptive names:** `api_requests_total` not `requests`

```promql
# ✅ Good
http_request_duration_seconds
database_queries_total
memory_usage_bytes

# ❌ Bad
httpDuration
queries
memory
```

### 3. Labels

- Use labels for dimensions, not values
- Keep cardinality low (< 1000 unique label combinations)
- Don't use user IDs, emails, or timestamps as labels

```javascript
// ✅ Good - low cardinality
counter.labels({
  method: 'GET',
  endpoint: '/api/users',
  status: '200'
}).inc();

// ❌ Bad - high cardinality
counter.labels({
  user_id: '12345',  // Too many unique values
  timestamp: Date.now()  // Infinite cardinality
}).inc();
```

### 4. Performance

- Cache metrics endpoint response for 1-5 seconds to reduce overhead
- Don't generate metrics on-the-fly for every request
- Use histogram buckets appropriate for your use case

```javascript
// Good - define buckets for your latency distribution
const histogram = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request latency',
  buckets: [0.001, 0.01, 0.1, 0.5, 1, 5, 10]  // 1ms to 10s
});
```

---

## Common Metrics to Track

### Application Metrics

```javascript
// HTTP request count
http_requests_total{method, path, status}

// Request duration
http_request_duration_seconds{method, path}

// Active requests
http_requests_in_flight

// Error rate
http_errors_total{method, path, error_type}

// Database queries
database_queries_total{operation, table}
database_query_duration_seconds{operation, table}
```

### Business Metrics

```javascript
// User signups
user_signups_total

// Orders/purchases
orders_total{status}
revenue_total{currency}

// Active users
active_users_gauge

// Feature usage
feature_usage_total{feature_name}
```

### System Metrics (auto-collected by prom-client)

```javascript
// Process metrics
process_cpu_seconds_total
process_resident_memory_bytes
process_heap_bytes

// Node.js metrics
nodejs_eventloop_lag_seconds
nodejs_active_handles
nodejs_active_requests
```

---

## Management Commands

### List Registered Endpoints

```bash
ssh ok-obs 'cd /opt/observability && \
  bash scripts/tenant-management/list-metrics-endpoints.sh'
```

### Update Scrape Interval

```bash
# Requires database access
ssh ok-obs 'cd /opt/observability && \
  PGPASSWORD=$POSTGRES_PASSWORD psql -U tenants -d tenants -c \
  "UPDATE metrics_endpoints SET scrape_interval_seconds = 60 WHERE id = 1;"'

# Regenerate config
ssh ok-obs 'cd /opt/observability && \
  bash scripts/tenant-management/generate-agent-config.sh && \
  docker compose restart grafana-agent'
```

### Remove Endpoint

```bash
ssh ok-obs 'cd /opt/observability && \
  bash scripts/tenant-management/remove-metrics-endpoint.sh ENDPOINT_ID'
```

---

## Troubleshooting

### Metrics Not Appearing

1. **Check endpoint is accessible:**
```bash
curl -H "Authorization: Bearer obs_your_api_key" https://your-app.com/api/metrics
```

2. **Verify endpoint is registered:**
```bash
ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/list-metrics-endpoints.sh'
```

3. **Check Grafana Agent logs:**
```bash
ssh ok-obs 'docker logs grafana-agent --tail 100'
```

4. **Look for scrape errors:**
```bash
# In Grafana, query:
up{tenant_id="your-tenant-id"}
# Should return 1 if scraping succeeds, 0 if fails
```

### Authentication Errors

- Ensure Authorization header format: `Bearer obs_xxxxx`
- Verify API key matches what's registered in the platform
- Check for typos in the API key

### High Cardinality Issues

If you see errors about too many time series:

```bash
# Find high-cardinality metrics
# In Grafana:
topk(10, count by (__name__)({tenant_id="your-tenant-id"}))
```

Reduce label cardinality by:
- Removing user IDs from labels
- Grouping similar values (e.g., HTTP status: 2xx, 4xx, 5xx instead of 200, 201, 404, etc.)
- Using histograms instead of individual metrics

---

## Example: Full Express.js App with Metrics

```javascript
const express = require('express');
const client = require('prom-client');

const app = express();
const register = new client.Registry();

// Collect default metrics
client.collectDefaultMetrics({ register, prefix: 'myapp_' });

// Custom metrics
const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status'],
  registers: [register]
});

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request latency in seconds',
  labelNames: ['method', 'route'],
  buckets: [0.001, 0.01, 0.1, 0.5, 1, 5],
  registers: [register]
});

// Middleware to track requests
app.use((req, res, next) => {
  const start = Date.now();

  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const route = req.route?.path || req.path;

    httpRequestsTotal.labels(req.method, route, res.statusCode).inc();
    httpRequestDuration.labels(req.method, route).observe(duration);
  });

  next();
});

// Your API routes
app.get('/', (req, res) => {
  res.json({ message: 'Hello World' });
});

app.get('/api/users', (req, res) => {
  res.json({ users: [] });
});

// Metrics endpoint (protected)
app.get('/api/metrics', (req, res) => {
  const authHeader = req.headers.authorization;

  if (authHeader !== `Bearer ${process.env.METRICS_API_KEY}`) {
    return res.status(401).send('Unauthorized');
  }

  res.set('Content-Type', register.contentType);
  res.end(register.metrics());
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`Metrics available at /api/metrics`);
});
```

---

## Next Steps

1. **Implement metrics endpoint** in your application
2. **Test locally** with curl
3. **Contact admin** to register your endpoint
4. **Build dashboards** in Grafana with your metrics
5. **Set up alerts** for critical metrics

---

**Last Updated:** October 27, 2025
