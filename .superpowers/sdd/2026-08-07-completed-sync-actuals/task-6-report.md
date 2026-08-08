# AMA-2387 — Task 6 report: Merge engine (local model)

**Status: CODE DONE**

## Built
- `ActualsSessionModels` — `ActualsSourceRecording`, `ActualsSession`, roles, sticky `ActualsMergeMemory`
- `ActualsMergeClassifier` — certain (±2 min + shape / external refs), uncertain ask, separate; watch>phone + richest primary; Split full restore
- `ActualsMergeAskCard` — Same session? Merge / Keep both (a11y IDs)
- `ActualsMergedDetailView` — provenance list + Not the same? Split
- Tests: `ActualsMergeClassifierTests`

Note: domain types use `ActualsSession*` to avoid clashing with `PlanningModels.CompletedSession`.
