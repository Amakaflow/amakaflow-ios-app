# Release UI baseline v1 — capture conditions

Every capture in this baseline is taken under exactly these conditions. A capture
taken under different conditions is not part of the baseline and must be retaken.
Change a value here only by opening a new baseline version, never by editing in place.

## Fixed conditions

| Condition | Value |
| --- | --- |
| Branch | `release/ui-baseline-v1` |
| Base git SHA | `74d2c250e0cac0ad4a10149b3cbb014c6f8860e7` |
| App marketing version | 1.0 |
| Device | iPhone 17 Pro Max (simulator) |
| iOS version | 26.1 (build 23B86) |
| Appearance | Dark |
| Dynamic Type | Default (Large) |
| Locale | en-US |
| Account | `baseline+clerk_test@amakaflow.dev` |
| Environment | staging |

`baseline+clerk_test@amakaflow.dev` is a dedicated non-personal account created
2026-08-17 for exactly this purpose. It is never David's personal account. Captures leave
the device, so a sanitized account is the privacy boundary, not a convenience.

It is not `claude+clerk_test@amakaflow.dev`. That one is the CI identity, hardcoded as the
fallback in `AuthViewModel.swift:110` and named across many Maestro flows. Reusing it
would couple this baseline to CI.

The account's password lives in the macOS login keychain under service
`amakaflow-baseline-sim`. The `AF-Baseline` simulator holds a persisted real Clerk
session, so a plain launch restores it and no auth bypass is needed.

## Why the simulator, and why this device

Only iPhone 17 Pro Max and iPhone Air are installed on the capture machine, both on iOS
26.1. Pro Max is the widest layout, so it under-reports truncation and wrapping bugs that
a smaller device would surface. Layout-width regressions are therefore out of scope for
this baseline and belong in a follow-up narrow-device pass.

## Status vocabulary

Registry rows carry one of: TODO, CAPTURED, RECONCILED, CANONICAL, BLOCKED, OUT_OF_SCOPE.
Design artifacts carry one of: Canonical, Legacy, Proposed, Unknown, Deprecated.

A screen with no runtime capture is UNKNOWN. It is never filled in from a mock.

## Baseline status

| Item | Status |
| --- | --- |
| Capture conditions fixed | done |
| Capture account exists | done (`baseline+clerk_test@amakaflow.dev`, 2026-08-17) |
| Seed data defined and reproducible | TODO (AMA-2501) |
| `uiTestMode` fixture seam | TODO (AMA-2502) |
| Screen registry | TODO (AMA-2503/2504) |
| Capture runs 0–8 | TODO (AMA-2505) |

## Known blocker

The capture machine has no staging Clerk admin credentials and no route to the Mini that
holds them. Account creation and staging seeding cannot run here. Everything that does not
require those credentials is being built regardless.

## Prior art

`docs/app-baseline/2026-08-17/` and `docs/app-baseline/2026-08-18/` hold 6 and 19 captures
taken with this same account via `scripts/capture-baseline.sh`. The account was right. What
keeps them out of this baseline is that the conditions above were not recorded at the time,
so a capture cannot be attributed to a device, OS, appearance, or build. They stay as
reference.
