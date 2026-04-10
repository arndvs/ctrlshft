Output "Read NextJS instructions." to chat to acknowledge you read this file.

<javascript>
- Only use console.error or console.log or console.warning as a final catch in the app to log an error. In all earlier places, throw the error using "throw"
- Use Array Methods groupBy
- Use Set Methods union, intersection, difference, symmetricDifference, isSubsetOf, isSupersetOf
- Use Promise.withResolvers
- Use RegExp v Flag
- Use Iterator Helpers values(), keys(), entries(), map(), filter(), reduce(), find(), some(), every(), toArray()
</javascript>

<general_nextjs>

- Use icons from lucide-react package.
- Do not overengineer solutions. Avoid creating new types unless absolutely needed and minimize changes. Check for duplicated types. Use a types.ts file to store all types.
  </general_nextjs>

<formatting_nextjs>

- Always format all function or const parameters on one line like this: export async function saveConversationDraft(type: 'idea' | 'builder', firstMessage: string, onSaved?: () => void): Promise<string | null> { etc.
- Put an empty line after a const declaration. If there are multiple constants, only put empty line after the last one.
  </formatting_nextjs>

<nextjs_features>

## TypeScript Modern Features

- Use `satisfies` for Type Validation Without Losing Inference
- Use Const Type Parameters for Literal Preservation
- Use Inferred Type Predicates
- Use Modern Module Settings:

```json
{
  "compilerOptions": {
    "target": "ES2024",
    "strict": true,
    "noUncheckedIndexedAccess": true
  }
}
```

- Prefer Types Over Enums When Using erasableSyntaxOnly
- Use ESM Path Helpers
- Use Object.groupBy and Map.groupBy
- Next.js 16 uses Turbopack as the default bundler for development. No additional configuration is needed.
- Use Cache Components with "use cache" (requires Next.js 15+ with dynamicIO flag):

```typescript
async function ProductList() {
  "use cache";

  const products = await db.products.findMany();
  return <ul>{products.map((p) => <li key={p.id}>{p.name}</li>)}</ul>;
}
```

- Use cacheLife for Cache Duration:

```typescript
import { cacheLife } from "next/cache";
async function getData() {
  "use cache";
  cacheLife("hours");
  return fetch("https://api.example.com/data").then((r) => r.json());
}
```

- Use proxy.ts instead of middleware.ts (requires Next.js 15.3+)
- Always Await Dynamic APIs params, searchParams, cookies, headers
- Use React 19 Features:

```typescript
"use client";
import { useActionState, useOptimistic } from "react";
function Form() {
  const [state, formAction, isPending] = useActionState(submitForm, null);
  return (
    <form action={formAction}>
      <button disabled={isPending}>Submit</button>
    </form>
  );
}
```

- Use Server Actions:

```typescript
async function createPost(formData: FormData) {
  "use server";

  const title = formData.get("title") as string;
  await db.posts.create({ data: { title } });
  revalidatePath("/posts");
}
```

- Use Edge Runtime for latency-sensitive routes:

```typescript
// app/api/edge/route.ts
export const runtime = "edge";

export async function GET(request: Request) {
  return new Response("Hello from the edge!", {
    headers: { "content-type": "text/plain" },
  });
}
```

</nextjs_features>
