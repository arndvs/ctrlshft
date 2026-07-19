#!/usr/bin/env bash
# test-migration-guard.sh — Tests for hooks/migration-guard.sh
#
# Run: bash test/hooks/test-migration-guard.sh

set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/../..")"
source "test/hooks/test-helpers.sh"

HOOK="hooks/migration-guard.sh"

echo "=== migration-guard.sh tests ==="
echo ""

echo "--- unsafe migrations deny ---"

run_hook "$HOOK" "$(make_pretooluse_json 'npx prisma migrate deploy')"
assert_deny "deny bare prisma migrate deploy" "Migration detected"

run_hook "$HOOK" "$(make_pretooluse_json 'pnpm exec drizzle-kit push')"
assert_deny "deny pnpm exec drizzle-kit push" "Migration detected"

run_hook "$HOOK" "$(make_pretooluse_json 'npx --yes prisma migrate deploy')"
assert_deny "deny runner-prefixed migration with flags" "Migration detected"

run_hook "$HOOK" "$(make_pretooluse_json 'sudo npx prisma migrate deploy')"
assert_deny "deny sudo-wrapped migration" "Migration detected"

run_hook "$HOOK" "$(make_pretooluse_json 'if true; then npx prisma migrate deploy; fi')"
assert_deny "deny migration after shell control keyword" "Migration detected"

echo ""
echo "--- safe test database prefixes allow ---"

run_hook "$HOOK" "$(make_pretooluse_json 'DATABASE_URL=postgres://localhost:5433/app npx prisma migrate deploy')"
assert_allow "allow localhost:5433 database URL"

run_hook "$HOOK" "$(make_pretooluse_json 'DATABASE_URL=postgres://localhost/app_test npx prisma migrate deploy')"
assert_allow "allow delimited _test database URL"

run_hook "$HOOK" "$(make_pretooluse_json 'DATABASE_URL=postgres://localhost:5433/app env FOO=bar npx prisma migrate deploy')"
assert_allow "allow env wrapper that preserves DATABASE_URL"

echo ""
echo "--- bypass attempts deny ---"

run_hook "$HOOK" "$(make_pretooluse_json 'DATABASE_URL=postgres://localhost:5433/app env -i npx prisma migrate deploy')"
assert_deny "deny env -i stripping safe DATABASE_URL" "Migration detected"

run_hook "$HOOK" "$(make_pretooluse_json 'DATABASE_URL=postgres://localhost:5433/app env --ignore-environment npx prisma migrate deploy')"
assert_deny "deny env --ignore-environment stripping safe DATABASE_URL" "Migration detected"

run_hook "$HOOK" "$(make_pretooluse_json 'DATABASE_URL=postgres://localhost:5433/app env -u DATABASE_URL npx prisma migrate deploy')"
assert_deny "deny env -u DATABASE_URL stripping safe DATABASE_URL" "Migration detected"

run_hook "$HOOK" "$(make_pretooluse_json 'DATABASE_URL=postgres://localhost:5433/app env --unset=DATABASE_URL npx prisma migrate deploy')"
assert_deny "deny env --unset=DATABASE_URL stripping safe DATABASE_URL" "Migration detected"

run_hook "$HOOK" "$(make_pretooluse_json 'DATABASE_URL=postgres://localhost:5433/app npx prisma migrate deploy && npx prisma migrate deploy')"
assert_deny "deny chained unsafe second migration segment" "Migration detected"

run_hook "$HOOK" "$(make_pretooluse_json 'DATABASE_URL=postgres://localhost:5433/app echo ok | npx prisma migrate deploy')"
assert_deny "deny pipeline RHS migration without safe env" "Migration detected"

run_hook "$HOOK" "$(make_pretooluse_json 'bash -c \"npx prisma migrate deploy\"')"
assert_deny "deny nested shell migration" "nested shells"

echo ""
echo "--- non-command mentions allow ---"

run_hook "$HOOK" "$(make_pretooluse_json 'echo \"npx prisma migrate deploy\"')"
assert_allow "allow quoted migration mention"

run_hook "$HOOK" "$(make_pretooluse_json 'grep -R \"artisan migrate\" docs')"
assert_allow "allow grep migration mention"

report
