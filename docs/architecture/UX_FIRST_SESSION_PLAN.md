# AmakaFlow v1 — First-Session UX Plan

**Spike ticket:** [AMA-1875](https://linear.app/amakaflow/issue/AMA-1875)
**Status:** Draft for David's review
**Last updated:** 2026-05-22

---

## TL;DR — Final recommendation (revised 2026-05-22 per David's clarification)

Ship an **animated-explainer onboarding** for v1 plus flip `FeatureFlags.nonMvp` to `true`. Combined effort: **~3–4 working days**.

**Critical clarification from David 2026-05-22 19:27:** when he said "demo," he meant *"something that shows the user how it works in animation rather than a actual demo of the app"* — i.e., motion-graphics explainer like Headspace / Calm / Duolingo, NOT a live demo running the real AI. This is a major shape change: no live API calls during onboarding, no real workout generation, no real state. Just 4-5 animated screens explaining what the app does, ending in Clerk sign-up.

**Why the change matters:**
- Live AI demo (the earlier plan) had a 5-20s wait while LLM ran during onboarding — bad UX in a first-impression context, expensive in API costs per visitor.
- Animated explainer can introduce 4-5 features in ~30-45s of motion (vs Live demo which could only really show the Suggest flow).
- No real state to manage = nothing to break.
- Lottie files from lottiefiles.com (David's pick — confirmed 19:33) give premium aesthetic at zero design cost.

**The flow (4-5 screens, ~45s total, no user input until end):**

1. *"Your AI coach plans your workouts"* — Lottie of a calendar/plan being built
2. *"Connect Watch, Garmin, or Strava"* — Lottie of devices syncing
3. *"Get nudges in Telegram (if you want)"* — Lottie of chat bubbles
4. *"Track your week + see progress"* — Lottie of a ring filling
5. *Sign-up CTA* — Clerk hosted flow

Auto-advance per screen (~7-9s), with a "Skip" tap target in top-right. No backout state to design — every back tap just goes to previous slide.

**Other changes (still in scope):**

- Flip `FeatureFlags.nonMvp` to `true` — un-hide Sources, Programs, Readiness History, Fatigue Advisor, Bulk Import. Already in code; cost of exposing them is ~0.
- Replace the empty `Workouts → This week` placeholder with 1 seeded sample workout + an "Ask coach" CTA so it's not totally barren on day 1.
- Promote AI Coach from "row inside More tab" to a Home-screen card.
- Splash: a Lottie animation under 1.5s with the AmakaFlow logo.
- Discover hub ("What can AmakaFlow do?") in More tab, SF Symbols + copy, reachable for users who want to browse beyond the core flow.
- Delete `MentalModelView` — the animated explainer subsumes its role.

**David's answers to spike Open Questions:**
1. No designer/brand kit → Lottie files from lottiefiles.com (free pack)
2. No commissioned icons → SF Symbols throughout
3. No live AI demo → animated explainer instead
4. "Sign in instead" question moot (no decision-tree screens, just linear advance)
5. Delete `MentalModelView`

The earlier "Lean demo" (live AI, 3 screens) and "Full demo" (live AI, 5-7 screens) sections below are now historical context — the chosen approach is neither. Animated explainer is its own variant; details in Section 5b (new).

---

## 1. Current first-session flow (audited from code, ~2026-05-22 main HEAD)

Entry point: `AmakaFlowCompanion/AmakaFlowCompanion/AmakaFlowCompanionApp.swift:161`.

```
┌─────────────────────────────┐
│ App launch                  │
│ (Color.black until Clerk    │
│  session resolves)          │
└──────────────┬──────────────┘
               │
               ▼
       ┌───────────────┐  no    ┌──────────────────────────┐
       │ Authenticated?├───────►│ unpairedRoot:            │
       └───────┬───────┘        │  • MentalModelView (1st) │
               │ yes            │  • PairingView           │
               │                │    └─ Clerk hosted UI    │
               ▼                │      "Continue to AmakaFlow Dev"
       ┌──────────────────────┐ │       (uses staging Clerk)
       │ ContentView (tabs)   │ └──────────────────────────┘
       │  ┌─Home              │
       │  ├─Workouts          │
       │  └─More              │
       │      └─AI Coach      │
       │      └─History       │
       │      └─Settings      │
       └──────────────────────┘
```

What a brand-new user sees in order:

1. **Black screen** (Clerk session check, ~0.5–1s)
2. **MentalModelView** — one-time intro card (we have this already in code; it's a value-prop summary, not a demo)
3. **Clerk hosted sign-in UI** — "Continue to AmakaFlow Staging" → email + password
4. **Onboarding cards** that fire on first Suggest tap, NOT on first launch:
   - `BiometricConsentView` ("Before we begin — I agree — continue")
   - `CoachingProfileOnboardingView` ("What are you training for?" + Experience + Goal + Days)
5. **Home tab** — "REST DAY / No workout scheduled / Start workout" + Coach visibility section + a Suggest Workout button + a Quick Start button + a Week Glance card showing 0 sessions
6. **Workouts tab** — week view, 7× "No session"
7. **More tab** — AI Coach, History, Settings (3 rows total)

Critical: **the only path that generates value (Suggest Workout) is reached by tapping a button that doesn't look any more important than the others on Home.** A new user has no reason to tap Suggest Workout first.

---

## 2. Feature inventory — what AmakaFlow already does

52 SwiftUI view files. Below is the full surface, grouped by what a user can do.

### Core workout flow
- Generate AI workout (`SuggestWorkoutView.swift` + `CoachingProfileOnboardingView.swift`)
- Accept + save workout to week
- Start workout (Phone-only or Apple Watch)
- Execute intervals (`WorkoutPlayerView.swift`)
- End + save completion → backend
- Review in Activity History (`ActivityHistoryView.swift`)

### Coaching
- AI Coach chat (`CoachChatView.swift` — 526 lines, full chat surface)
- Plan reveal (`PlanRevealView.swift`)
- Weekly review (`WeeklyReviewView.swift`)
- Fatigue advisor (`FatigueAdvisorView` + standalone `FatigueAdvisorStandaloneView`)
- Readiness history (`FatigueHistoryView.swift`)
- RPE feedback (`RPEFeedbackView.swift`)
- Activity feed (`ActivityFeedView.swift`)
- Agent inbox (`AgentInboxView.swift`) — agent decision log
- Coaching profile (`CoachingProfileOnboardingView.swift`)

### Imports / integrations
- AI workout import from URL (`AIImportView.swift` + `ImportURLView.swift`)
- Instagram reel ingestion — auto (`InstagramReelIngestionView.swift`) + manual (`ManualInstagramIngestionView.swift`)
- Deep link import (`DeepLinkImportView.swift`)
- Bulk import wizard (`BulkImportWizardView`)
- Telegram integration (`TelegramSetupView.swift`)
- Garmin Connect pairing (`PairingView.swift` + `GarminConnectManager.swift`)
- Strava integration (`StravaView.swift`)
- Calendar integration (`CalendarManager.swift` + `CalendarView.swift`)
- Apple Watch delivery (`WatchDeliveryView.swift` + `WatchConnectivityManager.swift`)

### Library / catalog
- Programs library (`ProgramsListView.swift` + `ProgramDetailView.swift`)
- Knowledge library (`KnowledgeLibraryView.swift` + `AddKnowledgeView.swift` + `KnowledgeCardDetailView.swift`)
- Sources hub (`SourcesView.swift` — HK + Garmin + Strava + Watch consolidated)

### Gamification + social
- XP bar (`XPBarView` — visible on Home today)
- Level-up celebration (`LevelUpCelebrationView.swift`)
- PR celebration (`PRCelebrationView.swift`) + PR history (`PRHistoryView.swift`)
- Workout share card (`WorkoutShareCardView.swift`)
- Weekly progress ring (`WeeklyProgressRing.swift`)
- Team feature (`TeamView.swift`)

### Nutrition / wellness (partial)
- Nutrition dashboard card on Home (`NutritionDashboardCard`)
- Protein + water trackers
- Food logging (`FoodLoggingView`)
- Biometric consent gate (`BiometricConsentView.swift`)
- Mental model intro (`MentalModelView.swift`) — fires once before pairing

### Settings + tools
- Notification preferences (`Settings/NotificationPreferencesView.swift`)
- Training preferences (`Settings/TrainingPreferencesView.swift`)
- Fatigue settings (`Settings/FatigueSettingsView.swift`)
- Voice transcription settings (`Settings/VoiceTranscriptionSettingsView.swift`)
- Debug log + debug settings
- Shoe comparison (`ShoeComparisonView.swift`) — running gear

### What's NOT discoverable in current UI (the "barren" problem)

Today the MoreView renders 3 visible rows: AI Coach, History, Settings. Everything in the list above that isn't on Home or in those 3 rows is unreachable through standard navigation. The user can't find it.

---

## 3. Competitor onboarding patterns (synthesized)

Researched flows: FitnessAI, Duolingo, Strava, Whoop, Headspace (via 2026 splash-screen best practices, design case studies, App Fuel flow captures).

| App | Pre-signup demo? | Onboarding shape | Signup placement | Splash style |
|---|---|---|---|---|
| **FitnessAI** | ✅ Yes — quiz → live AI plan generation → plan-summary screen | Goals + experience + equipment quiz, then AI generates plan. 3D muscle model gives live visual feedback during quiz. | Plan-summary screen lands you on subscription ask | Standard, no video |
| **Duolingo** | ✅ Yes — runs a real translation lesson before signup | "Let them do, don't tell them" — first lesson IS the onboarding | After 1st lesson; signup is optional and becomes more compelling as user progresses | Minimal logo flash |
| **Strava** | ❌ No demo, just data collection | Slide-out collects gender, sports, birthdate; "follow friends + notifications" | Account creation up front | Bright orange + white logo, no animation |
| **Headspace** | Partial — plays a short meditation before paywall | Minimalist illustrated welcome screens | Mid-flow after first meditation | Minimalist with brand color |
| **Future** | ❌ Demo focuses on real coach access, not a demo lesson | Collects fitness history + lifestyle + equipment, then matches a human coach | Plan presentation right before subscription ask | Standard |

### Pattern synthesis (what's true across the successful AI/coaching apps)

1. **Demo the AI before asking for signup.** Both FitnessAI and Duolingo do this. Pure quiz-then-signup is a churn anti-pattern in 2026.
2. **The "WOW" moment is the AI doing real work in front of you.** FitnessAI generates a plan instantly. Duolingo's first lesson actually teaches you a word.
3. **Signup lands on the plan-summary screen.** After the user has seen "this is what AmakaFlow built for me," they're far more likely to commit.
4. **Splash screens are FAST.** Industry research (2026 best-practice): splash under 1.5s, single brand color + logo, animation under 200ms or skip entirely. Video loops are overkill and hurt perceived startup time.
5. **Quiz + visual feedback is the dominant pattern for fitness.** FitnessAI's 3D muscle model is the canonical example. Pure text-form quizzes feel cold.

Sources:
- [FitnessAI onboarding flow](https://onboarding.fitnessai.com/flow)
- [Duolingo onboarding UX breakdown](https://userguiding.com/blog/duolingo-onboarding-ux)
- [Sports & Fitness Apps Onboarding + Paywall Best Practices (Figma community)](https://www.figma.com/community/file/1600914995891368589/sports-fitness-apps-onboarding-paywall-best-practices)
- [App Splash Screen Best Practices: Cut It to 1.5s or Lose 12% of Users](https://www.appypie.com/blog/app-splash-screen-best-practices)

---

## 4. The AmakaFlow demo-onboarding flow

### Design principles (drawn from research above)

1. AI does real work in front of the user. No mocked demo content.
2. Signup lands on the plan-summary screen, not before.
3. Quiz is short (3 fields max). Same fields `CoachingProfileOnboardingView` already collects.
4. Backout at any point → user lands at sign-in (don't waste their progress; we have it in local state).
5. Reuse what exists. The Suggest flow already does almost everything we need; we're just reordering and re-skinning.

### The 60-second WOW moment

> A new user opens AmakaFlow → sees a branded animated splash → lands on a "What are you training for?" quiz → picks an experience level, goal, and days/week → sees an animated loading state ("Our AI coach is crafting your first workout…") → the AI-generated workout materializes on screen, interval by interval → the user taps "Save & Continue" → signup happens HERE, with the workout already saved client-side and pushed up after auth.

The WOW is: **"the app just built you a workout that fits, before you even gave it your email."**

---

## 5. Variation A — "Lean demo" (recommended for v1)

### Screen-by-screen

```
┌─────────────────────────────────┐  ┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│  Screen 1: Splash + Welcome     │  │  Screen 2: Quiz (3 fields)      │  │  Screen 3: AI builds it for you  │
│                                 │  │                                 │  │                                 │
│   [animated logo, < 1.5s]       │  │   What are you training for?    │  │   ✨ Crafting your first         │
│                                 │  │                                 │  │      workout…                   │
│   AmakaFlow                     │  │   Experience: [Beg|Int|Adv]     │  │                                 │
│   "AI workouts that adapt to    │  │                                 │  │   [progress ring]               │
│    you, on every device."       │  │   Primary goal: [○ Lose weight  │  │                                 │
│                                 │  │                  ○ Build muscle │  │   ───────────────               │
│   [Get started →]               │  │                  ● General      │  │                                 │
│                                 │  │                  ○ Endurance    │  │   Your first workout            │
│   Sign in instead               │  │                  ○ Athletic]    │  │   Full Body Strength · 45m      │
│                                 │  │                                 │  │   ┌─────────────────────────┐   │
│                                 │  │   Days per week: [1][2][●3][4]…│  │   │ 1. Bench press · 3×10   │   │
│                                 │  │                                 │  │   │ 2. Squat · 3×8 @ 60kg   │   │
│                                 │  │   [Generate my workout →]       │  │   │ 3. Barbell row · 3×8    │   │
│                                 │  │                                 │  │   │ … 9 more steps         │   │
│                                 │  │                                 │  │   └─────────────────────────┘   │
│                                 │  │                                 │  │                                 │
│                                 │  │                                 │  │   [Save & continue →]           │
│                                 │  │                                 │  │   Try a different one           │
└─────────────────────────────────┘  └─────────────────────────────────┘  └─────────────────────────────────┘
     ~1.5s                                ~10s                                  ~15–25s (LLM)
```

Hand-off after Screen 3: Tap "Save & continue" → Clerk hosted sign-in (or "Sign in instead" up top jumps here directly). After auth, the workout already in local state is pushed to the backend and the user lands on Home with the demo workout sitting as Today's session + 2 placeholder workouts seeded for the rest of the week.

### What this skips

- The biometric-consent gate (`BiometricConsentView`) — moves to Settings or a non-blocking nudge after the first workout.
- The "Continue with Google / Apple" SSO buttons during demo — only shown on the actual Clerk sign-in step.
- The full "guided tour" of every feature — feature discoverability is solved by Block 7 below, not by stuffing it into onboarding.

### Effort: ~3–4 working days

| Task | Days |
|---|---|
| New view: `AmakaFlow/Views/Onboarding/DemoFlowView.swift` (3-screen state machine) | 1.0 |
| Branded animated splash (Lottie or SwiftUI motion, <1.5s) | 0.5 |
| Refactor `CoachingProfileOnboardingView` into an inline quiz screen + extract reusable form fields | 0.5 |
| Wire `SuggestWorkoutViewModel` to run pre-auth (store result locally, push post-signup) | 0.5 |
| `AmakaFlowCompanionApp.swift` flow change: replace `unpairedRoot` with `DemoFlowView` for fresh users; preserve MentalModelView for upgrades | 0.5 |
| Seed the week post-signup with the demo workout + 2 placeholders | 0.5 |
| Light QA + tap-test on TestFlight | 0.5 |

### Code reuse summary

- `SuggestWorkoutViewModel` — already does the LLM call and renders the workout. Reusable as-is.
- `CoachingProfileOnboardingView` — already has the 3-field form. Lift its form section into a reusable component.
- `SuggestWorkoutView.loadingView` — already has the "Generating your workout…" loading state. Reusable.
- `SuggestIntervalRow` — already renders an interval. Reuse for the materializing list.

What's new: 1 orchestrator view, 1 splash animation, 1 wire-up to defer the API call until auth completes.

---

## 6. Variation B — "Full demo" (deferred to v1.1)

Adds 2–4 more screens between the materialize step and signup:

```
Screen 4: "Here's how it lands in your week"
  → animated preview of the workout dropping onto Workouts → This week
Screen 5: "Meet your AI coach"
  → 2 prompt suggestions you can tap to see the coach reply (uses real LLM)
Screen 6 (optional): "Connect your gear"
  → optional cards for Apple Watch / Garmin / Strava / Telegram (skippable)
Screen 7: "Save your workout and get going"
  → signup
```

Effort: **~7 days total** (3–4 lean + 3–4 for the extra screens + LLM-driven coach demo + integration-discovery cards).

Why deferred: the lean demo gets us to a non-embarrassing first-session experience for v1 launch. The full demo's added screens are about conversion rate, which we have no data on yet. Ship lean → measure retention → invest in the longer demo only if first-session-to-day-2 retention is the bottleneck.

---

## 7. `FeatureFlags.nonMvp` recommendation — **FLIP TO TRUE**

The `FeatureFlags.nonMvp = false` decision in `AmakaFlow/Core/FeatureFlags.swift:31` was made under [AMA-1588] when the launch plan was "ship narrow at $9.99 + validate willingness to pay." That decision was correct under those constraints.

**The 2026-05-22 decision to ship v1 FREE invalidates that calculus.** Hiding features is now hurting us:

- Empty More tab = 3 rows visible
- Empty Workouts tab = 7 days of "No session"
- Hidden features include Programs, Sources hub, Bulk Import, Readiness History, Fatigue Advisor — all polished, all in the test suite, all gated for a reason that no longer applies

### Recommendation

Set `static let nonMvp: Bool = true` (or remove the gate altogether).

This single-line change un-hides:
- `Log Food` (and the nutrition card on Home)
- `Sources` (HealthKit + Garmin + Strava + Watch — the integrations David specifically called out as "hidden")
- `Programs` (workout programs library)
- `Readiness History`
- `Fatigue Advisor`
- `Bulk Import`

Effort: **~0.5 days** including QA pass on each newly-exposed flow + verifying no Sentry warning-stream from formerly-gated views.

### Sub-decision: which non-MVP features still warrant gating?

A handful of in-flight surfaces are probably not v1-ready and should stay flagged (or move behind a separate `FeatureFlags.preview`):

- `TeamView.swift` — social/teams feature, likely incomplete
- `MentalModelView.swift` — already only shown once, fine as-is
- `AnalyticsView.swift` — needs sanity check, may be empty for new users

For everything else: expose it.

---

## 8. Splash / launch-screen plan

David asked for "something modern — a video playing or something elegant." 2026 best-practice research (sources above) is unambiguous: **don't ship a video splash.** It hurts perceived startup time and gets cut by Apple's launch-screen budget.

### Recommendation

A branded **Lottie animation under 1.5 seconds** with the AmakaFlow logo + a subtle motion accent. Lottie is the industry default for premium-feeling splash motion at small file size.

Alternative if no design budget: **a static branded illustration** behind the existing logo, with a 200ms fade-in. Still feels intentional, zero risk of perf regression.

### Concrete proposal

- Asset: `AmakaFlow-logo-splash.lottie` (commission or generate via AI tool — search results show several 2026 tools that produce this from a brand spec)
- Where it lives: replace the `Color.black.ignoresSafeArea()` block at `AmakaFlowCompanionApp.swift:166` with a `LaunchSplashView` that plays the Lottie while `authViewModel.hasResolvedInitialSession` is false
- Duration: 1.2s max — kicks the Clerk session check + cancels itself once session resolves
- Brand color: keep dark mode (already forced via `.preferredColorScheme(.dark)` at line 261), use the existing accent green or orange as the animation accent

Effort: **~1 day** (asset creation + integration + falling back to instant logo if Lottie fails to load).

---

## 9. Feature discoverability plan

Onboarding can't carry 30+ features. Three surfaces, working together:

### Surface 1: "What can AmakaFlow do?" hub

A new view `AmakaFlow/Views/Discover/FeatureHubView.swift`, reachable from:
- A new "Discover" row at the top of `MoreView` (above AI Coach)
- A one-time post-onboarding modal card ("You just generated your first workout — here's what else AmakaFlow can do" with a tap-through)

Content: 6–8 cards, each linking to the actual feature. Cards include:
- 🤖 AI Coach chat
- 🍴 Track nutrition
- ⌚️ Apple Watch / Garmin sync (via Sources hub)
- 📱 Telegram check-ins
- 📚 Programs library
- 📥 Import workouts from anywhere (Instagram, YouTube, URL)
- 🔥 Fatigue advisor
- 🏃 Strava sync

Cards open the existing view. Zero new behavior, ~1 day of work.

### Surface 2: In-context nudges

After the demo workout completes (or after the first session of any kind), show a small dismissible coachmark card on Home:
- First load: "💬 Tap the AI Coach to ask anything about your training"
- Second load (after they tap Coach): "⌚️ Want this on your Watch? Tap Sources"
- Third load: "📥 You can import workouts from Instagram, YouTube, or any URL"

Effort: ~0.5 days (reusable component, cycle through 3–4 nudges over the first week).

### Surface 3: Empty-state copy upgrades

Every empty state today says some variant of "No X yet." Replace with concrete next-step copy:
- Workouts → This week → 0 sessions: "Your AI coach hasn't planned a week yet. Tap **Suggest workout** to start one."
- Coach chat → no threads: "Ask your AI coach anything: 'How should I train this week?' or 'What's a good cooldown for legs day?'"
- Activity History → No Activities Yet: stays as-is, this state should be rare post-onboarding

Effort: ~0.5 days across all empty states.

---

## 10. Post-onboarding view sketches

After Lean demo + signup + week-seeding, here's what Home should look like for a brand-new user on their second app open:

```
┌─────────────────────────────────────────┐
│  WED · MAY 22                           │
│                                          │
│  ┌─────────────────────────────────┐    │
│  │  ⚡ Today                        │    │
│  │  Full Body Strength · 45m       │    │
│  │  3×10 bench, 3×8 squats, …      │    │
│  │  [▶ Start workout]              │    │
│  │  Plan another? [+]              │    │
│  └─────────────────────────────────┘    │
│                                          │
│  COACH                                   │
│  ┌──────┐ ┌──────┐ ┌──────┐             │
│  │Coach │ │Activ.│ │Review│             │
│  │chat  │ │feed  │ │week  │             │
│  └──────┘ └──────┘ └──────┘             │
│                                          │
│  WEEK PROGRESS                           │
│  [○○●○○○○]  1 of 3 done this week       │
│                                          │
│  ✨ DISCOVER                             │
│  "You can also: connect Garmin · log    │
│   protein · ask your AI coach anything" │
│  → See all features                     │
│                                          │
└─────────────────────────────────────────┘
```

Workouts tab now shows the demo workout on today + 2 suggested placeholders Wed/Fri, not 7× "No session."

More tab now has Discover at the top.

The Coach card on Home becomes one of three primary CTAs alongside Today and Discover.

---

## 11. Acceptance summary — does this answer the spike?

| Acceptance criterion | Section | Status |
|---|---|---|
| New-user first 60-second experience | §4, §5 | ✅ Demo-first flow, 3 screens, ~30s, AI builds a real workout |
| Empty-state handling for Week + Coach views | §9 + §10 | ✅ Week seeded post-demo; empty-state copy upgrades; coach is now a Home card |
| Coach surfacing strategy | §10 | ✅ Promoted from More tab to Home card; AI Coach chat still accessible from More |
| Onboarding flow shape | §5 + §6 | ✅ Screen-by-screen sketched for Lean (v1) and Full (v1.1) |
| Feature discoverability | §9 | ✅ Discover hub + in-context nudges + empty-state copy |
| Aesthetic / modern feel | §8 | ✅ Lottie splash <1.5s + dark mode preserved |
| Whether to flip FeatureFlags.nonMvp for v1 | §7 | ✅ Yes — flip to true |

---

## 12. v1 critical path

```
Day 1–2: Splash animation asset + integration; FeatureFlags.nonMvp flip + QA pass
Day 3–4: DemoFlowView state machine + reusable quiz form + LLM call pre-auth
Day 5:   Post-signup seed workouts; Home/Workouts/More polish
Day 6:   Discover hub view + coachmark cards + empty-state copy
Day 7:   Tap-test, App Store metadata, submit to App Review
```

After v1 submits: App Review takes 24–48h. If approved, AmakaFlow is live with a coherent first-session experience.

---

## 13. Out of scope (explicit reminders)

- Paywall / monetization (AMA-1851 deferred to v1.1)
- Production Clerk instance + production DNS (decided 2026-05-22: staging IS production for v1)
- Backend changes
- Code in this PR — this is the spike artifact only. Implementation gets its own ticket(s).

---

## 14. Open questions for David before implementation starts

1. **Branded splash asset.** Do you have a designer or a brand kit, or do we generate the Lottie via an AI tool? (See [LottieFiles 2026 AI tools list](https://autoppt.com/blog/ai-splash-screen-makers/).)
2. **Discover hub iconography.** SF Symbols throughout, or commission a small icon set?
3. **Demo workout — what's the seed data for the 2 placeholder workouts that get added to the week post-onboarding?** Lean: pick from a small hard-coded library tied to the user's goal. Full: have the AI generate 3 at once during onboarding.
4. **Should "Sign in instead" on Screen 1 be visually de-emphasised** (we want most new users to walk through the demo, not skip it)? Recommend yes — make it a small text link.
5. **MentalModelView fate.** It's a one-time intro shown before pairing today. With demo onboarding replacing it, do we delete it or repurpose it as the screen-0 brand statement before the quiz?

A "yes" + answer to these five questions and implementation can start same-day.
