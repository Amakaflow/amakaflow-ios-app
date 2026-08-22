# Watch item sheet — edit watch-readiness & replace (AMA-2386)

> Date: 2026-08-07
> Ticket: [AMA-2386](https://linear.app/amakaflow/issue/AMA-2386)
> Spec of record: amakaflow-docs PR #65 · Handoff: `design-handoff/WATCHITEM.md`
> Status: **Approved** — Approach 1 (thin sheet + shared AMA-2378 rows)

## Problem

On-your-watches rows are inert. Tapping must open a **watch item sheet** (never the workout editor) to reshape watch-readiness and replace the delivered copy.

## Architecture (Approach 1)

- New `WatchItemSheet` + `WatchItemViewModel` + `WatchItemReplaceCoordinator`.
- Reuse AMA-2378 configurators (`EnrichmentSequenceScreen`, warm-up pick/ramp, rest UI) and the enrichment prefs / push store — one store shared with pre-send.
- Extract shared readiness row chrome only if needed; do not fork enhance sheet into a mode flag.
- Wire Apple scheduled rows + Garmin non-failed queue rows → `.sheet` with `.presentationDetents([.medium, .large])`.

## Behavior

| Concern | Rule |
| --- | --- |
| Snapshot pills | Describe **delivered** composition; do not change while editing |
| See steps › | AMA-2371 preview **read-only** (v1: delivered only) |
| Change count | N = distinct readiness rows differing from delivered baseline; revert decrements |
| CTA | Dim `No changes yet` → lime `Replace on watch · N change(s)` → busy `Updating on watch…` |
| Apple replace | Recompose → remove this plan → schedule new plan **same slot/date**; never silent empty slot |
| Garmin replace | Regenerate FIT → `recordPush` same workout id; waiting stays waiting |
| Demo | `AF_DEMO_WATCH_MANAGER` / `AF_DEMO_WATCH_MANAGER` → delayed mock Replace |
| Live | Demo off → real WorkoutKit / Garmin push paths |
| Toast | `beginPending("Updating on watch…")` → `Replaced ✓` / `Queue updated ✓` / real error |
| Counter reset | Only on confirmed success |
| Failed Garmin | Keep Fix routing — no sheet |
| Maestro | **Out of scope this PR** (iOS 26.1 sheet a11y gap) |

## Files

| Artifact | Path |
| --- | --- |
| Sheet | `AmakaFlow/Views/Components/WatchItemSheet.swift` |
| VM | `AmakaFlow/ViewModels/WatchItemViewModel.swift` |
| Copy | `AmakaFlow/Models/WatchItemCopy.swift` |
| Replace | `AmakaFlow/Services/WatchItemReplaceCoordinator.swift` |
| Wire | `AppleWatchScheduledListView.swift`, `GarminWatchQueueView.swift` |
| Tests | `WatchItemCopyTests`, `WatchItemChangeCounterTests`, `WatchItemReplaceCoordinatorTests` |

## Validation gates

1. Unit tests (change counter, copy-lock, Apple no-slot-loss, Garmin id-stable, toast pending rules).
2. Simulator dogfood (demo): idle / Garmin waiting / edited CTA / replacing toast.
3. Human merge gate: David re-tests Simulator before merge.
4. Maestro: follow-up after sheet-exposure infra.

## Open questions (v1 decisions)

- See steps pending composition → **delivered only** (revisit after dogfood).
- Mid-workout Apple replace → verify on device later; not a Simulator blocker.
