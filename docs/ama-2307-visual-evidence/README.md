# AMA-2307 visual evidence — Editor v2

**What we're testing:** Daily Driver Edit / New / post-import fix-up use the calm Editor v2 (flat cards, structure pills, ⋯ menus, focused sheets, reorder mode, format-first creation). Backfill keeps the legacy editor. Matches design-handoff `rig-editor2-*.png` + ADR-017.

| Surface | Simulator: Library → workout → Edit; FAB → New; import → Edit; Profile → backfill |
| Linear | AMA-2307 — iOS editor v2 |
| Ground truth | `00-rig-comparison-ground-truth.png`, `00-rig-creation-ground-truth.png` |

| What we're testing | Why | Click / check | Pass looks like |
| ----- | ----- | --- | ----- |
| Flat cards | Calm density | Open Edit | Name + summary + ⋯ only |
| Structure pill | Shared with clarify | Tap pill | Runs-as sheet; type colors match clarify |
| ⋯ verbs | Parity with old editor | Each menu item | Action completes; list updates |
| Focused edit | One exercise | Tap card body | Steppers; Done updates summary |
| Reorder mode | No persistent chrome | ⇅ Reorder → drag → Done | Compact rows; exits clean |
| Create | Format-first | FAB → New → add / chip | No upfront block question |
| Format chip | Pins group | EMOM chip → add | Adds land inside blue rail |
| Backfill | Don’t break logging | Profile backfill path | Legacy accordion still |

## Unit evidence

`xcodebuild … -only-testing:AmakaFlowCompanionTests/EditorV2Tests` → **TEST SUCCEEDED** (group/ungroup, format chip, reorder, structure_source export, max-controls invariant).

## Simulator fidelity loop

Capture Debug screenshots beside this README as:

- `01-edit-calm-list.png`
- `02-ellipsis-menu.png`
- `03-focused-edit.png`
- `04-reorder-mode.png`
- `05-create-empty.png`
- `06-add-exercise-sheet.png`
- `07-emom-first.png`
- `08-backfill-legacy.png`

Side-by-side vs the two rig PNGs; iterate until match.
