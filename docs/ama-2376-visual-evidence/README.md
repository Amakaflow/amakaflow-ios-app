# AMA-2376 visual evidence — Library collections, organize mode, pin, detail chips

Captured on iPhone 17 Pro Max Simulator (iOS 26.1) via Maestro:
`e2e/maestro/ama-2376-library-collections.yaml`

| File | Screen |
| --- | --- |
| `01-library.png` | Library home — Collections grid (`+ New`) + Uncategorized + On your watches (flat Results only when filtering; screenshot may be stale until re-captured) |
| `02-add-workouts.png` | Collection → "Add workouts" picker, 2 fixtures selected |
| `03-organize-move.png` | Organize mode, multi-select, Move to / Pin / Remove bar |
| `04-pinned.png` | Destination collection after move, pinned row (pin glyph) |
| `05-detail.png` | Workout detail — Pin active, `RACE WEEK` membership chip, `+ Add` |

## ⚠️ Reinstall / local-first known loss

Collections, collection membership, and pins are **local-only GRDB tables**
(`workout_collections`, `workout_collection_members`, `pinned_workouts` — v3
migration, Task 1). There is **no backend sync** for any of this data today.

- Uninstalling the app, or clearing simulator/device state (`clearState: true`
  in this Maestro flow, or a real user deleting + reinstalling AmakaFlow),
  **permanently deletes every collection, membership, and pin** — same
  local-first tradeoff as `LocalFirstStorageTests` elsewhere in the app.
- This is why the Maestro flow creates its own "Hyrox Prep" / "Race Week"
  collections from a clean launch every run rather than depending on
  pre-seeded state — there is nothing durable to seed.
- Worth flagging before this ships to real users: today there is no warning
  in-app that reinstalling wipes collections/pins, and no export/backup path.

## Checks vs mockups

Mockups: `1 · LIBRARY — PINNED + COLLECTIONS`, `2 · COLLECTION — HYROX PREP`,
`3 · ORGANIZE MODE — MULTI-SELECT`, `4 · ADD TO COLLECTION — FROM DETAIL`,
`5 · DETAIL — COLLECTIONS + PIN`.

| What we're testing | Mockup | Screenshot | Match |
| --- | --- | --- | --- |
| Library home — Collections grid + `+ New` | #1 | `01-library.png` | **Strong** — grid, card collage, `+ New` chip in the right place. Mockup also shows a `PINNED` row above Collections; not exercised in this flow (no pins yet at that point) but implemented per Task 5/`af_pinned_section`. |
| Create named collection ("Hyrox Prep") | #2 | `03-organize-move.png` header | **Strong** — title, workout count + duration meta line, `Organize`/`Done` toggle. |
| Add workouts picker (multi-select + count) | #4 (detail variant) | `02-add-workouts.png` | **Strong** — checkmark rows, live `Add (2)` count. Mockup's version is the *detail* "Add to collection" sheet, not the collection's own picker — both exist in this build (Task 6 vs Task 7) and both work; this flow exercises the collection-side one per the task brief. |
| Organize mode — multi-select + action bar | #3 | `03-organize-move.png` | **Strong** — `N SELECTED · DESELECT ALL`, green check rows, `Move to / Pin / Remove` bar. **Found + fixed a real bug here**: see "Bug found & fixed" below — the action bar was unreachable before the fix. |
| Pin persists across collections | #1/#3 (pin glyph) | `04-pinned.png` | **Strong** — pin glyph next to the workout name matches mockup's pin treatment. |
| Detail — Pin / Collect / To watch / Share + chips | #5 | `05-detail.png` | **Strong** — active (lime) Pin tile, `RACE WEEK` chip with `×`, `+ Add` chip, `Edit`/`Start` footer all match. Mockup's `Uncategorized` grey chip variant not shown here (single real-collection membership in this run) but implemented (`af_detail_collection_chip_*`). |
| Remove one collection chip from detail | #5 (implied) | n/a (asserted, not screenshotted) | **Pass** — tapping the chip's `×` removes the `RACE WEEK` chip; verified via `assertNotVisible` in the flow. |

Overall: functional behavior is a **strong match** to the mockups once the
chrome-overlap bug below is fixed. No mockup screen shows the app's floating
tab bar on the Collection/Organize screens (mockups are chrome-less full
bleed), which turned out to be the correct intent — see below.

## Bug found & fixed: Organize bar / "Add workouts" was unreachable

While wiring this Maestro flow, `Move to` / `Pin` / `Remove` (Organize mode)
and the `+ Add workouts` footer in `CollectionDetailView` were **completely
untappable** — not a Maestro flakiness issue, a real one. `CollectionDetailView`
was missing the `.ddSuppressFloatingChrome()` modifier that every other
pushed detail screen uses (`UnifiedWorkoutDetailView`, `DDActivityDetailView`,
etc.), so the app's global floating tab bar rendered **on top of** its
bottom-pinned action bar/footer and physically intercepted every tap in that
region — confirmed by bounds inspection (`maestro hierarchy`): both elements
occupied the same `y` range at the bottom of the screen. A real user tapping
"Add workouts" or any Organize action would have hit the tab bar underneath
instead (in one repro this popped all the way back to the `Today` tab).

Fix: added `.ddSuppressFloatingChrome()` to `CollectionDetailView` (one line,
same established pattern as the other 7 screens already using it) —
`AmakaFlow/Views/Library/CollectionDetailView.swift`. Rebuilt, reinstalled,
and re-ran the full flow; all steps pass. This also matches the mockups,
which never show the tab bar on this screen.

## Known testability quirk (not a functional bug)

Several AMA-2376 header/toolbar buttons share a SwiftUI body with an ancestor
container that also sets its own `accessibilityIdentifier` (e.g.
`af_collection_new`, `af_collection_organize`/`af_collection_done`,
`af_collection_add_workouts`, `af_organize_move`/`pin`/`remove`,
`af_add_to_collection_new`/`done`, `af_workout_pick_add`,
`af_detail_collection_chip_*_remove`). On this iOS/XCUITest build, the
child's identifier collapses to the ancestor's, so Maestro `id:` lookups for
those specific buttons don't resolve — confirmed via `maestro hierarchy`
(the button's `resource-id` reports the parent's id, not its own). Visible
text/labels are unaffected, and real users are unaffected (this is an
XCUITest-tree-only artifact). The flow works around it by tapping those by
`text:` instead of `id:` (documented inline in the YAML); ids that live in
their own child `View` struct (cards, member rows, add-to-collection rows,
detail action tiles) resolve correctly and are used normally.

## Watch door preserved

The AMA-2375 "On your watches" row/door (`af_library_watch_door` /
`af_library_on_your_watches_row`) is untouched by this work. It renders above
Results when filtering; otherwise Collections sit above On your watches with no
flat list. `01-library.png` may be stale until re-captured. Not re-tested
end-to-end here (out of scope for this task); confirmed present and visually
unchanged.

## Fixture notes

- Fixtures used: `fixture-hiit-001` ("HIIT Follow-Along", Instagram) and
  `fixture-strength-001` ("Strength Block W1D1", Coach) — both from
  `AmakaFlow/Resources/Fixtures/`.
- "Move to" after create-and-move does **not** show the toast (`showToast`
  is only wired for `Remove`, not `Move`) — the flow asserts the emptied
  source list instead of a toast for that step.
