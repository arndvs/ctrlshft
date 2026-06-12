---
description: "Expo mobile app conventions — Dev Client vs Expo Go, Metro startup, native rebuild triggers, QEMU/Android emulator, env vars, and backend prerequisites. Load when working on any Expo SDK app in a monorepo."
---
Output "Read Expo Mobile instructions." to chat to acknowledge you read this file.

# Expo Mobile — Launch Core Conventions

This instruction file applies whenever working on any app that forks from Launch Core (typically checked out at `~/dev/clients/launch` or a local equivalent). The patterns apply to: **Launch**, **Foreword**, **Scorpion Percussion**, **Aligned**, **Cast**, and any future forks.

---

## CRITICAL: Runtime Model — Dev Client, NOT Expo Go

**This app CANNOT run in Expo Go.** Launch Core uses native modules that Expo Go does not include:

- `@stripe/stripe-react-native` — native payments
- `react-native-purchases` / `react-native-purchases-ui` — RevenueCat IAP
- `expo-superwall` — paywall SDK
- `@sentry/react-native` — native crash reporting
- `expo-notifications` — APNs/FCM push
- `expo-secure-store` — secure credential storage
- `@better-auth/expo` — auth session native bridge
- `expo-apple-authentication` — Apple Sign In
- `jail-monkey` — jailbreak/root detection
- Multiple `@react-native-vector-icons/*` sets
- `react-native-reanimated` worklets
- `react-native-keyboard-controller`

**If Metro terminal says `Using Expo Go`, stop immediately. Press `s` or restart with `--dev-client`.**

The correct runtime pair is:
```
Expo Dev Client (native shell installed on emulator/device)
  + Metro bundler (JS server running locally)
```

---

## Stack Reference (SDK 56)

| Layer | Version |
|-------|---------|
| Expo SDK | ~56.x |
| React Native | 0.85.3 |
| Expo Router | ~56.2.x |
| React | 19.2.3 |
| New Architecture | enabled (`newArchEnabled: true`) |
| Android package | `com.launchhq.mobile` |
| iOS bundle ID | `com.launchhq.mobile` |

---

## The Three Systems — Never Conflate Them

| System | Purpose | When needed |
|--------|---------|-------------|
| **Metro** | JS bundler server (port 8081) | Every JS/TS change |
| **Expo Dev Client** | Native APK/IPA shell on device | After native dep, plugin, or `app.config.ts` changes |
| **Docker/API** | Backend services | Auth, payments, API feature tests |

**Most day-to-day work only needs Metro.** Only rebuild native when native changes.

---

## pnpm Script Reference

All commands run from the **monorepo root** via workspace scripts:

```bash
# Start Metro in dev-client mode (most common)
pnpm mobile:start
# Equivalent to: cd apps/mobile && pnpm exec expo start --dev-client -c

# Build and install Android dev client on emulator/device
pnpm mobile:android
# Equivalent to: cd apps/mobile && pnpm exec expo run:android --device

# Build and install iOS dev client
pnpm mobile:ios
# Equivalent to: cd apps/mobile && pnpm exec expo run:ios --device

# Regenerate native Android/iOS project files from app.config.ts
pnpm mobile:prebuild
# Equivalent to: cd apps/mobile && pnpm exec expo prebuild --clean

# Start backend services
pnpm docker:up        # Postgres + Redis on Docker
pnpm db:migrate       # Run Drizzle migrations
pnpm api:dev          # Start Koa API on :3001

# Dependency health check
pnpm --filter mobile exec expo doctor
pnpm --filter mobile exec expo install --check
```

> If a root-level script is not present, run from `apps/mobile/` directly with `pnpm exec expo ...`.

---

## When a Native Rebuild Is Required

A native rebuild (`pnpm mobile:android` or `pnpm mobile:ios`) is required after:

- Adding or removing a dependency that includes a **native module** (anything with an `android/` or `ios/` folder, or an Expo plugin)
- Changing `plugins` array in `app.config.ts`
- Changing `android.package`, `ios.bundleIdentifier`, `newArchEnabled`, or permissions
- Changing `app.config.ts` values that feed into native build (`googleServicesFile`, entitlements, `apsEnvironment`)
- Running `pnpm mobile:prebuild` (regenerates native project files)

A native rebuild is **NOT** required for:
- Changing any TypeScript/JavaScript source file
- Adding or changing styles, components, screens
- Changing environment variables in `.env` (reload Metro with `-c`)
- Installing pure JS packages

---

## Android Emulator Setup (Windows / QEMU)

### Required Tools
- Android Studio (includes SDK, AVD Manager, emulator)
- `adb` (Android Debug Bridge) — `platform-tools`
- Windows Hypervisor Platform (WHPX) for acceleration, or HAXM

### Environment Variables (set once, user-level)
```powershell
$sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
[Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdk, "User")
[Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $sdk, "User")
```

Add to user `Path`:
```
%LOCALAPPDATA%\Android\Sdk\platform-tools
%LOCALAPPDATA%\Android\Sdk\emulator
```

### Verified AVD (Launch Core)
```
Medium_Phone_API_36.0
```

### Boot the emulator
```powershell
emulator -avd Medium_Phone_API_36.0
```

### Verify ADB sees the device
```powershell
adb devices -l
# Must show: emulator-5554  device
# "offline" = still booting, wait and retry
```

If stuck offline:
```powershell
adb kill-server
adb start-server
adb devices -l
```

### ADB Reverse (Android emulator → host API)
```bash
adb reverse tcp:3001 tcp:3001   # API
adb reverse tcp:8081 tcp:8081   # Metro (if not using IP)
```

**Android emulator localhost alias:** `10.0.2.2` = your dev machine. If `adb reverse` is not set up, use `http://10.0.2.2:3001` for `EXPO_PUBLIC_API_URL` in `apps/mobile/.env`.

### Open dev client after Metro is running
```powershell
# Expo auto-opens on `a` keypress in Metro terminal, or manually:
adb shell am start -W -a android.intent.action.VIEW -d "launch://expo-development-client/?url=http%3A%2F%2F192.168.x.x%3A8081"
```

---

## Environment Variables

### `apps/mobile/.env`
```bash
EXPO_PUBLIC_API_URL=http://10.0.2.2:3001       # Android emulator → host
# OR for physical device on same Wi-Fi:
# EXPO_PUBLIC_API_URL=http://192.168.x.x:3001

EXPO_PUBLIC_APP_SCHEME=launch                   # Deep link scheme (REQUIRED — throws if missing)
EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID=...
EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID=...
EXPO_PUBLIC_IOS_URL_SCHEME=...
EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_...
EXPO_PUBLIC_SENTRY_DSN=https://...@sentry.io/...
```

### `app.config.ts` throws if `EXPO_PUBLIC_APP_SCHEME` is missing
This is enforced at config load time — Metro will not start without it.

---

## Correct Startup Sequence (from clean state)

```bash
# 1. Verify dependencies are clean
pnpm install

# 2. Boot the Android emulator (if using emulator)
emulator -avd Medium_Phone_API_36.0

# 3. Wait for ADB to report device state
adb devices -l   # must show "device" not "offline"

# 4. Start Metro
pnpm mobile:start
# Terminal must say: "Using development build"

# 5. Open the dev client
# Press 'a' in Metro terminal, OR manually launch via adb intent

# 6. Start backend (only needed for API-dependent features)
pnpm docker:up && pnpm db:migrate && pnpm api:dev
```

---

## Common Failure Modes and Fixes

### Metro says "Using Expo Go"
```bash
# Stop Metro, restart with --dev-client explicitly
cd apps/mobile && pnpm exec expo start --dev-client -c
```

### Redbox: "Unable to load index.android.bundle"
- Metro is not running or not reachable from the device
- The installed APK is not a proper dev client build (run `pnpm mobile:android` to rebuild)
- `adb reverse` not set — emulator cannot reach Metro on host

### pnpm install fails with `ERR_PNPM_ENOENT` + `@better-auth/expo_tmp_*`
Node modules is corrupted. Clean install:
```bash
rm -rf node_modules apps/*/node_modules packages/*/node_modules
pnpm install
```

### Metro cache stale after config change
```bash
cd apps/mobile && pnpm exec expo start --dev-client -c --clear
# or nuclear:
rm -rf node_modules/.cache
```

### VS Code Problems shows hundreds of missing modules after dependency repair
Do **not** change source code just because the Problems panel explodes after a
`node_modules` cleanup/reinstall. First run the CLI source of truth:

```bash
pnpm typecheck
```

If CLI typecheck passes, treat the Problems list as stale VS Code TypeScript
language-server state. Reload the VS Code window, select the workspace
TypeScript version, and restart the TypeScript server. For local-only stability,
an ignored `.vscode/settings.json` can pin:

```json
{
  "typescript.tsdk": "node_modules/typescript/lib",
  "typescript.enablePromptUseWorkspaceTsdk": true
}
```

### Android build fails (Gradle)
```bash
cd apps/mobile/android && ./gradlew clean && cd .. && pnpm mobile:android
```

### iOS Pods out of sync
```bash
cd apps/mobile/ios && rm -rf Pods Podfile.lock && pod install --repo-update
cd .. && pnpm mobile:ios
```

### "Network request failed" in app
1. Check API is running: `curl http://localhost:3001/health`
2. Check `EXPO_PUBLIC_API_URL` in `apps/mobile/.env` — use `10.0.2.2` not `localhost` for Android emulator
3. Verify `adb reverse tcp:3001 tcp:3001` if using localhost URL

### Google Sign-In "state mismatch"
Both API and mobile must use the same origin:
```bash
# apps/api/.env
BETTER_AUTH_URL=https://your-ngrok.ngrok-free.app
# apps/mobile/.env
EXPO_PUBLIC_API_URL=https://your-ngrok.ngrok-free.app
```

### Auth callbacks fail with ngrok
Both `BETTER_AUTH_URL` (API) and `EXPO_PUBLIC_API_URL` (mobile) must point to the same ngrok HTTPS URL. Restart both servers after updating.

---

## Key Files

| File | Purpose |
|------|---------|
| `apps/mobile/app.config.ts` | Expo config — plugins, bundle IDs, env validation |
| `apps/mobile/package.json` | Mobile deps and scripts |
| `apps/mobile/.env` | Mobile env vars (gitignored, copy from `.example.env`) |
| `apps/mobile/eas.json` | EAS Build profiles (development / staging / production) |
| `docs/features/local-device-setup.md` | **Canonical** local device setup guide |
| `docs/features/mobile-quality.md` | Mobile quality standards |
| `docs/repo-docs/10_mobile-app/environment-setup.md` | Archived env reference |
| `working/research/mobile-startup-stability.md` | Startup audit notes |

**Canonical docs are in `docs/features/`.** `docs/repo-docs/` is archived upstream reference — treat as secondary.

---

## Native Modules Requiring Dev Client (Quick Reference)

These are present in `apps/mobile/package.json` and are the reason Expo Go cannot be used:

```
@stripe/stripe-react-native
react-native-purchases
react-native-purchases-ui
expo-superwall
@sentry/react-native
expo-notifications
expo-secure-store
expo-apple-authentication
@better-auth/expo
jail-monkey
react-native-reanimated
react-native-keyboard-controller
@react-native-vector-icons/*
react-native-gesture-handler
@gorhom/bottom-sheet
```

---

## EAS Build Profiles

| Profile | Purpose | Installs to |
|---------|---------|-------------|
| `development` | Dev client for local Metro | Simulator / device |
| `staging` | TestFlight / internal testing | TestFlight / internal |
| `production` | App Store / Play Store release | Store |

Local development uses the **emulator/device** with `pnpm mobile:android` — not EAS cloud builds.

---

## Fork Checklist (when forking Launch Core into a new app)

Before starting a fork:
- [ ] Update `app.config.ts` — `name`, `slug`, `ios.bundleIdentifier`, `android.package`
- [ ] Update `apps/mobile/.env` — `EXPO_PUBLIC_APP_SCHEME` (must match new scheme)
- [ ] Run `pnpm mobile:prebuild` to regenerate native project with new IDs
- [ ] Run `pnpm mobile:android` or `pnpm mobile:ios` to install the new dev client
- [ ] Update `eas.json` project ID if using EAS cloud builds
- [ ] Replace icon/splash assets in `apps/mobile/assets/images/`
- [ ] Remove capabilities not needed by the fork (see capability table in `wiki/concepts/launch-boilerplate.md`)
