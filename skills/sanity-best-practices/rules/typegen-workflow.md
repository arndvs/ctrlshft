---
title: TypeGen Update Workflow
description: Run extract then generate after schema or query changes
tags: typegen, typescript, workflow, types
---

## TypeGen Update Workflow

TypeGen works in a cycle: Extract schema → Generate types. Run this whenever schema or queries change.

### Setup

**package.json:**
```json
{
  "scripts": {
    "typegen": "sanity schema extract --path=./src/sanity/extract.json --enforce-required-fields && sanity typegen generate"
  }
}
```

**sanity.cli.ts:**
```ts
import { defineCliConfig } from 'sanity/cli'

export default defineCliConfig({
    reactStrictMode: true,
    typegen: {
        enabled: true,
        path: './src/**/*.{ts,tsx,js,jsx}',
        schema: './src/sanity/extract.json',
        generates: './src/sanity/types.ts',
        overloadClientMethods: true,
    },
    schemaExtraction: {
        enabled: true,
        path: './src/sanity/extract.json',
        enforceRequiredFields: true,
    },
})
```

`schemaExtraction` is configured separately from `typegen`. If you run extraction manually, use `sanity schema extract --enforce-required-fields` to mirror `enforceRequiredFields: true`.

### Workflow

1. Modify schema (`schemaTypes/...`)
2. Modify queries (files with `defineQuery`)
3. Run `npm run typegen`
4. Restart TS Server if types don't update

### Usage

```typescript
import { defineQuery } from "next-sanity";

// Query name determines type name
const POST_QUERY = defineQuery(`*[_type == "post"]{ title, slug }`)

// Generated type: POST_QUERYResult
import type { POST_QUERYResult } from "@/sanity/types"

function PostList({ posts }: { posts: POST_QUERYResult }) {
  // Fully typed!
}
```

### Git Strategy

**Option A: Commit generated types (most teams)**
- Types available immediately after `git pull`
- CI doesn't need to run typegen

**Option B: Generate in CI (larger teams)**
```gitignore
# .gitignore
src/sanity/types.ts
src/sanity/extract.json
```

Then in CI: `npm run typegen && npm run build`

Reference: [Sanity TypeGen](https://www.sanity.io/docs/apis-and-sdks/sanity-typegen)
