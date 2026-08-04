# AmakaFlow Daily Driver — Design Token Map (Web → SwiftUI)

> **Ground truth**: `screenshots/*.png` (rendered from the Claude Design prototype).
> `reference/` holds the exact source: `screens-daily-driver.jsx` + `tokens.css` + `ui.jsx`.
> **Rule zero: match the screenshot, not your taste. Never invent a color, font size,
> radius, or spacing value that is not in this file or the reference source.**
>
> Source project: Claude Design "AmakaFlow MVP Design Refresh"
> (`claude.ai/design/p/2ff39626-7f9e-440a-8182-7b19aa44227f`), file `Daily Driver Proto.html`.
> Snapshot etag: `1784219904920586` (2026-07-16). Only `screens-daily-driver.jsx`,
> `tokens.css`, `ui.jsx` are current — every other file in the original export
> (`screens-v2/v3/main/agent/...`, `AmakaFlow Hi-fi*.html`) is an OLD design. Ignore them.

## Visual voice (from the design brief in the JSX header)

True black · one loud lime accent · Poppins-class rounded display type ·
glowing pill CTAs · media cards with creator credit · colorful icon chips ·
floating tab island with center ＋ FAB.

## Typography

| Role | Web | SwiftUI |
|---|---|---|
| Display (`.dd-display`: titles, tab labels, card titles, big numbers) | Poppins 500–800, letter-spacing −0.02em | Bundle **Poppins** (SemiBold/Bold/ExtraBold). `Font.custom("Poppins-Bold", size:)` + `.kerning(-0.02 * size)` |
| Body / UI | Geist 400–700 | **SF Pro** (system font) — acceptable stand-in; bundle Geist only if parity review fails |
| Numerics, timestamps, labels (`.af-mono`, `.af-label`) | Geist Mono, tabular numerals | `.monospaced()` / SF Mono with `.monospacedDigit()` |

Type scale (from reference; px ≈ pt):
- Screen title: 32 / weight 800 (Poppins)
- Player block timer: ~64 mono lime
- Card title: 15 / 700 (Poppins)
- Body: 13 / 400; secondary meta: 10.5–11 mono muted
- Micro-label / source chip: 8.5–10 mono UPPERCASE, letter-spacing 0.08em
- Tab label: 10 / 600 (Poppins)

## Color — dark theme (primary; converted from oklch, exact)

| Token | Value | SwiftUI asset name |
|---|---|---|
| Canvas behind phone (web only) | `#050506` | — (not used in app) |
| `bg` (screen background) | `#0A0A0A` | `ddBackground` |
| `bg-subtle` | `#121212` | `ddBackgroundSubtle` |
| `bg-elev` (tab bar base, sheets) | `#171717` | `ddBackgroundElevated` |
| `fg` | `#FAFAFA` | `ddForeground` |
| `fg-muted` | `#A4A4A4` | `ddForegroundMuted` |
| `fg-dim` | `#696969` | `ddForegroundDim` |
| `border` | white @ 9% | `ddBorder` |
| `border-str` | white @ 16% | `ddBorderStrong` |
| `input/chip/accent bg` | `#1F1F1F` | `ddInputBackground` |
| **`ready-high` — THE lime accent** | `#7AB953` | `ddLime` |
| `ready-mod` (amber) | `#E0AF3B` | `ddAmber` |
| `ready-low` (coral) | `#E95048` | `ddCoral` |
| `destructive` | `#D4183D` | `ddDestructive` |

DD palette (hard-coded in `screens-daily-driver.jsx`):

| Token | Value | Use |
|---|---|---|
| `DD.ink` | `#0D1200` | Text/icons **on** lime (FAB glyph, CTA labels) |
| `DD.card` | white @ 5.5% | Timeline/list card fill |
| `DD.card2` | white @ 9% | Chip fill inside cards |
| `DD.blue` | `#5AB8F4` | Icon chip — runs |
| `DD.orange` | `#F4A24A` | Icon chip — misc |
| `DD.purple` | `#C58AF4` | Icon chip — AMRAP/power |
| `DD.red` | `#F4564A` | Icon chip — intensity |
| Tab island fill | `rgb(16,16,18)` @ 96% + blur | `.ultraThinMaterial`-style over content |

Light theme exists (`tokens.css [data-theme="light"]`) but **dark is the product voice**;
implement dark first. Known proto bug: light Profile stat values are invisible — do not copy.

## Shape & effects

| Element | Value |
|---|---|
| Card radius | 16 (timeline cards) / `--radius` 10 (base cards) / 14 lg / 6 sm |
| Buttons & chips | Fully rounded (Capsule) |
| Tab island | radius 32, floats 12pt from edges, shadow `0 10 30 black@55%` |
| FAB | 56×56 circle, lime, 25pt plus glyph in `DD.ink`; sits above tab bar (right 18, bottom 92) |
| **Lime glow** (FAB, primary CTAs) | web: `0 0 22px lime@60% + 0 6px 18px black@50%` → SwiftUI: `.shadow(color: ddLime.opacity(0.55), radius: 11)` + `.shadow(color: .black.opacity(0.5), radius: 9, y: 6)` |
| Readiness dot halo | 8pt dot + 3pt ring of its color @ 18% |
| Icon chips | size 38 (radius ≈ 29% of size = 11), white glyph at 47% of size |
| Hairlines | 1pt `ddBorder` |

## Components (see `reference/ui.jsx` + `screens-daily-driver.jsx`)

`af-btn` pill buttons (sm 6×12/12pt · md 10×16/13 · lg 14×20/15 · xl 18×24/16, pressed scale 0.985) ·
cards · chips · segmented control · switch (36×20, knob 16) · RPE grid (10 cells, square, radius 8) ·
bottom sheet (top radius 20, drag handle 36×4) · timeline rail (34pt icon circle + 2pt connector line) ·
progress bar 3pt.

## Screen inventory → screenshots

| Screen | File | Notes |
|---|---|---|
| Today (tab 1) | `dd-today-dark.png` | Completed-only diary timeline; week strip; device pill |
| Library (tab 2) | `dd-library-dark.png` | Search, source filter chips, media cards w/ creator credit |
| Library collections (AMA-2376) | (rig) `screens-collections.jsx` | Collection detail title **21pt heavy Poppins**; meta **9pt mono**; pinned **11pt**; grid card **14pt** + mono caption — see SPEC §3 |
| Profile (tab 3) | `dd-profile-dark.png` | Stat tiles, weekday dots, insight banner, week list |
| Settings | `dd-settings-dark.png` | Grouped disclosure cards w/ colored icon chips |
| Device detail | `dd-device-dark.png` | Battery hero, queue w/ failed state, per-type toggles |
| Player | `dd-player-dark.png` | Block timer (giant lime mono), bottom control sheet |
| Gym detail | `dd-gym-dark.png` | Shared-gym card, equipment tag groups |
| Workout detail | `dd-detail-dark.png` | Media hero, creator row, block list, Edit/Start bar |
| Activity detail | `dd-activity-dark.png` | Unlinked-activity mapping, stat tiles, HR zone bar |
| Editor (edit/new/import/backfill) | `dd-editor-*.png` | Block cards w/ colored type chips; import = swap suggestions; backfill = Save log |

Interaction states live in `SPEC.md`.
