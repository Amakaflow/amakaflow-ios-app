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
| 2 | Subscription / IAP testing harness (RevenueCat Test Store) | [AMA-1851](https://linear.app/amakaflow/issue/AMA-1851) | ⏳ Deferred to v1.1 (decision 2026-05-22). v1 ships free; paid tier added post-launch once retention signal lands. Rationale: pricing wasn't validated at $9.99, paywall design + Apple subscription review adds 1-3 days to App Review SLA, and "does the product work" is a different validation run from "will users pay." | None for v1 — paid tier deferred |
| 3 | CI → TestFlight on `main` merge | [AMA-1852](https://linear.app/amakaflow/issue/AMA-1852) | 🔲 Not started | Manual + skippable today |
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

### Gap 2 — AMA-1851: Subscription / IAP testing harness (⏳ deferred to v1.1)

**Decision 2026-05-22:** v1 ships FREE. Monetization deferred to v1.1.

**Why:** Pricing wasn't validated at $9.99 (felt too expensive). Paywall design + Apple subscription review adds 1-3 days to App Review SLA. "Does the product work" is a different validation run from "will users pay." Solo-founder pattern: ship free first, watch retention, then layer in the paywall with a strategy informed by actual usage.

**Setup done so far (for when we come back):**

- [x] RevenueCat account created (`Amakaflow` org)
- [x] iOS app added in RevenueCat dashboard with bundle ID `com.myamaka.AmakaFlowCompanion`
- [x] In-App Purchase key (`SubscriptionKey_2HR6TQ2QXF.p8`) uploaded to RevenueCat — credentials validated

**Deferred to v1.1 (don't tick these for v1 launch):**

- [ ] Subscription products created in App Store Connect (tier structure TBD — trial + lower price than $9.99 leaning candidate per 2026-05-22 discussion)
- [ ] Products imported into RevenueCat Product Catalog
- [ ] Entitlements defined (e.g., `premium`)
- [ ] Offerings configured
- [ ] iOS SDK `Purchases.configure(...)` wired in `AmakaFlowCompanionApp`
- [ ] Paywall view + entitlement gating in iOS
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
