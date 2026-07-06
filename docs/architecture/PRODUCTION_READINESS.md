# Production Readiness Checklist — AmakaFlow v1

**Single source of truth** for what stands between AmakaFlow today and v1 App Store launch.

**Linear dashboard:** [Production-Ready v1 project](https://linear.app/amakaflow/project/production-ready-v1-2ea0beaf4e0b)
**Daily Telegram digest:** `scripts/production-readiness-digest.sh` (runs via launchd at 05:00 CT)
**How to ship v1:** every checkbox below ticked + a green run of `scripts/release-preflight.sh` on `main`.

---

## Status snapshot

| # | Gap | Linear | State | Risk if unlaunched |
|---|---|---|---|---|
| 1 | AMA-1847/1848 fixes deployed + verified on staging | [AMA-1850](https://linear.app/amakaflow/issue/AMA-1850) | ✅ Done (2026-05-20). Deploy: mapper-api commit 1eee286 + mobile-bff f86672b. L4 evidence captured 22:27 CT — Activity History shows the saved row end-to-end. Bug chain found + fixed mid-verification: [AMA-1867](https://linear.app/amakaflow/issue/AMA-1867) (workout_name persistence), [AMA-1868](https://linear.app/amakaflow/issue/AMA-1868) (Maestro flow nav resync), [AMA-1870](https://linear.app/amakaflow/issue/AMA-1870)/[AMA-1871](https://linear.app/amakaflow/issue/AMA-1871) (placeholder profile missing `name`), [AMA-1872](https://linear.app/amakaflow/issue/AMA-1872) (cgid wiring + server-side fallback). | n/a — done |
| 2 | Subscription / IAP (RevenueCat + backend billing) | [AMA-1851](https://linear.app/amakaflow/issue/AMA-1851) | 🟡 **Infra merged** (2026-06-05): iOS #291–293, backend #493–494. v1 **still ships FREE** — `AMAKAFLOW_PAYWALL_GATE` off. Activation (ASC products, RC dashboard, staging deploy, L2–L4 harness) deferred until post-launch monetization decision. **Canonical doc:** `amakaflow-backend/docs/architecture/billing-revenuecat-ama-1851.md` | None for v1 while gate off |
| 3 | CI → TestFlight on `main` merge | [AMA-1852](https://linear.app/amakaflow/issue/AMA-1852) | 🟡 **Infra merged** — secrets preflight + setup guide (PR #294). **AMA-2267:** persisted signing `.p12` secrets + import script; **AMA-2276:** smoke job layered timeouts (40 min cap). Pending: wire signing secrets + 2 green consecutive dispatches. See `docs/ci/TESTFLIGHT_SECRETS.md` | Manual TestFlight until green CI upload |
| 4 | Release-readiness checklist + per-PR "Verify by" footer | [AMA-1853](https://linear.app/amakaflow/issue/AMA-1853) | ✅ Done. PRs #215 + #216 shipped this doc + the PR-template "Verify by" section + the daily Telegram digest. | n/a — done |
| 5 | CJ-01 L3 sign-in real-session bypass | [AMA-1849](https://linear.app/amakaflow/issue/AMA-1849) | ✅ Done. PR #219 merged; real workout_completions row test passes via the 2026-05-20 22:27 CT E2E Maestro run (gap #1 evidence is the same run). | n/a — done |
| 6 | Crash-free startup gate | [AMA-1854](https://linear.app/amakaflow/issue/AMA-1854) | ✅ Done. PR #218 merged; iOS 26.2 cold-launch matrix gate is required on app-entrypoint PR changes (verified live on PR #222 which triggered the matrix). | n/a — done |
| 7 | Watch + Garmin path coverage | [AMA-1855](https://linear.app/amakaflow/issue/AMA-1855) | ✅ Done. L1 backend (PR #411, 5 pytest cases) + L2 iOS assembly (19/19 cases: 8 Watch via PR #220 + 11 Garmin via PR #222) pinning the wire shape. L4 evidence captured via the AMA-1850 verification flow (which exercises the Watch + Garmin save paths through `WorkoutCompletionRequest`). L3 (XCUITest Watch sim driving) deferred — L4 evidence covers it for v1. | n/a — done |

Legend: ✅ Done · 🟡 In progress · ⏳ Waiting on external · 🔲 Not started

---

## Per-gap acceptance

### Gap 1 — AMA-1850: Verify AMA-1848 fixes live on staging

- [x] mapper-api deploy on staging includes AMA-1848 Bug A + Bug C commits (final: commit 1eee286 also folds in AMA-1867/1871/1872 fixes uncovered mid-verification)
- [x] AMA-1834 L4 Maestro flow run shows the `cj01-step8-activity-history-shows-workout` evidence screenshot (captured 2026-05-20 22:27 CT)
- [x] Supabase staging shows the resulting `workout_completions` row — Activity History shows "iOS Workout • 0:12 • Phone" for the test user
- [x] AMA-1834 + AMA-1847 + AMA-1848 + AMA-1850 + AMA-1849 all Done

### Gap 2 — AMA-1851: Subscription / IAP (infra merged; activation deferred)

**Launch posture (unchanged):** v1 ships **FREE**. `AMAKAFLOW_PAYWALL_GATE` defaults off — no production paywall until explicit QA + pricing decision.

**Canonical architecture doc:** `amakaflow-backend/docs/architecture/billing-revenuecat-ama-1851.md` (PRs, secrets, cache, next steps).

**Merged code (2026-06-05):**

| Layer | PRs | Notes |
|-------|-----|-------|
| iOS | #291, #292, #293 | Paywall shell, RevenueCat purchase/restore, BFF `fetchSubscription` |
| Backend | #493, #494 | Subscription route, webhook, BFF proxy, in-process RC cache |

**Done — code & L1 tests:**

- [x] RevenueCat account + iOS app + IAP key in dashboard
- [x] RevenueCat SDK `Purchases.configure` + billing client (iOS #292)
- [x] Paywall view + `SubscriptionAccessViewModel` (gate-off safe)
- [x] `GET /billing/subscription` + BFF `GET /v1/billing/subscription`
- [x] `POST /webhooks/revenuecat` + in-process cache (backend #494)
- [x] L1 backend pytest (billing router, webhook, RevenueCat helpers)
- [x] iOS unit tests (`SubscriptionAccessViewModel`, `fetchSubscription` integration)

**Still open — activation (don't block v1 launch):**

- [ ] Deploy `develop` billing commits to staging + set `REVENUECAT_SECRET_API_KEY` / `REVENUECAT_WEBHOOK_AUTHORIZATION`
- [ ] App Store Connect sandbox subscription products (pricing TBD — below $9.99 candidate)
- [ ] RevenueCat product catalog, `pro` entitlement, offerings, webhook URL
- [ ] Staging E2E: sandbox purchase → webhook → subscription API returns `pro`
- [ ] L2 iOS XCTest purchase + restore; L3 XCUITest paywall; L4 Maestro evidence
- [ ] Phase 3.1 persistent cache (Redis / Supabase) for multi-instance mapper-api
- [ ] Release IPA inspection: no Test Store config in production archive

### Gap 3 — AMA-1852: CI → TestFlight auto-deploy on `main` merge

- [x] `.github/workflows/ios-testflight.yml` merged
- [x] App Store Connect API key wired as GHA secret (issuer id + key id + .p8)
- [x] Clerk publishable keys wired (`CLERK_PUBLISHABLE_KEY_STAGING` + `CLERK_PUBLISHABLE_KEY_DEV`)
- [x] Secrets preflight job + setup guide (`docs/ci/TESTFLIGHT_SECRETS.md`)
- [x] Build number auto-bump via `100 + github.run_number` in workflow (no `agvtool` / pbxproj commits)
- [ ] Archive + altool upload green on 2 consecutive `main` merges — **blocked 2026-06-05:** Apple Developer certificate limit (`Choose a certificate to revoke`); see TESTFLIGHT_SECRETS.md troubleshooting
- [ ] Sentry debug symbols upload confirmed on a promoted build (`SENTRY_AUTH_TOKEN` secret present; verify in Sentry UI post-green upload)

### Gap 4 — AMA-1853: Release-readiness checklist + per-PR "Verify by"

- [x] `docs/architecture/PRODUCTION_READINESS.md` lives on `main` (this file)
- [x] PR template updated with a `Verify by` section
- [x] `CONTRIBUTING.md` documents the per-PR pattern (or equivalent — pattern shipped in PR template)
- [x] Subsequent PRs include a Verify by section (verified: PRs #218, #219, #220, #221, #222, #224 all do)

### Gap 5 — AMA-1849: CJ-01 L3 sign-in real-session bypass

- [x] DEBUG-only Frontend API bypass populates `Clerk.shared.session` with a real session (via public `Clerk.shared.auth.setActive(sessionId:)`)
- [x] `AuthViewModel.token()` returns a valid Clerk JWT after the bypass (uses normal SDK path post-setActive)
- [x] CJ-01 L3 + AMA-1834 L4 produce a real `workout_completions` row on staging — verified 2026-05-20 22:27 CT via the AMA-1850 E2E Maestro run
- [ ] Release archive PlistBuddy inspection confirms zero bypass code in the shipped binary (verify pre-archive — deferred to TestFlight pipeline [AMA-1852](https://linear.app/amakaflow/issue/AMA-1852))
- [ ] Blueprint update to flip CJ-01 sign-in from "fragile" to "hard gate" — [AMA-1874](https://linear.app/amakaflow/issue/AMA-1874)

### Gap 6 — AMA-1854: Crash-free startup gate

- [x] Minimum supported iOS version decided (matrix: iOS 26.2 + iOS 18.5 considered → trimmed to iOS 26.2 per AMA-1866)
- [x] Device matrix decided (cost-aware: 1 sim per PR run on iOS 26.2 / iPhone 16 Pro Max)
- [x] `.github/workflows/ios-cold-launch-matrix.yml` merged (PR #218)
- [x] Helper script `scripts/cold-launch-check.sh` ships + works locally (verified 2026-05-19 — PID 95878, +15s grace, pass)
- [x] Gate fires on PRs that touch app-entrypoint code — verified live on PR #222 which triggered the matrix (passed in 4m34s); synthetic-crash regression test deferred as separate follow-up — [AMA-1873](https://linear.app/amakaflow/issue/AMA-1873)

### Gap 7 — AMA-1855: Watch + Garmin coverage

- [x] CJ-02 Watch: L1 backend (PR #411, 5 cases) + L2 iOS (PR #220, 8 assembly cases pinning the Watch wire shape)
- [x] CJ-03 Garmin: L1 backend (PR #411 includes Garmin path) + L2 iOS (PR #222, 11 assembly cases including AMA-1867 `workout_name` round-trip via test seam `makeGarminCompletionRequestForTesting`)
- [x] Both listed in `docs/testing/critical-journeys.md` (added in this PR — see CJ-02 and CJ-03 sections; closes [AMA-1869](https://linear.app/amakaflow/issue/AMA-1869))
- [ ] Real-device smoke on Apple Watch + Garmin (deferred to TestFlight pipeline / post-launch; sim verification covers the contract)
- [ ] L3 (XCUITest Watch sim driving) deferred — L4 evidence flow (AMA-1850's run) exercises the same `WorkoutCompletionRequest` assembly that L3 would, and the 19 L2 assembly tests pin every wire-shape invariant. Adding L3 is post-launch work.

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
