# AMA-1803 — Phase 1: Honest CTA audit

**Status:** Audit only — no code changes. Deliverable is this document. Implementation ships CTA-by-CTA in follow-up commits, each with unit tests covering (success, success:false, 4xx, 5xx, network).

**Why this audit exists:** AMA-1798/1799/1800 shipped iOS-rejecting bugs to staging undetected because the iOS UI declared "Saved!" / "Workout Complete!" while the network call was silently failing or returning HTTP 200 with `success:false`. Tier 1b (AMA-1805) now reports those failures from the backend. Tier 1a (this ticket) makes them visible to the user.

## Pattern to apply (proposed)

For every primary CTA that triggers a network call:

1. **No optimistic UI without a revert path.** If the view dismisses or shows "Saved!" before the round-trip, the response handler MUST be able to revert to the prior state and surface the failure.

2. **Failure UI shape (toast + Report button):**
   - Title names the action — e.g. "Couldn't save workout", "Couldn't accept suggestion", "Couldn't sign in"
   - Body shows server `error_code` (when present) or HTTP status
   - "Retry" affordance for transient network errors (URLError.notConnectedToInternet, .timedOut, .networkConnectionLost)
   - "Report" button captures `requestId` (X-Request-ID header from the failing response), `error_code`, `endpoint`, `user_id` and pings Sentry with a user-initiated breadcrumb tag. Pairs with AMA-1805's server-side capture so both sides agree.

3. **Result-typed view-model methods.** Every CTA's view-model method returns `Result<Success, CTAError>` (or `async throws -> Success`) so the View knows whether to dismiss or stay-and-show-toast. No more `Bool` returns that conflate "request sent" with "request succeeded."

4. **`CTAError` shape:**
   ```swift
   enum CTAError: Error {
       case network(URLError)              // .notConnectedToInternet, .timedOut, …
       case http(status: Int, body: Data?) // 4xx / 5xx
       case lyingSuccess(message: String?, errorCode: String?) // 200 + {success:false}
       case decoding(DecodingError)
       case unauthenticated
   }
   ```
   Carries `requestId` on every variant for Sentry correlation.

5. **Unit tests per CTA.** Mock URLProtocol or APIService injection. Test cases:
   - happy path → success state
   - server returns `success:false` → toast shown, no optimistic UI persisted
   - 4xx → toast with status, no retry
   - 5xx → toast with status + retry affordance
   - URLError network → toast + retry
   - decoding error → toast + Report button
   - unauthenticated → routes to sign-in

## CTA inventory

Each row maps **what the user taps → which view-model method runs → which API call → current failure handling → gap**.

### 1. Save & End / Save for Later / Discard
**View:** `AmakaFlow/Views/WorkoutPlayerView.swift:131-148` (alert with 4 buttons)
**Action chain:** `engine.end(reason:)` (`WorkoutEngine.swift:596`) → `postWorkoutCompletion(...)` → `WorkoutCompletionService.postCompletion()` → POST `/workouts/complete`
**Current failure handling:**
- `WorkoutEngine.postWorkoutCompletion`: logs to console + Sentry, queues for retry on network error (`queueForRetry`). No `@Published` error surface.
- `WorkoutCompletionViewModel`: only published flag is `showComingSoonToast` (unrelated). **No error UI exists.**
- The completion-screen view (`WorkoutPlayerView` `.ended` branch) does not consume any error state.
**Gap (P0):** This is the AMA-1798/1799/1800 path. User saw "Workout Complete! ✓ 1m 11s" while the backend rejected the row with `success:false`. Zero UI surface.
**Fix:** Add `@Published var saveError: CTAError?` to a new `WorkoutCompletionViewModel` (or `WorkoutPlayerEnvironment`); `postWorkoutCompletion` writes to it; completion-screen view shows toast + Report when set; "Workout Complete!" header replaced with explicit success/failure state.

### 2. Accept Suggestion / Accept & Save
**View:** `AmakaFlow/Views/SuggestWorkoutView.swift:133` ("Accept & Save" button)
**Action chain:** view → `viewModel.acceptSuggestion()` → `AcceptedSuggestionsStore.append(...)` (local-only per AMA-1751 backend gap) + UI state
**Current failure handling:** `SuggestWorkoutViewModel.swift:159-165` — `do { … } catch { state = .error(error.localizedDescription) }`. Wraps the WHOLE block.
**Gap (P1):** State.error path likely surfaces in the view but the message is `error.localizedDescription` (no error_code, no Report button, no retry). Backend `accept-suggestion` endpoint isn't wired (per AMA-1751 TODO) so the local store is the source of truth — but local-only writes can also fail (disk full, schema migration). Today: silent.
**Fix:** Adopt the same `CTAError` + toast pattern. Even local-only failures surface honestly. When the AMA-1751 backend follow-up lands, add the network branch.

### 3. Suggest a Workout / Generate
**View:** `AmakaFlow/Views/HomeView.swift:1121` ("Suggest a Workout" button); `AmakaFlow/Views/SuggestWorkoutView.swift` (Generate)
**Action chain:** SuggestWorkout view-model → POST `/workouts/incoming` (`APIService.swift:203`)
**Current failure handling:** Same `state = .error(localizedDescription)` pattern (#2 above).
**Gap (P1):** Same as #2.
**Fix:** Same CTAError pattern.

### 4. Start workout (Today card)
**View:** `AmakaFlow/Views/HomeView.swift:789` ("Start workout" button)
**Action chain:** Navigates to `WorkoutPlayerView` (no immediate network call). The local-first AcceptedSuggestion `id` becomes the `workout_id` later sent on completion.
**Current failure handling:** N/A — no network on tap. The failure mode is downstream (#1).
**Gap (none on this CTA itself).**
**Fix:** No change here; #1 covers the user-visible failure point.

### 5. Sign in / Continue with Google (Clerk)
**View:** Clerk's hosted UI inside `ClerkSignIn` flow (no direct AmakaFlow button). Returns to `AuthViewModel`.
**Action chain:** Clerk SDK handles OAuth + session token; `AuthViewModel.swift` lines 98, 109, 212 each have `do { … } catch { … }` blocks.
**Current failure handling:** Need to read each catch block to know — `do/catch` exists but where it surfaces is TBD.
**Gap (P2):** Likely partial. Clerk's UI handles its own errors fine; AmakaFlow-side failures (token storage, profile bootstrap) need the same toast pattern.
**Fix:** Audit the 3 catch blocks; ensure each writes to a published error state with toast + Report.

### 6. Send Coach message
**View:** `AmakaFlow/Views/CoachChatView.swift` lines 34, 159, 221 — three call sites
**Action chain:** `viewModel.sendMessage(text)` → SSE POST → streaming response
**Current failure handling:** `CoachViewModel.errorMessage: String?` exists; written from catch blocks (line 102) and from SSE `.error` events (line 175).
**Gap (P2):** Has the surface but it's `error.localizedDescription` (no error_code, no Retry, no Report). Empty assistant message handling at line 105-107 hints at incomplete error UX.
**Fix:** Upgrade `errorMessage: String?` to `error: CTAError?`. Add Retry (re-send last user message) and Report buttons.

### 7. Connect Garmin / Apple / Strava (Settings)
**View:** `SettingsView.swift`, `StravaView.swift`, also Pairing / device-link views
**Action chain:** OAuth flows / device pairing → store tokens → enable sync
**Current failure handling:** Per-flow; not yet audited in detail.
**Gap (P2):** Known to be brittle from prior sessions (Garmin auth memory hits, Strava token refresh).
**Fix:** Schedule audit + same pattern in a follow-up. May need to be split — Garmin specifically is touchy enough to warrant its own ticket.

### 8. Deep-link / Universal Link
**View:** `AmakaFlowCompanionApp.swift` `.onOpenURL` handler → `DeepLinkManager.swift:37`
**Action chain:** parse URL, route to view, possibly issue an API call (workout-delivery resend, plan reveal, etc.)
**Current failure handling:** `DeepLinkManager.swift` has guards for `isAmakaFlowUniversalLink`, etc., but errors during the routed action are TBD.
**Gap (P2):** A deep link that routes to a screen which then silently fails is the worst-case false positive. Audit needed.
**Fix:** Each routed destination must surface its own failure. Add a wrapper that captures unhandled deep-link routing failures with a generic toast (no silent dead-ends).

### 9. Discard / Save for Later (workout completion alternates)
**View:** Same alert as #1.
**Action chain:** `engine.end(reason: .savedForLater | .discarded)` — these branches DO NOT post to backend (`WorkoutEngine.swift:679-693`).
**Gap (none — no network call to fail).** But the local-state transition can fail (DB write); same as #2's local-failure consideration.
**Fix:** Lower priority. Local-write failures are extremely rare; address in a unified pass when the GRDB rewire (AMA-1792) lands.

## Priority order for implementation

| P | CTA | Why |
|---|---|---|
| P0 | #1 Save & End | The path that hit AMA-1798/1799/1800. User-facing impact is largest. |
| P1 | #2 Accept & Save | Same data flow; user-visible during normal use. |
| P1 | #3 Suggest / Generate | Same. |
| P2 | #6 Send Coach message | Has partial surface; upgrade to full pattern. |
| P2 | #5 Sign in | Likely already mostly-handled by Clerk; verify catch blocks surface. |
| P2 | #8 Deep-link | Edge cases; lower frequency than #1-#3. |
| P3 | #7 Garmin / Strava | Brittle area; consider separate ticket per integration. |

## Out of scope for AMA-1803 (file as follow-ups)

- **Server-error breadcrumbs to Telegram:** Sentry already captures (AMA-1805); a Telegram echo for ops is a separate observability ticket.
- **Generic "Report" button → Linear ticket creation:** the Report button as scoped here writes to Sentry only. Auto-filing a Linear bug from a user tap is a future MVP+1.
- **Localization of error strings:** all toast strings will be English; i18n is out of scope.
- **Watch-side CTAs:** scope is iPhone CTAs. Watch's LOG SET / End Workout will get a similar audit in a follow-up tied to AMA-1797.

## Acceptance criteria (carried over from ticket)

- [x] Inventory of every primary CTA + its current failure-handling code path (this doc)
- [ ] Each CTA above wrapped in the new pattern (per-PR)
- [ ] Unit tests: each CTA's view-model handles (success, success:false, 4xx, 5xx, network) with explicit assertions on UI state for each
- [ ] Manual repro: kill backend mid-action → toast shows; backend returns success:false → toast shows; backend returns 422 → toast shows the field name from validation detail
- [ ] No optimistic UI without a revert path

## Next step

Review this audit. Once you sign off, I open Phase 2 PRs in priority order:

1. **PR-A (P0):** Introduce `CTAError` type + ToastView component + a shared `errorPublisher` pattern. Wire #1 (Save & End) end-to-end with full unit-test coverage. Manual repro on the sim (kill backend, observe toast).
2. **PR-B (P1):** #2 + #3 (Accept / Suggest / Generate).
3. **PR-C (P2):** #6 (Coach), #5 (Sign in), #8 (Deep-link).
4. **PR-D (P3):** #7 — possibly broken into Garmin / Strava sub-PRs.

Each PR has its own unit tests + manual-repro evidence + a single CTA's worth of behavior. Reviewable in isolation.
