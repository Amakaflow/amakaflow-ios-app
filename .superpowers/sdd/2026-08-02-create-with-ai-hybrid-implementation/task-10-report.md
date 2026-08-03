# Task 10 report — ViewModel staged generate and refine stack

## Status

Extended `SuggestWorkoutViewModel` with cancellable generation tasks, draft snapshots,
refine history and Undo, full rerolls that clear tweaks, and an applying state for the
Create with AI refine dock. Refine requests compose notes through the 1,000-character
prompt cap and retain duration, focus, and generated `includeContext` flags.

The ViewModel now stores `whyThis` from each response, restores it with Undo, and maps
HTTP 429 failures to the approved `CreateWithAICopy.rateLimited` CTA copy. Create with
AI no longer renders the Daily Coach “Rest today” action.

## Tests

- Focused `SuggestWorkoutViewModelTests`: passed on iPhone 17 / iOS 26.1 simulator.
- Added coverage for refine notes cap, include-context passthrough, Undo restoration,
  reroll history clearing, `whyThis`, and friendly HTTP 429 copy.
- `git diff --check`: passed.
- IDE lint diagnostics on changed Swift files: no errors.

## Notes

- Xcode emitted existing Swift concurrency and missing Sentry upload-token warnings;
  the focused test command exited successfully.

## Review fix round 1

- Changed prompt composition to reserve space for the newest full tweaks, trimming
  the ask head and dropping older tweaks when necessary. `appliedTweaks` now contains
  only tweaks present in the notes sent to the API.
- Added a generation version guard around profile, readiness, suggestion, onboarding,
  success, empty, error, and refine-applying publications so cancelled or superseded
  requests cannot overwrite newer state.
- Added red/green regressions for long ask + newest tweak retention, cancellation after
  delayed profile/suggestion responses, and a stale profile response arriving after a
  newer successful generation.
- Focused `CreateWithAICopyTests` and `SuggestWorkoutViewModelTests`: passed on iPhone
  17 / iOS 26.1 simulator.
