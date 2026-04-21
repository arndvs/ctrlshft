# clients/

Private client and project context for ctrl+shft.

This directory keeps private context out of the main repo while still allowing
a shared template + loading mechanism.

## Structure

- `clients/_template/` — tracked templates for onboarding new clients
- `clients/<client-slug>/` — private client folders (ignored)

## Quick start

Run:

- `bash ~/dotfiles/bin/new-client.sh`

Then map one or more project directories in `clients/<client-slug>/.projects`.

## How loading works

- `detect-client.sh` runs on every `cd()` (via shell integration).
- It scans all `clients/*/.projects` mappings.
- On match, it writes `working/active-client.md` with `@` references to:
  - `client.instructions.md`
  - `project.instructions.md` (if mapped)
- `CLAUDE.base.md` always references `@~/dotfiles/working/active-client.md`.

If no client is active, `working/active-client.md` contains an empty placeholder.
