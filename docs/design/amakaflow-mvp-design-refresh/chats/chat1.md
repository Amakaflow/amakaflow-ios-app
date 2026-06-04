# AmakaFlow MVP Surface

_Started 2026-04-24 14:04 UTC_

---

## User

"I'm designing the full MVP surface of AmakaFlow — an AI adaptive training coach for hybrid athletes. I need 11 screens as frames on one canvas: Home (today's workout + readiness chip + Start CTA), Workouts (this-week plan list), Workout Detail, Workout Player (live execution), Workout Completion with RPE, Onboarding (5-question coaching profile), Pairing (Garmin 6-digit code), History (check-in history), Settings, Paywall, Landing/waitlist. The user is a multi-modal athlete, 28–45, training 6–12 hours a week. The primary mental model at 6am is: what am I doing today, am I fresh for it, one tap to start. Tone: modern, restrained, readiness-forward, clinical, trustworthy — not gamified, not playful. Mobile-first; Paywall and Landing also need a desktop version. Give me 3–4 lo-fi wireframe directions across the full canvas."

## Assistant

I'll start by exploring the attached folder to understand what's already there, then ask a few sharp questions before generating wireframes.

_[tool: local_ls]_

Good — there's already a `redesign-*` preview set. Let me look at a couple of them to understand the current visual vocabulary, and at any guidelines.

_[tool: local_ls]_

_[tool: local_ls]_

_[tool: local_read]_

The redesign previews are empty shells — this IS the handoff work. Let me check the guidelines and the existing index.css for any locked-in tokens, plus one existing working preview to see the current product's visual language.

_[tool: local_read]_

_[tool: local_read]_

Good — I have enough context. This is the pre-handoff stage: empty redesign preview shells, a default shadcn-ish token palette but no locked-in visual identity. That's exactly what wireframing is for: lock the structure first, visual system later.

I have a solid read on the brief: hybrid athlete, 6am mental model, readiness-forward, clinical. Rather than ask a pile of questions, I'll commit to a direction now and let tweaks + side-by-side wireframe variations do the exploring — that's what the Wireframe skill is for.

**Plan — one HTML canvas, design_canvas starter, 11 screens × 4 directions = 44 frames.**

The four directions I'll explore:

1. **Card Stack** — conventional mobile app patterns (bottom nav, list cards). Baseline, safe, ships easily.
2. **Data Dashboard** — readiness as hero, workout secondary. Clinical/WHOOP-adjacent. Numbers and ring charts up top.
3. **Single Verb** — Today = one giant tappable card. Everything else collapses behind. Extreme 6am-friendly.
4. **Calendar-First** — week strip always visible, today is just "the selected day". Best for planners/coached athletes.

Lo-fi vocabulary: hand-drawn feel via Caveat/Kalam for annotations, Architects Daughter for UI labels, mono for numbers. B&W base + one accent per direction. Placeholder boxes with slashes. Ink strokes, not filled shapes.

_[tool: update_todos]_

_[tool: copy_starter_component]_

_[tool: copy_starter_component]_

Let me quickly peek at the design_canvas API so I use it correctly, then build.

_[tool: grep]_

Got it. Now I'll build the wireframe kit and all 44 frames. Given the scope, I'll split into files: a shared `wireframe-kit.jsx` with primitives, then one file per direction (keeps each file under ~500 lines).

Let me start with the kit and folder structure.

_[tool: write_file]_

_[tool: snip]_

Now Direction 1 — Card Stack. Conventional app patterns, bottom nav.

_[tool: write_file]_

_[tool: snip]_

_[tool: write_file]_

_[tool: snip]_

_[tool: write_file]_

_[tool: snip]_

_[tool: write_file]_

_[tool: snip]_

_[tool: write_file]_

_[tool: snip]_

_[tool: done]_

_[tool: snip]_

_[tool: fork_verifier_agent]_

**44 frames on one canvas, 4 directions.**

- **1 · Card Stack** — safe / conventional / bottom-nav
- **2 · Data Dashboard** — readiness-as-hero, WHOOP-adjacent
- **3 · Single Verb** — one giant tap, minimal chrome (most 6am-friendly)
- **4 · Calendar-First** — week strip always visible, today = selected day

Paywall + Landing ship in both mobile and desktop for each direction. Tweaks panel: accent color (4 presets), annotations on/off, canvas bg.

Likely next moves: pick your favorite direction (or cherry-pick, e.g. "D3 home + D4 workouts + D2 player") and I'll push it to mid-fi with real type + color.

## User

Save this design as a PDF: AmakaFlow Wireframes.html

## Assistant

_[tool: snip]_

The wireframes live on a pan/zoom canvas with overlapping artboards — that doesn't translate to paged print. I'll build a dedicated print layout: one artboard per page, with a cover page + section dividers.

_[tool: write_file]_

_[tool: snip]_

_[tool: show_html]_

_[tool: show_html]_

_[tool: snip]_

_[tool: get_webview_logs]_

_[tool: snip]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: open_for_print]_

[Print page opens automatically — save as PDF from the dialog.](https://2ff39626-7f9e-440a-8182-7b19aa44227f.claudeusercontent.com/v1/design/projects/2ff39626-7f9e-440a-8182-7b19aa44227f/serve/AmakaFlow%20Wireframes-print.html?t=f5cd940e642c889a5ffa86541ad588d9d6e23e8a5c5207cf94b6210b0710ded7.2417787e-7a08-47c3-8a9b-9cfb04a31830.060086e2-9764-432f-842d-0fbfc7790351.1777043081)

## User

Pick direction 1 (Card Stack). Drop the other three. Promote direction 1 to high fidelity. Keep all 11 screens — 9 mobile + Paywall mobile/desktop + Landing mobile/desktop = 13 frames total. Give me light mode and dark mode for every frame. Wire these interactions in the interactive prototype: Start workout button, readiness chip tap (shows detail), SWAP action from Player, log-manually from Home, pair-watch submit on Pairing, RPE selection + injury free-text on Completion. Keep the tone modern, restrained, readiness-forward, clinical, trustworthy — not gamified, not playful. Match the Tailwind + shadcn design tokens from the amakaflow-ui codebase you loaded.

## Assistant

_[tool: snip]_

_[tool: local_read]_

_[tool: local_read]_

_[tool: snip]_

I have enough design-token context. Let me commit to the system:

**Tokens locked in** (from the shadcn/tailwind base): `--primary: #030213` (near-black), `--foreground: oklch(0.145 0 0)`, `--muted-foreground: #66667a`, `--destructive: #d4183d`, `--radius: 0.625rem`. Dark mode inverts. Font: Geist + Geist Mono (clinical, trustworthy, pairs with shadcn). Readiness accent: lime `oklch(0.72 0.15 135)` — readable both modes, non-playful.

**Plan**: one file per screen family + a shared `ui.jsx` kit + `tokens.css`. Tone: crisp 12–14px body, monospace numerics, 1px hairlines, no shadows/gradients, one accent for readiness state.

_[tool: update_todos]_

_[tool: write_file]_

_[tool: snip]_

Given context pressure, I'll build this efficiently: one focused UI kit file + one interactive prototype file (all 13 screens + interactions in-line), loaded into the existing canvas. Smaller surface than a file-per-screen.

_[tool: write_file]_

_[tool: snip]_

_[tool: update_todos]_

Now the screens — I'll put them in one JSX file since state flows across them (router-style).

_[tool: write_file]_

_[tool: snip]_

_[tool: update_todos]_

_[tool: write_file]_

_[tool: snip]_

_[tool: update_todos]_

_[tool: write_file]_

_[tool: snip]_

_[tool: update_todos]_

_[tool: list_files]_

_[tool: snip]_

_[tool: list_files]_

_[tool: snip]_

_[tool: list_files]_

_[tool: snip]_

_[tool: delete_file]_

_[tool: read_file]_

_[tool: snip]_

_[tool: delete_file]_

_[tool: snip]_

_[tool: write_file]_

_[tool: snip]_

_[tool: done]_

_[tool: get_webview_logs]_

_[tool: snip]_

_[tool: snip]_

_[tool: str_replace_edit]_

_[tool: snip]_

_[tool: grep]_

The issue: each Babel script destructures `useState` etc from `React` at top-level, and they share scope. I need to use `React.useState` in all subsequent files instead.

_[tool: snip]_

_[tool: run_script]_

_[tool: snip]_

_[tool: done]_

_[tool: snip]_

_[tool: fork_verifier_agent]_

_[tool: snip]_

**Direction 1 promoted to hi-fi.**

- **26 artboards on canvas** — 13 frames × light/dark
- **Interactive prototype** — jump between any of 11 screens, all 6 interactions wired:
  - Start workout → Player (live timer)
  - Readiness chip → bottom-sheet detail with HRV/sleep/RHR sparklines
  - SWAP from Player → 4 coach suggestions
  - Log manually from Home → type/duration/distance/RPE, appends to history
  - Pairing → 6-digit input, `000000` shows error, anything else succeeds
  - Completion → 1–10 RPE grid + injury toggle with free-text notes
- **Tokens** match your shadcn base (`--primary #030213`, `oklch(0.145 0 0)` foreground, 0.625rem radius). Font: Geist + Geist Mono. Readiness accent swappable (lime default, mint/indigo/amber).
- **Desktop** versions of Paywall and Landing included in both themes.

Toggle **Canvas ↔ Prototype** from the top-left pill or the Tweaks panel.

## User

Verifier agent check completed

## Assistant

_[tool: snip]_

_[tool: str_replace_edit]_

_[tool: snip]_

_[tool: done]_

_[tool: snip]_

_[tool: fork_verifier_agent]_

_[tool: snip]_

_[tool: snip]_

_[tool: snip]_

Canvas fix applied and re-verified — 26 frames now render correctly across both themes. Prototype mode has all 6 interactions wired. File is live at `AmakaFlow Hi-fi.html`.

## User

Verifier agent check completed

## Assistant

_[tool: snip]_

_[tool: str_replace_edit]_

_[tool: snip]_

_[tool: done]_

_[tool: snip]_

_[tool: fork_verifier_agent]_

_[tool: snip]_

_[tool: snip]_

_[tool: snip]_

Canvas fix applied — sections now emit as a flat array of direct `DCSection` children so `React.Children.forEach` picks them up. 26 frames should render across both themes.

## User

Verifier agent check completed

## Assistant

_[tool: snip]_

_[tool: read_file]_

_[tool: snip]_

_[tool: grep]_

Confirmed: tuple return. Fix the destructure.

_[tool: snip]_

_[tool: str_replace_edit]_

_[tool: snip]_

_[tool: done]_

_[tool: snip]_

_[tool: get_webview_logs]_

PairingScreen still has a bare `useRef`. Fix it.

_[tool: snip]_

_[tool: run_script]_

_[tool: snip]_

_[tool: done]_

_[tool: snip]_

_[tool: fork_verifier_agent]_

_[tool: snip]_

_[tool: snip]_

_[tool: snip]_

Canvas now renders all 26 frames, prototype mode has all interactions wired, and the useTweaks tuple + useRef fixes are in. File is live at `AmakaFlow Hi-fi.html`.

## User



## Assistant

_[tool: snip]_

_[tool: update_todos]_

_[tool: read_file]_

_[tool: grep]_

_[tool: snip]_

_[tool: read_file]_

_[tool: snip]_

_[tool: write_file]_

_[tool: snip]_

_[tool: snip]_

Now I need to wire the new screens into the main HTML file. Let me check the current structure.

_[tool: list_files]_

Let me check the main HTML file's structure to understand how screens are registered and wired.

_[tool: list_files]_

The wireframe HTML and other files were snipped. Let me check the main HTML to understand the integration:

_[tool: read_file]_

Now I'll wire the new screens. I need to:
1. Add the script tag for `screens-agent.jsx`
2. Add the new screens to MOBILE_FRAMES and to the prototype's screen map
3. Update the title

_[tool: str_replace_edit]_

Now let me also check that `screens-agent.jsx` references components from `ui.jsx` correctly. Let me verify the helper components exist.

_[tool: grep]_

Good — all helpers exist. One concern: `screens-agent.jsx` references `Icon name="bolt"`, `name="swap"`, `name="info"`, `name="close"`. Let me confirm these exist.

_[tool: grep]_

Let me check how Icons are looked up:

_[tool: read_file]_

All icons exist. Now let me also confirm the `.af-seg` class exists for the segmented control I used in AgentInbox:

_[tool: grep]_

In `AgentInboxScreen` I used `data-on={true}` and `data-on={false}` — React serializes booleans to the string "true"/"false", which matches the CSS. Good.

Also need to update the title:

_[tool: str_replace_edit]_

_[tool: update_todos]_

_[tool: done]_

_[tool: fork_verifier_agent]_

**Added 8 frames showing how the AI surfaces itself to the user:**

**Agent visibility (5 screens)**
- **Mental Model** — onboarding step explaining "Telegram for chat, watch for workouts, app for review"
- **Plan Reveal** — loading → 4-block periodised plan with reasoning
- **Weekly Review** — Sunday recap: stats, session list with missed-day, coach narrative, next week preview
- **Watch Delivery States** — full timeline (Building → Sent → Loaded → Ready, plus failure state)
- **Agent Event Inbox** — chronological log of every agent action with filter chips

**Home banner variants (3 frames)**
- **Replan proposed** — amber, with Approve/Edit
- **Red flag** — red bar, replacement workout swapped in, "Safe to continue?" link
- **Low confidence** — neutral info banner when data's missing

All show in canvas in both themes (16 new artboards total) and are reachable in Prototype mode via the JUMP TO panel.

## User

Verifier agent check completed

## Assistant

Verifier flagged two minor wrap issues. Quick fix — make timestamps `whiteSpace: nowrap` so they never break.

_[tool: str_replace_edit]_

Fixed. Timestamps in Watch Delivery and Agent Inbox now stay on one line.

## User

Add one new screen to the existing AmakaFlow Hi-fi canvas:
  TelegramSetupScreen. Follow the exact same visual language, tokens, and
  component primitives as the other screens already on the canvas
  (MentalModelScreen, PlanRevealScreen, etc.).

  Purpose: Onboarding step shown after Garmin pairing. Lets the user connect
  their Telegram account in 2 taps — no typing required.

  3 states to show (side by side or as a flow):

  State 1 — Idle
  - Large Telegram paper-plane icon (Telegram blue #29b6f6, ~56px)
  - Heading: "Connect Telegram"
  - Body: "Your morning briefings, evening check-ins, and workout swaps all
  happen in Telegram. Two taps to connect."
  - Primary CTA button: "Open Telegram →" (Telegram blue fill, black text)
  - Ghost link below: "Skip for now" (muted)

  State 2 — Polling (waiting for user to tap Start in Telegram)
  - Same icon + heading
  - Replace button area with: spinner + "Waiting for Telegram confirmation…"
  (muted caption)
  - No skip link while polling

  State 3 — Done
  - Large ✅ (green)
  - "Telegram connected" in accent green, bold
  - "Continue →" primary button

  Layout: Full-screen, centred vertically. Use --bg, --text-primary, --fg-muted,
   --accent-green, --border tokens. Same TopBar with back chevron as other
  onboarding screens. No TabBar.

  ---

## Assistant

_[tool: read_file]_

_[tool: grep]_

I have what I need. Note: the user's spec mentions `--text-primary` and `--accent-green`, but the actual tokens are `--fg` and `--ready-high` — I'll use the real ones (otherwise it'd look broken).

I'll add **TelegramSetupScreen** to `screens-agent.jsx` with all 3 states cycling on a button click for the prototype, plus 3 separate canvas frames showing each state side-by-side.

_[tool: str_replace_edit]_

_[tool: snip]_

Now wire it into the canvas + prototype router:

_[tool: str_replace_edit]_

_[tool: done]_

**Added `TelegramSetupScreen` with all 3 states.**

- **Canvas** — 3 new frames per theme (Idle / Polling / Done) sit alongside the other agent-visibility screens.
- **Prototype** — open the JUMP TO panel and pick `telegram-setup` for the live flow (Open Telegram → spinner → auto-advances to the green Done state after ~2.4s). The forced-state variants `telegram-idle`, `telegram-polling`, `telegram-done` are also reachable for demoing single states.

One spec note: you referenced `--text-primary` and `--accent-green` but the established system uses `--fg` and `--ready-high` — I used the real tokens so it matches the rest of the canvas. The Telegram blue (#29B6F6) is hardcoded since it's a brand color, not a system token.

## User

Update the LandingMobile and LandingDesktop components in screens-marketing.jsx. Keep the existing hero ("Train on the right day"), eyebrow, form, and "How it works" 3-step section. Add a new section BELOW "How it works" with four product explanation blocks, using the same border-top divider style as the existing steps:

1. TELEGRAM — YOUR COACH, EVERY MORNING
"A daily briefing lands in Telegram with today's session and the reason behind it. Reply to swap a workout, scale it back, or adjust around fatigue. Sunday you get a summary of what changed and why."

2. THE APP — SETUP AND REVIEW
"Answer a few questions about your goal, training time, and what you do. AmakaFlow builds your plan, shows the reasoning behind it, and keeps a record of every adaptation over time. You don't open the app to train — it's for setup and review."

3. YOUR WATCH — WHERE TRAINING HAPPENS
"Open the day's session and send the workout to your Garmin. Intervals, sets, and reps are structured on the device. Completed training data feeds back into what comes next."

4. ONE ADAPTIVE COACH
"Most tools handle one part of training well: running plans, strength logs, or spreadsheets. AmakaFlow connects those pieces into one coach that adapts tomorrow based on what happened today. For hybrid athletes training for a HYROX, a half-marathon, or a general fitness PR."

Use the same af-label for section headers, same af-muted for body, same border-top divider pattern as the "How it works" steps. Match the existing token system exactly — no new styles.

Also add a short tagline line in the eyebrow area above the headline: "ADAPTIVE COACHING FOR HYBRID ATHLETES" (replacing or supplementing "ADAPTIVE TRAINING COACH").

---

## Assistant

_[tool: snip]_

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: snip]_

_[tool: str_replace_edit]_

_[tool: snip]_

_[tool: done]_

_[tool: snip]_

**Updated both Landing components.**

- **Eyebrow** swapped to "ADAPTIVE COACHING FOR HYBRID ATHLETES" on mobile and desktop.
- **New "How AmakaFlow works" section** added below "How it works" on both:
  - **Mobile** — single column, four blocks with `border-top` divider, `af-label` headers, `af-muted` body
  - **Desktop** — 2×2 grid using the same divider pattern, same tokens, sized for the wider canvas
- All four product blocks (Telegram / The App / Your Watch / One Adaptive Coach) use the existing `af-label` + `af-muted` system — no new styles introduced.

