# AMA-2286 — Garmin one-tap push (dogfood)

## Path (no third stack)

1. Library → Start → **Garmin**
2. iOS `POST /v1/devices/watch-delivery/{id}/push` (BFF → mapper)
3. Mapper FIT preflight → `garmin_workout_queue` + delivery `pushed`
4. Watch **AmakaFlow CIQ widget** (AMA-1387) downloads FIT → native player

**Out of scope:** Amazfit, Apple try (AMA-2287), phone player (AMA-2290), garth Connect scrape.

## Dogfood samples

| Sample | Fixture / Library | What must survive |
| -- | -- | -- |
| Strength | `strength_block_w1.json` (`fixture-strength-001`) | Names, sets, reps |
| Run intervals | `running_intervals_4x800.json` (`fixture-running-intervals-001`) | 4×800 structure + recoveries |

## Hardware checklist (Forerunner / Fenix)

- [ ] CIQ widget paired (Profile → Devices + code on watch)
- [ ] Strength push: status shows Sent/Queued (not “stub”); names visible on watch after CIQ download
- [ ] Interval push: lap structure usable in native player
- [ ] Forced fail: `UITEST_GARMIN_PUSH_FAIL=not_paired` or unpaired account → clear what+why ≤ few seconds
- [ ] Storage stress: ~20 workouts — cleanup / “storage full” copy if watched

## BLOCKED (device verify)

If hardware unavailable in-session: ship sim/API proof (unit tests + mapper/BFF 422/202). Device verify owned by David on FR965 / Fenix 8 — note evidence screenshots on Linear when done.

## AMA-1387 status

Document Done or blocked next action on both AMA-2286 and AMA-1387 after this PR.
