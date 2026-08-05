# MOTION.md — DD Motion v1 (AMA-2383)

> Ticket: [AMA-2383](https://linear.app/amakaflow/issue/AMA-2383/dd-motion-v1-it-writes-itself-build-animation-watchimportai-toast)
> Spec of record: `amakaflow-docs/docs/superpowers/specs/2026-08-05-dd-motion-v1-design.md` (PR #63)
> Reference source: `reference/screens-motion.jsx` (build engine) · `reference/screens-toast.jsx` (toast)
> Live rigs (watch them, don't guess): [build](https://claude.ai/design/p/2ff39626-7f9e-440a-8182-7b19aa44227f?file=hifi%2Frig-motion.html) · [toast](https://claude.ai/design/p/2ff39626-7f9e-440a-8182-7b19aa44227f?file=hifi%2Frig-toast.html)
> Frames: `screenshots/rig-motion-landed.jpg` · `screenshots/rig-toast-variants.jpg`

Two deliverables: a **build reveal** ("it writes itself") for anything that gets composed, and **DD Toast** for every action confirmation. Read the reference JSX for exact values — this file is the CSS→SwiftUI translation.

## 1. Motion tokens — implement ONCE as `MotionTokens`

| Token | CSS (reference) | SwiftUI |
| --- | --- | --- |
| fast / base / slow | 160 / 280 / 420 ms | `Double` constants |
| easeOutQuart | `cubic-bezier(.25,1,.5,1)` | `.timingCurve(0.25, 1, 0.5, 1, duration:)` |
| spring | `cubic-bezier(.34,1.4,.64,1)` | `.spring(response: 0.35, dampingFraction: 0.8)` |
| toastSpring | — | `.spring(response: 0.32, dampingFraction: 0.72)` |
| buildStagger | 130 ms/beat | per-beat delay |

**No magic numbers in views.** Every animation in this ticket references `MotionTokens`.
**Reduce Motion**: all entrances become fade-only; text wipes render instantly; the build reveal is skipped entirely (full content immediately). Gate on `@Environment(\.accessibilityReduceMotion)`.

## 2. Build reveal engine

Reference: `SMBuildScreen` in `reference/screens-motion.jsx`. Script-driven: an ordered list of beats, kinds `band | row | bullet | credit | pills`. Rows nest under the last band. One beat reveals every `buildStagger` ms.

Per-beat choreography (see `sm-*` keyframes in the rig's `<style>`):
- **band**: slide up 10px + fade, base/easeOutQuart
- **row**: container slide 10px (260ms quart); **number pops** (scale .4→1, 320ms spring); **detail line wipes left→right** — `clip-path: inset(0 100% 0 0) → inset(0)` over 500ms quart, +120ms delay. SwiftUI: mask a `Rectangle` whose width animates 0→full (linear width anim under quart timing). This wipe is the "being written" read — do not replace with a plain fade.
- **chip**: pop (spring), +280ms after its row
- **counter**: `COMPOSING… n OF m` + blinking lime caret (`▍`, 0.7s steps). Counts rows+bullets only, not bands.
- **auto-scroll**: newest row kept in view (`scrollTo` bottom, smooth). Verify no layout thrash.
- **CTA**: rendered from t=0 but disabled/dim with the building verb ("Composing…"); on done → 350ms color transition to lime + one glow pulse (`sm-cta-land`: translateY 14→0 spring, shadow swells then settles). Never tappable before done.

### Surfaces + verbs

| Surface | iOS view | Verb | Beat source |
| --- | --- | --- | --- |
| Apple Watch preview | `AppleWorkoutKitPreviewSheet` | COMPOSING | **Scripted** (data local) — cap total ≤2s |
| Reel import result | import result/detail view | PARSING | Beat per parsed block; credit card beat FIRST, amber SWAP chips pop with their rows |
| Create-with-AI draft | `SuggestWorkoutView` (createWithAI mode, AMA-2373) | DRAFTING | **One beat per SSE chunk** — the animation IS progress. WHY THIS bullets beat before blocks. Falls back to scripted if response arrives whole |

**Honest-progress rule:** never animate slower than the data; never show a beat for content that hasn't arrived.

## 3. DD Toast

Reference: `TTHost` in `reference/screens-toast.jsx`; motion in rig `tt-*` keyframes.

Anatomy: top-center capsule, 54pt below top (tune for Dynamic Island); `rgba(24,24,27,0.97)` bg, border, 999 radius, shadow; 26pt icon chip + bold 13pt line + optional 8pt mono sub + optional trailing action.

Motion: **in** 320ms toastSpring from y −24 + fade · **hold** 1800ms (4000ms when an action button present) · **out** 240ms rise −18 + fade. **Queue of one** — later toasts wait; no stacking.

| Variant | Chip | Copy pattern |
| --- | --- | --- |
| success | lime + check (icon pops) | `Saved to Library` / sub `CHEST PUMP — 45 · IN UNCATEGORIZED` |
| device | blue + watch | `Sent to Garmin` / sub `OPEN THE AMAKAFLOW WIDGET TO DOWNLOAD`; `On your Apple Watch` / sub `WORKOUT APP · 11 STEPS · 8 SLOTS FREE` |
| undo | amber + ⊗, amber `Undo` action | `Removed from watch` / sub `LIBRARY UNTOUCHED` |
| **push morph** | spinner → check crossfade | phase 1 `Sending to Garmin…` (never auto-dismisses); on API resolve → morph in place to success (or error with the real reason) → then hold+out |

Architecture: single `ToastHost` at app root; call sites publish `ToastEvent`s (event bus / environment object). **Replace every legacy bottom-toast call site** (save, push, schedule, remove, undo, collection ops). A11y: VoiceOver announces the resolved state only.

## 4. Acceptance (visual gate)

- Frame-sample the build at ~0.4s (mid-write: caret + a half-wiped line visible) and ~3s (lime CTA landed) — must match `screenshots/rig-motion-landed.jpg` anatomy.
- Push toast under a mocked 900ms delay shows the spinner phase, then morphs — never shows success first.
- Reduce Motion: full content instantly, fade-only toasts.
- 60fps on oldest supported device.
