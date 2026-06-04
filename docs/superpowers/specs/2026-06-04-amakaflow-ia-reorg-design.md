# AmakaFlow IA Reorg — Surface hidden features + a Connections hub (Option B)

**Status:** DESIGN SPEC — awaiting David's review (brainstorming gate). No implementation until approved.
**Date:** 2026-06-04 · **Scope:** iOS app (`amakaflow-ios-app`) · in-between reorg (Option B), tabs unchanged.

## Problem
Everything that isn't a tab is crammed into **Profile → Settings** ("Control center") as one long list — Notifications, Voice, Fatigue, Nutrition, Social/Activity, Training prefs, Equipment, **Sync Dashboard**, Shoe comparison, **Devices/pairing**, **Telegram/Messaging**, calendar sync, Debug, legal. A new user can't discover how to connect Telegram, pair a device, or find sync status; legacy web-app-sync settings linger. It reads as one undifferentiated pile.

## Decision (David, 2026-06-04): Option B — Grouped Settings + a Connections hub
Validated against real feature-dense apps (Mobbin): **IKEA Home smart** (Settings hub w/ "Connected 🟢" + "Integrations · all your smart stuff in one place"), **Komoot** ("favorite devices": Garmin/Apple Health + brand grid), **Open** ("Connect Apple Health/Strava/Oura"), **Flighty→TripIt** (per-connection detail: Status ● Connected · Disconnect · what-it-does), **Clay/Alfread** (inline status), **MyFitnessPal/Viator** (grouped sections). B is the convergent best-practice; no better pattern surfaced.

### Screens
1. **Profile (reorganized)** — same screen, split from one dump into clear, named sections:
   - **Connections** (hub card, top) — see #2.
   - **Profile & Training** — Edit profile (goals/experience/sessions), Training preferences, Equipment.
   - **Coaching** — Readiness sources, Fatigue threshold, Notifications · Voice cues.
   - **Nutrition & Activity** — Nutrition, Activity/Social.
   - **App** — Debug & diagnostics (KEPT), Account · privacy · export · sign out.
2. **Connections hub** — status-bearing rows (IKEA/Open pattern): Apple Watch (● Connected), Garmin (Connect →), Telegram/Messaging (Off →), Sync & delivery (● Healthy), Calendar (Connect →). Each shows a one-line "what it does" + live status.
3. **Per-connection detail** (Flighty pattern) — Status (● Connected / Off) · Connect/Disconnect · one-line purpose. Reuse the existing screens behind these entries (Devices/Pairing, Telegram setup, Sync Dashboard, Calendar) — this is a re-entry/re-grouping, not a rewrite of those screens.

### Removed / kept
- **Remove** the legacy web-app-sync rows. ⚠️ **CONFIRM WITH DAVID** which exact rows — code scan didn't definitively identify them (`CalendarSyncView` is Google/Outlook calendar sync, possibly still wanted). Removal candidates list to be ticked by David before build.
- **Keep** Debug & diagnostics (its own "App" section).
- Shoe comparison / Activity feed: **default keep** in Profile (Nutrition & Activity / Profile & Training) unless David says move/cut.
- **Home setup-nudges (Option C):** deferred — not in this pass; can layer later.

## Design system (match, don't reinvent)
Recreate using the existing hi-fi tokens from the Claude Design bundle (`amakaflow-mvp-design-refresh`): **Geist / Geist Mono**, `--radius` 10/6/14, oklch dark/light surfaces, readiness scale (lime/amber/coral), pill `.af-btn`, `.af-label` mono eyebrows. The bundle already contains a Devices/Pairing screen + settings flow in this language — the new Profile/Connections screens extend it.

## "Keep a copy we validate against" — design artifact
Produce an **updated hi-fi design artifact** for the new screens (Profile grouped + Connections hub + per-connection detail), matching `tokens.css`/`ui.jsx`, added to the design package (`amakaflow-mvp-design-refresh/project/hifi/screens-connections.jsx` + wired into `AmakaFlow Hi-fi.html`) and committed to the repo (e.g. `amakaflow-docs/design/` or `docs/design/`). This is the visual source-of-truth the implemented Settings is validated against. (We can't push back to claude.ai/design; the in-repo hi-fi is the canonical copy.)

## Implementation outline (iOS) — for the plan/prompt after approval
- Restructure `SettingsView` from section-cards-of-everything into the 5 named groups above; add a **`ConnectionsHubView`** (status rows) as the top entry.
- Per-connection detail: route the existing `SyncDashboardView`, Telegram setup, `PairingScreen`/Devices, `CalendarSyncView` under the Connections hub with a consistent status/connect/disconnect header.
- Remove confirmed legacy rows; keep `DebugSettingsView`/`DebugLogView`.
- Status sourcing: derive connection status from existing VMs (devices paired, Telegram linked, sync health, calendar connected) for the chips/rows.
- A11y ids on the new rows; UI test that the Connections hub + each section render and the legacy rows are gone.

## Validation
Implemented Settings matches the hi-fi artifact; Telegram/Devices/Sync are reachable in ≤1 tap from Profile via Connections; no legacy web-sync rows; Debug intact.

## Open items for David
1. **Which exact rows are the legacy web-sync ones to delete?** (blocking the removal list)
2. Shoe comparison / Activity feed — keep (default) or move/cut?
3. Confirm: defer Home setup-nudges (Option C) to a later pass? (default yes)

## Out of scope
Tab-bar changes; rewriting the underlying Devices/Telegram/Sync/Calendar screens (only their grouping/entry); Option C Home nudges; backend changes.
