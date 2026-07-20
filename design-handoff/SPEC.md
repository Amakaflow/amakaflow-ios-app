# Daily Driver — Screen & Interaction Spec

> Read alongside `DESIGN.md` (tokens) and `screenshots/` (ground truth pixels).
> Source of record for anything ambiguous: `reference/screens-daily-driver.jsx`
> (line refs below point into that file). IA per AMA-2272 Daily Driver scope:
> 3-tab layout, one workout format, gym/device chosen at Start time.

## Global shell

- **3 tabs**: Today · Library · Profile — floating "tab island" (radius 32, 12pt from
  screen edges, dark translucent + blur). Active tab = lime icon + label.
- **Global ＋ FAB** (lime, glowing) floats above the island on tab screens → opens the
  **Create sheet**.
- **Toasts**: dark pill, bottom-center, auto-dismiss 2s. Used liberally for feedback
  ("Logged — RPE 8", "On your T-Rex 3 ✓").
- Prototype stubs (`"would open…"` toasts) mark intentionally-unbuilt edges — treat as
  out of scope, don't invent flows for them.

## Screens

### 1. Today (`dd-today-dark.png`, jsx L129)
Completed-only diary — **no scheduling, no planned hero, no Start button**. The day
fills itself from Strava/Garmin pulls, watch sessions, phone sessions.
- Header: "Today" (32/800) + device pill (readiness dot + watch icon + battery %) → Device screen.
- Week strip: M–S with dot = trained; today boxed. Tap past day → (stub) day diary.
- Timeline rail: icon circle (34pt, colored by activity type) + connector line; cards show
  time range, title, mono stats (duration/cal/BPM), source chip ("IMPORTED FROM STRAVA").
- Card actions: **Log RPE** (amber text) → RPE sheet (10-chip grid) → toast + lime "RPE n ✓";
  unrecognized session → **"What was this?"** (amber) → Activity detail.
- System events render as plain rail rows ("GARMIN SYNCED · 2 ACTIVITIES PULLED", "DAY STARTED").
- Footer hint: "Sessions land here as they happen — or add one with ＋."

### 2. Create sheet — the 4 doors (jsx L251)
Bottom sheet from FAB: **Import from URL** (paste → animated processing steps →
"Imported ✓ — review & save" → Workout detail) · **Build from scratch** → Editor(new) ·
plus 2 more doors (voice/scan per jsx). Cancel closes.

### 3. Library (`dd-library-dark.png`, jsx L459)
- Header "Library" + small ＋ (also opens Create sheet).
- Search field; filter chips: All (lime when active) / Instagram / TikTok / Manual / Coach.
- Workout cards: 58pt gradient thumbnail w/ type icon, title (15/700), meta line
  ("8 blocks · 45 min · by you"), source chip color-coded (MANUAL gray, INSTAGRAM purple,
  TIKTOK cyan w/ play glyph, COACH amber). Tap → Workout detail.

### 4. Profile (`dd-profile-dark.png`, jsx L1122)
- Header: avatar (lime circle, initial), name, program line ("Hyrox prep · Week 3 of 12"),
  gear → Settings.
- 2×2 stat tiles: sessions this week (n/5 lime) · training time · day streak 🔥 · month sessions.
  Tiles tap → expand week list / stub toasts.
- Weekday completion dots (M/T lime when trained).
- **Insight banner** (amber-tinted card): "Monday's strength needs weights — 2-minute
  backfill" → Editor(backfill). Disappears once `backfilled`.
- "This week" list: session rows w/ icon chip, mono meta (day · duration · RPE · source),
  big right-aligned stat (5.1 KM / 21 MIN). Rows reflect state (run appears after RPE logged).

### 5. Settings (`dd-settings-dark.png`, jsx L1384)
Grouped disclosure cards, each w/ colored icon chip (38pt): My Gyms (orange) → Gym detail ·
Connected wearables (green) → Device · Connected apps (blue) · App (purple) ·
Account & data (gray). Row count badge right; chevron expands rows inline.

### 6. Device (`dd-device-dark.png`, jsx L2135)
- Status line: "● CONNECTED · SYNCED 2M AGO" (lime mono) · Title "Amazfit T-Rex 3".
- Battery hero: giant lime "78%" + "enough for tonight".
- **Queue**: delivered item (lime check) vs **failed item** (red X, red-bordered card,
  reason text, "Fix in editor →" button).
- "Sessions on this watch": per-type toggle rows (Hyrox/HIIT on, Runs off, …) with copy
  explaining fallback to phone/other watch.

### 7. Player (`dd-player-dark.png`, jsx L1985)
Full-bleed follow-along on phone: header "HYROX SIM · ON PHONE · NO WATCH NEEDED" +
collapse chevron · "BLOCK 3 OF 8" label · exercise name (28+/700) · reps (blue) ·
**giant lime mono block timer (~64pt)** · "NEXT · ROWER — 500 M" · 8-segment block
progress bar. Bottom sheet: elapsed (amber mono) + ♥ HR (red), prev/next circles,
64pt lime pause button, "End workout".

### 8. Gym detail (`dd-gym-dark.png`, jsx L1457)
Back link "‹ My Gyms" · title + location mono · **Shared gym card** (lime-tinted): member
sync copy, toggle, last-update mono line · lime XL pill "Set as active gym" · equipment
sections (FREE WEIGHTS / MACHINES / CARDIO & CONDITIONING) as filled chips; missing gear =
dashed "+ EZ bar" chips (tap adds).

### 9. Workout detail (`dd-detail-dark.png`, jsx L1638)
Media hero (gradient, play glyph, close X) w/ overlay chips ("FROM INSTAGRAM · 5 ROUNDS ·
~20 MIN · HIIT") · title + description · creator row (avatar, "Workout by gospelofgainz",
"Open in Instagram" pill) · block sections ("Round 1–3" + right-aligned mono summary) with
exercise rows (icon, name, mono reps/load, muscle tag) · sticky bottom bar: ghost "✎ Edit" +
glowing lime "▶ Start" → **Start sheet** (jsx L378: On phone → Player · Push to watch →
1.4s "pushing" → toast "On your T-Rex 3 ✓" · Send to Garmin via FIT).

### 10. Activity detail (`dd-activity-dark.png`, jsx L1796)
For pulled-but-unlinked activities: back "‹ Today" · icon chip + title + mono meta ·
**amber "Not linked to a workout yet" banner** · 4 stat tiles (KM/MIN/CAL/AVG BPM) ·
HR zones card (♥ "Most time in Zone 3", stacked zone bar Z1–Z5 w/ % labels) · lime XL
"Map to a workout" + ghost "Add details manually". Matched variant shows linked workout instead.

### 11. Editor — SUPERSEDED for edit/import/new (2026-07-20, ADR-017)
> The block-accordion editor below now applies to **backfill mode only**
> (`dd-editor-backfill-dark.png`). Edit, post-import fix-up, and create-from-scratch
> use **Editor v2** (§13) per ADR-017. The `dd-editor-dark.png` / `dd-editor-import-dark.png`
> / `dd-editor-new-dark.png` screenshots are historical — do not build from them.

#### 11-legacy. Old editor (`dd-editor-backfill-dark.png`, jsx L703)
Shared: back, COLLAPSE/EXPAND ALL, title, "DEFAULT REST 60S · APPLIED UNLESS OVERRIDDEN",
block cards with **left color spine + type chip** (CIRCUIT green / ROUNDS green / AMRAP
amber / FOR TIME purple / SETS gray — full type menu: Circuit·EMOM·AMRAP·Tabata·For Time·
Sets·Superset·Rounds·Warm-up·Cool-down), exercise rows (reorder carets, name, mono
"REPS · KG · REST", edit/remove icons), dashed "+ Add exercise" / "+ Add block", glowing
lime save bar.
- **edit**: existing workout ("Save workout").
- **new**: placeholder title, block-type picker sheet open first.
- **import**: "⚠ 2 SWAP SUGGESTIONS" (amber) — equipment-aware rows: "No barbell — swap to
  DB thrusters 2×16?" + amber **Swap** pill.
- **backfill**: pre-filled from program ("LAST TIME" values), CTA "Save log" → toast
  "Weights saved to Monday's log" → Profile.

### 12. Check the structure — import clarify step (`rig-clarify-states.png`, `reference/screens-clarify.jsx`) — AMA-2305
Every social import (URL / screenshot / voice) lands HERE between the processing
animation and save. Decision + rationale: `amakaflow-docs/decisions/ADR-017-structure-intervene-and-calm-editor.md`.
- Header: "Check the structure" + honest subline ("grouping was implied, not stated"),
  provenance card (creator avatar chip, "@TRAINWITHSMEE · REEL CAPTION PARSED",
  lime "✓ Confirm all (N)" when pending > 0).
- **Suggested groups**: card per group, left spine in structure color, amber
  `SUGGESTED · SUPERSET` mono tag, member rows with A1/A2 (superset) or station numbers,
  footer: lime **✓ Confirm** + gray **Undo**. Confirm → tag flips lime `SUPERSET ✓`,
  footer becomes "SAVES AS A SUPERSET BLOCK" + Ungroup. Undo dissolves to flat rows.
  Circuits carry an inline `− ×N ＋` rounds stepper.
- **Flat rows**: checkbox circle, name, mono summary, `NOT GROUPED` tag. Select 2+ →
  chip bar slides in: `Superset` / `Circuit ×4` / Cancel (1 selected = chips at 40%
  opacity + "PICK ANOTHER TO GROUP THEM").
- **"Not right? Describe it"** dashed door → sheet: helper copy, 3-row textarea,
  tappable example utterances, **Apply to workout** (disabled when empty) →
  ~1.3s "Reading your note…" spinner (lime arc) → sheet closes, list regroups, affected
  groups get blue `FROM YOUR NOTE · <TYPE>` tags + same Confirm affordance.
- Footer dual CTA (detail-screen anatomy): dark "Leave flat" + lime glowing
  "Save · N blocks ✓" (or "Looks right — Save" at 0 confirmed). Above it, honesty line:
  "Unconfirmed groups save as a flat list — we never guess silently."
- Rules: inferred structure is NEVER persisted unconfirmed; "Leave flat" is a valid
  confirmed answer; re-labeling replaces, never stacks. Provenance = the UI face of
  `structure_source` (explicit / inferred / user_confirmed / user_note / unknown).

### 13. Editor v2 — calm list (`rig-editor2-*.png`, `reference/screens-editor2.jsx`) — AMA-2307
Replaces the block accordion for edit / import fix-up / creation (Hevy pattern,
Mobbin-verified — see ADR-017). One structure model shared with §12: colored rail +
pill label, same type colors.
- **Exercise card**: name + mono summary + ⋯ ONLY (max 2 tap targets per row).
  Tap body → focused edit sheet; tap ⋯ → verb menu.
- **Groups**: pill row above the run (`SUPERSET A` colored pill + `4 ROUNDS · 3 MIN REST`
  mono meta + sliders icon, whole row tappable) over a railed card containing member rows.
- **⋯ menu** (sheet, one verb per row, icons): Reorder exercises / Replace exercise /
  Add to superset ↔ Remove from superset (contextual) / Add a set / Remove exercise (red).
- **Superset picker**: "Superset <X> with:" list of other exercises → tap → src moves
  adjacent to target, joins (or creates) the superset. Toast confirms.
- **Focused edit sheet**: only that exercise's fields as big steppers
  (Sets/Reps/Distance/Weight/Rest — whichever are non-nil). Done.
- **Group config sheet**: "RUNS AS" type chips (Superset·Circuit·EMOM·AMRAP·Tabata·For
  time) + only that type's steppers (EMOM=Minutes; AMRAP/For time=Cap min;
  Tabata=Work/Rest/Rounds; Superset=Rounds+Rest; Circuit=Rounds) + Done +
  "Ungroup — back to straight sets".
- **Reorder mode** (header `⇅ Reorder` ↔ `✓ Done`): list collapses to compact rows
  (name + group label + grip icon, left spine keeps group color), drag-and-drop,
  lime Done. No persistent reorder chrome anywhere else.
- **Creation (mode=new)**: empty state "Start with any exercise" + defaults copy +
  optional "KNOW THE FORMAT ALREADY?" chips (EMOM/AMRAP/Tabata/For time/Circuit).
  Chip → pins a format group pill + dashed "Timing's set — add the moves" placeholder;
  subsequent adds land inside as plain reps. No chip → adds land flat as 3×10 · 60s.
  Add-exercise sheet: search, equipment-aware rows (barbell = amber "NOT IN YOUR GYM"),
  "＋ Create <query>", defaults footnote, "Done adding" once non-empty.
- **Guards**: never ask block type before the first exercise; rest is captured as
  seconds (intent) ONLY — no timed/lap-button toggle (open question on AMA-2300);
  backfill keeps the legacy editor (§11-legacy).

## State model (prototype)

`{ push: planned|pushing|onwatch|done|logged, runRPE: null|1–10, backfilled: bool,
createOpen: bool, toast: string|null, detailId, activityId }` — Today, Profile, and
Device all react to it (logged RPE adds the run to Profile's week list; backfill kills
the insight banner and adds a lifting session).

## Known prototype bugs (do NOT replicate)

- Light-theme Profile: stat values invisible (white-on-white) — see `dd-profile-light.png`.
- FAB overlaps last list item on scrollable screens; give lists 96pt bottom padding
  (proto does this via `ScreenPad`) so content clears it.
