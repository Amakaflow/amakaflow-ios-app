# Mobile-Facing Domains (AMA-1824)

**Status:** Locked first-wave scope. Anti-drift gate for [AMA-1817 epic](https://linear.app/amakaflow/issue/AMA-1817).

This doc names the mobile-facing API surfaces the iOS app interacts with and decides which get the BFF + OpenAPI codegen treatment **first**. It is a discipline tool, not a final domain model: deferred areas stay on direct service calls until they earn the same treatment via measured pain.

## TL;DR

- **First-wave BFF coverage (Phase 1818/1819):** `workout`, `sync`, `coach`.
- **Deferred (stay direct):** `social/gamification`, `calendar`, `device/account`, `telegram setup`.
- **Naming:** `sync` is correct (sync_queue carries every queued mutation: completion writes, accept-suggestion writes, tombstones — not only completions).

## Why this split, not 6 domains

`AmakaFlow/Services/APIService.swift` (~3000 lines, ~85 methods) naturally clusters into ~6 buckets, but the AMA-1817 epic locks first-wave at 3. That's not a claim that the app only has three domains — it's a claim that **three of them deserve a protective mobile-facing anti-corruption layer first**, while the rest stay on direct service calls.

This is the [strangler fig pattern](https://martinfowler.com/articles/strangler-fig-mobile-apps.html) applied to mobile + BFF: move a thin, high-risk slice first, keep old paths alive for the rest, validate each routed area before expanding.

## First-wave domains

### `workout` — planning + active session

Why first-wave: highest user-flow surface. Plan generation, scheduled / planned / pending workout reads, day state, and write-through for save/start/complete-by-id are the critical path of the product. AMA-1814 (path rename) and the AMA-1798/9/00 chain were all in this domain.

BFF route prefix: **`/v1/workout/...`**

iOS APIService methods in scope (~25):

- Reads: `fetchWorkouts`, `fetchScheduledWorkouts`, `fetchPushedWorkouts`, `fetchPendingWorkouts`
- Day surfaces: `fetchDayState`, `fetchDayStates`, `detectConflicts`, `resolveConflict`
- Programs: `fetchPrograms`, `fetchProgramDetail`, `generateProgram`, `fetchGenerationStatus`, `updateProgramStatus`, `updateProgramProgress`, `deleteProgram`, `generateWeek`
- Writes: `saveWorkout`, `syncWorkout`, `completeWorkout`, `parseWorkoutText`, `logManualWorkout`
- Exports: `exportWorkoutFIT`, `exportWorkoutCSV`, `getAppleExport`

### `sync` — queued mutation reconciliation

Why first-wave: this is the reliability/error-recovery surface. The local-first GRDB SyncEngine (AMA-1791/1792) flushes every mutation through this domain. AMA-1812 (`/sync/pending` 500) and AMA-1813 (`/workouts/complete` 422) both lived here.

What `sync` actually means: **replaying and reconciling all queued writes from `sync_queue` (completions, accepted suggestions, tombstones)** — not just workout completion submission. This is why the name stays `sync` over `completion`.

BFF route prefix: **`/v1/sync/...`**

iOS APIService methods in scope (~6):

- `postWorkoutCompletion`
- `confirmSync`, `reportSyncFailed`
- `fetchCompletions`, `fetchCompletionDetail`
- `exportUserData` (write-side reconciliation read)

### `coach` — AI / chat / suggestions / shape-shifting media ingestion

Why first-wave: highest schema-drift risk. Coach payloads evolve as AI prompts and models change, and ingestion accepts heterogeneous media (text, audio, Instagram, photo). Generated client + server-side translation in the BFF lets iOS keep a stable shape while the underlying chat-api / workout-ingestor-api evolve.

Coach depends on `mapper-api` + `chat-api` + `workout-ingestor-api` as needed; BFF front-loads orchestration so iOS calls one place (`/v1/coach/...`) instead of routing per-feature to the right backend service.

BFF route prefix: **`/v1/coach/...`**

iOS APIService methods in scope (~17):

- Conversation: `askCoach`, `sendCoachMessage`, `fetchCoachMemories`, `getFatigueAdvice`
- Suggestion: `suggestWorkout`, `postRPEFeedback`
- Voice + ingestion: `parseVoiceWorkout`, `transcribeAudio`, `ingestInstagramReel`, `ingestText`, `parseText`, `analyzePhoto`, `lookupBarcode`
- Personal dictionary: `syncPersonalDictionary`, `fetchPersonalDictionary`
- Bulk import: `detectImport`, `matchExercises`, `previewImport`, `executeImport`, `fetchImportStatus`, `cancelImport`
- Nutrition adjacent: `getFuelingStatus`, `checkProteinNudge`
- Action queue: `fetchPendingActions`, `respondToAction`

## Deferred (stay direct, not first-wave)

These remain hand-coded `APIService.swift` methods calling backend services directly. They graduate to the BFF when they cause measured pain (see Guardrails below).

| Bucket | Methods | Why deferred |
|---|---|---|
| **social/gamification** | `fetchXP`, `fetchSocialFeed`, `addSocialReaction`, `removeSocialReaction`, `fetchSocialComments`, `postSocialComment`, `fetchSocialSettings`, `updateSocialSettings`, `fetchUserPublicProfile`, `followUser`, `unfollowUser`, `fetchChallenges`, `fetchChallengeDetail`, `createChallenge`, `joinChallenge`, `fetchMyCrews`, `fetchCrewDetail`, `fetchCrewFeed`, `createCrew`, `joinCrew`, `leaveCrew`, `fetchFriendsLeaderboard`, `fetchCrewLeaderboard`, `fetchVolumeAnalytics`, `fetchShoeComparison` | Broad surface (~25 methods) but not the source of current contract pain. |
| **calendar** | `fetchConnectedCalendars`, `connectCalendar`, `syncCalendar`, `disconnectCalendar` | Small, separable, low-churn. |
| **device/account** | `registerPushToken`, `deleteAccount`, `fetchProfile`, `fetchSubscription`, `fetchNotificationPreferences`, `updateNotificationPreferences`, `exportUserData` (delete-account flow) | Stable, low-churn. **Watch-list:** if auth/session/profile shapes start changing, this jumps forward. |
| **telegram setup** | `mintTelegramLinkToken`, `getTelegramLinkStatus`, `resendWatchDelivery` | Operational onboarding, not core workout-flow orchestration. |

## Guardrails (anti-drift)

1. **BFF covers only endpoints that materially affect workout completion, sync correctness, or coach UX in phases 1818/1819.** Nothing else.
2. **Deferred buckets stay direct, but no new hand-shaped schemas are added without a contract note in the PR description.** New endpoints in the deferred buckets must reference an OpenAPI path + version.
3. **Promotion trigger:** if a deferred bucket causes two drift incidents OR one high-severity user-flow failure, it becomes a candidate for the next BFF wave. File a follow-up ticket under AMA-1817 to expand scope; do not silently widen Phase 1818/1819.
4. **The BFF is an anti-corruption + shaping layer, not a dumping ground for business logic.** Reusable domain capabilities belong behind the BFF (in the underlying services), not inside it.
5. **Domain count is locked at 3 first-wave + 4 deferred.** Adding a 5th first-wave domain requires an explicit AMA-1817 epic update.

## How this maps to AMA-1817 children

| Ticket | What it consumes from this doc |
|---|---|
| **[AMA-1818](https://linear.app/amakaflow/issue/AMA-1818) Phase 1 codegen** | The 5 endpoints called out in [`POST /v1/workout/save`, `POST /v1/sync/complete`, `GET/POST /v1/sync/pending|confirm|failed`, `GET /v1/workout/planned`] — generated Swift client targets these. |
| **[AMA-1819](https://linear.app/amakaflow/issue/AMA-1819) Phase 2 BFF** | Three route prefixes (`/v1/workout/...`, `/v1/sync/...`, `/v1/coach/...`) implemented as thin proxies to mapper-api / chat-api. |
| **[AMA-1820](https://linear.app/amakaflow/issue/AMA-1820) Phase 3 split APIService** | Domain repositories named after this doc: `WorkoutAPIRepository`, `SyncAPIRepository`, `CoachAPIRepository`, plus a per-deferred-bucket repo. |
| **[AMA-1821](https://linear.app/amakaflow/issue/AMA-1821) Phase 4 CI gates** | Schema diff applies to BFF spec only (first-wave). Flow tests cover the 3 user journeys that traverse all 3 first-wave domains. |
| **[AMA-1822](https://linear.app/amakaflow/issue/AMA-1822) OpenAPI persisted** | Generates spec from BFF + the 3 underlying services it proxies. |
| **[AMA-1823](https://linear.app/amakaflow/issue/AMA-1823) request_id correlation** | Applies to every BFF call (i.e. all 3 first-wave domains). |

## Out of scope for this doc

- BFF implementation (AMA-1819).
- Codegen tooling choice (AMA-1818 — likely `swift-openapi-generator`).
- Backend service splits beyond the 3-domain mapping.
- Auth / Clerk migration.
- New features.

## Source

- [AMA-1817 epic](https://linear.app/amakaflow/issue/AMA-1817) (Contract-first API architecture)
- [AMA-1824 ticket](https://linear.app/amakaflow/issue/AMA-1824) (Lock 3 mobile-facing domains)
- Perplexity diagnosis 2026-05-09 04:13Z (BFF + OpenAPI codegen recommendation)
- 4-bug postmortem 2026-05-09: AMA-1812 (sync 500), AMA-1813 (complete 422), AMA-1814 (path rename), AMA-1815 (Quick Start dup)
