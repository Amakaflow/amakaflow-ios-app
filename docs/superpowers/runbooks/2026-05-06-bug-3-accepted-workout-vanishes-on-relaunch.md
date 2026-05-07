# Bug 3 — Accepted Suggest-Workout still vanishes on app close/reopen (build 30)

> **Filed:** 2026-05-06 (TF builds 28/29/30).
> **Reporter:** David, on-device.
> **Severity:** high — blocks the core MVP "Suggest → Accept → Start" loop end-to-end.
> **Status:** open. Two patch attempts (PR #169 + a local revert in build 30) did not fix it.
> **Assigned:** Joshua.

---

## Symptom

1. Open AmakaFlow → Home tab.
2. Tap **Suggest Workout** → wait for AI generation → tap **Accept** (or whatever the save CTA is).
3. The workout appears on the Home Today card with the "Ready" badge. Looks saved.
4. Force-quit the app from the iPhone app switcher.
5. Re-open AmakaFlow → Home Today card is back to **"REST DAY / No workout scheduled"**. The workout is gone.
6. More → History also empty. There is no record anywhere in the app.

Reproducible 100% across builds 28, 29, and 30.

## What's been tried (didn't fix it)

### Attempt 1 — PR #169 (`fix(AMA-1751): persist accepted Suggest-Workout results locally`)

Added `AcceptedSuggestionsStore` (UserDefaults-backed Codable cache) and made `SuggestWorkoutView.acceptWorkout` call a new `WorkoutsViewModel.acceptSuggestedWorkout(_:)` that writes to the store + appends to `incomingWorkouts`. `loadWorkouts()` was patched to merge the stored entries into the API result.

Tested in TF build 29. Bug still reproduces.

### Attempt 2 — local fix in build 30 (`acceptedStore.removeAll()` revert)

PR #169 had a CR follow-up that wiped the cache when `pairingService.isPaired == false` (so a logged-out user wouldn't inherit the prior account's workouts). I theorized this was firing during the cold-launch window before Clerk's async session restore completed, destroying the cache before the first authenticated `loadWorkouts()` could merge it.

Build 30 removed the `removeAll()` call. **Bug still reproduces.** So either the theory was wrong, or there is a second wipe path I haven't found.

---

## Hypotheses (unverified)

1. **The persistence write isn't actually happening.** `AcceptedSuggestionsStore.save` swallows JSON encode errors silently (`guard let data = try? encoder.encode(...)`). If Workout's nested `Block`/`Exercise` types fail to encode for some reason in the production build, save is a no-op and `all()` returns []. Need to add a real error log + a quick sanity trip via a one-time toast/banner during dev.
2. **There's a second create path that doesn't go through `acceptSuggestedWorkout(_:)`.** SuggestWorkoutView's "Accept" was patched, but there may be another path (Quick Start, manual entry, Coach chat tool card?) that mutates `incomingWorkouts` directly without writing to the store.
3. **The decode side fails silently.** `AcceptedSuggestionsStore.all()` does `(try? decoder.decode([Workout].self, from: data)) ?? []`. If the Workout decoder is stricter than the encoder (e.g. requires `intervals` legacy field that we don't write), every read returns []. Symmetry needs verification.
4. **The `loadWorkouts()` merge is being run but the merged-in entries are subsequently overwritten** by another publisher elsewhere (e.g. a stale cached copy in HomeView or a re-init of WorkoutsViewModel that reads only the API result).
5. **TF's UserDefaults sandbox isn't behaving as expected.** Unlikely but plausible.

## Investigation plan

1. Add `print` / DebugLogService logging at every step of `AcceptedSuggestionsStore.save`, `all()`, `write()` and at the merge in `loadWorkouts`. Ship a build and tail the logs via Settings → Debug Log.
2. Grep all assignments to `incomingWorkouts` to find paths that bypass the store. Patch any that exist.
3. Round-trip test: from inside `acceptSuggestedWorkout`, immediately call `acceptedStore.all()` and assert the just-saved id is present. If it's not, the encode is silently failing.
4. If logs confirm the workout IS persisted but NOT merged on next launch, investigate the order of `loadWorkouts` vs the HomeView's fetch and whether something re-initializes the VM after merge.

## Where to start (next agent)

- Files: `AmakaFlow/Services/AcceptedSuggestionsStore.swift`, `AmakaFlow/ViewModels/WorkoutsViewModel.swift`, `AmakaFlow/Views/SuggestWorkoutView.swift`, `AmakaFlow/Views/HomeView.swift`.
- Recent merges: PR #169 (78523f5), then build 30 local edit (not yet pushed) that removed the `removeAll()` line in `WorkoutsViewModel.loadWorkouts`.
- TF build under test: 30. Reverting the build to 27 shows the original symptom (no persistence at all), so the "fix" did SOMETHING but not enough.

## Acceptance criteria

- Suggest → Accept → see workout on Home with "Ready" badge.
- Force-quit + reopen the app. Workout is still on Home with "Ready" badge.
- Tap **Start workout** → enters the player path successfully.
- Complete the workout (phone or watch path) → workout disappears from Home Today and shows up in More → History.
