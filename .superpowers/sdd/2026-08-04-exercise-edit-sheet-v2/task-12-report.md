# Task 12 report — Visual / Maestro validation vs mockups

## Status

**DONE_WITH_CONCERNS** — Maestro flow authored and static mockup-parity checklist
completed via code inspection. Flow was **not executed on a physical device or
simulator** in this session; screenshot evidence and Linear attachment remain
human follow-up.

## Delivered

### Maestro flow

`e2e/maestro/ama-2379-edit-sheet-v2.yaml`

| Step | Coverage |
| --- | --- |
| 1 | Open Push-day editor → Bench Press sheet → `af_exsheet_target_range` (defaults 8–12) → `af_exsheet_done` → assert row `3 × 8–12` (en-dash) |
| 2 | Re-open → `af_exsheet_target_open` → Done → assert `3 × OPEN` |
| 3 | Re-open → `af_exsheet_rest_open` → cycle all five `af_exsheet_target_*` chips → assert `af_exsheet_rest_open_caption` / `af_exsheet_rest_duration` unchanged |
| 4 | Triceps Pushdown → screenshot each TARGET kind + SETS/REST grid (`docs/ama-2379-visual-evidence/`) |

Auth scaffold matches ama-2372 visual flows (`AF_SESSION_IDENTITY`,
`AF_SKIP_ONBOARDING`, `AF_USE_FIXTURES`).

### Static mockup-parity checklist

Reference: Task 11 brief (`SGEditSheet` / `hifi/screens-editsheet.jsx`) and
implemented `EditorV2EditSheet.swift`. Compared against task-11 acceptance
criteria (not legacy `screens-editor2.jsx` focused sheet, which predates TARGET
family).

| Area | Mockup / spec expectation | Code (`EditorV2EditSheet.swift`) | Static pass | Needs on-device capture |
| --- | --- | --- | --- | --- |
| **Reps** | TARGET chip selected; SETS left (1fr); REPS stepper right (1.35fr); 72pt cells | `proportionalGrid` ratio `1 / 2.35` vs `1.35 / 2.35`; `stepperCell` min/max height 72; `af_exsheet_reps` | Yes | Chip selected state, stepper typography |
| **Range** | Single card REPS MIN \| MAX (not floating link); reads as one card | `rangeCell` — shared `card2` background, 1px divider, `af_exsheet_range_min` / `_max` | Yes | Divider alignment, min/max tap targets |
| **Timed** | WORK stepper ±10s, floor 10 | `step: 10`, `min: 10`, `formatSeconds` for display, `af_exsheet_work` | Yes | `0:40` vs `40s` formatting at sub-minute values |
| **Cals** | CALORIES stepper ±5, floor 5 | `step: 5`, `min: 5`, `af_exsheet_calories` | Yes | Stepper label casing vs mockup |
| **Open** | Amber card: “Open goal — NO TARGET — GO TILL READY · END ON TAP” | `openGoalCell` amber fill/stroke, copy matches, `af_exsheet_open_goal` | Yes | Amber opacity/stroke vs design rig |
| **TARGET row** | Full-width segment: Reps · Range · Timed · Cals · Open | `ForEach(EditorV2EditTargetKind.allCases)` + `af_exsheet_target_*` | Yes | Chip padding/selected invert colors |
| **Live summary** | Same string as row after Done | `summaryDraft.summaryLine` under title | Yes | Mono 9.5pt line break on long rest suffix |
| **SETS + REST** | SETS always left; REST Open/Timed unchanged (AMA-2368) | `showsRestEditor`; `af_exsheet_rest_open` / `_timed` / `_duration` / `_open_caption` | Yes | Open caption wrapping at narrow widths |
| **Done** | Full-width capsule | `af_exsheet_done`, `DailyDriver.foreground` capsule | Yes | Bottom safe-area padding |
| **Row commit** | Range → `3 × 8–12`; Open → `3 × OPEN` | Covered by `PrescriptionDisplayTests` + Maestro asserts | Yes (unit + flow) | En-dash glyph on device font |

### Human follow-up (Task 12 brief steps 4–5)

- [ ] Run Maestro on simulator/device:
  `maestro test e2e/maestro/ama-2379-edit-sheet-v2.yaml`
- [ ] Attach five TARGET screenshots + SETS/REST grid to Linear AMA-2379 and PR
- [ ] Confirm Range card reads as **one** surface (no visual gap between MIN/MAX)
- [ ] Confirm SETS + REST grid does not shift when switching TARGET kinds

## Concerns

- **No on-device Maestro run** — flow is syntactically aligned with sibling
  ama-237* visual YAML but unverified against a built Companion binary.
- **Screenshot paths** — `takeScreenshot` targets
  `docs/ama-2379-visual-evidence/`; directory is created at run time by Maestro,
  not checked in.
- **iOS 26 tab bar** — flow taps `"Library"` by label (ama-2374 pattern) when
  `library_tab` id is hidden; confirm on target OS version.

## Verification (this session)

- Maestro YAML follows ama-2372 launch/nav scaffold and af_exsheet_* IDs from
  `EditorV2EditSheet.swift` and `EditorV2Tests.testEditSheetTargetAccessibilityIdentifiersAreStable`.
- Static checklist derived from Task 11 brief + Swift implementation review.
- Maestro **not executed** (no simulator/device in agent environment).
