# iOS MVP — Real-device test runbook (v2, derived from code)

> **Why v2:** the original AMA-1751 runbook was written from spec on 2026-05-03
> and assumed buttons/flows that don't exist in the shipped app
> ("push to Garmin button", web parity, Calendar tab, Social tab). This
> version is derived from `Core/FeatureFlags.swift` and the actual
> `Views/` source on develop on 2026-05-06. Every step here references a
> real screen + real action with the accessibility identifier or button
> label so the tester knows exactly where to look.

> **Source of truth:** `AmakaFlow/Core/FeatureFlags.swift` documents MVP
> scope as "Home + Workouts + Pairing + Settings + minimal More."
> Everything else (Calendar tab, Social tab, Programs, Sources, Food
> logging, Readiness History, Fatigue Advisor, Bulk Import) is gated
> behind `FeatureFlags.nonMvp` and **invisible in MVP builds**. Don't
> test what the user can't reach.

---

## Pre-flight (5 min)

| ID | Step | Pass criteria |
|---|---|---|
| **P1** | TestFlight install of latest `AmakaFlowCompanion` build | App installs without provisioning errors |
| **P2** | Cold-launch on iPhone | Splash → either onboarding or Home appears within 5s; **no crash** (Bug A from May 6 was a `preconditionFailure` here) |
| **P3** | Sign in via Clerk | Email/social → home view loads. Clerk uses the `ruling-mite-84.clerk.accounts.dev` instance (single instance for staging) |
| **P4** | Backend health smoke | From your laptop: `curl https://chat-api-whkq.onrender.com/health && curl https://mapper-api.staging.amakaflow.com/health && curl https://calendar-api.staging.amakaflow.com/health && curl https://workout-ingestor-api.staging.amakaflow.com/health && curl https://orchestrator-api-v64v.onrender.com/health`. All five return 200. |

---

## Tab bar — what exists in MVP

The bottom tab bar shows **3 tabs** (Home / Workouts / More). If you see Calendar or Social tabs, you're on a non-MVP build (`AMAKAFLOW_NON_MVP=1`) — fine for dev, but launch testing should be on an MVP build.

Accessibility identifiers (handy for screenshots / future automation):
- `home_tab`, `workouts_tab`, `more_tab`

---

## Home tab

The Home tab is the user's daily landing. The screen shows in this order from top:

1. **Date header** (e.g. "WED · MAY 6")
2. **Readiness ring** (will show "No readiness data" until a wearable is connected — that's expected for a fresh user)
3. **Today section**: a card for today's workout (e.g. *"Full Body General Fitness Session — 45m, 13 steps, Strength"* with `Ready` badge) showing **Details** + **Start workout** buttons
4. **Coach section** with three rows: **Plan reveal**, **Activity** ("Agent decisions"), **Review** ("Sunday summary")
5. **Suggest Workout** CTA at the bottom (yellow pill) — calls AI to generate a workout

### H1 — A workout card appears for "today"
| | |
|---|---|
| **Where** | Home tab, "TODAY" section |
| **Action** | Just observe the screen on launch |
| **Pass** | A card shows with workout name, duration, step count, and Type, plus a Ready badge |
| **Fail signals** | Empty state, error, "no plan available" |
| **Notes if it fails** | The default plan is auto-generated for new users without an explicit coaching profile. If empty, the daily-runner background job didn't fire — check `chat-api` Render logs for errors on `/coach/...` endpoints |

### H2 — Tap **Suggest Workout** → AI generates a workout
| | |
|---|---|
| **Where** | Home tab, yellow Suggest Workout pill at the bottom |
| **Action** | Tap it. A sheet opens. Tap **Generate** (or whatever the primary CTA is in the sheet). |
| **Pass** | A workout card renders with title, duration, and intervals/blocks within ~10s |
| **Fail signals** | "Server error: 503", "Hostname not found", spinner forever |
| **Common causes (already fixed today, but watch for regressions)** | 503 = chat-api missing OPENAI_API_KEY (fixed via AMA-1780). DNS error = wrong default environment for Release builds (fixed via Environment.swift `.staging` patch). |

### H3 — Tap the **Start workout** button on today's card
| | |
|---|---|
| **Where** | Today's workout card |
| **Action** | Tap **Start workout** |
| **Pass** | A full-screen WorkoutPlayerView opens with intervals laid out and a Start/Play control |
| **Fail signals** | Player crashes, intervals show as raw JSON, blank screen |
| **Note** | A "device picker" sheet may appear first on the first run — pick **Apple Watch + iPhone** or **iPhone Only** |

### H4 — Coach: tap **Plan reveal**
| | |
|---|---|
| **Where** | Home tab, Coach section, "Plan reveal" row |
| **Action** | Tap it. A sheet opens. |
| **Pass** | Sheet shows how the *next* training block was constructed — agent reasoning, structure preview |
| **Fail signals** | Empty sheet, "no plan to reveal", error |

### H5 — Coach: tap **Activity** ("Agent decisions")
| | |
|---|---|
| **Where** | Home tab, Coach section, "Activity" row |
| **Action** | Tap it. AgentInboxView appears. |
| **Pass** | A list of agent decisions (rebalance, replan, nudges) — even an empty state with copy is fine |

### H6 — Coach: tap **Review** ("Sunday summary")
| | |
|---|---|
| **Where** | Home tab, Coach section, "Review" row |
| **Action** | Tap it. WeeklyReviewView opens. |
| **Pass** | Weekly summary — completed workouts, missed days, volume |

---

## Workouts tab

The Workouts tab is a list of saved workouts. Tap a row → workout detail sheet opens.

### W1 — List populates
| | |
|---|---|
| **Where** | Workouts tab |
| **Action** | Just observe |
| **Pass** | Some workouts visible (the auto-generated daily plans should appear here too). Empty state with "Add Sample Workout" CTA is OK on a brand new account |

### W2 — Tap a workout → Detail sheet
| | |
|---|---|
| **Where** | Workouts tab, any row |
| **Action** | Tap a workout |
| **Pass** | A sheet slides up showing intervals, target metrics, Estimate, and a primary action button |

### W3 — Detail sheet: **Start on Apple Watch** (the actual "push to Watch" path)
| | |
|---|---|
| **Where** | WorkoutDetailView, primary CTA |
| **Action** | Tap **Start on Apple Watch** |
| **Pass** | Button text changes to "Workout Sent — Ready on Watch" and a "Waiting for Watch" full-screen cover may appear. The watch should buzz / show the AmakaFlow Companion app with the workout queued. |
| **Fail signals** | "Watch not paired", silent failure, button stuck on the old text |
| **Note** | This path uses **Apple WatchConnectivity / WorkoutKit** — NOT a direct Garmin push. For Garmin you use the CIQ widget separately (out of scope for the iOS app's own surface; tested via Telegram + the watch widget directly). |
| **iOS 18+ only** | If the iPhone is on iOS 17 or earlier, the WorkoutKit path is gated; user gets an inline message "WorkoutKit requires iOS 18.0+. Use Watch sync or Calendar instead." |

### W4 — Watch delivery state surfaces correctly
| | |
|---|---|
| **Where** | After W3, navigate to Settings → "Watch delivery" (or wait for a status banner) |
| **Action** | Observe |
| **Pass** | One of: Queued, Sending, On watch, Delayed, Failed — with the right icon/copy. See `Views/WatchDeliveryView.swift` for the canonical state set |

---

## More tab

The More tab is a list with three sections: **Features** (AI Coach, History), **Tools** (hidden in MVP), **Settings**.

Visible rows on MVP (per `MoreView.swift`):
- `more_row_coach` — AI Coach → CoachChatView
- `more_row_history` — History → ActivityHistoryView
- `more_row_settings` — Settings → SettingsView

If you see Food / Sources / Programs / Readiness History / Fatigue Advisor / Bulk Import, you're on `AMAKAFLOW_NON_MVP=1`. Don't test those for MVP launch.

### M1 — AI Coach
| | |
|---|---|
| **Where** | More tab → AI Coach |
| **Action** | Tap, type a message ("how should I structure this week?"), send |
| **Pass** | Response streams in within ~5–10s. May include tool cards (workout previews) and stage indicators |
| **Fail signals** | 503, blank reply, hangs >30s |
| **Common causes** | chat-api LLM provider misconfigured (post-AMA-1780, pulls from OPENAI_API_KEY first). Streaming uses `AIClient` which is still Anthropic-only as of 2026-05-06 (Phase 2 of AMA-1779 hasn't shipped) — if Anthropic isn't configured **but you set OPENAI_API_KEY for AMA-1780**, chat streaming may still fail. **This is a known gap until AMA-1779 Phase 2 ships.** |

### M2 — History
| | |
|---|---|
| **Where** | More tab → History |
| **Action** | Tap |
| **Pass** | A list of past workouts, completion entries, RPE markers |
| **Empty-state OK** | Brand-new test user has no history |

### M3 — Settings → core rows
| | |
|---|---|
| **Where** | More tab → Settings |
| **Action** | Scroll through the rows |
| **Pass** | At minimum these are visible: profile/identity, Connect Telegram (AMA-1763), Watch device preference, environment toggle (debug only), debug logs |

### M4 — Settings → Connect Telegram (AMA-1763)
| | |
|---|---|
| **Where** | More tab → Settings → Connect Telegram |
| **Action** | Tap "Connect Telegram" → on iPhone, Telegram opens with `@amakaflow_userbot` and a Start button |
| **Pass** | Tap Start → bot replies with a confirmation message → Telegram link is durably stored. Going back to AmakaFlow, the row should show "Connected" |

---

## Telegram bot (paired)

After M4, your Telegram is paired with the AmakaFlow user. The bot supports a small command set; commands not listed are not in MVP.

| Command | Pass criteria |
|---|---|
| `/start` (no args) | Welcome message with command help |
| `/today` | Some response about today's workout. **Known parity gap (2026-05-06): the bot says "your workout is on your watch" but doesn't echo the workout content the iOS Home tab shows. File a sub-bug if you want full parity.** |
| Free-text message | Bot routes through intent classifier and responds with quick-reply buttons (Swap workout / Too tired today / I'm injured / All good, let's go) |
| `/push <workout name>` | Bot queues the named workout for Garmin via the canonical CIQ path |

---

## What's intentionally NOT tested in MVP

These are real screens in the codebase but hidden by `FeatureFlags.nonMvp`. Skip them — they aren't in the user's path until the willingness-to-pay test resolves:

- Calendar tab
- Social tab (feed, challenges, crews)
- Food logging / Nutrition tracker
- Sources (workout import library)
- Programs (multi-week plans)
- Readiness History, Fatigue Advisor
- Bulk Import wizard
- Web app (`staging.amakaflow.com`) — defensive smoke only; not a primary user surface

---

## Bug filing template

When something fails:

```
Title: [Real-device test 2026-05-06] <screen>: <symptom>

Repro:
1. Cold-launch from TestFlight build <N>
2. Sign in as <persona>
3. Tap <screen path>
4. Observe <symptom>

Expected: <what the runbook step says should happen>
Actual: <what you saw>
Severity: blocker | high | medium | low
```

Filed under MyAmaka team, project AmakaFlow MVP. Tag `lane:claude-code` for backend or `lane:joshua` for iOS.

---

## Pass thresholds for MVP launch

- All Pre-flight (P1–P4) ✅
- Home: H1 + H3 must pass (the user can see and start today's workout). H2/H4/H5/H6 strongly preferred.
- Workouts: W2 + W3 must pass (the user can preview and send to watch). W4 surfaces correctly even if the actual delivery is Delayed.
- More: M3 + M4 must pass (Settings reachable, Telegram pair-able). M1 nice-to-have until AMA-1779 Phase 2 ships.
- Telegram: at least `/start` and `/today` work, even if `/today` parity is incomplete.

If those pass, MVP is launchable. Everything else is polish.

---

## Open known gaps (don't be surprised)

- **Coach chat streaming** may 503 even after AMA-1780 because `AIClient` (the streaming backbone) is still Anthropic-only. Fix lands in AMA-1779 Phase 2.
- **Telegram `/today` parity** — bot doesn't echo the iOS workout content. File a sub-bug after the test pass.
- **`strava-sync-api.staging.amakaflow.com`** doesn't resolve in DNS (AMA-1778). Strava OAuth is broken on staging until that's fixed.
- **Production hostnames (`*.amakaflow.com`)** don't exist yet. The Release build defaults to `.staging` (Environment.swift patch on 2026-05-06) so this doesn't affect TF testing today, but a production launch needs the CNAMEs first.
