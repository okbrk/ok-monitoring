# Building a Customer-Facing Admin Dashboard

This guide will help you build a custom admin dashboard for your customers to view their monitoring data, without giving them direct access to Grafana.

## Architecture

```
┌─────────────────────────────────────┐
│   Customer Dashboard (Your App)     │
│   - Next.js / React                 │
│   - TailwindCSS / Shadcn UI         │
│   - Tanstack Query                  │
└──────────────┬──────────────────────┘
               │ API Calls (VPN-protected)
               │
┌──────────────▼──────────────────────┐
│   API Routes / Backend              │
│   - Query Loki/Mimir/Tempo          │
│   - Manage Tenants (PostgreSQL)     │
│   - Generate Reports                │
└──────────────┬──────────────────────┘
               │
         ┌─────┴─────┬──────────┬──────────┐
         │           │          │          │
      ┌──▼──┐    ┌──▼──┐   ┌──▼──┐   ┌──▼────┐
      │Loki │    │Mimir│   │Tempo│   │Postgres│
      └─────┘    └─────┘   └─────┘   └────────┘
```

## Tech Stack Recommendation

### Frontend
- **Next.js 14+** with App Router
- **Shadcn UI** + **TailwindCSS** for components
- **Tanstack Query** for data fetching
- **Recharts** or **Chart.js** for visualizations
- **Tailwind VPN** for security (optional but recommended)

### Backend
- **Next.js API Routes** or **tRPC**
- Direct queries to Loki/Mimir/Tempo APIs
- PostgreSQL for tenant management
- **NextAuth.js** for authentication

## Project Setup

### 1. Create Next.js Project

```bash
npx create-next-app@latest customer-dashboard
cd customer-dashboard
```

### 2. Install Dependencies

```bash
# UI Components
npx shadcn-ui@latest init
npx shadcn-ui@latest add card chart button select date-picker

# Data Fetching
npm install @tanstack/react-query @tanstack/react-query-devtools
npm install axios

# Authentication
npm install next-auth@latest
npm install @auth/prisma-adapter @prisma/client
npm install bcryptjs

# Charts
npm install recharts

# Utilities
npm install date-fns zod
```

## Backend API Integration

### Querying Loki (Logs)

Create an API route to query logs:

```typescript
// app/api/logs/route.ts
import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/app/api/auth/[...nextauth]/route'

const LOKI_URL = process.env.LOKI_URL || 'http://localhost:3100'

export async function GET(request: NextRequest) {
  const session = await getServerSession(authOptions)
  if (!session?.user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const searchParams = request.nextUrl.searchParams
  const tenantId = session.user.tenantId
  const start = searchParams.get('start') || Date.now() - 3600000 // 1 hour ago
  const end = searchParams.get('end') || Date.now()
  const query = searchParams.get('query') || '{job="app"}'

  try {
    const response = await fetch(
      `${LOKI_URL}/loki/api/v1/query_range?query=${encodeURIComponent(query)}&start=${start}&end=${end}&limit=1000`,
      {
        headers: {
          'X-Scope-OrgID': tenantId,
        },
      }
    )

    const data = await response.json()
    return NextResponse.json(data)
  } catch (error) {
    return NextResponse.json(
      { error: 'Failed to fetch logs' },
      { status: 500 }
    )
  }
}
```

### Querying Mimir (Metrics)

```typescript
// app/api/metrics/route.ts
import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/app/api/auth/[...nextauth]/route'

const MIMIR_URL = process.env.MIMIR_URL || 'http://localhost:8080'

export async function GET(request: NextRequest) {
  const session = await getServerSession(authOptions)
  if (!session?.user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const searchParams = request.nextUrl.searchParams
  const tenantId = session.user.tenantId
  const query = searchParams.get('query') || 'up'
  const start = searchParams.get('start')
  const end = searchParams.get('end')
  const step = searchParams.get('step') || '15s'

  try {
    const url = new URL(`${MIMIR_URL}/prometheus/api/v1/query_range`)
    url.searchParams.set('query', query)
    if (start) url.searchParams.set('start', start)
    if (end) url.searchParams.set('end', end)
    url.searchParams.set('step', step)

    const response = await fetch(url.toString(), {
      headers: {
        'X-Scope-OrgID': tenantId,
      },
    })

    const data = await response.json()
    return NextResponse.json(data)
  } catch (error) {
    return NextResponse.json(
      { error: 'Failed to fetch metrics' },
      { status: 500 }
    )
  }
}
```

### Querying Tempo (Traces)

```typescript
// app/api/traces/route.ts
import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/app/api/auth/[...nextauth]/route'

const TEMPO_URL = process.env.TEMPO_URL || 'http://localhost:3200'

export async function GET(request: NextRequest) {
  const session = await getServerSession(authOptions)
  if (!session?.user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const searchParams = request.nextUrl.searchParams
  const tenantId = session.user.tenantId
  const traceId = searchParams.get('traceId')

  if (!traceId) {
    return NextResponse.json(
      { error: 'traceId is required' },
      { status: 400 }
    )
  }

  try {
    const response = await fetch(
      `${TEMPO_URL}/api/traces/${traceId}`,
      {
        headers: {
          'X-Scope-OrgID': tenantId,
        },
      }
    )

    const data = await response.json()
    return NextResponse.json(data)
  } catch (error) {
    return NextResponse.json(
      { error: 'Failed to fetch trace' },
      { status: 500 }
    )
  }
}
```

## Frontend Components

### Dashboard Page

```typescript
// app/dashboard/page.tsx
'use client'

import { useQuery } from '@tanstack/react-query'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { MetricsChart } from '@/components/metrics-chart'
import { LogsTable } from '@/components/logs-table'
import { DateRangePicker } from '@/components/date-range-picker'
import { useState } from 'date'

export default function DashboardPage() {
  const [dateRange, setDateRange] = useState({
    start: Date.now() - 3600000, // 1 hour ago
    end: Date.now(),
  })

  // Fetch metrics
  const { data: metrics, isLoading: metricsLoading } = useQuery({
    queryKey: ['metrics', dateRange],
    queryFn: async () => {
      const res = await fetch(
        `/api/metrics?query=rate(http_requests_total[5m])&start=${dateRange.start}&end=${dateRange.end}`
      )
      return res.json()
    },
  })

  // Fetch logs
  const { data: logs, isLoading: logsLoading } = useQuery({
    queryKey: ['logs', dateRange],
    queryFn: async () => {
      const res = await fetch(
        `/api/logs?query={job="app"}&start=${dateRange.start}&end=${dateRange.end}`
      )
      return res.json()
    },
  })

  return (
    <div className="space-y-6 p-6">
      <div className="flex justify-between items-center">
        <h1 className="text-3xl font-bold">Dashboard</h1>
        <DateRangePicker value={dateRange} onChange={setDateRange} />
      </div>

      {/* Key Metrics */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader>
            <CardTitle>Total Requests</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">12,345</div>
            <p className="text-xs text-muted-foreground">
              +20.1% from last hour
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Error Rate</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">0.5%</div>
            <p className="text-xs text-muted-foreground">
              -2.3% from last hour
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Avg Response Time</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">124ms</div>
            <p className="text-xs text-muted-foreground">
              -5ms from last hour
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Active Users</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">573</div>
            <p className="text-xs text-muted-foreground">
              +12 from last hour
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Charts */}
      <Card>
        <CardHeader>
          <CardTitle>Request Rate</CardTitle>
        </CardHeader>
        <CardContent>
          {metricsLoading ? (
            <div>Loading...</div>
          ) : (
            <MetricsChart data={metrics} />
          )}
        </CardContent>
      </Card>

      {/* Recent Logs */}
      <Card>
        <CardHeader>
          <CardTitle>Recent Logs</CardTitle>
        </CardHeader>
        <CardContent>
          {logsLoading ? (
            <div>Loading...</div>
          ) : (
            <LogsTable data={logs} />
          )}
        </CardContent>
      </Card>
    </div>
  )
}
```

### Metrics Chart Component

```typescript
// components/metrics-chart.tsx
'use client'

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts'
import { format } from 'date-fns'

interface MetricsChartProps {
  data: any
}

export function MetricsChart({ data }: MetricsChartProps) {
  if (!data?.data?.result?.[0]?.values) {
    return <div>No data available</div>
  }

  const chartData = data.data.result[0].values.map(([timestamp, value]) => ({
    time: format(new Date(timestamp * 1000), 'HH:mm'),
    value: parseFloat(value),
  }))

  return (
    <ResponsiveContainer width="100%" height={350}>
      <LineChart data={chartData}>
        <CartesianGrid strokeDasharray="3 3" />
        <XAxis dataKey="time" />
        <YAxis />
        <Tooltip />
        <Line
          type="monotone"
          dataKey="value"
          stroke="#8884d8"
          strokeWidth={2}
        />
      </LineChart>
    </ResponsiveContainer>
  )
}
```

### Logs Table Component

```typescript
// components/logs-table.tsx
'use client'

import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { format } from 'date-fns'

interface LogsTableProps {
  data: any
}

export function LogsTable({ data }: LogsTableProps) {
  if (!data?.data?.result) {
    return <div>No logs available</div>
  }

  const logs = data.data.result.flatMap((stream) =>
    stream.values.map(([timestamp, message]) => ({
      timestamp: parseInt(timestamp) / 1000000, // Convert to ms
      message,
      labels: stream.stream,
    }))
  )

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Timestamp</TableHead>
          <TableHead>Message</TableHead>
          <TableHead>Level</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {logs.map((log, index) => (
          <TableRow key={index}>
            <TableCell className="font-mono text-xs">
              {format(new Date(log.timestamp), 'yyyy-MM-dd HH:mm:ss')}
            </TableCell>
            <TableCell className="font-mono text-xs max-w-2xl truncate">
              {log.message}
            </TableCell>
            <TableCell>
              <span
                className={`px-2 py-1 rounded text-xs ${
                  log.labels.level === 'error'
                    ? 'bg-red-100 text-red-800'
                    : 'bg-gray-100 text-gray-800'
                }`}
              >
                {log.labels.level || 'info'}
              </span>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}
```

## Authentication with NextAuth

```typescript
// app/api/auth/[...nextauth]/route.ts
import NextAuth from 'next-auth'
import CredentialsProvider from 'next-auth/providers/credentials'
import { PrismaAdapter } from '@auth/prisma-adapter'
import { prisma } from '@/lib/prisma'
import bcrypt from 'bcryptjs'

export const authOptions = {
  adapter: PrismaAdapter(prisma),
  providers: [
    CredentialsProvider({
      name: 'credentials',
      credentials: {
        email: { label: 'Email', type: 'email' },
        password: { label: 'Password', type: 'password' },
      },
      async authorize(credentials) {
        if (!credentials?.email || !credentials?.password) {
          throw new Error('Invalid credentials')
        }

        const user = await prisma.user.findUnique({
          where: { email: credentials.email },
          include: { tenant: true },
        })

        if (!user || !user.hashedPassword) {
          throw new Error('Invalid credentials')
        }

        const isValid = await bcrypt.compare(
          credentials.password,
          user.hashedPassword
        )

        if (!isValid) {
          throw new Error('Invalid credentials')
        }

        return {
          id: user.id,
          email: user.email,
          name: user.name,
          tenantId: user.tenant.tenantId,
        }
      },
    }),
  ],
  callbacks: {
    async jwt({ token, user }) {
      if (user) {
        token.tenantId = user.tenantId
      }
      return token
    },
    async session({ session, token }) {
      if (session.user) {
        session.user.tenantId = token.tenantId
      }
      return session
    },
  },
  pages: {
    signIn: '/login',
  },
  session: {
    strategy: 'jwt',
  },
}

const handler = NextAuth(authOptions)
export { handler as GET, handler as POST }
```

## Deployment

### 1. Environment Variables

```bash
# .env
DATABASE_URL="postgresql://..."
NEXTAUTH_SECRET="generate-with-openssl-rand-base64-32"
NEXTAUTH_URL="http://localhost:3000"

# Observability Backend (accessible via Tailscale)
LOKI_URL="http://<tailscale-ip>:3100"
MIMIR_URL="http://<tailscale-ip>:8080"
TEMPO_URL="http://<tailscale-ip>:3200"
POSTGRES_URL="postgresql://tenants:password@<tailscale-ip>:5432/tenants"
```

### 2. Deploy to Vercel

```bash
vercel
# Set environment variables in Vercel dashboard
```

### 3. Security

- Dashboard should also be behind Tailscale VPN
- Or use IP whitelisting in Vercel
- Always use HTTPS
- Implement rate limiting

## Next Steps

1. **Add more visualizations**: Error traces, Web Vitals, custom dashboards
2. **Real-time updates**: Use WebSockets or polling for live data
3. **Alerting**: Email/Slack notifications for critical events
4. **Reports**: Generate PDF reports for customers
5. **Multi-site support**: Allow customers to monitor multiple websites

## Resources

- [Loki API Documentation](https://grafana.com/docs/loki/latest/api/)
- [Mimir API Documentation](https://grafana.com/docs/mimir/latest/references/http-api/)
- [Tempo API Documentation](https://grafana.com/docs/tempo/latest/api_docs/)
- [Next.js Documentation](https://nextjs.org/docs)
- [Shadcn UI](https://ui.shadcn.com)
- [Tanstack Query](https://tanstack.com/query/latest)

