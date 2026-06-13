---
name: mobile-dev
description: "Expo mobile development workflow — clean state reset, startup sequence, native rebuild decisions, and Android emulator/QEMU troubleshooting for Launch Core and its forks (Foreword, Scorpion, Aligned, Cast)."
contexts: [expo, react-native, mobile]
---

# Mobile Dev Skill

Output "Read Mobile Dev skill." to chat to acknowledge you read this file.

Use this skill when:
- Starting a new mobile dev session
- Debugging a Metro or emulator issue
- Deciding whether a native rebuild is needed
- Setting up a fresh fork of Launch Core
- Troubleshooting "Using Expo Go" or redbox errors

---

## Phase 0 — Read Context First

Before touching the app, load the Expo Mobile instructions:

```
~/dotfiles/instructions/expo-mobile.instructions.md
```

This file contains the stack reference, native module list, correct startup sequence, and all troubleshooting commands. Do not skip it.

---

## Phase 1 — Clean State Reset

Always start from a known-clean state to avoid residual Metro/emulator confusion.

```bash
# 1. Force-stop the app on emulator (swallows errors if not running)
adb shell am force-stop com.launchhq.mobile 2>/dev/null || true

# 2. Remove ADB reverse mappings
adb reverse --remove-all 2>/dev/null || true

# 3. Check current state
adb devices -l
lsof -nP -iTCP:8081 -sTCP:LISTEN 2>/dev/null || ss -ltn 2>/dev/null | grep ':8081' || true
git status --short --branch
```

Expected clean state:
- `adb devices` shows `emulator-5554 device` (or no devices if emulator not running)
- Nothing listening on `8081`
- Branch is what you expect

---

## Phase 2 — Dependency Health Check

```bash
# Check for corrupted node_modules (common after better-auth/expo installs)
ls node_modules/@better-auth/ 2>/dev/null | grep tmp || echo "no tmp files"

# If corrupted, clean install
rm -rf node_modules apps/*/node_modules packages/*/node_modules
pnpm install

# Verify mobile deps are aligned with Expo SDK
pnpm --filter mobile exec expo doctor
```

If VS Code shows a wall of `Cannot find module ...` or cascading implicit-`any`
diagnostics after dependency repair, verify the CLI first:

```bash
pnpm typecheck
```

If the CLI passes, treat the editor errors as stale TypeScript server state:
reload VS Code, use the workspace TypeScript SDK, and restart the TypeScript
server before changing application code.

---

## Phase 3 — Decide: Rebuild Native or Just Start Metro?

Answer these questions in order:

| Question | Yes → | No → |
|----------|-------|------|
| Did you add/remove a native module? | Rebuild | Next |
| Did you change `plugins` in `app.config.ts`? | Rebuild | Next |
| Did you change bundle ID, package name, or `newArchEnabled`? | Rebuild | Next |
| Did you change `googleServicesFile` or entitlements? | Rebuild | Next |
| Did you only change TS/JS/CSS? | Just Metro | — |

**Rebuild command:**
```bash
pnpm mobile:android   # Android
pnpm mobile:ios       # iOS
```

**Metro-only command:**
```bash
pnpm mobile:start     # Must show "Using development build"
```

---

## Phase 4 — Start the Emulator (if not running)

```bash
# Boot the verified AVD
emulator -avd Medium_Phone_API_36.0

# Wait for boot, then verify
adb devices -l
# Must show: emulator-5554  device  (not offline)

# If offline: restart ADB
adb kill-server && adb start-server && adb devices -l

# Set up port reverse so emulator can reach host API/Metro
adb reverse tcp:3001 tcp:3001
adb reverse tcp:8081 tcp:8081
```

---

## Phase 5 — Start Metro

```bash
pnpm mobile:start
```

Watch for:
- ✅ `Using development build` — correct
- ❌ `Using Expo Go` — wrong runtime, stop and restart with `--dev-client`

Open the dev client:
- Press `a` in the Metro terminal for Android
- Or launch via ADB intent if Expo CLI doesn't open it:
```bash
adb shell am start -W -a android.intent.action.VIEW \
  -d "launch://expo-development-client/?url=http%3A%2F%2F10.0.2.2%3A8081"
```

---

## Phase 6 — Start Backend (API-dependent work only)

Only needed for auth, payments, uploads, AI, or push feature work:

```bash
pnpm docker:up     # Postgres + Redis
pnpm db:migrate    # Run pending Drizzle migrations
pnpm api:dev       # Koa API on :3001

# Health check
curl http://localhost:3001/health
```

---

## Diagnostic Checklist

When the app won't load or shows a redbox, run this checklist:

```bash
# 1. Is Metro running?
lsof -nP -iTCP:8081 -sTCP:LISTEN 2>/dev/null || ss -ltn 2>/dev/null | grep ':8081'

# 2. Is the emulator connected?
adb devices -l

# 3. Can the emulator reach the host?
adb shell curl http://10.0.2.2:8081/status 2>/dev/null || echo "unreachable"

# 4. Is the dev client build current?
adb shell pm list packages | grep launchhq

# 5. Is the correct runtime in use?
# Check Metro terminal output for "Using development build"

# 6. Are env vars set?
cat apps/mobile/.env | grep EXPO_PUBLIC_API_URL
```

---

## Quick Reference: Port Map

| Port | Service | Who uses it |
|------|---------|-------------|
| 8081 | Metro bundler | Dev client on emulator |
| 3001 | Koa API | App and Metro |
| 5434 | Postgres (Docker) | API |
| 6379 | Redis (Docker) | API |

Android emulator maps host `localhost` to `10.0.2.2`. Always use `10.0.2.2` (not `localhost`) in `EXPO_PUBLIC_API_URL` for emulator testing.

---

## Session Handoff Note

When ending a mobile dev session, capture state in a note so the next session starts clean:
- Current branch and any uncommitted changes
- Whether native rebuild was done
- Whether emulator has a current dev client build
- Last known working state of Metro + API
