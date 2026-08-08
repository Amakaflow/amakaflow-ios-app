# SDD ledger — plan: docs/superpowers/plans/2026-08-07-completed-sync-actuals.md

Worktree: `/Users/davidandrews/dev/amakaflow-workspace/.worktrees/ama-2387-ios`
Branch: `feature/ama-2387-completed-sync-actuals`

Task 1: code complete — arm64 .o compiled; XCTest blocked (CoreSimulator hang)
Task 2: code complete — same
Task 3: code complete — primer + HealthKit connector + deny→Settings; arm64 .o compiled
Task 4: code complete — OAuth scope UI + stub auth
Task 5: code complete — linked badge, DD Toast, honest sync counter banner
Task 6: code complete — merge classifier + ask card + merged detail
Task 7: code complete — plan matcher + map-to-plan screen
Task 8: code complete — fill-in actuals + GRDB local-first; arm64 .o under `/tmp/ama-2387-t8-dd`
Task 9–10: pending

**Env note (2026-08-07):** `simctl install` / `xcodebuild test` hang after package resolve / codesign UITests. Restart CoreSimulator + fresh device still hung on boot. Arm64 object files for Tasks 1–3 exist under `/tmp/ama-2387-dd`; Task 8 under `/tmp/ama-2387-t8-dd`.

## Codebase map
- Teach card: `AmakaFlow/Views/Components/ActualsTeachCard.swift`
- Connect: `ActualsConnectSourcesView` → Apple primer / Strava+Garmin OAuth scope
- HealthKit: `ActualsHealthKitConnecting` + `ActualsAppleHealthPrimerView`
- OAuth stub: `ActualsProviderAuthProviding` + `ActualsOAuthScopeView` (no `activity:write`)
- Do not reuse `SourcesView` / ConnectionsHub
