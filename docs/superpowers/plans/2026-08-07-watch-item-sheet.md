# Watch Item Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tap an On-your-watches Apple/Garmin row to open `WatchItemSheet`, reshape AMA-2378 readiness, and replace the watch copy (demo mock or live).

**Architecture:** Thin sheet + VM + replace coordinator. Reuse AMA-2378 configurators and enrichment store. Hybrid Replace: demo flag → delayed mock; live → Apple same-slot / Garmin id-stable.

**Tech Stack:** SwiftUI, WorkoutKit schedule seams, Garmin queue store, DDToastCenter, XCTest.

## Global Constraints

- Branch: `feature/ama-2386-watch-item-sheet` from `origin/main` in worktree `.worktrees/ama-2386-watch-item-sheet`
- Do not touch AMA-2385 checkout or `ios-ama-2386-handoff`
- a11y IDs: `af_watchitem_*`
- Maestro: out of scope this PR
- Copy locked to JSX / Linear strings
- Counter resets only on confirmed Replace success
- Failed Garmin rows never open this sheet

---

### Task 1: WatchItemCopy + change-counter + unit tests

**Files:**
- Create: `AmakaFlow/Models/WatchItemCopy.swift`
- Create: `AmakaFlow/Models/WatchItemChangeTracker.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/WatchItemCopyTests.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/WatchItemChangeTrackerTests.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj` (add sources)

**Interfaces:**
- Produces: `WatchItemCopy.replaceCTA(changeCount:)`, `WatchItemCopy.replaceNote(isApple:)`, `WatchItemCopy.sectionLabel`, toast strings
- Produces: `WatchItemChangeTracker` with `baseline`/`draft` row flags, `changeCount`, `markSucceeded()`

- [ ] **Step 1: Write failing copy + tracker tests**
- [ ] **Step 2: Implement copy + tracker**
- [ ] **Step 3: Add to pbxproj; run tests; commit**

---

### Task 2: WatchItemSheet shell + row tap wiring (Simulator-visible)

**Files:**
- Create: `AmakaFlow/Views/Components/WatchItemSheet.swift`
- Create: `AmakaFlow/ViewModels/WatchItemViewModel.swift`
- Modify: `AmakaFlow/Views/AppleWatchScheduledListView.swift` — tap non-edit rows → sheet
- Modify: `AmakaFlow/Views/GarminWatchQueueView.swift` — tap non-failed rows → sheet
- Modify: pbxproj

**Interfaces:**
- Consumes: `WatchItemCopy`, `WatchItemChangeTracker`
- Produces: sheet with header, snapshot pills, 4 readiness toggles (local draft), change-gated CTA, footer links
- Demo snapshot pills from title heuristics until delivered-metadata lands in Task 4

- [ ] **Step 1: Sheet + VM with demo toggles driving change count**
- [ ] **Step 2: Wire Apple + Garmin taps**
- [ ] **Step 3: Build for Simulator; verify tap opens sheet; commit**

---

### Task 3: Demo Replace + DD Toast morph

**Files:**
- Create: `AmakaFlow/Services/WatchItemReplaceCoordinator.swift`
- Modify: `AmakaFlow/Services/UITestEnvironment.swift` — optional `UITEST_WATCHITEM_REPLACE_DELAY_MS`
- Modify: `WatchItemSheet` / VM to call coordinator
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/WatchItemReplaceCoordinatorTests.swift`

**Interfaces:**
- `WatchItemReplaceCoordinator.replace(...) async -> Result`
- Demo path: sleep delay → success (Apple `Replaced ✓` / Garmin `Queue updated ✓`)
- Toast: `beginPending` → `resolve`

- [ ] **Step 1: Failing coordinator tests (demo success + failure)**
- [ ] **Step 2: Implement demo replace + wire CTA**
- [ ] **Step 3: Simulator dogfood 4 states; commit**

---

### Task 4: Shared enrichment readiness + live replace seams

**Files:**
- Modify: sheet to open AMA-2378 configurators; persist via enrichment prefs APIs
- Extend: `WatchItemReplaceCoordinator` live Apple same-slot + Garmin id-stable
- Tests: prefs round-trip; Apple no silent empty slot; Garmin id stable

- [ ] **Step 1: Wire configurators + one-store edits**
- [ ] **Step 2: Live Apple/Garmin replace paths**
- [ ] **Step 3: Unit tests + Simulator hybrid check; commit**

---

### Task 5: See steps read-only + Open workout / Remove footers

**Files:**
- Modify: `WatchItemSheet` — See steps → read-only preview; Open workout callback; Remove reuses AMA-2375 + Undo toast

- [ ] **Step 1: Wire footers + See steps**
- [ ] **Step 2: Simulator verify; commit**

---

### Task 6: Human dogfood gate + PR

- [ ] Relaunch Simulator signed-in with demo flags
- [ ] David walks idle / waiting / edited / replacing
- [ ] Open PR targeting `main`; do not merge until David confirms
