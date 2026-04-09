GitHub issues are provided at the start of context. These are your open tasks.

You've also been passed a file containing the last few commits. Read these to understand the work that has been done.

## Task Selection

Pick the next task based on this priority order:

1. Critical bugfixes — bugs can block other work
2. Development infrastructure — tests, types, dev scripts need to be solid before features
3. Tracer bullets for new features — small end-to-end slices that validate approach
4. Polish and quick wins — small improvements and additions
5. Refactors — code cleanup and improvements

If there are no more tasks to complete, output <promise>NO MORE TASKS</promise>.

## Exploration

Explore the repo to understand the codebase structure and the relevant code for the current task.

## Implementation

Complete the task as described in the issue.

## Feedback Loops

Before committing, detect and run the project's feedback loops. Check for:

- `package.json` scripts (test, typecheck, lint)
- `composer.json` scripts
- `Makefile` targets
- `pyproject.toml` scripts

Run whatever the project uses. Do not skip feedback loops.

## Git Commit

Make a git commit. Include in the commit message:

- Key decisions made
- Files changed
- Blockers and notes for the next iteration

After committing:

- Close the original GitHub issue if the task is complete
- If the task is not complete for any reason, leave a comment on the GitHub issue with what was done

ONLY WORK ON A SINGLE TASK.
