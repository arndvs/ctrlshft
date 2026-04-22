---
description: "Safety rules for database migrations — backwards compatibility, rollback paths, and data preservation."
paths:
  - "**/migrations/**"
  - "**/prisma/migrations/**"
  - "**/db/migrate/**"
---

# Migration Safety

- Migrations must be backwards-compatible — no dropping columns that running code still reads
- Add new columns as nullable or with a default before backfilling
- Never rename columns in a single migration — add new, migrate data, drop old across separate deploys
- Include a rollback path or document why rollback is not feasible
- Keep migrations small and focused — one schema change per migration
- Test migrations against a copy of production data volume when possible
