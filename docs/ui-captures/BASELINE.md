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
| Account | `design_capture_v1` (staging Clerk, instance `ruling-mite-84`) |
| Environment | staging |

`design_capture_v1` is a dedicated non-personal account. It replaces David's personal
account in every capture workflow. Captures leave the device, so a sanitized account is
the privacy boundary, not a convenience.

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
| `design_capture_v1` account created | BLOCKED (needs staging Clerk credentials, see below) |
| Seed data defined and reproducible | TODO (AMA-2501) |
| `uiTestMode` fixture seam | TODO (AMA-2502) |
| Screen registry | TODO (AMA-2503/2504) |
| Capture runs 0–8 | TODO (AMA-2505) |

## Known blocker

The capture machine has no staging Clerk admin credentials and no route to the Mini that
holds them. Account creation and staging seeding cannot run here. Everything that does not
require those credentials is being built regardless.

## Prior art

`docs/app-baseline/2026-08-17/` and `docs/app-baseline/2026-08-18/` hold hand-taken
captures from David's personal account. They are useful reference and are not part of this
baseline. They are not reproducible and the account is wrong.
