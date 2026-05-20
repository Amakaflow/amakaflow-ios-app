# Production Readiness Checklist — AmakaFlow v1

**Single source of truth** for what stands between AmakaFlow today and v1 App Store launch.

**Linear dashboard:** [Production-Ready v1 project](https://linear.app/amakaflow/project/production-ready-v1-2ea0beaf4e0b)
**Daily Telegram digest:** `scripts/production-readiness-digest.sh` (runs via launchd at 05:00 CT)
**How to ship v1:** every checkbox below ticked + a green run of `scripts/release-preflight.sh` on `main`.

---

## Status snapshot

| # | Gap | Linear | State | Risk if unlaunched |
|---|---|---|---|---|
| 1 | AMA-1847/1848 fixes deployed + verified on staging | [AMA-1850](https://linear.app/amakaflow/issue/AMA-1850) | 🟡 Deploy ✅ (mapper-api + mobile-bff live 2026-05-20, health+smoke green); L4 evidence pending [AMA-1868](https://linear.app/amakaflow/issue/AMA-1868) (Maestro selector drift) | Save & End workflow may still no-op silently |
| 2 | Subscription / IAP testing harness (RevenueCat Test Store) | [AMA-1851](https://linear.app/amakaflow/issue/AMA-1851) | 🔲 Not started | Launch-day revenue risk |
| 3 | CI → TestFlight on `main` merge | [AMA-1852](https://linear.app/amakaflow/issue/AMA-1852) | 🔲 Not started | Manual + skippable today |
| 4 | Release-readiness checklist + per-PR "Verify by" footer | [AMA-1853](https://linear.app/amakaflow/issue/AMA-1853) | 🟡 In this PR | No objective "shippable" gate |
| 5 | CJ-01 L3 sign-in real-session bypass | [AMA-1849](https://linear.app/amakaflow/issue/AMA-1849) | 🟡 In PR | L3 only validates UI nav, not end-to-end |
| 6 | Crash-free startup gate | [AMA-1854](https://linear.app/amakaflow/issue/AMA-1854) | 🟡 In PR | Fresh installs may crash undetected |
| 7 | Watch + Garmin path coverage | [AMA-1855](https://linear.app/amakaflow/issue/AMA-1855) | 🟡 L1 + L2 Watch + L2 Garmin done (19/19 assembly tests — 8 Watch + 11 Garmin — pinning the wire shape); L3 (XCUITest Watch sim driving) + L4 (Maestro evidence) pending [AMA-1868](https://linear.app/amakaflow/issue/AMA-1868) | Watch/Garmin users hit untested flows |

Legend: ✅ Done · 🟡 In progress · ⏳ Waiting on external · 🔲 Not started

---

## Per-gap acceptance

### Gap 1 — AMA-1850: Verify AMA-1848 fixes live on staging

- [ ] mapper-api deploy on staging includes AMA-1848 Bug A + Bug C commits (`b6c3b95` + `32d0710`)
- [ ] AMA-1834 L4 Maestro flow run shows the `step10a-history-row-found` evidence screenshot
- [ ] Supabase staging shows the resulting `workout_completions` row with a valid `client_generated_id`
- [ ] AMA-1834 + AMA-1847 + AMA-1848 all closed as Done

### Gap 2 — AMA-1851: Subscription / IAP testing harness

- [ ] RevenueCat SDK integration baseline confirmed
- [ ] Test Store entitlements configured for AmakaFlow's planned products
- [ ] L1 backend test for the subscription webhook handler
- [ ] L2 iOS XCTest for purchase happy-path + restore + refund
- [ ] L3 XCUITest for paywall → entitlement-gated screen
- [ ] L4 Maestro evidence screenshots committed
- [ ] Release-mode IPA inspection confirms no Test Store config leaked

### Gap 3 — AMA-1852: CI → TestFlight auto-deploy on `main` merge

- [ ] `.github/workflows/ios-testflight.yml` merged
- [ ] App Store Connect API key wired as GHA secret (issuer id + key id + .p8)
- [ ] Build number auto-bump via `agvtool` working
- [ ] Smoke-test verified end-to-end on at least 2 `main` merges
- [ ] Sentry debug symbols upload still firing post-archive

### Gap 4 — AMA-1853: Release-readiness checklist + per-PR "Verify by"

- [ ] `docs/architecture/PRODUCTION_READINESS.md` lives on `main` (this file)
- [ ] PR template updated with a `Verify by` section
- [ ] `CONTRIBUTING.md` documents the per-PR pattern
- [ ] Next 3 PRs all include a Verify by section

### Gap 5 — AMA-1849: CJ-01 L3 sign-in real-session bypass

- [x] DEBUG-only Frontend API bypass populates `Clerk.shared.session` with a real session (via public `Clerk.shared.auth.setActive(sessionId:)`)
- [x] `AuthViewModel.token()` returns a valid Clerk JWT after the bypass (uses normal SDK path post-setActive)
- [ ] CJ-01 L3 + AMA-1834 L4 produce a real `workout_completions` row on staging (depends on AMA-1850 deploy first)
- [ ] Release archive PlistBuddy inspection confirms zero bypass code in the shipped binary (verify pre-archive)
- [ ] Blueprint updated to flip CJ-01 sign-in from "fragile" to "hard gate" (after L3 wiring exercises this bypass)

### Gap 6 — AMA-1854: Crash-free startup gate

- [x] Minimum supported iOS version decided (matrix: iOS 26.2 + iOS 18.5)
- [x] Device matrix decided (cost-aware: 2 sims per PR run)
- [x] `.github/workflows/ios-cold-launch-matrix.yml` merged (in this PR)
- [x] Helper script `scripts/cold-launch-check.sh` ships + works locally (verified 2026-05-19 — PID 95878, +15s grace, pass)
- [ ] At least one synthetic-crash PR verified the gate catches it (filed as follow-up)

### Gap 7 — AMA-1855: Watch + Garmin coverage

- [ ] CJ-02 Watch-only workout journey across L1/L2/L3/L4
- [ ] CJ-03 Garmin push journey across L1/L2/L3/L4
- [ ] Both listed in `docs/testing/critical-journeys.md`
- [ ] Real-device smoke on Apple Watch + Garmin before promoting to Done

---

## Out of scope for v1

- AMA-1817 follow-ups (APIService.swift split, full BFF coverage for coach) — quality-of-life, not launch blockers
- Multi-language UI
- Marketing infrastructure

---

## Workflow

1. I tick boxes here as PRs merge. The Linear ticket statuses are the authoritative state; this doc mirrors them for permanent record.
2. Every PR adds a `## Verify by` block (template enforces this — see [PR template](../../.github/PULL_REQUEST_TEMPLATE.md)) so reviewers can confirm a change works on their phone without re-running anything.
3. Daily Telegram digest at 05:00 CT lists yesterday's moves + today's queue + open blockers.
4. When all 7 gaps are ticked, run `scripts/release-preflight.sh` for the final sign-off + cut a tag.
