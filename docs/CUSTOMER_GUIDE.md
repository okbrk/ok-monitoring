# Website Monitoring Integration Guide

Welcome! This guide will help you integrate your website with our monitoring platform to track performance, errors, and user experience.

## Your Credentials

You should have received these from us:

- **Tenant ID**: `your-tenant-id`
- **API Key**: `obs_xxxxxxxxxxxxx`
- **Endpoints**:
  - OTLP: `https://otlp.yourdomain.com`
  - API: `https://api.yourdomain.com`

⚠️ **Keep your API key secure!** Never commit it to version control.

---

## For Next.js / React Applications

### Quick Start with Vercel OpenTelemetry

If you're using Vercel, this is the easiest integration:

#### 1. Install Dependencies

```bash
npm install @vercel/otel @opentelemetry/api
```

#### 2. Create `instrumentation.ts` (or `.js`) in your project root

```typescript
// instrumentation.ts
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    await import('./instrumentation.node')
  }
}
```

#### 3. Create `instrumentation.node.ts`

```typescript
// instrumentation.node.ts
import { registerOTel } from '@vercel/otel'

export function register() {
  registerOTel({
    serviceName: 'your-app-name',
    traceExporter: 'otlp',
  })
}
```

#### 4. Add Environment Variables

In your `.env.local` or Vercel environment variables:

```bash
# OpenTelemetry Configuration
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.yourdomain.com
OTEL_EXPORTER_OTLP_HEADERS=X-Scope-OrgID=your-tenant-id,Authorization=Bearer obs_xxxxxxxxxxxxx

# Service configuration
OTEL_SERVICE_NAME=your-app-name
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production
```

#### 5. Enable Instrumentation in `next.config.js`

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    instrumentationHook: true,
  },
}

module.exports = nextConfig
```

That's it! Your Next.js app will now send traces automatically.

### Advanced: Manual Instrumentation with Tanstack Query

For more control, especially with Tanstack Query (React Query):

#### 1. Install Dependencies

```bash
npm install @opentelemetry/api \
  @opentelemetry/sdk-trace-web \
  @opentelemetry/instrumentation \
  @opentelemetry/exporter-trace-otlp-http \
  @opentelemetry/auto-instrumentations-web \
  @opentelemetry/resources \
  @opentelemetry/semantic-conventions
```

#### 2. Create OpenTelemetry Provider

```typescript
// lib/telemetry.ts
import { WebTracerProvider } from '@opentelemetry/sdk-trace-web'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base'
import { registerInstrumentations } from '@opentelemetry/instrumentation'
import { getWebAutoInstrumentations } from '@opentelemetry/auto-instrumentations-web'
import { Resource } from '@opentelemetry/resources'
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions'

export function initTelemetry() {
  const resource = new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'your-app-name',
    [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
    'deployment.environment': process.env.NEXT_PUBLIC_ENV || 'production',
  })

  const provider = new WebTracerProvider({ resource })

  const exporter = new OTLPTraceExporter({
    url: 'https://api.yourdomain.com/v1/traces',
    headers: {
      'X-Scope-OrgID': 'your-tenant-id',
      'Authorization': 'Bearer obs_xxxxxxxxxxxxx',
    },
  })

  provider.addSpanProcessor(new BatchSpanProcessor(exporter))
  provider.register()

  // Auto-instrument fetch, XMLHttpRequest, etc.
  registerInstrumentations({
    instrumentations: [
      getWebAutoInstrumentations({
        '@opentelemetry/instrumentation-fetch': {
          propagateTraceHeaderCorsUrls: [/.*/],
          clearTimingResources: true,
        },
      }),
    ],
  })
}
```

#### 3. Initialize in `_app.tsx`

```typescript
// pages/_app.tsx
import { useEffect } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { initTelemetry } from '@/lib/telemetry'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Add tracing to Tanstack Query
      onError: (error) => {
        // Errors are automatically traced
        console.error('Query error:', error)
      },
    },
  },
})

function MyApp({ Component, pageProps }) {
  useEffect(() => {
    initTelemetry()
  }, [])

  return (
    <QueryClientProvider client={queryClient}>
      <Component {...pageProps} />
    </QueryClientProvider>
  )
}

export default MyApp
```

#### 4. Track Custom Events in Your Components

```typescript
import { trace } from '@opentelemetry/api'

function MyComponent() {
  const tracer = trace.getTracer('app')

  const handleCheckout = async () => {
    const span = tracer.startSpan('checkout.process')

    try {
      span.setAttribute('cart.items', cartItems.length)
      span.setAttribute('cart.total', total)

      await processCheckout()

      span.setStatus({ code: SpanStatusCode.OK })
    } catch (error) {
      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: error.message
      })
      throw error
    } finally {
      span.end()
    }
  }

  return <button onClick={handleCheckout}>Checkout</button>
}
```

### Frontend Error Tracking

Track client-side errors automatically:

```typescript
// lib/error-tracking.ts
import { trace, SpanStatusCode } from '@opentelemetry/api'

export function setupErrorTracking() {
  const tracer = trace.getTracer('error-handler')

  window.addEventListener('error', (event) => {
    const span = tracer.startSpan('error.unhandled')
    span.setAttribute('error.type', 'unhandled')
    span.setAttribute('error.message', event.message)
    span.setAttribute('error.filename', event.filename)
    span.setAttribute('error.lineno', event.lineno)
    span.setStatus({ code: SpanStatusCode.ERROR })
    span.end()
  })

  window.addEventListener('unhandledrejection', (event) => {
    const span = tracer.startSpan('error.unhandled_promise')
    span.setAttribute('error.type', 'promise_rejection')
    span.setAttribute('error.reason', String(event.reason))
    span.setStatus({ code: SpanStatusCode.ERROR })
    span.end()
  })
}

// Call in _app.tsx
setupErrorTracking()
```

### Web Vitals Monitoring

Track Core Web Vitals automatically:

```typescript
// lib/web-vitals.ts
import { trace } from '@opentelemetry/api'
import { onCLS, onFID, onLCP, onFCP, onTTFB } from 'web-vitals'

export function measureWebVitals() {
  const tracer = trace.getTracer('web-vitals')

  onCLS((metric) => {
    const span = tracer.startSpan('web_vital.cls')
    span.setAttribute('metric.value', metric.value)
    span.setAttribute('metric.rating', metric.rating)
    span.end()
  })

  onFID((metric) => {
    const span = tracer.startSpan('web_vital.fid')
    span.setAttribute('metric.value', metric.value)
    span.setAttribute('metric.rating', metric.rating)
    span.end()
  })

  onLCP((metric) => {
    const span = tracer.startSpan('web_vital.lcp')
    span.setAttribute('metric.value', metric.value)
    span.setAttribute('metric.rating', metric.rating)
    span.end()
  })

  onFCP((metric) => {
    const span = tracer.startSpan('web_vital.fcp')
    span.setAttribute('metric.value', metric.value)
    span.end()
  })

  onTTFB((metric) => {
    const span = tracer.startSpan('web_vital.ttfb')
    span.setAttribute('metric.value', metric.value)
    span.end()
  })
}

// Call in _app.tsx
measureWebVitals()
```

---

## For WordPress Sites

### Option 1: Using a Plugin (Easiest)

We recommend **OpenTelemetry for WordPress** plugin:

#### 1. Install Plugin

```bash
# Via WP-CLI
wp plugin install opentelemetry-for-wp --activate

# Or download from GitHub
# https://github.com/open-telemetry/opentelemetry-php-contrib
```

#### 2. Configure in `wp-config.php`

Add these constants before `/* That's all, stop editing! */`:

```php
// OpenTelemetry Configuration
define('OTEL_SERVICE_NAME', 'your-wordpress-site');
define('OTEL_EXPORTER_OTLP_ENDPOINT', 'https://otlp.yourdomain.com');
define('OTEL_EXPORTER_OTLP_HEADERS', 'X-Scope-OrgID=your-tenant-id,Authorization=Bearer obs_xxxxxxxxxxxxx');
define('OTEL_PHP_AUTOLOAD_ENABLED', true);
```

### Option 2: Custom PHP Integration

If you prefer manual integration or need more control:

#### 1. Install Composer Dependencies

```bash
composer require \
  open-telemetry/sdk \
  open-telemetry/exporter-otlp \
  open-telemetry/transport-grpc
```

#### 2. Create Telemetry Helper

```php
<?php
// wp-content/mu-plugins/telemetry.php

use OpenTelemetry\SDK\Trace\TracerProviderFactory;
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Trace\SpanProcessor\SimpleSpanProcessor;
use OpenTelemetry\SDK\Resource\ResourceInfo;
use OpenTelemetry\SDK\Resource\ResourceInfoFactory;
use OpenTelemetry\SemConv\ResourceAttributes;

function init_telemetry() {
    $resource = ResourceInfoFactory::defaultResource()
        ->merge(ResourceInfo::create([
            ResourceAttributes::SERVICE_NAME => 'wordpress-site',
            ResourceAttributes::SERVICE_VERSION => get_bloginfo('version'),
            'deployment.environment' => WP_ENV ?? 'production',
        ]));

    $transport = (new OtlpHttpTransportFactory())->create(
        'https://api.yourdomain.com/v1/traces',
        'application/x-protobuf',
        [
            'X-Scope-OrgID' => 'your-tenant-id',
            'Authorization' => 'Bearer obs_xxxxxxxxxxxxx',
        ]
    );

    $exporter = new SpanExporter($transport);
    $tracerProvider = (new TracerProviderFactory())->create(
        new SimpleSpanProcessor($exporter),
        $resource
    );

    return $tracerProvider->getTracer('wordpress');
}

// Initialize on WordPress init
add_action('init', function() {
    global $tracer;
    $tracer = init_telemetry();
});

// Track page loads
add_action('wp', function() {
    global $tracer;
    $span = $tracer->spanBuilder('page.load')
        ->setAttribute('page.url', $_SERVER['REQUEST_URI'])
        ->setAttribute('page.title', wp_title('', false))
        ->startSpan();

    register_shutdown_function(function() use ($span) {
        $span->end();
    });
});

// Track WooCommerce checkout (if applicable)
add_action('woocommerce_checkout_order_processed', function($order_id) {
    global $tracer;
    $order = wc_get_order($order_id);

    $span = $tracer->spanBuilder('checkout.completed')
        ->setAttribute('order.id', $order_id)
        ->setAttribute('order.total', $order->get_total())
        ->setAttribute('order.items', $order->get_item_count())
        ->startSpan();
    $span->end();
});
```

### WooCommerce Specific Tracking

```php
<?php
// Track add to cart
add_action('woocommerce_add_to_cart', function($cart_item_key, $product_id, $quantity) {
    global $tracer;
    $product = wc_get_product($product_id);

    $span = $tracer->spanBuilder('cart.add_item')
        ->setAttribute('product.id', $product_id)
        ->setAttribute('product.name', $product->get_name())
        ->setAttribute('quantity', $quantity)
        ->startSpan();
    $span->end();
}, 10, 3);

// Track form submissions (Contact Form 7)
add_action('wpcf7_mail_sent', function($contact_form) {
    global $tracer;
    $span = $tracer->spanBuilder('form.submission')
        ->setAttribute('form.id', $contact_form->id())
        ->setAttribute('form.title', $contact_form->title())
        ->startSpan();
    $span->end();
});
```

---

## For Shopify Sites

Shopify requires a different approach since you can't install server-side code.

### Frontend Monitoring via Theme Customization

#### 1. Add Tracking Script

Go to **Online Store > Themes > Edit Code** and add to `theme.liquid` before `</head>`:

```html
<!-- OpenTelemetry Tracking -->
<script src="https://cdn.jsdelivr.net/npm/@opentelemetry/api@latest/build/esm/index.js" type="module"></script>
<script type="module">
  import { trace, context } from 'https://cdn.jsdelivr.net/npm/@opentelemetry/api@latest/build/esm/index.js'
  import { WebTracerProvider } from 'https://cdn.jsdelivr.net/npm/@opentelemetry/sdk-trace-web@latest/build/esm/index.js'
  import { OTLPTraceExporter } from 'https://cdn.jsdelivr.net/npm/@opentelemetry/exporter-trace-otlp-http@latest/build/esm/index.js'
  import { BatchSpanProcessor } from 'https://cdn.jsdelivr.net/npm/@opentelemetry/sdk-trace-base@latest/build/esm/index.js'

  const provider = new WebTracerProvider()
  const exporter = new OTLPTraceExporter({
    url: 'https://api.yourdomain.com/v1/traces',
    headers: {
      'X-Scope-OrgID': 'your-tenant-id',
      'Authorization': 'Bearer obs_xxxxxxxxxxxxx'
    }
  })

  provider.addSpanProcessor(new BatchSpanProcessor(exporter))
  provider.register()

  const tracer = trace.getTracer('shopify-store')

  // Track page views
  const pageSpan = tracer.startSpan('page.view')
  pageSpan.setAttribute('page.url', window.location.href)
  pageSpan.setAttribute('page.title', document.title)
  {% if template %}
  pageSpan.setAttribute('page.template', '{{ template }}')
  {% endif %}
  pageSpan.end()

  // Track add to cart
  document.addEventListener('submit', function(e) {
    if (e.target.matches('form[action="/cart/add"]')) {
      const span = tracer.startSpan('cart.add')
      const formData = new FormData(e.target)
      span.setAttribute('product.id', formData.get('id'))
      span.setAttribute('quantity', formData.get('quantity') || 1)
      span.end()
    }
  })
</script>
```

#### 2. Track Checkout Events

In **Settings > Checkout > Order status page**, add this to "Additional scripts":

```html
<script type="module">
  import { trace } from 'https://cdn.jsdelivr.net/npm/@opentelemetry/api@latest/build/esm/index.js'

  const tracer = trace.getTracer('shopify-store')

  {% if first_time_accessed %}
  const span = tracer.startSpan('checkout.completed')
  span.setAttribute('order.id', '{{ order.id }}')
  span.setAttribute('order.total', {{ total_price }})
  span.setAttribute('order.items', {{ line_items.size }})
  span.setAttribute('customer.id', '{{ customer.id }}')
  span.end()
  {% endif %}
</script>
```

---

## Testing Your Integration

### 1. Check if Data is Being Sent

```bash
# Test the health endpoint
curl https://api.yourdomain.com/health

# Should return: OK
```

### 2. Send a Test Trace

```javascript
// In browser console or Node.js
const testTrace = {
  resourceSpans: [{
    resource: {
      attributes: [{
        key: 'service.name',
        value: { stringValue: 'test-service' }
      }]
    },
    scopeSpans: [{
      spans: [{
        name: 'test-span',
        startTimeUnixNano: Date.now() * 1000000,
        endTimeUnixNano: (Date.now() + 100) * 1000000,
      }]
    }]
  }]
}

fetch('https://api.yourdomain.com/v1/traces', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-Scope-OrgID': 'your-tenant-id',
    'Authorization': 'Bearer obs_xxxxxxxxxxxxx'
  },
  body: JSON.stringify(testTrace)
})
```

### 3. View Your Data

Contact us to access your custom monitoring dashboard where you'll see:
- Real-time performance metrics
- Error rates and traces
- User experience metrics (Web Vitals)
- Custom events you're tracking

---

## Common Issues

### CORS Errors (Browser)

If you see CORS errors, ensure your requests include the proper headers. The API supports CORS for all origins.

### No Data Appearing

1. Check that your API key and tenant ID are correct
2. Verify the endpoint URLs
3. Check browser/server console for errors
4. Ensure HTTPS is used (HTTP won't work)

### High Data Volume

If you're sending too much data:
- Implement sampling (e.g., only track 10% of requests)
- Filter out health check endpoints
- Reduce the number of custom attributes

```javascript
// Example sampling
if (Math.random() < 0.1) { // 10% sampling
  // Only send trace 10% of the time
  sendTrace()
}
```

---

## Support

If you need help:
- **Email**: support@yourdomain.com
- **Response time**: Within 24 hours

## Security Notes

- **Never expose API keys** in client-side code (use environment variables)
- **Use HTTPS** for all requests
- **Rotate keys** if compromised (contact us)
- **Monitor your usage** to detect anomalies
