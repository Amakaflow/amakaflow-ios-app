# Passive Strength Free Capture (Watch) — Design

**Date:** 2026-08-12  
**Status:** Approved  
**Ticket:** AMA-2420  
**Repo:** `amakaflow-ios-app`

## One sentence

Experimental **Start strength** opens a passive AmakaFlow Watch session: countdown → live metrics → swipe Pause / End / Discard → phone Fill in — no set/rest/crown prompts.

## Problem

Freeform Start (#590) reused the interactive set engine. Dogfood showed users want “turn on and leave it” capture; phone Fill in from HealthKit already works.

## Product loop

```text
Watch Today → Start strength (flag on)
  → 3-2-1 countdown
  → HKWorkoutSession (traditionalStrengthTraining, indoor)
  → Main: elapsed time, HR, active cal, total cal
  → Swipe: Pause | End | Discard
  → End: save HK + sync summary → Today Fill in
  → Discard: drop session, no Actuals draft
```

## Non-goals

- Crown / set logging / AS PLANNED during freeform
- Work/rest or narrow-rep IMU assists during freeform
- Changing plan-linked **Start planned** (stays interactive)

## Implementation sketch

| Piece | Role |
|---|---|
| `PassiveStrengthSessionEngine` | Thin HK + elapsed timer; no steps |
| `PassiveStrengthSessionView` | Countdown + metrics + swipe controls |
| `HealthKitWorkoutManager.discardSession` | End without `finishWorkout` |
| `TodayScheduleView` freeform link | → passive view (not standalone execution) |
| `WatchActualsDraftBuilder` | Empty set logs → blank Exercise stub for Fill in |

## Success

Flag on → Start strength → leave running → End → Today shows session with Fill in; no rest/step prompts during capture.
