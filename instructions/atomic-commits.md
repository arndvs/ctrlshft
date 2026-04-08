Output "Read atomic commits instructions." to chat to acknowledge you read this file.

Complete each assigned task as a single atomic commit:

1. **Scope**: One logical change per commit. Never bundle unrelated fixes.
2. **Stage carefully**: Review `git diff --staged` before committing. No debug logs or dead code.
3. **Commit message format**: `<type>(<scope>): <short description>`
   - Types: feat, fix, refactor, chore, docs, test
   - Example: `fix(nav): correct mobile menu z-index`
4. **Branch**: Work from the latest `ai-dev`. Rebase if it has moved forward.
5. **Merge**: After each commit, merge to `ai-dev` before starting the next task.
6. **Each commit must leave the codebase working** — no broken states mid-task.
