# AMA-2310 — Start → Garmin dogfood evidence

## What we're testing

Library → Start → Garmin is usable when unpaired (clear pair/CIQ path) and when paired (push status in seconds). Builds on AMA-2286 software path; closes dogfood friction AMA-2310.

| Surface | Simulator Start sheet (+ device FR965/Fenix when available) |
| Linear | [AMA-2310](https://linear.app/amakaflow/issue/AMA-2310) |
| Related | AMA-1387 CIQ · AMA-2286 one-tap |

## Checks

| What we're testing | Why | Click / check | Pass looks like |
| ----- | ----- | --- | ----- |
| Unpaired recovery | Dead grey row is the friction | Start → Garmin unpaired | CTA “Tap to pair CIQ / open Devices” + PAIR tag → Devices sheet |
| Paired push | Software path | Start → Garmin with `UITEST_GARMIN_PAIRED` | Status queued/sent/ready ≤ few seconds |
| Fail honesty | Trust | `UITEST_GARMIN_PUSH_FAIL=not_paired` | what+why copy |
| Watch land | Golden loop | CIQ download → native player | Strength on FR965/Fenix (or AMA-1387 leftover documented) |

## How to reproduce (sim)

```bash
# Unpaired recovery
maestro test e2e/maestro/ama-2310-visual-garmin-unpaired.yaml

# Paired push + forced fail
maestro test e2e/maestro/ama-2286-visual-garmin-start.yaml
```

Env pattern: `UITEST_MODE` + fixtures + `UITEST_SKIP_ONBOARDING` (+ `UITEST_GARMIN_PAIRED` for paired path).

## Screenshots

Place Maestro / device captures here:

- `ama-2310-garmin-unpaired-recovery.png` — unpaired Start sheet + Devices
- `ama-2286-garmin-handoff-success.png` — Sent to Garmin
- `ama-2286-garmin-handoff-not-paired.png` — forced fail copy
- Optional: FR965/Fenix native player after CIQ download

## Hardware checklist

See `docs/ama-2286-garmin-one-tap/README.md` (updated for AMA-2310 recovery).
