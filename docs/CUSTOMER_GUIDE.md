# Customer Integration Guide - Website Monitoring

Welcome! This guide will help you integrate your website with our monitoring platform.

## Your Credentials

You should have received:

- **Tenant ID**: `your-tenant-id`
- **API Key**: `obs_xxxxxxxxxxxxx`
- **Platform Domain**: `obs.okbrk.com`

⚠️ **Keep your API key secure!** Never commit it to version control or share publicly.

## Quick Start

### Test Your Connection

```bash
# Test if you can reach our platform
curl https://api.obs.okbrk.com/health

# Should return: OK
```

If you get a response, you're ready to integrate!

---

## Integration by Platform

Choose your platform and follow the guide:

- [Next.js / React](#nextjs--react-applications)
- [WordPress / WooCommerce](#wordpress--woocommerce)
- [Shopify](#shopify-stores)

---

## Next.js / React Applications

### Method 1: Vercel Deployment (Easiest)

If you're deploying on Vercel:

#### Step 1: Install Dependencies

```bash
npm install @vercel/otel @opentelemetry/api
```

#### Step 2: Create `instrumentation.ts` in Your Project Root

```typescript
// instrumentation.ts (or .js)
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    await import('./instrumentation.node')
  }

  if (process.env.NEXT_RUNTIME === 'edge') {
    await import('./instrumentation.edge')
  }
}
```

#### Step 3: Create `instrumentation.node.ts`

```typescript
// instrumentation.node.ts
import { registerOTel } from '@vercel/otel'

export function register() {
  registerOTel({
    serviceName: 'your-app-name',
  })
}
```

#### Step 4: Add Environment Variables

In Vercel dashboard or `.env.local`:

```bash
# Replace with YOUR credentials
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.obs.okbrk.com
OTEL_EXPORTER_OTLP_HEADERS=X-Scope-OrgID=your-tenant-id,Authorization=Bearer obs_xxxxxxxxxxxxx

OTEL_SERVICE_NAME=your-app-name
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production
```

#### Step 5: Enable in `next.config.js`

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    instrumentationHook: true,
  },
}

module.exports = nextConfig
```

#### Step 6: Track Web Vitals

Add to `app/layout.tsx` or `pages/_app.tsx`:

```typescript
// app/layout.tsx (App Router)
import { Suspense } from 'react'
import { WebVitals } from '@/components/web-vitals'

export default function RootLayout({ children }) {
  return (
    <html>
      <body>
        {children}
        <Suspense>
          <WebVitals />
        </Suspense>
      </body>
    </html>
  )
}
```

Create `components/web-vitals.tsx`:

```typescript
// components/web-vitals.tsx
'use client'

import { useReportWebVitals } from 'next/web-vitals'

export function WebVitals() {
  useReportWebVitals((metric) => {
    // Send to your monitoring platform
    fetch('https://api.obs.okbrk.com/v1/metrics', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Scope-OrgID': process.env.NEXT_PUBLIC_TENANT_ID!,
        'Authorization': `Bearer ${process.env.NEXT_PUBLIC_API_KEY!}`,
      },
      body: JSON.stringify({
        name: `web_vital_${metric.name.toLowerCase()}`,
        value: metric.value,
        rating: metric.rating,
        timestamp: Date.now(),
      }),
    })
  })

  return null
}
```

**That's it!** Your Next.js app will now send traces and metrics automatically.

---

### Method 2: Custom Next.js Setup

For more control or non-Vercel deployments:

#### Step 1: Install OpenTelemetry

```bash
npm install @opentelemetry/api \
  @opentelemetry/sdk-node \
  @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-grpc
```

#### Step 2: Create `instrumentation.node.ts`

```typescript
// instrumentation.node.ts
import { NodeSDK } from '@opentelemetry/sdk-node'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc'
import { Resource } from '@opentelemetry/resources'
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions'
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node'

const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'your-app-name',
    [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
    'deployment.environment': process.env.NODE_ENV || 'production',
  }),
  traceExporter: new OTLPTraceExporter({
    url: 'https://otlp.obs.okbrk.com:443',
    headers: {
      'X-Scope-OrgID': process.env.TENANT_ID!,
      'Authorization': `Bearer ${process.env.API_KEY!}`,
    },
  }),
  instrumentations: [getNodeAutoInstrumentations()],
})

sdk.start()

export function register() {
  // SDK started above
}
```

#### Step 3: Environment Variables

```bash
# .env.local
TENANT_ID=your-tenant-id
API_KEY=obs_xxxxxxxxxxxxx
```

---

## WordPress / WooCommerce

### Step 1: Install Required Plugin

Use **WP Log Viewer** + **Custom logging**:

```bash
# Via WP-CLI
wp plugin install wp-log-viewer --activate
```

### Step 2: Add Custom Logging Function

Add to your theme's `functions.php`:

```php
<?php
// Send logs to monitoring platform
function send_to_monitoring($level, $message, $context = []) {
    $tenant_id = 'your-tenant-id';  // Replace with your tenant ID
    $api_key = 'obs_xxxxxxxxxxxxx'; // Replace with your API key

    $log_entry = [
        'streams' => [[
            'stream' => [
                'job' => get_bloginfo('name'),
                'service_name' => $tenant_id,
                'level' => $level,
                'host' => $_SERVER['HTTP_HOST']
            ],
            'values' => [[
                (string)(time() * 1000000000), // Nanosecond timestamp
                json_encode([
                    'message' => $message,
                    'context' => $context,
                    'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? '',
                    'ip' => $_SERVER['REMOTE_ADDR'] ?? '',
                    'url' => $_SERVER['REQUEST_URI'] ?? ''
                ])
            ]]
        ]]
    ];

    wp_remote_post('https://api.obs.okbrk.com/loki/api/v1/push', [
        'headers' => [
            'Content-Type' => 'application/json',
            'X-Scope-OrgID' => $tenant_id,
            'Authorization' => 'Bearer ' . $api_key
        ],
        'body' => json_encode($log_entry),
        'timeout' => 5,
        'blocking' => false  // Don't slow down page load
    ]);
}

// Track page views
add_action('wp_head', function() {
    send_to_monitoring('info', 'Page viewed', [
        'page_title' => wp_title('', false),
        'post_type' => get_post_type(),
        'user_logged_in' => is_user_logged_in()
    ]);
});

// Track errors
add_action('wp_die_handler', function($message) {
    send_to_monitoring('error', 'WordPress Error', [
        'error' => $message
    ]);
});
?>
```

### Step 3: Track WooCommerce Events (if applicable)

```php
<?php
// Track product views
add_action('woocommerce_after_single_product', function() {
    global $product;
    send_to_monitoring('info', 'Product viewed', [
        'product_id' => $product->get_id(),
        'product_name' => $product->get_name(),
        'price' => $product->get_price()
    ]);
});

// Track add to cart
add_action('woocommerce_add_to_cart', function($cart_item_key, $product_id, $quantity) {
    $product = wc_get_product($product_id);
    send_to_monitoring('info', 'Item added to cart', [
        'product_id' => $product_id,
        'product_name' => $product->get_name(),
        'quantity' => $quantity,
        'event' => 'cart_add_item'
    ]);
}, 10, 3);

// Track checkout started
add_action('woocommerce_checkout_process', function() {
    send_to_monitoring('info', 'Checkout started', [
        'cart_total' => WC()->cart->get_total(''),
        'items_count' => WC()->cart->get_cart_contents_count(),
        'event' => 'checkout_started'
    ]);
});

// Track order completion
add_action('woocommerce_thankyou', function($order_id) {
    $order = wc_get_order($order_id);
    send_to_monitoring('info', 'Order completed', [
        'order_id' => $order_id,
        'total' => $order->get_total(),
        'items' => $order->get_item_count(),
        'event' => 'checkout_completed'
    ]);
});
?>
```

### Step 4: Test Integration

Visit any page on your WordPress site, then contact us to verify we're receiving your data.

---

## Shopify Stores

Since Shopify doesn't allow server-side code, we'll track via frontend JavaScript.

### Step 1: Add Tracking Script to Theme

1. Go to **Online Store** → **Themes** → **Edit Code**
2. Open `theme.liquid`
3. Add before `</head>`:

```html
<!-- Monitoring Platform Integration -->
<script>
(function() {
  const TENANT_ID = 'your-tenant-id';  // Replace with your tenant ID
  const API_KEY = 'obs_xxxxxxxxxxxxx'; // Replace with your API key
  const API_URL = 'https://api.obs.okbrk.com/loki/api/v1/push';

  function sendLog(level, message, context) {
    const logEntry = {
      streams: [{
        stream: {
          job: '{{ shop.name }}',
          service_name: TENANT_ID,
          level: level,
          host: window.location.hostname
        },
        values: [[
          String(Date.now() * 1000000), // Nanosecond timestamp
          JSON.stringify({
            message: message,
            context: context,
            url: window.location.href,
            userAgent: navigator.userAgent
          })
        ]]
      }]
    };

    navigator.sendBeacon(API_URL, new Blob([JSON.stringify(logEntry)], {
      type: 'application/json',
      headers: {
        'X-Scope-OrgID': TENANT_ID,
        'Authorization': 'Bearer ' + API_KEY
      }
    }));
  }

  // Track page views
  sendLog('info', 'Page viewed', {
    page_title: document.title,
    page_type: '{{ request.page_type }}',
    {% if template %}template: '{{ template }}'{% endif %}
  });

  // Track errors
  window.addEventListener('error', function(e) {
    sendLog('error', 'JavaScript error', {
      message: e.message,
      filename: e.filename,
      lineno: e.lineno
    });
  });
})();
</script>
```

### Step 2: Track Add to Cart

Add to your cart form or product page:

```html
<script>
document.addEventListener('submit', function(e) {
  if (e.target.matches('form[action*="/cart/add"]')) {
    const formData = new FormData(e.target);
    sendLog('info', 'Item added to cart', {
      product_id: formData.get('id'),
      quantity: formData.get('quantity') || 1,
      event: 'cart_add_item'
    });
  }
});
</script>
```

### Step 3: Track Checkout

In **Settings** → **Checkout** → **Order status page**, add:

```html
<script>
{% if first_time_accessed %}
(function() {
  const logEntry = {
    streams: [{
      stream: {
        job: '{{ shop.name }}',
        service_name: 'your-tenant-id',
        level: 'info'
      },
      values: [[
        String(Date.now() * 1000000),
        JSON.stringify({
          message: 'Order completed',
          order_id: '{{ order.id }}',
          total: {{ total_price }},
          items_count: {{ line_items.size }},
          event: 'checkout_completed'
        })
      ]]
    }]
  };

  navigator.sendBeacon('https://api.obs.okbrk.com/loki/api/v1/push',
    new Blob([JSON.stringify(logEntry)], {type: 'application/json'}));
})();
{% endif %}
</script>
```

---

## Testing Your Integration

### Send a Test Event

You can test your integration using `curl`:

```bash
# Replace with YOUR credentials
TENANT_ID="your-tenant-id"
API_KEY="obs_xxxxxxxxxxxxx"

# Send test log
curl -X POST https://api.obs.okbrk.com/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: $TENANT_ID" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "streams": [{
      "stream": {"job": "test", "service_name": "'$TENANT_ID'"},
      "values": [["'$(date +%s)'000000000", "Test log from my application"]]
    }]
  }'

# Should return: success (or empty response)
```

### Verify Data is Received

Contact your platform administrator and ask them to verify your data is appearing in the system. They can see your logs in Grafana.

---

## Advanced: Custom Events Tracking

### Track Custom Business Events

For Next.js/React:

```typescript
// lib/track-event.ts
export function trackEvent(eventName: string, properties: Record<string, any>) {
  fetch('https://api.obs.okbrk.com/v1/logs', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Scope-OrgID': process.env.NEXT_PUBLIC_TENANT_ID!,
      'Authorization': `Bearer ${process.env.NEXT_PUBLIC_API_KEY!}`,
    },
    body: JSON.stringify({
      resourceLogs: [{
        resource: {
          attributes: [{
            key: 'service.name',
            value: { stringValue: 'your-app-name' }
          }]
        },
        scopeLogs: [{
          logRecords: [{
            timeUnixNano: String(Date.now() * 1000000),
            severityText: 'INFO',
            body: { stringValue: eventName },
            attributes: Object.entries(properties).map(([key, value]) => ({
              key,
              value: { stringValue: String(value) }
            }))
          }]
        }]
      }]
    })
  }).catch(console.error)  // Don't fail app if monitoring fails
}

// Usage in your components
import { trackEvent } from '@/lib/track-event'

function CheckoutButton() {
  const handleClick = () => {
    trackEvent('checkout_started', {
      cart_total: 99.99,
      items_count: 3,
      user_id: userId
    })
    // ... rest of checkout logic
  }

  return <button onClick={handleClick}>Checkout</button>
}
```

### Track User Actions

```typescript
// Track button clicks
trackEvent('button_clicked', {
  button_name: 'signup',
  page: window.location.pathname
})

// Track form submissions
trackEvent('form_submitted', {
  form_name: 'contact',
  success: true
})

// Track feature usage
trackEvent('feature_used', {
  feature: 'dark_mode',
  enabled: true
})
```

---

## Troubleshooting

### Data Not Appearing

**Check 1: Verify Credentials**

```bash
# Test your endpoint
curl -I https://api.obs.okbrk.com/health

# Should return: HTTP/2 200
```

**Check 2: Verify API Key Format**

- Must include `Bearer` prefix in Authorization header
- Example: `Authorization: Bearer obs_abc123...`
- Tenant ID in `X-Scope-OrgID` header (no Bearer)

**Check 3: Check Console for Errors**

In your browser console (F12), look for:
- Network errors to `api.obs.okbrk.com`
- CORS errors (shouldn't happen - we allow all origins)
- 401/403 errors (wrong API key or tenant ID)

**Check 4: Contact Support**

If you've verified the above and still have issues, contact us with:
- Your tenant ID
- Screenshot of any errors
- Sample of your integration code (hide API key)

### Performance Impact

Our monitoring is designed to have minimal impact:

- **Async sending**: Doesn't block your app
- **Batching**: Events batched before sending
- **Sampling**: Can be configured for high-traffic apps
- **Fallback**: If monitoring fails, your app continues normally

### High-Traffic Applications

For apps with >1000 requests/second, implement sampling:

```typescript
// Only send 10% of traces
if (Math.random() < 0.1) {
  // Send trace
}
```

Or configure in environment:
```bash
OTEL_TRACES_SAMPLER=traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1  # Sample 10%
```

---

## Security Best Practices

### ✅ Do's

- Store API keys in environment variables
- Use `.env.local` for Next.js (gitignored by default)
- Use WordPress options table or constants in `wp-config.php`
- Rotate keys periodically (contact us for new keys)
- Use HTTPS for all connections

### ❌ Don'ts

- Never commit API keys to Git
- Don't expose API keys in client-side JavaScript (use server-side)
- Don't share API keys between environments (dev/staging/prod)
- Don't log sensitive user data (PII, passwords, tokens)

### Recommended Setup

```typescript
// ✅ Good - Server-side only
// app/api/track/route.ts
export async function POST(request: Request) {
  const body = await request.json()

  await fetch('https://api.obs.okbrk.com/v1/logs', {
    headers: {
      'X-Scope-OrgID': process.env.TENANT_ID!, // Server-side env var
      'Authorization': `Bearer ${process.env.API_KEY!}`, // Server-side env var
    },
    body: JSON.stringify(body)
  })

  return Response.json({ success: true })
}

// ❌ Bad - API key exposed in client
const response = await fetch('https://api.obs.okbrk.com/v1/logs', {
  headers: {
    'Authorization': 'Bearer obs_abc123...' // NEVER hardcode in client code!
  }
})
```

---

## Rate Limits & Quotas

Your monitoring plan includes:

| Resource | Limit | Notes |
|----------|-------|-------|
| **Log Ingestion** | 10 MB/s | Burst up to 20 MB/s |
| **Metrics** | 1M active series | Per tenant |
| **Traces** | 100K spans/trace | Per trace |
| **Retention** | 30 days | Logs, metrics, traces |
| **Query Rate** | Unlimited | Fair use expected |

If you need higher limits, contact us.

---

## Next Steps

1. **Integrate** using the guide above for your platform
2. **Send test data** to verify connection
3. **Contact us** to confirm data is being received
4. **Monitor** your application's performance
5. **Reach out** if you need help or have questions

## Support

- **Email**: support@example.com
- **Response Time**: Within 24 hours
- **Status Page**: https://api.obs.okbrk.com/health

---

## Example Applications

### Complete Next.js Example

```typescript
// app/layout.tsx
import { WebVitals } from './web-vitals'

export default function RootLayout({ children }: { children: React.Node }) {
  return (
    <html>
      <body>
        {children}
        <WebVitals />
      </body>
    </html>
  )
}

// app/web-vitals.tsx
'use client'
import { useReportWebVitals } from 'next/web-vitals'

export function WebVitals() {
  useReportWebVitals((metric) => {
    // Only track in production
    if (process.env.NODE_ENV !== 'production') return

    const body = {
      streams: [{
        stream: {
          job: 'my-nextjs-app',
          service_name: process.env.NEXT_PUBLIC_TENANT_ID,
          metric_name: metric.name
        },
        values: [[
          String(Date.now() * 1000000),
          JSON.stringify({
            name: metric.name,
            value: metric.value,
            rating: metric.rating,
            id: metric.id
          })
        ]]
      }]
    }

    fetch('https://api.obs.okbrk.com/loki/api/v1/push', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Scope-OrgID': process.env.NEXT_PUBLIC_TENANT_ID!,
        'Authorization': `Bearer ${process.env.NEXT_PUBLIC_API_KEY!}`
      },
      body: JSON.stringify(body),
      keepalive: true
    }).catch(() => {}) // Fail silently
  })

  return null
}
```

### Complete WordPress Example

See the WordPress section above for the complete `functions.php` integration.

---

**Welcome aboard! Your monitoring is just a few lines of code away.** 🚀
