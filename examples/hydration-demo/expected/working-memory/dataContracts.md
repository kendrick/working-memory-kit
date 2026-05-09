# Data Contracts

Source: `src/api/types.ts`. All API responses conform to one of these interfaces. When mocking, conform exactly.

## User

```typescript
interface User {
  id: string;
  email: string;
  displayName: string;
  role: "admin" | "ops_lead" | "viewer";
  createdAt: string; // ISO 8601
}
```

## Vehicle

```typescript
interface Vehicle {
  id: string;
  fleetId: string;
  status: "active" | "idle" | "maintenance" | "out_of_service";
  driverId: string | null;
  lastPingAt: string; // ISO 8601
  position: { lat: number; lng: number } | null;
}
```

## Driver

```typescript
interface Driver {
  id: string;
  userId: string;
  licenseNumber: string;
  status: "available" | "on_route" | "off_duty";
}
```

## Incident

```typescript
interface Incident {
  id: string;
  vehicleId: string;
  driverId: string | null;
  reportedAt: string;
  severity: "low" | "medium" | "high" | "critical";
  description: string;
  resolvedAt: string | null;
}
```

## Pagination wrapper

```typescript
interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}
```

All list endpoints return `PaginatedResponse<T>`.
