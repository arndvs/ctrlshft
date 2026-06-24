---
description: "Better Auth conventions — context routing, skill loading, environment safety, security hardening, plugins, and migrations."
---
Output "Read Better Auth instructions." to chat to acknowledge you read this file.

# Better Auth Context

Load this instruction when `$ACTIVE_CONTEXTS` contains `better-auth`, or when the user mentions Better Auth, `betterauth`, `auth.ts`, `auth-client.ts`, Better Auth plugins, Better Auth migrations, or TypeScript authentication setup with Better Auth.

## Skill Router

Before modifying Better Auth code, load the relevant local skill(s) from `~/dotfiles/skills/_local/`:

| Task | Skill |
|------|-------|
| General Better Auth setup, server/client config, adapters, sessions, plugins, env vars | `better-auth-best-practices` |
| Adding login/sign-up/authentication to a TypeScript or JavaScript app | `create-auth-skill` |
| Secrets, cookies, CSRF, trusted origins, rate limits, audit logging, production hardening | `better-auth-security-best-practices` |
| Email/password login, verification, reset flows, password policies, hashing | `email-and-password-best-practices` |
| Organizations, teams, invitations, roles, permissions, RBAC | `organization-best-practices` |
| MFA/2FA, TOTP, OTP, backup codes, trusted devices | `two-factor-authentication-best-practices` |

If multiple topics apply, load multiple skills before planning. Do not guess from training data when the package docs or installed version can answer the question.

## Version and Documentation Awareness

- Check the app's `package.json` and lockfile for the installed `better-auth` version before changing APIs.
- Prefer the official Better Auth docs and the installed package exports over memory when there is any uncertainty.
- For framework-specific integration, also load that framework's instructions (`nextjs`, `expo`, etc.) when its context is active.

## Environment and Secrets

- Never hardcode `BETTER_AUTH_SECRET`, OAuth client secrets, database URLs, SMTP/API keys, or token encryption keys.
- Required environment variables belong in the target app's env system; example files may contain placeholders only.
- If adding Better Auth to an app and no env example exists, create one with placeholders for required variables and tell the user.
- Use `BETTER_AUTH_SECRET` and `BETTER_AUTH_URL` unless the project has a clear existing convention.
- OAuth providers require both ID and secret variables, named consistently with the existing project style.

## Implementation Guardrails

- Detect the framework, router, package manager, database/ORM, existing auth provider, and desired auth methods before writing code.
- Do not run Better Auth migrations blindly. Explain what schema changes are expected, use the project's migration workflow, and preserve rollback/data-safety conventions.
- Re-run the Better Auth CLI generate/migrate step after adding or changing plugins.
- Keep CSRF and origin checks enabled unless the user explicitly asks and a compensating control exists.
- Configure `trustedOrigins`, secure cookies, rate limits, and strong secrets before production deployment.
- Import plugin code from documented paths for the installed version; verify exports if TypeScript reports missing symbols.

## Completion Checklist

- Relevant Better Auth skill(s) loaded.
- Env placeholders added without secrets.
- Route handler/server adapter/client helper added for the detected framework.
- Database schema/migration path documented or run with user-safe validation.
- Security-sensitive settings reviewed: secret, URL, trusted origins, cookies, CSRF, rate limits.
- Typecheck/tests/lint run when available.