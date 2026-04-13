---
name: tdd
description: "Red-green refactor workflow for test-driven development. Use when asked to 'write tests first', 'TDD', 'red-green refactor', 'test-driven', or 'failing test first'. Backend-only — do not use for frontend components."
disable-model-invocation: true
---

# TDD (Red-Green Refactor)

Output "Read TDD skill." to chat to acknowledge you read this file.

## Scope

Backend code only — API routes, services, utilities, data transformations. Frontend components change too fluidly for TDD. If the task involves UI, use `/do-work` instead.

## Workflow

For each vertical slice, repeat this cycle:

### 1. Red — Write a failing test

Write ONE test that describes the expected behavior. Run it. It MUST fail. If it passes, the test is not testing anything new — rewrite it.

### 2. Green — Write minimum code to pass

Implement the minimum code required to make the test pass. No more. Run the test. It MUST pass.

### 3. Refactor — Clean up while green

Improve the implementation without changing behavior. Run the test after every change — it must stay green. Extract helpers, rename variables, simplify logic.

### 4. Commit

Once the test is green and the code is clean, commit. One test + its implementation = one commit.

## Rules

- ONE test at a time. Do not write a test suite upfront — that's horizontal coding.
- Run the test after EVERY step (red, green, refactor). Never skip a run.
- If combining with tracer bullets: one test per vertical slice, one slice at a time.
- Auto-detect the test runner from the workspace (package.json scripts, pytest, phpunit, etc.).
- If no test runner exists, tell the user and ask how to run tests.
