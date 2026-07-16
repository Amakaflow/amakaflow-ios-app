# design-handoff/ — Claude Design → code, the repeatable way

> **Docs copy** — canonical source lives in `amakaflow-docs` PR
> [#40](https://github.com/Amakaflow/amakaflow-docs/pull/40) /
> `design/amakaflow-mvp-design-refresh/daily-driver-handoff/`. Keep both in sync via the
> refresh pipeline below. Ticket: AMA-2293 (parent AMA-2272).

This folder is the ONLY design input agents (Cursor, Claude Code, anyone) should use.
Never point an agent at the raw Claude Design export — it contains dead designs
(AmakaFlow Hi-fi*, screens-v2/v3/…) that agents gravitate to.

## Contents

| Path | What | Why |
|---|---|---|
| `screenshots/` | Rendered PNGs of all 13 screens (dark) + 3 light samples | Visual ground truth — agents match pixels, not vibes |
| `DESIGN.md` | CSS→SwiftUI token map (exact hex from oklch), type scale, shapes, effects | Translation decisions made once, not per-screen |
| `SPEC.md` | Per-screen layout, states, interactions, known proto bugs | What to build beyond the static pixels |
| `reference/` | `screens-daily-driver.jsx` + `tokens.css` + `ui.jsx` — exact prototype source | Court of last resort for any ambiguous value |

Cursor enforcement: `.cursor/rules/design-fidelity.mdc` (auto-attaches on View files).

## Refresh pipeline (when the design changes in Claude Design)

Design source: Claude Design project `2ff39626-7f9e-440a-8182-7b19aa44227f`,
file `Daily Driver Proto.html` + `hifi/{screens-daily-driver.jsx,tokens.css,ui.jsx}`.
Current snapshot etag: `1784219904920586` (2026-07-16).

1. **Pull current files** via the claude-design MCP (`read_file`) — NOT the browser
   Export ZIP (it can surface stale screenshots). Compare etags to see what changed.
2. **Re-render screenshots**: serve the export folder (`python3 -m http.server`),
   use the `rig.html` trick — patch the proto so `?screen=dd-X&theme=dark` sets initial
   state — and capture each screen. (Claude Code does steps 1–2 automatically; ask it
   to "refresh the design handoff".)
3. **Diff `tokens.css`** against `DESIGN.md`; update the token map if values moved.
4. **Update `SPEC.md`** for changed screens only (etag diff tells you which).
5. Commit the folder; UI work resumes against the new ground truth.

## Verification loop (every screen implementation)

Build in simulator → screenshot → side-by-side vs `screenshots/dd-<screen>-dark.png`
→ list differences → fix → repeat until they match. This loop, not the first attempt,
is what produces fidelity.
