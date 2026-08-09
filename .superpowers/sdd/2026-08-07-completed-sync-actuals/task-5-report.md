# AMA-2387 — Task 5 report: Linked ✓ + backfill counter + DD Toast

**Status: CODE DONE**

## Built
- `ActualsSyncProgress` + `ActualsSyncProgressStore` — `beginBackfill(total:)` / `recordIngestedSession()`; never invents counts
- `ActualsSyncCounterBanner` — a11y `af_actuals_sync_counter`
- `ActualsLinkFeedback.announceLinked` → DDToastCenter success + `PULLING YOUR LAST 30 DAYS…` sub
- Connect Sources badge: `LINKED ✓ JUST NOW` when freshly linked
- Today shows banner when `progress.shouldShowBanner`
- Toast wired on Apple grant + Strava/Garmin authorize success
- Tests: `ActualsSyncProgressTests`
