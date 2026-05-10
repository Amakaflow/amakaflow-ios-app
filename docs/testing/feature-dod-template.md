# Feature Definition of Done — 4 Layer Matrix

Copy this template into every Linear ticket whose work touches user-visible behavior, contracts, or critical journeys. Source blueprint: `docs/testing/blueprint.md`.

## Scope
- Ticket:
- Feature / journey:
- User-visible behavior expected:
- Backend routes touched:
- iOS modules touched:
- Contracts changed: Yes/No

## L1 — FastAPI / contract
- [ ] Required
- [ ] Backend tests added or updated
- [ ] Success path asserted
- [ ] Failure / auth path asserted
- [ ] Contract fixture updated if needed
- Evidence:

## L2 — XCTest
- [ ] Required
- [ ] Unit or integration tests added/updated
- [ ] Mapping / reducer / persistence behavior asserted
- [ ] No real network dependence
- Evidence:

## L3 — XCUITest
- [ ] Required for major journeys
- [ ] Critical journey created or updated
- [ ] Native success criteria asserted
- [ ] Interruptions handled (permissions, alerts, auth)
- Evidence:

## L4 — Maestro evidence
- [ ] Evidence flow created or updated
- [ ] Screenshots captured at key checkpoints
- [ ] Video or JUnit attached in CI
- [ ] Marked evidence-only unless explicitly approved otherwise
- Evidence:

## Known blockers
- Infrastructure blockers linked separately
- Local-only limitations documented
- Anything skipped has reason and follow-up ticket

## Merge decision
- [ ] All required layers green
- [ ] Evidence artifacts attached
- [ ] Report consolidated
- [ ] Ready to merge
