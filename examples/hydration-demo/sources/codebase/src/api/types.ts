// API response contracts. All API responses conform to one of these interfaces.
// When mocking data, conform to these shapes exactly.

export interface User {
  id: string;
  email: string;
  displayName: string;
  role: UserRole;
  createdAt: string; // ISO 8601
}

export type UserRole = "admin" | "ops_lead" | "viewer";

export interface Vehicle {
  id: string;
  fleetId: string;
  status: VehicleStatus;
  driverId: string | null;
  lastPingAt: string; // ISO 8601
  position: GeoPoint | null;
}

export type VehicleStatus =
  | "active"
  | "idle"
  | "maintenance"
  | "out_of_service";

export interface GeoPoint {
  lat: number;
  lng: number;
}

export interface Driver {
  id: string;
  userId: string;
  licenseNumber: string;
  status: "available" | "on_route" | "off_duty";
}

export interface Incident {
  id: string;
  vehicleId: string;
  driverId: string | null;
  reportedAt: string;
  severity: "low" | "medium" | "high" | "critical";
  description: string;
  resolvedAt: string | null;
}

export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}
