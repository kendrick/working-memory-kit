# Decision Log

<!-- Append-only. Most recent at top. -->

## 2026-04-19: Migrate client state from Redux to Zustand

**Source:** commit a4f8e21 (`refactor(state): migrate from Redux to Zustand`)

**Context:** Redux store had grown to 1.2k LOC of boilerplate for what was effectively client-only UI state. Server state had already moved to TanStack Query (see 2026-03-01 entry). What remained didn't justify Redux's overhead.

**Decision:** Replace remaining Redux stores with Zustand. Selectors stay close to where they're used.

**Alternatives considered:** Stay on Redux Toolkit (less migration, more boilerplate); Jotai (similar tradeoffs to Zustand, less familiar to the team).

## 2026-04-12: Switch to React Router v6 data routers

**Source:** commit f5b3d47 (`refactor(routing): switch to react-router v6 data routers`)

**Decision:** Adopt the data router API for all routes. Loaders and actions colocate fetch with the route.

## 2026-03-08: Remove last class component

**Source:** commit d39124f (`refactor(components): remove last class component (FleetSidebar)`)

**Decision:** All components are functional. Class components are no longer permitted in this codebase.

## 2026-03-01: Adopt TanStack Query for server state

**Source:** commit f5b346f (`docs: ADR 0003 - choose TanStack Query over manual fetch`)

**Context:** Manual fetch with custom caching was inconsistent across features. Three different cache invalidation patterns coexisted.

**Decision:** Use TanStack Query for all server state. Cache keys live alongside the hooks that use them.

**Alternatives considered:** SWR (simpler API but less mature mutation/optimistic-update story); custom continued (status quo).
