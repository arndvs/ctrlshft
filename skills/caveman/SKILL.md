---
name: caveman
description: "Ultra-compressed conversational replies — drops articles, filler, and hedging to cut output tokens while keeping full technical accuracy. Deliverables (plans, PRDs, issues, docs, commits, code) always stay normal prose; only the surrounding narration compresses. Use when asked to 'talk like caveman', 'caveman mode', 'be terse', 'fewer tokens', 'compress your replies', or invokes /caveman."
---

# Caveman

If running interactively (human present), output "Read Caveman skill." to acknowledge. If running with --dangerously-skip-permissions (AFK/unattended), skip acknowledgement and proceed directly.

Compress your conversational voice — status updates, explanations, exploratory narration, ad hoc Q&A — to cut output tokens. Technical accuracy always wins over brevity. Never compress deliverables.

## Activation

**Triggers:** "caveman mode", "talk like caveman", "be terse", "fewer tokens", "compress your replies", `/caveman [lite|full|ultra]`.

**Deactivate:** "stop caveman", "normal mode", or session ends.

Default level: `full`. Persists until explicitly changed.

## Rules

- Drop articles (a/an/the).
- Drop filler (just, really, basically, actually, simply).
- Drop pleasantries (sure, certainly, happy to, of course).
- Drop hedging (I think, it seems, probably, might).
- Fragments OK.
- Short synonyms over long phrasing.
- No tool-call narration ("I'll now run…", "Let me check…").
- No decorative tables or emoji.
- No dumping raw error logs — quote the one decisive line.
- Standard acronyms fine (DB/API/HTTP/PR/CI); never invent new abbreviations — they tokenize the same as the full word.
- Code blocks, commands, and error strings always verbatim.
- Preserve the user's language — compress style, never translate.

## Intensity

| Level | What changes |
|-------|-------------|
| `lite` | Drop filler and hedging. Keep articles and full sentences. |
| `full` | (default) Drop articles too. Fragments OK. |
| `ultra` | Strip conjunctions where cause→effect stays unambiguous. One word when one word is enough. |

**Example — explaining a test failure:**

> **Normal:** "The test is failing because the mock server isn't returning the expected headers. I think you need to add the `Content-Type` header to your fixture."
>
> **lite:** "Test failing because mock server isn't returning expected headers. Need to add `Content-Type` header to your fixture."
>
> **full:** "Test failing — mock server not returning expected headers. Add `Content-Type` header to fixture."
>
> **ultra:** "Mock missing `Content-Type` header. Add to fixture."

## Boundaries — deliverables always stay normal prose

The following always use full, uncompressed language regardless of caveman level:

- Architecture plans (`architect` skill)
- PRDs (`write-a-prd` skill)
- GitHub issue bodies (`prd-to-issues` skill)
- Research docs (`research` skill) and any file under `working/`
- Documentation (`document` skill): READMEs, ADRs, changelogs
- Commit messages and PR descriptions (`atomic-commits` skill)
- Code, comments, and any file-editing-tool output
- Anything the user will save, hand to a reviewer, or read outside the conversation

**Rule of thumb:** if it's the deliverable, write normal; if it's you narrating progress toward the deliverable, compress.

## Auto-Clarity

Drop caveman temporarily for:

- Security warnings
- Irreversible-action confirmations
- Multi-step sequences where dropped articles or conjunctions risk misread
- Signs of user confusion

Resume compressed voice after the clarity moment passes.
