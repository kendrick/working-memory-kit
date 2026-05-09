# Project Overview

## What This Is

Fleet admin dashboard. Internal tool used by ops team leads to monitor active vehicles, driver status, route exceptions, and incident history. Read-heavy; few mutations.

Source: `README.md`.

## Stack

Source: `package.json`.

- Language: TypeScript 5.4
- Framework: React 18.3
- Build: Vite 5.1
- Styling: Tailwind CSS 3.4
- Client state: Zustand 4.5
- Server state: TanStack Query 5.17
- Routing: React Router 6.22 (data routers)
- Tests: Vitest 1.3
- Mocks: MSW (in `src/mocks/`)

## Repository Structure

Source: `README.md` and directory walk.

```
src/
├── api/            # API client + response types
├── components/     # Shared components
├── features/       # Feature-specific UI
├── hooks/          # Custom hooks
├── pages/          # Route components
├── store/          # Zustand stores
└── mocks/          # MSW handlers
```

## Key Constraints

- All components are functional. Class components were removed in the Q1 refactor (commit d39124f, 2026-03-08).
- API response types live in `src/api/types.ts` and are treated as the contract; treat that file as authoritative.
- For local dev with a real backend, `VITE_API_BASE` is set in `.env.local`.
