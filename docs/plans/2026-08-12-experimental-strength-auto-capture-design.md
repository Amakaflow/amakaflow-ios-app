# Experimental Strength Auto-Capture (Watch) — Design

**Date:** 2026-08-12  
**Status:** Approved direction  
**Repos:** `amakaflow-ios-app` (Watch + phone Actuals)  
**Related:** AMA-2387 (Actuals fill-in), AMA-188 (CoreMotion reps), AMA-524 (sensor detect, stalled), AMA-286 (crown weight), AMA-2290 (StrengthBackfill)

## One sentence

Experimental Watch strength recorder: one-tap session start, auto-capture what motion/plan can reliably infer, then **fill out and correct on phone with the same Actuals map + fill-in system** — never silent irreversible invent.

## Problem

Apple Workout / Fitness cannot be remotely started from AmakaFlow. Users still need a fast gym path: start recording, get set-level detail without typing everything, then finish honesty in the same correction loop we already ship for Strava/Apple Health sessions.

## Product loop

```text
Pick Strength (experimental)
  → one-tap Watch HKWorkoutSession (traditionalStrengthTraining, indoor)
  → prefer Today’s planned workout when present
  → auto where confidence is high (session bounds, rest, complete-as-prescribed;
     later: work/rest + narrow rep assist)
  → uncertain / missing fields → phone Today Actuals fill-in (same AMA-2387 system)
  → verified → editor ghosts / Progress
```

### Correction surface (locked)

**Today Actuals fill-in** (AMA-2387 map + planned-vs-done), not a separate StrengthBackfill-only sheet.

StrengthBackfill patterns may seed UX, but the product system of record for post-session correction is Actuals.

## Non-goals (experimental v1)

- Remotely starting Apple Fitness / Workout.app
- Silent exercise identity or load inference from IMU as ground truth
- Irreversible auto-logs without confirm / fill-in path
- Persisting raw high-frequency IMU streams by default
- Marketing “exact exercise recognition for all movements”

## HealthKit vs AmakaFlow

| Layer | Owns |
|---|---|
| **HealthKit** | One `HKWorkout` per session: type, start/end, active energy, HR, source metadata. Optional events/segments later. |
| **AmakaFlow** | Exercise blocks, planned snapshot, per-set reps/load/RPE, `detectionMethod`, confidence |

```text
WorkoutSession (AmakaFlow)
  ├─ linked Library / plan id? (when started from Today)
  ├─ HKWorkout uuid / metadata
  └─ ExerciseBlock[]
       ├─ exerciseId / name
       ├─ plannedSets / plannedReps / plannedLoad
       └─ Set[]
            ├─ reps, load, unit
            ├─ RPE / RIR?
            ├─ startedAt / endedAt
            ├─ detectionConfidence
            ├─ detectionMethod: manual | autoConfirmed | inferred
            └─ IMU feature summary (optional; not raw stream)
```

## Activity type

- Default experimental strength start: `.traditionalStrengthTraining` + `.indoor`
- Later: `.functionalStrengthTraining` for circuits / kettlebell / bodyweight blocks
- Multi-activity segments only when a session truly switches modes (e.g. Hyrox) — out of v1

## UX principles

| Moment | Watch | Reliability |
|---|---|---|
| Before lifting | Show planned exercise + prescribed load/reps when plan known | High |
| Start set | Large Start set, or motion-onset (later) | High with manual start |
| Set ends | Infer rest; propose reps when confident | Moderate–high (narrow upper-body) |
| Confirm | “Back squat · 100 kg × 5” one-tap accept/edit (crown) | High after confirm |
| Rest | Countdown; next planned set | High |
| End | Finish one HKWorkout; sync draft sets → phone | High |
| After | Today Actuals: fill / correct / verify | High |

**Plan-first unlock:** when Today’s plan is known, constrain suggestions to the next prescribed movement — do not classify among hundreds of exercises.

Lower-body / machines: prefer **tap to start / tap to finish** set; automate rest, duration, HR context, next-set timer, adherence — do not pretend wrist IMU sees the squat.

## Build phases

### Phase 0 — Experimental gate
- Feature flag / Settings: **Experimental → Strength auto-capture**
- Off by default; copy discloses Watch AmakaFlow recorder (not Apple Fitness auto-start)

### Phase 1 — One-tap session start
- Expose Start on Watch Today when experimental flag on (freeform open always; prefer plan-linked when a synced strength workout matches)
- `HKWorkoutConfiguration`: `.traditionalStrengthTraining`, indoor
- `HKWorkoutSession` + builder collection; store **one** workout at end
- Reuse / extend `HealthKitWorkoutManager` + standalone engine; fix orphaned Start entry in live tab UI

### Phase 2 — Manual set logging (crown) + sync
- Port crown weight UI onto standalone Watch path (`WeightInputWatchView` patterns)
- Rest timer between sets
- Sync draft `set_logs` / Actuals draft on completion (not only phone-follow remote)
- Incomplete sessions still land on Today for fill-in

### Phase 3 — Auto-fill prescribed → one-tap complete
- Seed crown from planned load/reps
- “Complete as prescribed” one-tap when plan known
- `detectionMethod = autoConfirmed` after user accept

### Phase 4 — Work / rest boundary assist
- IMU state machine: IDLE/REST ↔ WORK SET
- Confidence-gated; low confidence → manual confirm
- Heart rate as effort/rest context only — not rep counting

### Phase 5 — Narrow rep assist + suggestion ranking
- Validated exercise family only (e.g. curls, presses, rows, swings)
- Candidate ranking + correction minimization; never silent commit below threshold
- Corrections feed labeled data for later models

## Relation to prior spikes

| Prior work | Role here |
|---|---|
| AMA-2387 Actuals | **Post-session correction system** |
| AMA-286 crown weight | Reuse on standalone |
| AMA-2290 StrengthBackfill | Patterns only; not the correction surface |
| AMA-525 FormFeedback | Later IMU / form cues; not MVP logging |
| AMA-524 detect | Pre-start schedule suggest — **out of this epic** |
| AMA-188 CoreMotion reps | Phase 5+ |

## Validation (high level)

- Flag off → no experimental Start path
- One HKWorkout per session; no per-set HKWorkout spam
- Confirmed sets round-trip into Actuals fill-in / verify
- Unconfirmed / inferred sets require fill-in before `verified`
- Plan-linked start prefers next exercise defaults
- No silent merge of exercise identity from motion alone

## Open follow-ups (not blocking Phase 0–2)

- ~~Freeform Strength open (no plan)~~ — shipped: Watch Today Start when flag on; Actuals fill-in still applies
- Functional strength / multi-sport segments
- Opt-in short-lived encrypted IMU debug samples for model eval
- Optionally WC-sync named workouts when pushing to Fitness so plan-linked Start has titles
