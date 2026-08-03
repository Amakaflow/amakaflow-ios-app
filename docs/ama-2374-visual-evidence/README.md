# AMA-2374 visual evidence — Watch preview + Start parity

Captured on iPhone 17 Simulator (iOS 26.1) via Maestro:
`e2e/maestro/ama-2374-visual-watch-preview-parity.yaml`

| File | Screen |
| --- | --- |
| `01-start-session.png` | Start session |
| `02-enhance-sheet.png` | Make it watch-ready? |
| `03-watch-preview.png` | To your Apple Watch (bands) |
| `04-watch-preview-cta.png` | Schedule on the watch + Back |

## Match vs AMA-2369 redesign mockups

| Screen | Match | Remaining gaps |
| --- | --- | --- |
| **Watch preview** | **Strong** — `Mobility prep` / `Barbell back squat` · `5 SETS`; rest chips on the right; no WORK/WARM-UP cards; CTA + Back | Meta line lacks `· ~12 MIN`; step details are shorter (`8 REPS` vs `8 REPS · LIGHT`) |
| **Start session** | **Strong** — This phone / Apple Watch / Garmin; SCHEDULE / FIT PUSH; chevrons; lime/blue chips | Section headers left-aligned (rig centers them); fixture gym pill shows `24hr Katy` |
| **Enhance** | **Good** — Make it watch-ready?, toggles, Open rest, Add N & send, Send as-is | Offer order Rest before Warm-up sets; missing “YOU END REST ON THE WATCH” hint next to Open rest |

## Fixture notes

- Enrich stub returns a complete applied summary (AMA-2363 gate).
- `MapperWorkoutKitPlanProvider` uses `AppDependencies.current.apiService` (was hard-coded to live `APIService.shared`).
- Fixture `mapToWorkoutKit` returns Jump Rope + WU + working-sets shape so banding can be dogfooded offline.
