# Capture account seed

Account: `baseline+clerk_test@amakaflow.dev`.

The seed is the data every v1 capture is taken against. It has to be deterministic,
reproducible from scratch, and identical whether the app is reading staging or reading
local fixtures. Two seeds that drift produce captures that disagree for reasons nobody
can attribute.

## One source of truth

The seed is defined once, as data, and consumed twice.

- The seeder writes it into the `baseline+clerk_test@amakaflow.dev` account.
- The app reads the same data locally under the debug fixture seam (AMA-2502) when a
  capture needs a state the backend cannot be pushed into on demand.

Neither consumer may hold seed values of its own. A screen whose data exists only in a
seeder script, or only in a Swift mock, is not part of this baseline.

## Required content

Each row is a state the baseline must be able to capture. `Source` says which consumer
can produce it. Anything marked fixture-only is a state the live backend cannot be held
in reliably, which is exactly why the AMA-2502 seam exists.

| # | Content | Why the baseline needs it | Source |
| --- | --- | --- | --- |
| 1 | Completed coaching profile | Profile tab populated, not the first-run empty state | staging |
| 2 | Workout history spanning several weeks, mixed modalities | Today and history views with real density | staging |
| 3 | Saved workouts across at least two collections | Library populated, collection navigation reachable | staging |
| 4 | One workout parsed from a social-media import | The import provenance UI has no other way to appear | staging |
| 5 | One sync success with visible evidence | The success path of the sync surface | staging |
| 6 | One sync failure with visible evidence | The failure path, which never appears on demand live | fixture |
| 7 | No device connected | The devices-empty state under Profile | fixture |
| 8 | Friends state with at least one connection | Friends list populated rather than empty | staging |
| 9 | Empty library | The first-run Library state, unreachable once 3 exists | fixture |
| 10 | Loading and error states per surface | Neither is reachable by waiting | fixture |
| 11 | HealthKit permission denied | Permission-denied copy and recovery affordance | fixture |

Rows 6, 7, 9, 10, and 11 are the concrete argument for AMA-2502. Five of eleven required
states cannot be produced by seeding an account, so an account-only approach leaves the
baseline with holes it would have to mark UNKNOWN.

## Determinism rules

- No relative dates baked into seed values. Dates are expressed as offsets from a fixed
  capture date so a capture taken a month later frames identically.
- No generated IDs in anything a capture can show. UUIDs on screen are a known defect
  class in this app and would make two captures of the same screen differ.
- Re-running the seeder against an already-seeded account converges to the same state
  rather than appending. Seeding is idempotent or it is not reproducible.

## Status

The account exists and needs no creation. It was made 2026-08-17 for this purpose, its
password is in the macOS login keychain under service `amakaflow-baseline-sim`, and the
`AF-Baseline` simulator holds a persisted session. What remains is seeding it to the
content below.

Content and rules are fixed here. The serialized format is deliberately not specified yet:
it has to match the fixture-loading shape chosen in AMA-2502, and picking it first would
force that design instead of following it.

Automated capture is blocked on AMA-2457, not on credentials.
