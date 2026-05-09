# Fleet Admin Dashboard

Internal admin dashboard for fleet operations. Used by ops team leads to see active vehicles, driver status, route exceptions, and incident history. Read-heavy; few mutations.

## Stack

- React 18 + TypeScript 5
- Vite for dev/build
- Tailwind CSS for styling
- Zustand for client state
- TanStack Query for server state and caching
- Vitest for tests

## Running locally

```bash
npm install
npm run dev
```

The dev server runs on `localhost:5173`. Backend is mocked via MSW handlers in `src/mocks/`; for real backend access, set `VITE_API_BASE` in `.env.local`.

## Repository structure

```
src/
├── api/            # API client + types
├── components/     # Shared components
├── features/       # Feature-specific UI (vehicle list, driver detail, etc.)
├── hooks/          # Custom hooks
├── pages/          # Route components
└── store/          # Zustand stores
```

## Notes for new contributors

- Components are functional only; we removed the last class component in the Q1 refactor.
- Tailwind utility-first; avoid custom CSS unless it's clearly outside Tailwind's range.
- API responses are typed via interfaces in `src/api/types.ts`; treat that file as the contract.
