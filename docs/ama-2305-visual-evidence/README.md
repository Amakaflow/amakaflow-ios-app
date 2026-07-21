# AMA-2305 visual evidence — Check the structure

**What we're testing:** After every social import, the app shows the ADR-017 clarify step before save. Suggestions are confirmable; Describe round-trips `structure/apply`; Leave flat / Save never persist unconfirmed inferred structure.

| State | Design ground truth | Pass looks like |
| --- | --- | --- |
| Import landing | Panel 1 of `rig-clarify-states.png` | Header "Check the structure", SUGGESTED groups, Confirm all, Leave flat + Looks right — Save |
| Describe sheet | Panel 2 | Sheet title "Describe the structure", example chips, Apply to workout |
| Note applied | Panel 3 | FROM YOUR NOTE tags on regrouped blocks + same Confirm affordance |

Simulator screenshots from the fidelity loop should be added beside this README as `01-import-landing.png`, `02-describe-sheet.png`, `03-note-applied.png`.

Maestro scaffold: `e2e/maestro/ama-2305-visual-structure-clarify.yaml`
