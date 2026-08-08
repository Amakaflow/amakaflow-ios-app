# AMA-2387 — Task 10 validation checklist

**Branch:** `feature/ama-2387-completed-sync-actuals`  
**Spec:** `design-handoff/ACTUALS.md` · rig: `design-handoff/screenshots/rig-actuals-panels.jpg`  
**Date:** 2026-08-07

## Flow coverage (teach → verified)

| Step | Status | Evidence |
|------|--------|----------|
| 1 Teach card (Today empty + never connected) | **Code done** | `ActualsTeachCard` wired in `TodayDiaryView`; visibility gated by `ActualsTeachCardVisibility` |
| 2 Connect sources | **Code done** | `ActualsConnectSourcesView` from teach CTA; locked copy + Strava brand CTA |
| 3 Apple Health primer → HK read request | **Code done (live HK prompt)** | `ActualsAppleHealthPrimerView` + `LiveActualsHealthKitConnector` (read-only types). Deny → Settings deep-link |
| 4 Strava / Garmin OAuth scope UI | **Stub auth** | Scope UI shows upload `NOT REQUESTED`. `StubActualsProviderAuth` — no `ASWebAuthenticationSession` / BFF yet |
| 5 Linked ✓ JUST NOW + honest sync counter | **Code done** | Badge + DD Toast + `ActualsSyncProgressStore` (increments only after real backfill begin) |
| 6 Merge ask / merged detail / Split | **Code done** | Classifier + ask card + merged detail; not yet driven by live ingest on Today |
| 7 Map-to-plan | **Code done** | Matcher + screen; entry when unmapped activity lands (ingest TBD) |
| 8 Fill-in actuals (gated + RPE + GRDB) | **Code done** | VM/view + V4 tables; airplane local write covered by unit tests (compile) |
| 9 Verified + editor ghosts | **Code done** | Verified card/view; `ActualsGhostFeed` wired into `DDEditorSeed` |

### Simulator dogfood

**Blocked in this agent environment:** CoreSimulator / `xcodebuild test` hangs after codesign (`simctl install` / boot).  
**TEST BUILD SUCCEEDED** for Tasks 8–9 under `/tmp/ama-2387-t8-dd` and `/tmp/ama-2387-t9-dd`.

**Manual dogfood (device or healthy sim):**

1. Fresh install → Today empty → teach card → Connect a source  
2. Apple: primer → Continue → system Health sheet → Turn On All → Allow → LINKED ✓ JUST NOW  
3. Strava/Garmin: Authorize on stub scope UI (cancel = nothing linked)  
4. Previews: Merge ask → Merge/Keep both; Merged detail → Split / Fill in actuals  
5. Fill-in → confirm rows + RPE → Save → verified payoff  
6. Editor (edit/backfill seed) → ghost weight shows last actual + `· LAST TIME`

Reference panels (not new captures): `../design-handoff/screenshots/rig-actuals-panels.jpg`  
Copy of rig for PR browsing: `./rig-actuals-panels.jpg`

## Remaining behind protocols (live work)

| Item | Protocol / stub | Remaining |
|------|-----------------|-----------|
| Apple Health **ingest** | `ActualsHealthKitConnecting` (auth only) | `HKObserverQuery` + anchored queries; 30-day backfill feed into Today |
| Strava / Garmin **OAuth + token exchange** | `ActualsProviderAuthProviding` → `StubActualsProviderAuth` | Real `ASWebAuthenticationSession` + BFF (client secret never on device) |
| Provider **activity sync** | — | Pull last 30 days; feed merge classifier |
| Sync queue for actuals | Local GRDB write only | Enqueue / hydrate when backend endpoints exist |
| Today cards for merged / unmapped / fill-in debt | Screens + models exist | Wire ingest results into diary timeline |

## Unit / a11y gate (from ACTUALS.md)

| Gate | Status |
|------|--------|
| Merge tiers + sticky Keep-both | Unit tests compiled (`ActualsMergeClassifierTests`) |
| Provenance precedence / Split restore | Covered in merge tests |
| Gated CTA + RPE required | `ActualsFillInTests` |
| Ghost = last actual | `ActualsVerifiedGhostTests` |
| Backfill counter never fakes | `ActualsSyncProgressTests` |
| a11y IDs per handoff | Present on teach/connect/merge/map/fill-in/verified |
| Maestro sheet caveat (iOS 26.1) | Flow uses full screens / navigationDestination — good |

## Out of scope (confirmed untouched)

Provider writes · plan editing · cardio actuals grid · >30-day backfill · auto-RPE from HR
