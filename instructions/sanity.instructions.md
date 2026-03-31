# Sanity Instructions

Output "Read Sanity instructions." to chat to acknowledge you read this file.

## MCP Server Setup

The Sanity MCP server is remote-hosted — no local npm install required.
Server URL: `https://mcp.sanity.io`
Authentication: OAuth (default) or scoped API token.

Always verify the server is active before any Sanity task. If tools are unavailable or you get a 401 error, the OAuth session may have expired (sessions last ~7 days). To fix, run:

```bash
npx sanity@latest mcp configure
```

Then re-select your editor. To configure for the first time on an existing project:

```bash
sanity mcp configure
```

## Authentication Check

Always call `get_initial_context` first — it must be called before any other tools to initialize context and receive usage instructions. It also returns the active `projectId`, `dataset`, and `apiVersion`.

## Key Concepts

| Concept           | Description                                                         |
| ----------------- | ------------------------------------------------------------------- |
| **Project ID**    | Unique identifier for a Sanity project (e.g. `abc123xy`)            |
| **Dataset**       | Named content store within a project (commonly `production`)        |
| **Document ID**   | Unique ID for a document; drafts are prefixed `drafts.`             |
| **GROQ**          | Sanity's query language — use `query_documents` to execute          |
| **Portable Text** | Sanity's rich text format — complex; see caveats below              |
| **Release**       | A named batch of draft changes to publish together                  |
| **Schema**        | The content model — always check schema before querying or mutating |

## Extracting IDs from URLs

- Project: `https://www.sanity.io/manage/project/{PROJECT_ID}`
- Studio document: `https://{studio}.sanity.studio/structure/{type};{DOCUMENT_ID}`
- Dataset is shown in Studio URL or project settings

## Available Tools

### Setup & Context

| Tool                  | Purpose                                                    |
| --------------------- | ---------------------------------------------------------- |
| `get_initial_context` | **Always call first.** Initializes context, returns config |
| `get_schema`          | Fetch full schema or a specific type's schema              |
| `list_workspaces`     | List available workspace schema names                      |
| `get_sanity_config`   | Returns projectId, dataset, apiVersion                     |

### Querying

| Tool                      | Purpose                                  |
| ------------------------- | ---------------------------------------- |
| `query_documents`         | Execute a GROQ query against the dataset |
| `get_document`            | Retrieve a document directly by ID       |
| `search_documents`        | Semantic search via embeddings index     |
| `list_embeddings_indices` | List available semantic search indices   |

### Document Operations

| Tool                             | Purpose                                                     |
| -------------------------------- | ----------------------------------------------------------- |
| `create_documents_from_json`     | Create documents from JSON (creates drafts by default)      |
| `create_documents_from_markdown` | Create documents from Markdown                              |
| `patch_document`                 | Direct field-level patch — preferred over AI mutation tools |
| `discard_drafts`                 | Discard draft without deleting the published document       |

### Schema & Deployment

| Tool                        | Purpose                                                 |
| --------------------------- | ------------------------------------------------------- |
| `deploy_schema`             | Deploy a schema programmatically                        |
| `list_sanity_rules`         | List available best-practice agent rules                |
| `get_sanity_rules`          | Load specific rules (Next.js, GROQ, schemas, SEO, etc.) |
| `search_docs` / `read_docs` | Search and read official Sanity documentation           |

### Releases & Versions

| Tool             | Purpose                               |
| ---------------- | ------------------------------------- |
| `list_releases`  | List content releases for the project |
| `create_version` | Stage a document into a release       |
| `discard_drafts` | Discard a draft                       |

### Project & Dataset Management

| Tool             | Purpose                                 |
| ---------------- | --------------------------------------- |
| `list_projects`  | List all Sanity projects on the account |
| `find_projects`  | Search projects                         |
| `list_datasets`  | List datasets in the current project    |
| `create_dataset` | Create a new dataset                    |
| `create_project` | Create a new Sanity project             |

### Other

| Tool              | Purpose                                          |
| ----------------- | ------------------------------------------------ |
| `generate_image`  | AI-generated image, placed into a document field |
| `add_cors_origin` | Add a CORS origin to a project                   |

## Common Workflows

**Explore content:**

1. `get_initial_context` → confirm project/dataset
2. `get_schema` → understand the content model before querying
3. `query_documents` with GROQ → retrieve content

**Create or edit a document:**

1. `get_initial_context`
2. `get_schema` for the relevant type
3. `create_documents_from_json` or `patch_document` for targeted field edits
4. Documents are created as **drafts** by default — publish manually in Studio or via a release

**Batch publish with a release:**

1. `list_releases` → find or create a release
2. `create_version` → stage documents into the release
3. Publish the release from Sanity Studio or via the releases API

**Debug a missing document:**

1. `get_document` with the document ID
2. Check publish state, required fields, and schema validation

**Set up a new project from scratch:**

1. `create_project` → auto-adds `localhost:3333` CORS origin
2. `deploy_schema` → define the content model
3. `create_documents_from_json` → seed content

## GROQ Quick Reference

```groq
// All published documents of a type
*[_type == "post"]

// With specific fields
*[_type == "post"]{ _id, title, slug, publishedAt }

// Filter + order
*[_type == "post" && defined(publishedAt)] | order(publishedAt desc)[0..9]

// Dereference a reference field
*[_type == "post"]{ title, "authorName": author->name }

// Draft documents are prefixed "drafts."
*[_id in path("drafts.**")]
```

## Important Caveats

- **Check schema first.** Always call `get_schema` for the relevant type before writing queries or mutations — don't guess field names.
- **Portable Text (Block content).** Some models struggle to write valid Portable Text. If you're having issues with rich text fields, avoid `create_documents_from_markdown` and use `patch_document` with explicit block structures instead. You can also instruct the agent to skip Portable Text fields and fill them manually in Studio.
- **Drafts vs. published.** Creating a document via MCP produces a draft (`drafts.` prefix). It is not live until published.
- **AI credits.** Tool calls that create or modify documents count as Agent Action requests and consume AI credits. Monitor usage in project settings.
- **Token budgeting.** Large queries are paginated automatically. Responses include a count like "12 of 847 documents" — paginate if you need more.
- **Permissions.** If you get a 403, check that your OAuth account or API token has the correct role (Editor or Developer) for the project and dataset.
