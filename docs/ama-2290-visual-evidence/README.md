# AMA-2290 visual evidence — phone strength record + backfill

**What we're testing:** Phone strength record → Today → fast manual backfill; watch optional; no AI gate.

| File | Meaning |
| --- | --- |
| `01-start-phone.png` / `01-phone-player.png` | Start sheet → Phone selected (Watch try unreachable = optional) |
| `01b-player-running.png` | Phone player running with no Watch |
| `02-backfill-ui.png` | Post-stop Session recorded + Log sets (AI optional) + Watch-optional HR copy |
| `03-backfill-ready-to-save.png` | Same backfill surface — Save & Done commits without AI |
| `04-today-phone-source.png` | Today diary shows Phone-sourced rows (Garmin + Phone fixtures) |

## Auth path used

`UITEST_CLERK_TEST_SESSION` + `UITEST_SKIP_ONBOARDING=true` + `UITEST_USE_FIXTURES=true` + `UITEST_SKIP_APPLE_WATCH=true` (+ `UITEST_FIXTURES=emom_strength` for Library EMOM seed).

## Reuse

- `WorkoutEngine` (deferred strength save) + `WorkoutPlayerView` + `WorkoutCompletionModule.savePhoneCompletion`
- `StrengthBackfill` / `StrengthBackfillView`
- Today refresh via `.workoutCompleted` → `ActivityHistoryViewModel`
- Fixture diary append: `FixtureAPIService.recordPhoneCompletion`

## Unit proof

`StrengthBackfillTests`: phone start→complete→Today; backfill round-trip; empty weights OK; `requiresAppleWatch == false`; `requiresAISuggestions == false`.

## Out of scope

Amazfit, Apple try (AMA-2287), friction log (AMA-2288), Garmin rework.

## Re-run

```bash
maestro --device <SIM_UDID> test e2e/maestro/ama-2290-visual-strength-backfill.yaml
```
