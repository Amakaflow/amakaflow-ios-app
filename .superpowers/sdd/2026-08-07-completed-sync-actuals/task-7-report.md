# AMA-2387 — Task 7 report: Map-to-plan

**Status: CODE DONE**

## Built
- `ActualsPlanMatcher` — scores scheduled-time / duration / distance / type / HR shape; WHY fragments (`SAME START`, `DISTANCE FITS`, `HR SAYS TEMPO`, …)
- `ActualsMapToPlanView` — activity header + stats, "Which workout was this?", ranked candidates, Search all, keep-as-is
- a11y: `af_actuals_map_candidate_<n>`, `af_actuals_map_keep_as_is`
- Tests: `ActualsPlanMatcherTests`
