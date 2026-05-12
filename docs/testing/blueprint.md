# AmakaFlow Testing Blueprint

## Purpose

This blueprint defines a stable testing architecture for the AmakaFlow iOS app and its FastAPI-backed services. The goal is to replace ambiguous agent status updates with a repeatable system that clearly answers five questions for every feature: what changed, what was tested, what passed, what failed, and what evidence exists. The architecture follows a testing pyramid: fast backend and app-level validation form the base, native iOS journey checks sit above that, and Maestro is retained as an evidence and observability layer rather than the primary validator.

The pilot workflow for this blueprint is the single critical journey already identified for AmakaFlow: **Sign-in → Generate → Save & End → Verify persistence → Reopen app**. That flow becomes the first path required to pass all layers before the model is expanded to other journeys.

## Principles

### Core rules

- Backend correctness is proven in FastAPI tests before simulator-driven UI work begins.
- iOS behavior is proven in XCTest before broad end-to-end automation is trusted.
- Critical mobile journeys are proven in Apple-native XCUITest, which is the authoritative UI validator for iOS release confidence.
- Maestro is used for reusable flows, screenshots, videos, and CI-readable evidence; it is not considered sufficient by itself to mark a feature validated.
- Every ticket ships with an explicit 4-layer Definition of Done matrix and a machine-readable record of pass/fail by layer.
- Platform blockers such as simulator-only config or key-injection failures are tracked as infrastructure tickets, not buried inside feature PR summaries.

### Validation model

A feature is only considered validated when the required layers for that feature are green. A Claude or CI message that says files landed, a PR opened, or a flow executed does not count as user-facing validation unless the relevant assertions also passed and artifacts were attached.

## Test layers

| Layer | Name | Scope | Primary tool | Required? | Output |
|---|---|---|---|---|---|
| L1 | Service and contract | FastAPI routes, auth, schema, business logic | pytest + FastAPI TestClient | Yes | JUnit, coverage, failing assertion details |
| L2 | App logic and adapters | Swift client mapping, reducers, persistence, view models | XCTest | Yes | xcode test result bundle, coverage, failing test names |
| L3 | Native critical journeys | Main user flows on iOS UI | XCUITest | Required for major journeys and release-critical flows | xcresult, screenshots, failing step context |
| L4 | Evidence and observability | Reusable flows, screenshots, videos, exploratory CI runs | Maestro | Required as evidence for major journeys, but not authoritative alone | JUnit, screenshots, screen recordings, markdown summary |

### Layer policy

- **Minor backend-only work:** L1 required, L2/L3/L4 only if app contract changes.
- **App logic or API integration work:** L1 and L2 required, L3 required when the user journey changes, L4 required if the feature is visible and needs evidence artifacts.
- **Major user journey work:** all four layers required, with L3 as validator and L4 as evidence.
- **Infrastructure and test-platform work:** prove the platform fix directly and update affected test plans, but do not masquerade infra fixes as feature validation.

### Known L3 limitations (vendor-imposed)

Some L3 coverage is implemented with deliberate fragility because a vendor SDK does not expose stable test hooks. These are temporary tooling constraints, not permanent exemptions from L3 coverage. Each gets:

- a documented fragile fallback path that still attempts the assertion,
- an upstream issue with the vendor requesting test hooks or accessibility identifiers,
- a Linear ticket tracking the workaround until the upstream gap is closed.

Current entries:

| Journey step | Vendor SDK | Limitation | Fallback in use | Upstream | Workaround ticket |
|---|---|---|---|---|---|
| CJ-01 sign-in | clerk-ios (`ClerkKitUI.AuthView`) | WebView-hosted form, zero `accessibilityIdentifier` annotations, `SignIn.create` is internal access (not callable from app code) | `UITEST_CLERK_TEST_SESSION` env-var bypass in `AuthViewModel` (AMA-1843, DEBUG-only) — skips Clerk subscription, mocks `isAuthenticated=true` + a synthetic `UserProfile`. Lets XCUITest drive past the auth gate but **no real Clerk JWT**, so backend API calls 401. UI-navigation evidence only. | [clerk-ios#413](https://github.com/clerk/clerk-ios/issues/413) | AMA-1843 (mock bypass — landed); follow-up for real-session bypass via raw Clerk Frontend API |

#### CJ-01 sign-in bypass usage

XCUITest opts in by setting the env var on the launched app under test:

```swift
let app = XCUIApplication()
app.launchEnvironment["UITEST_CLERK_TEST_SESSION"] = "user_id=user_3DPjPhIrk4X7JDQQsi7PH63Iurd,email=claude+clerk_test@amakaflow.dev"
app.launch()
```

Payload format is `key=value` pairs joined by `,`. All fields optional; defaults to a synthetic `user_uitest_ama1843` identity. The bypass is gated by both `#if DEBUG` and a non-empty env var, so Release archives do not compile it (verified by inspecting the deployed IPA's symbol table — see memory `inspect-deployed-ipa-before-claiming-shippable.md`).

**Expected backend behavior under bypass:** every authenticated request returns 401 because `AuthViewModel.cachedBearerToken()` and `token()` both return `nil` (no real session). This is intentional — the L3 test under bypass validates UI navigation only; backend persistence requires the real-session bypass (filed as the follow-up below).

When upstream clerk-ios#413 lands one of (a) `@_spi(Test) public` on `SignIn.create` + `verifyCode`, or (b) `accessibilityIdentifier` on `AuthView` fields, the bypass is removed and L3 sign-in becomes a hard gate again.

## Repository structure

The repository should make test intent obvious by separating product code, fixtures, contracts, and evidence-producing automation. The exact folder names can adapt to the current repo layout, but the ownership boundaries below should remain stable.

```
amakaflow-ios-app/
├── AmakaFlow/
│   ├── App/
│   ├── Features/
│   ├── Shared/
│   ├── Networking/
│   ├── Persistence/
│   └── TestSupport/
├── AmakaFlowTests/
│   ├── Unit/
│   │   ├── Features/
│   │   ├── Networking/
│   │   ├── Persistence/
│   │   └── Helpers/
│   ├── Integration/
│   │   ├── APIContract/
│   │   ├── Auth/
│   │   └── WorkoutLifecycle/
│   ├── Fixtures/
│   │   ├── JSON/
│   │   ├── Models/
│   │   └── StubResponses/
│   └── TestPlans/
│       ├── ci-unit.xctestplan
│       └── local-fast.xctestplan
├── AmakaFlowUITests/
│   ├── Journeys/
│   │   ├── Auth/
│   │   ├── Generate/
│   │   └── WorkoutLifecycle/
│   ├── Screens/
│   ├── Interruptions/
│   ├── Fixtures/
│   └── TestPlans/
│       ├── ci-smoke-ui.xctestplan
│       └── release-critical.xctestplan
├── e2e/
│   ├── maestro/
│   │   ├── flows/
│   │   │   ├── auth/
│   │   │   ├── generate/
│   │   │   ├── workout-lifecycle/
│   │   │   └── smoke/
│   │   ├── _lib/
│   │   │   ├── app-launch.yaml
│   │   │   ├── clerk-signin.yaml
│   │   │   ├── permissions.yaml
│   │   │   └── assertions.yaml
│   │   ├── fixtures/
│   │   ├── outputs/
│   │   └── README.md
│   └── reports/
│       ├── maestro/
│       └── consolidated/
├── contracts/
│   ├── mobile-bff/
│   │   ├── openapi.json
│   │   ├── changelog.md
│   │   └── compatibility/
│   └── test-data/
├── backend-tests/
│   └── references/
├── docs/
│   ├── testing/
│   │   ├── blueprint.md
│   │   ├── test-inventory.md
│   │   ├── critical-journeys.md
│   │   ├── feature-dod-template.md
│   │   └── known-platform-blockers.md
│   └── runbooks/
├── scripts/
│   ├── test/
│   │   ├── run_l1_backend.sh
│   │   ├── run_l2_xctest.sh
│   │   ├── run_l3_xcuitest.sh
│   │   ├── run_l4_maestro.sh
│   │   └── consolidate_reports.sh
│   └── ci/
└── .github/
    └── workflows/
        ├── ios-pr-validation.yml
        ├── ios-nightly-evidence.yml
        └── release-readiness.yml
```

### Structure rules

- `AmakaFlowTests/Unit` contains fast, deterministic logic tests with no real network calls.
- `AmakaFlowTests/Integration` contains app-side contract, serialization, auth, and persistence integration tests using stable fixtures and mocks.
- `AmakaFlowUITests/Journeys` contains only user-meaningful paths, not every screen permutation; each file should represent a named journey, not a widget-level checklist.
- `e2e/maestro/_lib` contains reusable subflows only; business assertions belong in named scenario flows and must be mirrored by L1, L2, or L3 if they are release-critical.
- `docs/testing/test-inventory.md` becomes the source of truth for what features have which layer coverage and what is intentionally not automated yet.

## Naming conventions

Naming is critical because the main current problem is ambiguity. Test names must tell a human what feature, state, and expected outcome they cover.

### Ticket and feature IDs

Use the Linear ticket or epic ID in all major scenario names when work is tied to a ticket.

- Feature doc: `AMA-1834-workout-save-end.md`
- Contract fixture: `ama-1834-workout-complete-success.json`
- Maestro scenario: `ama-1834-signin-generate-saveend-evidence.yaml`
- XCUITest class: `AMA1834_WorkoutLifecycle_CriticalJourneyTests`
- XCTest file: `AMA1834_WorkoutCompletionMapperTests.swift`

### XCTest naming

Use the format:

```
test_<feature>__<condition>__<expectedOutcome>
```

Examples:

- `test_workoutCompletionRequest__optionalFieldsPresent__encodesExpectedPayload`
- `test_authSessionReducer__expiredToken__returnsSignedOutState`
- `test_persistenceStore__saveEndSucceeds__reopenLoadsCompletedWorkout`

This naming makes failure logs readable in CI and avoids generic names like `testSaveWorks`.

### XCUITest naming

Use the format:

```
test_<journey>__<startState>__<userOutcome>
```

Examples:

- `test_signInGenerateSaveEnd__freshInstall__completedWorkoutVisibleAfterReopen`
- `test_signIn__permissionDialogAppears__interruptionHandledAndHomeVisible`

Permission and interruption handlers should live in dedicated helpers because Apple explicitly treats UI interruptions as a first-class testing concern.

### Maestro naming

Use the format:

```
<ticket>-<journey>-<purpose>.yaml
```

Examples:

- `ama-1834-signin-generate-saveend-evidence.yaml`
- `ama-1834-clerk-signin-reusable.yaml`
- `ama-1840-smoke-critical-journey-evidence.yaml`

The suffix must indicate intent:

- `-evidence` for screenshot and observability runs
- `-smoke` for fast non-authoritative sanity checks
- `-setup` for reusable environment prep
- `-debug` for temporary investigation flows that should not be merge-gated

## Critical journey catalog

AmakaFlow should define a small catalog of critical journeys before expanding coverage. Each journey must have a named owner, required layers, and a stable data strategy.

| Journey ID | User journey | Minimum required layers | Notes |
|---|---|---|---|
| **CJ-01** | Sign-in → Generate → Save & End → Verify → Reopen | L1, L2, L3, L4 | **Pilot journey and first release gate** |
| CJ-02 | Sign-in → View calendar/program → open generated workout | L1, L2, L3, L4 | Add after CJ-01 is stable |
| CJ-03 | Sync-triggered update appears correctly in app | L1, L2, L3, L4 | Needs deterministic staged sync fixture |
| CJ-04 | Auth expiry / relaunch / recovery path | L1, L2, L3, L4 | Important because auth interruptions are a recurring instability source |

**Do not expand beyond one pilot critical journey until CJ-01 has produced two consecutive trustworthy CI runs and one trustworthy local developer run under the new model.**

## CI architecture

CI must make results readable in one pass. Each pipeline should output a consolidated status artifact that states which layers ran, whether they passed, what was skipped, and where the evidence lives.

### Workflow 1: PR validation

Trigger on every PR that changes iOS app code, contracts, or test assets.

Stages:

1. **Static checks**: Swift format/lint, YAML validation for Maestro, contract file diff check.
2. **L1 references**: if backend contract fixtures or generated client changed, require linked backend pytest results or contract compatibility check.
3. **L2 XCTest**: run fast unit and integration suite on simulator-compatible environment.
4. **L3 XCUITest smoke**: run only the impacted critical journeys, starting with CJ-01.
5. **L4 Maestro evidence**: run evidence flow, capture screenshots and video, publish JUnit and markdown summary.
6. **Consolidation**: generate a single markdown artifact named `pr-test-report.md` with per-layer results.

Merge rule:

- Required: static checks, L2, impacted L3, report consolidation.
- Required when relevant: linked L1 proof for contract or backend-coupled changes.
- Informational but expected for major journeys: L4 evidence.

### Workflow 2: Nightly evidence

Run on schedule against staging or a controlled environment. The purpose is drift detection and evidence gathering, not PR gating.

Stages:

1. Build installable app.
2. Run full Maestro evidence suite with screenshots after each checkpoint.
3. Run selected XCUITest release-critical journeys.
4. Publish a consolidated trend report with last successful run, newly failing steps, and artifact links.

Nightly output should answer: what changed since last known green, what regressed, and whether the regression is validator-level or evidence-level.

### Workflow 3: Release readiness

Run before TestFlight promotion or release candidate signoff.

Stages:

1. Full L2 suite.
2. Full critical L3 suite on target simulator matrix.
3. L4 evidence capture for each critical journey.
4. Manual signoff checklist artifact.

This workflow is where the final human-readable release note is created: validated journeys, known gaps, platform blockers, and deferred risk. This matches the need to stop shipping on vague "agent says green" signals.

## Report format

Every CI run should publish one consolidated markdown report using a standard schema.

```markdown
# PR Test Report: AMA-1834

## Scope
- Files changed:
- Contracts changed:
- User-visible surfaces changed:

## Layer status
| Layer | Ran | Status | Required | Evidence |
|---|---|---|---|---|
| L1 | Yes | Pass | Yes | linked backend report |
| L2 | Yes | Pass | Yes | xcresult |
| L3 | Yes | Fail | Yes | screenshot 14, xcresult |
| L4 | Yes | Pass | Evidence | video, screenshots, junit |

## Failures
- L3 / CJ-01 / Save & End button not visible after generation
- Repro environment: iPhone 16 simulator, iOS version, build sha

## Known blockers
- AMA-1840 Debug-sim Clerk key injection affects local Maestro launch only

## Decision
- Merge blocked: L3 failed on required critical journey
```

This file becomes the only message humans need to read. Chat or agent summaries may link to it, but should not replace it.

## Data strategy

Tests become unreadable when state is random. The pilot flow should run against deterministic test accounts, seedable fixtures, and visible assertions.

### Accounts and fixtures

- Maintain a dedicated Clerk staging test account for UI automation and document it in the secure test runbook.
- Seed backend test data for the pilot journey so generated outputs are predictable enough to assert meaningfully.
- Keep JSON fixtures for expected request and response bodies under version control in `contracts/test-data` or `AmakaFlowTests/Fixtures`.

### Assertions

Each layer should assert different truths:

- **L1** asserts response correctness, auth handling, schema compatibility, and edge cases.
- **L2** asserts app mapping, reducer transitions, persistence, and view model outputs.
- **L3** asserts user-visible success criteria in the native app, including interruption handling for permissions and system dialogs.
- **L4** asserts only observable checkpoints and captures screenshots; it should not carry exclusive business truth for release decisions.

## Pilot implementation plan

The first implementation should be intentionally narrow.

### Phase 1: Blueprint adoption

- Land this blueprint in `docs/testing/blueprint.md` (this PR).
- File and link architecture umbrella ticket (AMA-1839).
- Park Maestro-only PRs that claim validation without required layers for the target journey.
- Restructure existing tickets to reference the 4-layer matrix and identify missing coverage explicitly.

### Phase 2: CJ-01 implementation

Build coverage for the pilot journey in this order:

1. **L1** backend tests for sign-in dependent API contract, workout generation completion, save and end persistence verification path.
2. **L2** XCTest for request encoding, response mapping, local state transitions, persistence reload behavior.
3. **L3** XCUITest for the full critical journey from app launch through reopen verification.
4. **L4** Maestro evidence flow with screenshots after sign-in, after generate, after save and end, after verification, and after reopen.

Gate progression should be strict: if L1 or L2 is red, do not spend time stabilizing L4. If L3 is red, L4 may still run for evidence, but the feature is not validated.

### Phase 3: Inventory and expansion

After CJ-01 is stable:

- create `docs/testing/test-inventory.md`
- classify all existing user-visible flows as critical, supporting, or exploratory
- promote only a few more journeys at a time into L3 and L4
- keep Maestro library subflows minimal and shared

## Definition of Done template

The following template should be copied into every relevant ticket. Source of truth: `docs/testing/feature-dod-template.md`.

```markdown
## Definition of Done — 4 Layer Matrix

### Scope
- Ticket:
- Feature / journey:
- User-visible behavior expected:
- Backend routes touched:
- iOS modules touched:
- Contracts changed: Yes/No

### L1 — FastAPI / contract
- [ ] Required
- [ ] Backend tests added or updated
- [ ] Success path asserted
- [ ] Failure / auth path asserted
- [ ] Contract fixture updated if needed
- Evidence:

### L2 — XCTest
- [ ] Required
- [ ] Unit or integration tests added/updated
- [ ] Mapping / reducer / persistence behavior asserted
- [ ] No real network dependence
- Evidence:

### L3 — XCUITest
- [ ] Required for major journeys
- [ ] Critical journey created or updated
- [ ] Native success criteria asserted
- [ ] Interruptions handled (permissions, alerts, auth)
- Evidence:

### L4 — Maestro evidence
- [ ] Evidence flow created or updated
- [ ] Screenshots captured at key checkpoints
- [ ] Video or JUnit attached in CI
- [ ] Marked evidence-only unless explicitly approved otherwise
- Evidence:

### Known blockers
- Infrastructure blockers linked separately
- Local-only limitations documented
- Anything skipped has reason and follow-up ticket

### Merge decision
- [ ] All required layers green
- [ ] Evidence artifacts attached
- [ ] Report consolidated
- [ ] Ready to merge
```

## PR template additions

The repo PR template should be updated so Claude and humans must answer the same questions every time.

```markdown
## Test impact
- Critical journey affected:
- Layers required: L1 / L2 / L3 / L4
- Contracts changed:
- New fixtures added:

## Validation summary
| Layer | Status | Link |
|---|---|---|
| L1 |  |  |
| L2 |  |  |
| L3 |  |  |
| L4 |  |  |

## Known blockers
-

## Merge rule
- [ ] This PR meets all required layers for its scope
- [ ] This PR does not rely on Maestro alone as validation
```

## Guardrails for Claude-driven development

Claude should not be asked vague questions such as "is this tested?" because that invites narrative instead of proof. The task contract for Claude should state the exact journey, exact required layers, exact files to update, and exact artifacts to attach.

Use these rules:

- Never accept "flow ran" as equivalent to "feature passed."
- Never merge on Maestro-only proof for release-critical behavior.
- Require one consolidated message per run that links the report artifact, not a stream of intermediate status notes.
- Require Claude to distinguish clearly between file changes, validator results, evidence artifacts, and known blockers.
- Require out-of-scope platform issues to be filed separately, as planned for AMA-1840.

## Rollout order

1. Land this blueprint in `docs/testing/blueprint.md` (this PR).
2. File and link the architecture umbrella ticket (AMA-1839 — already filed).
3. Add PR template and report schema (this PR).
4. Implement CJ-01 across L1-L4.
5. Fix AMA-1840 so local debug/simulator runs are trustworthy again.
6. Revisit parked PR #200 only after the required pilot layers are present and the evidence report is readable.

## Success criteria

This blueprint is working when a single engineer can open a PR or nightly report and answer, in under two minutes, the following:

- What exact journey was tested?
- Which layers ran?
- Which layer is authoritative for pass/fail?
- What failed?
- What evidence exists?
- Is the feature safe to merge?

When those answers are obvious, AmakaFlow will have moved from agent narration to test architecture.

## Source

Drafted by David Andrews, 2026-05-09. Captures the architecture decision made after the AMA-1817 contract-first epic shipped and the testing pyramid had drifted into Maestro-as-validator. References: FastAPI testing docs, Apple XCTest/XCUIAutomation/UI-interruption-handling docs, Maestro flow conditions.
