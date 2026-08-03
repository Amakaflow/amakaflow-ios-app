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
