# Hydration Demo Fixture Set

Synthesized fake codebase for demoing the [AI-assisted hydration pipeline](../../guide/ai-assisted-hydration.md). All content is fictional; the company and app don't exist.

## Layout

```
hydration-demo/
├── sources/
│   ├── codebase/           # tiny mini-app the bootstrap can scan
│   │   ├── package.json
│   │   ├── README.md
│   │   └── src/
│   │       ├── api/types.ts
│   │       └── components/UserCard.tsx
│   └── git-log-sample.md   # fake recent git history
└── expected/
    └── working-memory/     # what AI should produce
        ├── projectOverview.md
        ├── conventions.md
        ├── dataContracts.md
        └── decisionLog.md
```

## Demo flow

1. The codebase under `sources/codebase/` is what an agent would scan to extract working memory content.
2. Run the hydration pipeline against the codebase plus the git log sample.
3. Compare the AI-produced drafts against the records in `expected/working-memory/`.

## What this demonstrates

| Source | Produces |
| --- | --- |
| `package.json` | Stack section of `projectOverview.md` |
| `src/api/types.ts` | Entries in `dataContracts.md` |
| `src/components/UserCard.tsx` | Convention entries (functional component pattern, Tailwind class style, prop interface naming) |
| `git-log-sample.md` | Decision log entries inferred from conventional-commit prefixes and recent refactors |
| `README.md` | "What This Is" section of `projectOverview.md` |

`activeContext.md` is excluded; that file is per-developer and gitignored, not a hydration target.
