# AMA-2291 visual evidence

**What we're testing:** Library → one detail for any source; Start chooses gym + device (Garmin default when paired); Edit always works; social credit row links out.

| File | Meaning |
| --- | --- |
| `01-detail-social.png` | Instagram-sourced workout unified detail (credit row + Edit/Start) |
| `02-start-sheet-garmin-default.png` | Start sheet with gym + Garmin/Apple/Phone; Garmin Default when `UITEST_GARMIN_PAIRED` |
| `03-edit-open.png` | Edit opens structure editor (AI never gatekeeps) |
| `04-detail-manual.png` | Manual-sourced workout same detail chrome |

## Auth path used

`UITEST_CLERK_TEST_SESSION` + `UITEST_SKIP_ONBOARDING=true` + `UITEST_USE_FIXTURES=true` + `UITEST_GARMIN_PAIRED=true`.

## Re-run

```bash
maestro --device <SIM_UDID> test e2e/maestro/ama-2291-visual-detail-start.yaml
```
