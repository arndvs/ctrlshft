Load the mobile-dev skill from ~/dotfiles/skills/mobile-dev/SKILL.md.

Execute a full fresh-session reset + restart workflow for the Launch monorepo on Windows:

1) Run Phase 1 clean-state reset from the skill (force-stop app, remove ADB reverse, verify listeners/devices).
2) Ensure Android emulator is connected and healthy.
3) Re-establish ADB reverse for 3001 and 8081.
4) Start the required stack for auth testing:
   - Metro in dev-client mode
   - API server
   - ngrok tunnel if auth base URL requires it
5) Verify health with concrete checks (API health endpoint, Metro reachable, auth endpoint reachable).
6) Print a concise readiness summary with:
   - Active processes/ports
   - Tunnel URL in use
   - Exact next test step to run in app

If an existing stale process blocks startup, terminate it and continue without asking unless data-loss risk exists.

$ARGUMENTS