# Conventions

## Naming

- Component files use PascalCase: `UserCard.tsx`, `VehicleList.tsx`
- Hooks use `use` prefix: `useFleetData.ts`
- Stores under `src/store/` use camelCase: `vehiclesStore.ts`

Example: `src/components/UserCard.tsx`

## File organization

- Shared components in `src/components/`
- Feature-specific components in `src/features/<feature>/`
- API types centralized in `src/api/types.ts` (source: commit 8e4cd0d, "consolidate API response types into single file")
- Zustand stores in `src/store/`

## Component patterns

- Functional components only. Last class component removed 2026-03-08 (commit d39124f).
- Props use a TypeScript `interface` named `<Component>Props`. Example: `UserCardProps` in `src/components/UserCard.tsx`.
- Optional handlers default to `undefined`; check with `if (onHandler)` before invoking.
- Tailwind utility-first. Avoid custom CSS unless clearly outside Tailwind's range. Source: `README.md`, "Notes for new contributors."

## Error handling

- API calls go through the central `apiClient` wrapper (source: commit 4a08c9c, "centralize error handling in apiClient wrapper")
- Transient 503s are retried in `apiClient` (source: commit d3f1b25)
- 401 from any endpoint clears the stale session (source: commit 06c4e58)
