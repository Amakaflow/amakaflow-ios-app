# Completed-workout sync & fill-in actuals (AMA-2387) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect Apple Health / Garmin / Strava (read-only), land finished sessions on Today, merge duplicates, map unplanned sessions, fill-in actuals vs plan, and feed editor ghosts.

**Architecture:** Local-first Actuals domain (`CompletedSession` / `SourceRecording` / `ExerciseActual`) with GRDB persistence. Provider ingest + OAuth BFF behind protocols (stubbed so iOS ships before backend). Today teach card + Connect Sources screen + merge/map/actuals flows. `verified` only after user confirmation.

**Tech Stack:** SwiftUI, HealthKit, ASWebAuthenticationSession, GRDB, DDToastCenter, XCTest. Backend endpoints stubbed.

## Global Constraints

- Branch: `feature/ama-2387-completed-sync-actuals` in worktree `.worktrees/ama-2387-ios` (from `origin/main`)
- Spec: `design-handoff/ACTUALS.md` + docs PR #66; ground truth `design-handoff/screenshots/rig-actuals-panels.jpg`
- Hard rules: `verified` only by user confirm; never post to providers; merged cards always disclose `MERGED · N SOURCES`; cardio = metrics+RPE only; never edit plan from this flow
- a11y IDs: `af_actuals_teach_card` · `af_actuals_connect_<provider>` · `af_actuals_source_row_<provider>` · `af_actuals_sync_counter` · `af_actuals_merge_ask` (+ `_merge` / `_keep`) · `af_actuals_merged_split` · `af_actuals_map_candidate_<n>` · `af_actuals_map_keep_as_is` · `af_actuals_row_<exercise>` (+ `_asplanned` / `_adjust`) · `af_actuals_all_asplanned` · `af_actuals_rpe_<n>` · `af_actuals_save`
- Prefer full screens over medium-detent sheets (iOS 26.1 Maestro a11y gap)
- Copy locked to JSX / Linear — never invent synced/verified claims
- Add new `AmakaFlow/` sources to `project.pbxproj` (AMA-2386 pattern); tests under `AmakaFlowCompanionTests/`
- Prefer folders: `AmakaFlow/Views/Actuals/`, `AmakaFlow/Services/Actuals/`, GRDB `Migrations/V4_*` (AMA-2376 store→repo pattern). Reuse `DDToastCenter`, `RPEFeedbackView`/`AFRPEGrid`. Do not reuse `SourcesView` or ConnectionsHub for Connect Sources.

---

### Task 1: Actuals source-connection store + Today teach card

**Files:**
- Create: `AmakaFlow/Models/ActualsCopy.swift` — locked strings
- Create: `AmakaFlow/Services/ActualsSourceConnectionStore.swift` — protocol + UserDefaults store (`appleHealth` / `garmin` / `strava` connected flags; `hasEverConnected` permanent)
- Create: `AmakaFlow/Views/Components/ActualsTeachCard.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/ActualsSourceConnectionStoreTests.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/ActualsTeachCardVisibilityTests.swift`
- Modify: `AmakaFlow/Views/TodayDiaryView.swift` — show teach card when `!hasAnySourceConnected && todaysCompletions.isEmpty`; else existing empty/timeline
- Modify: `project.pbxproj`

**Interfaces:**
- `ActualsSourceProvider` enum: `appleHealth`, `garmin`, `strava`
- `ActualsSourceConnecting`: `isConnected(_:)`, `hasAnySourceConnected`, `markConnected(_:)`, `markDisconnected(_:)`
- `ActualsTeachCardVisibility.shouldShow(hasAnySourceConnected:todayEmpty:)` → Bool
- Teach card a11y: `af_actuals_teach_card`; CTA navigates to Connect Sources (Task 2 destination; stub NavigationLink OK)

- [ ] **Step 1: Write failing visibility + store tests**
- [ ] **Step 2: Implement store, copy, teach card; wire Today**
- [ ] **Step 3: pbxproj; run tests; commit**

---

### Task 2: Connect Sources screen

**Files:**
- Create: `AmakaFlow/Views/ActualsConnectSourcesView.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/ActualsConnectSourcesCopyTests.swift`
- Modify: teach card CTA + Settings entry point → this screen
- Modify: pbxproj

**Interfaces:**
- Per-source rows with exact JSX one-liners; Strava Connect CTA `#FC4C02`; dashed/dedupe footer copy
- a11y: `af_actuals_source_row_<provider>`, `af_actuals_connect_<provider>`
- Footer: SAME WORKOUT FROM TWO SOURCES? … NOTHING COUNTS TWICE.
- Subhead includes "We only read; we never post."

- [ ] **Step 1: Failing copy/ID tests**
- [ ] **Step 2: Implement screen + navigation**
- [ ] **Step 3: Run tests; commit**

---

### Task 3: Apple Health connect (primer + read-only auth stub)

**Files:**
- Create: `AmakaFlow/Views/ActualsAppleHealthPrimerView.swift`
- Create: `AmakaFlow/Services/ActualsHealthKitConnecting.swift` — protocol; live wraps `HKHealthStore.requestAuthorization` for workout/HR/activeEnergy read-only; mock for tests
- Create: tests for deny → Settings deep-link path + markConnected on grant
- Modify: Connect Sources Apple row → primer → request
- Modify: pbxproj

**Interfaces:**
- Primer WHY tags exact to JSX; amber Turn-On-All coaching
- Deny: leave disconnected; retry opens Settings→Health when alreadyDetermined denied

- [ ] **Step 1: Failing primer/auth-state tests**
- [ ] **Step 2: Implement primer + protocol + wire**
- [ ] **Step 3: Run tests; commit**

---

### Task 4: Strava / Garmin OAuth UI + BFF protocol stub

**Files:**
- Create: `AmakaFlow/Views/ActualsOAuthScopeView.swift` — scope display with upload struck-through NOT REQUESTED
- Create: `AmakaFlow/Services/ActualsProviderAuthProviding.swift` — protocol; stub returns cancel/success without real OAuth until BFF
- Create: tests for cancel = nothing linked; success → markConnected
- Modify: Connect Sources Strava/Garmin CTAs
- Modify: pbxproj

**Interfaces:**
- Never request `activity:write`
- a11y connect buttons already defined

- [ ] **Step 1: Failing scope-copy + cancel tests**
- [ ] **Step 2: Implement UI + stub auth**
- [ ] **Step 3: Run tests; commit**

---

### Task 5: Linked ✓ + backfill counter + DD Toast

**Files:**
- Create: `AmakaFlow/Models/ActualsSyncProgress.swift`
- Create: `AmakaFlow/Views/Components/ActualsSyncCounterBanner.swift`
- Wire ToastHost / DDToastCenter: "Strava linked — pulling your last 30 days…"
- Tests: counter only increments on real ingest events (never fake)
- Modify: Today when syncing
- Modify: pbxproj

**Interfaces:**
- `ActualsSyncProgress(ingested:total:)` → display string
- a11y: `af_actuals_sync_counter`

- [ ] **Step 1: Failing progress string tests**
- [ ] **Step 2: Banner + toast wire**
- [ ] **Step 3: Run tests; commit**

---

### Task 6: Merge engine (local model)

**Files:**
- Create: `AmakaFlow/Models/ActualsSessionModels.swift` — CompletedSession, SourceRecording, roles
- Create: `AmakaFlow/Services/ActualsMergeClassifier.swift`
- Create: `AmakaFlow/Views/Components/ActualsMergeAskCard.swift`
- Create: `AmakaFlow/Views/ActualsMergedDetailView.swift`
- Create: unit tests (certain/uncertain/sticky Keep-both/Split restore/provenance)
- Modify: pbxproj

**Interfaces:**
- Certain: ±2 min + shape OR external refs → silent merge, badge `MERGED · N SOURCES`
- Uncertain: ask card; Keep-both sticky
- Precedence: watch > phone; richest = primary; duplicates hidden (never deleted)
- a11y: `af_actuals_merge_ask`, `_merge`, `_keep`, `af_actuals_merged_split`

- [ ] **Step 1: Failing classifier + split tests**
- [ ] **Step 2: Implement engine + UI**
- [ ] **Step 3: Run tests; commit**

---

### Task 7: Map-to-plan

**Files:**
- Create: `AmakaFlow/Services/ActualsPlanMatcher.swift`
- Create: `AmakaFlow/Views/ActualsMapToPlanView.swift`
- Create: tests for WHY lines + keep-as-is
- Modify: pbxproj

**Interfaces:**
- Score: scheduled-time, duration, distance, type, HR shape
- a11y: `af_actuals_map_candidate_<n>`, `af_actuals_map_keep_as_is`

- [ ] **Step 1: Failing matcher tests**
- [ ] **Step 2: Implement + wire from "What was this?"**
- [ ] **Step 3: Run tests; commit**

---

### Task 8: Fill-in actuals (gated save) + GRDB local-first

**Files:**
- Create: `AmakaFlow/Models/ExerciseActual.swift`
- Create: `AmakaFlow/ViewModels/ActualsFillInViewModel.swift`
- Create: `AmakaFlow/Views/ActualsFillInView.swift`
- Create: `AmakaFlow/Storage/Repositories/ActualsRepository.swift` + migration
- Create: tests for as-planned / adjust / gated CTA / RPE required / airplane local write
- Modify: pbxproj

**Interfaces:**
- Gated CTA: `Confirm N more to save` → `Save session · RPE n`
- a11y: `af_actuals_row_<exercise>`, `_asplanned`, `_adjust`, `af_actuals_all_asplanned`, `af_actuals_rpe_<n>`, `af_actuals_save`
- `verified` set only on successful save with all rows + RPE

- [ ] **Step 1: Failing VM + repo tests**
- [ ] **Step 2: Implement fill-in + GRDB**
- [ ] **Step 3: Run tests; commit**

---

### Task 9: Verified card + editor ghost feed

**Files:**
- Create: `AmakaFlow/Views/Components/ActualsVerifiedCard.swift`
- Create: `AmakaFlow/Services/ActualsGhostFeed.swift` — last-actual precedence over prescription
- Create: tests for deltas + ghost precedence
- Wire editor ghost read path to ActualsGhostFeed
- Modify: pbxproj

**Interfaces:**
- Deltas: `+N KG VS PLAN` / `AS PLANNED`
- Ghost: last actual when present else prescription

- [ ] **Step 1: Failing ghost + delta tests**
- [ ] **Step 2: Implement + wire**
- [ ] **Step 3: Run tests; commit**

---

### Task 10: Visual dogfood + validation checklist

**Files:**
- Optional: `docs/ama-2387-visual-evidence/` screenshots vs rig
- Linear comment with validation gate status

- [ ] **Step 1: Simulator pass teach → connect → stub OAuth → merge ask → fill-in → verified**
- [ ] **Step 2: Note remaining live HealthKit/OAuth items behind protocols**
- [ ] **Step 3: Open implementation PR (base `main`)**
