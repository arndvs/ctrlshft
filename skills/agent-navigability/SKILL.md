---
name: agent-navigability
description: Audit a codebase for how easily a coding agent can navigate it, and propose structural fixes. Use this whenever an agent keeps re-exploring the same code, burns context finding where things live, edits the wrong file, or misses call sites it should have found; when reviewing structure, naming, module boundaries, or type usage for legibility rather than correctness; when onboarding cost is high for agents or new engineers; or when someone asks why agent runs on this repo are slow, expensive, or unreliable. Also use for requests like "restructure this for agents", "why does it keep missing files", "review our naming", or planning a refactor whose goal is comprehension rather than behaviour. Includes a migration mode for repo-wide restructuring such as separating client from server, splitting a monolith, or changing the top-level layout, which produces a phased plan rather than a findings list.
---

# Agent navigability audit

Every fresh agent session re-derives where things live. That cost is paid on
every run, forever, and it scales with how many agents you run rather than how
many engineers you have. A structure that's merely tolerable for a team that
already knows it can be genuinely expensive for something that doesn't.

The test throughout: **can an agent find the right file without reading the wrong
ones?** Not "is this well designed" — a clean architecture can still be
unnavigable, and a messy one can be easy to search. Legibility is a separate axis
from quality, and this skill only audits legibility.

Findings here are structural. If the question is about runtime output, error
handling, or observability, use `logging-audit` instead — that's the behavioural
half of the same problem.

---

## Step 1: Navigate it yourself first

Don't read the repo and form opinions. **Attempt a real task and watch where you
struggle.** Pick something plausible — "add a field to the main entity and thread
it through", "find every place that writes to storage", "add an endpoint like the
existing ones" — and note, concretely:

- Which files you opened that turned out to be irrelevant
- Where you had to guess, and what you guessed from
- Searches that returned too much to be useful
- Points where you couldn't tell which of several similar files was the live one

That list *is* the finding set. Structural advice derived from reading a tree is
generic and mostly unactionable; advice derived from a failed search is specific
and obviously true once stated.

If the repo is large, sample: the main entry point, one recently changed feature,
and the test directory.

## Step 2: Establish the prevailing pattern

Consistency beats correctness here. A repo where every module follows an unusual
convention is navigable; a repo with three good conventions in different corners
is not. So find what dominates before recommending anything:

- Directory layout — by layer, by feature, by domain?
- Where do tests live relative to source?
- How are modules named, and how is a public interface distinguished?
- Is there existing agent-facing documentation (`CLAUDE.md`, `AGENTS.md`,
  `.cursor/rules`, `README` per package)?

Then audit for **deviation from the dominant pattern**, not deviation from an
ideal. Recommending a restructure that fights the codebase's own grain produces
a PR nobody merges.

Load `references/checklist.md` for the specific structural properties to check.

---

## Step 3: What to look for

Ordered by how much agent time each wastes.

### High cost

**Unsearchable names.** The single highest-leverage finding. A name earns its
keep if grepping it returns roughly the places that matter. `Data`, `Manager`,
`Handler`, `Item`, `process`, `util`, `helper`, `Request`, `Response` fail this —
searching returns hundreds of unrelated hits, so the agent falls back to reading
files. Specific, verbose names are navigational infrastructure: `InvoiceLineItem`
finds its own call sites; `Item` cannot.

Weight this by how central the name is. A badly named local variable costs
nothing; a badly named core type costs on every run that touches it.

**No obvious entry point.** An agent should be able to identify where a service
starts in one look. Flag: no `main`/`index`/`app` at a predictable path, several
plausible candidates with nothing distinguishing the live one, or startup logic
buried in a file named for something else.

**Untyped data crossing boundaries.** Dicts, `any`, bare JSON, or stringly-typed
payloads passed between modules erase the trail. A named type is followable —
grep it and you get the full path from producer to consumer. An anonymous dict
has to be reconstructed by reading every hop. Applies to classes, interfaces,
structs, enums, and named exceptions equally.

**Duplicate or ambiguous authority.** Two files that could plausibly own the same
behaviour: `utils.py` and `helpers.py`, `config.ts` and `settings.ts`, a `v2`
directory alongside the original with no indication which is live. The agent
picks one, sometimes the dead one, and the edit silently does nothing.

**Files too large to load selectively.** A 3,000-line module forces an all-or-
nothing context decision. Rough ceiling around 1,000 lines, applied with
judgment — generated code, migrations, and lock files don't count, and a
cohesive long file beats five arbitrary fragments. Flag when the file has clearly
accumulated unrelated responsibilities, not merely when it's long.

### Worth fixing

**Tests that don't mirror source.** When `src/core/parser.ts` has its test at a
predictable path, an agent finds and extends it without searching. When tests are
organised by type, or by who wrote them, or not at all, it either searches or —
worse — writes a duplicate test in the wrong place.

**Magic values inline.** Literals scattered through the code instead of a named
constant. Costs on every change: the agent has to find all of them, and it will
miss some. A named constant makes the search exact.

**Missing local documentation.** A root `README` doesn't help an agent working
three directories down. A short `CLAUDE.md` or `AGENTS.md` in a subsystem — what
it does, what to touch, what not to — is read exactly when relevant and costs
nothing otherwise. Recommend these for subsystems with non-obvious constraints,
not for every directory; noise here has the same cost as noise anywhere.

**Undiscoverable commands.** How to run, test, and lint should be in one
predictable place. If it's spread across a README, a CI config, and tribal
knowledge, every session rediscovers it — usually by reading the CI config, which
is expensive and often wrong for local use.

**Inconsistent layering.** Some features organised by layer, others by domain.
Each requires a different search strategy, and the agent can't tell which applies
until it's already looked.

### Lower priority

**Deep nesting.** Long paths cost tokens and make partial matches ambiguous. Real
but minor; only raise it alongside something else.

**Dead code.** Unreferenced files and legacy paths are read, considered, and
sometimes edited. Worth flagging when concentrated, not worth a sweep.

---

## Step 4: Report

Lead with what it costs, not what it violates.

```
### High cost

**`src/models.py`** — `QueryRequest`, `DataResponse`, and `Item` appear 340 times
across the repo; searching any of them returns most of the codebase, so tracing a
field means reading files rather than grepping.

Rename to what they carry: `SqlQueryRequest`, `TableSchemaResponse`,
`InvoiceLineItem`. Mechanical, and it makes every future search exact.

### Worth fixing

**`app/server/` vs `app/api/`** — both define route handlers; nothing indicates
which is live. An agent editing endpoints has a coin flip.

Consolidate, or leave a one-line `CLAUDE.md` in the dead one saying so.
```

Every finding needs a location, the concrete cost, and a fix. "This violates
single responsibility" is not a finding. "An agent adding a field here must read
four files to know which one is authoritative" is.

**Sequence the recommendations.** Structural changes have wildly different
costs — renaming a type is a mechanical refactor with test coverage; splitting a
module is a design decision with merge-conflict fallout. Put the cheap
high-yield changes first and say plainly which ones aren't worth doing now.

If the repo is already navigable, say so. Restructuring for its own sake costs
review time and breaks people's mental maps, and a skill that always finds
problems teaches people to stop running it.

---

## Migration mode

Some findings are too large for the incremental path: separating client from
server, splitting a monolith into services, moving from layer-based to
feature-based layout. These touch every import in the repo. They can't be
proposed as a routine finding — an audit that files "reorganise your top-level
directories" alongside three renames gets the whole batch declined.

Switch to this mode when the structural problem is repo-wide rather than local,
or when someone explicitly asks about restructuring. The output is not findings —
it's a phased plan a human accepts once.

**Establish the payoff first, concretely.** The client/server case is the clean
example: with the split, an agent working on either half can ignore the other, so
roughly half the search space disappears on every run forever. State the
equivalent for the proposed split. If it can't be stated, the migration is
refactoring for its own sake and should be declined here rather than after the
work starts.

**Phase by reversibility, not by area.** Order the work so each phase lands
independently and leaves the repo working:

1. Mechanical, test-covered moves — renames, file relocations with import updates
2. Boundary introduction — a types module, an interface layer, an explicit seam
   between the halves, with both sides still in place
3. The split itself, once the seam exists and is exercised
4. Cleanup — dead paths, now-redundant indirection

Phases one and two carry almost no risk and deliver most of the navigability
benefit. That ordering matters more than the destination, because a migration
that stalls after phase two has still improved things, whereas one that stalls
mid-split leaves the repo worse than when it started.

**State what breaks.** Open PRs will conflict; anything referencing moved paths
from outside the repo will break. Name these, and name the window where merge
pain is lowest.

**Give a stop condition.** Migrations that lose their sponsor halfway are the
common failure. Say which phase is the minimum worth doing, so a partial
migration is a decision rather than an abandonment.

## A note on what this can't fix

Navigability improvements compound but don't substitute. A perfectly organised
repo still leaves an agent re-deriving structure each session — the fix for that
is a priming command or an `AGENTS.md`, not more refactoring. See
`references/orientation-assets.md`.

Recommend those alongside structural fixes, and prefer them when the structural
change is expensive. A file that documents where things live is dramatically
cheaper than moving them, and often buys most of the same benefit.

They stop being enough when the problem is ambiguity rather than ignorance. A
document can say where things live; it can't make two files that plausibly own
the same behaviour distinguishable, and it can't make an overloaded name
searchable.
