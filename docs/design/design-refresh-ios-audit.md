# AmakaFlow Design Refresh vs iOS — Audit Report

**Date:** 2026-06-04  
**Design source:** [`AmakaFlow MVP Design Refresh/project/AmakaFlow Hi-fi.html`](../../../AmakaFlow%20MVP%20Design%20Refresh/project/AmakaFlow%20Hi-fi.html)  
**iOS app:** `amakaflow-ios-app`  
**Review method:** Code inspection + design canvas (`tokens.css`, `screens-*.jsx`) compared to SwiftUI implementations in `AmakaFlow/Views/`.

---

## Executive verdict

| Area | Alignment |
|------|-----------|
| Design tokens + primitives | **Match** |
| 6-tab navigation (AMA-1992) | **Match** |
| v1 polish screens (signup, library, equipment, messaging) | **Mostly match** |
| Connections reorg (AMA-2103) | **Match** |
| Agent visibility surfaces | **Mostly match** |
| Home populated layout | **Diverge** (largest visual debt) |
| Workout player SWAP | **Was missing** → implemented in this pass |
| Completion RPE UI | **Was partial** → aligned to 1–10 grid + injury notes |
| Home readiness score | **Was unwired** → wired via `/v1/planning/days` |

Overall: **~70% aligned** before this pass; functional gaps (readiness, SWAP, RPE) addressed below. Home layout restructure remains future work.

---

## Artboard scoring by canvas section

Legend: **M** = Match · **P** = Partial · **X** = Missing

### Core MVP (`mobile` — 11 frames × 2 themes)

| Artboard | Score | iOS screen | Notes |
|----------|-------|------------|-------|
| Home (populated) | **P** | `HomeView` populated | Layout differs: no 2-col readiness/load, no lime program card, extra CTAs (Suggest, Quick Start, Voice, XP) |
| Home (empty) | **M** | `HomeView.homeEmptyState` | Three paths match design; Build plan gated by `FeatureFlags.programWizardEnabled` |
| Workouts | **P** | `WorkoutsView` | List + source badges; range filter UX differs from design |
| Workout detail | **P** | `WorkoutDetailView` | Structure present; external-source banner variant partial |
| Workout player | **P→M** | `WorkoutPlayerView` | SWAP action added (AMA design refresh pass) |
| Completion | **P→M** | `RPEFeedbackView` | Now uses `AFRPEGrid` 1–10 + injury free-text |
| Onboarding | **P** | `CoachingProfileOnboardingView` | Embedded in suggest flow, not standalone 5-step wizard |
| Pairing | **P** | `ConnectionsHubView` | Multi-device pairing moved from legacy `PairingView` (now Clerk auth) |
| History | **M** | `ActivityHistoryView` | Functional list |
| Profile / Settings | **M** | `SettingsView` | Grouped IA + Connections hub card |
| Paywall | **X** | — | No dedicated SwiftUI paywall in main flows |
| Landing (desktop) | **X** | — | Marketing screens not in iOS app |

### v1 polish (8 frames × 2 themes)

| Artboard | Score | iOS screen |
|----------|-------|------------|
| Sign up (animated hero) | **M** | `SignUpView` + `SignUpDemoHeroView` |
| Coach tab | **P** | `CoachChatView` (SSE chat vs design briefing surface) |
| Library | **M** | `LibraryView` |
| Library empty | **M** | `LibraryEmptyStateView` |
| Equipment profile | **M** | `EquipmentProfileView` |
| Messaging | **M** | `MessagingView` |
| Detail from source | **P** | `WorkoutDetailView` + `WorkoutSourceBadge` |
| Home empty variant | **M** | Same as core empty state |

### Connections (`connections` — 6 frames × 2 themes)

| Artboard | Score | iOS screen |
|----------|-------|------------|
| Profile reorganized | **M** | `SettingsView` sections |
| Connections hub | **M** | `ConnectionsHubView` |
| Apple Watch detail | **M** | Connection detail shell |
| Garmin detail | **M** | Connection detail shell |
| Telegram detail | **P** | `TelegramSetupView` states partial |
| Sync / Calendar detail | **M** | Connection detail shell |

### Agent visibility (8 + 3 banner frames)

| Artboard | Score | iOS screen |
|----------|-------|------------|
| Mental model | **M** | `MentalModelView` |
| Plan reveal | **M** | `PlanRevealView` |
| Weekly review | **M** | `WeeklyReviewView` |
| Watch delivery | **M** | `WatchDeliveryView` |
| Agent event inbox | **M** | `AgentInboxView` |
| Telegram setup (idle/polling/done) | **P** | `TelegramSetupView` |
| Home replan / red flag / low confidence | **M** | `HomeBannerKind` in `HomeView` |

### v1 coverage A / B / C

| Tier | Score | Notes |
|------|-------|-------|
| Part A essentials | **P** | Screens exist; not all polished to hi-fi fidelity |
| Part B [DECIDE] | **P** | Social, XP, nutrition, ingest — present, optional v1 cuts |
| Part C secondary | **P** | Analytics, sources, export, debug — present in Settings/More paths |

---

## Home populated layout — delta analysis

Design reference: `screens-main.jsx` → `HomeScreen` (non-empty).

| Element | Design spec | Current iOS (`HomeView`) | Gap |
|---------|-------------|--------------------------|-----|
| **Header** | Centered "Today" title + date subtitle; gear icon → Settings | Left-aligned `AFLabel` weekday·date; bolt icon (no Settings link) | Layout + navigation |
| **Readiness block** | 2-column grid: Readiness % (large mono) + Today's load (gradient bar + RPE marker) | Single full-width `readinessCard` with ring; score was hardcoded `nil` | Layout + data (score now wired via `HomeViewModel.loadReadiness()`) |
| **Program card** | Lime gradient card: block/week/race countdown | `todaysWorkoutHero` AFCard (neutral surface) | Visual treatment |
| **Week strip** | Sun–Sat with activity icons and values | `weekGlanceCard`: Mon–Sun letter boxes + progress bar | Different component |
| **Summary metrics** | 4-column row (design-specific KPIs) | Hero stats inside workout card only | Missing standalone row |
| **Recovery card** | Tappable card → readiness sheet | Readiness card opens `ReadinessDetailView` | Partial (different placement) |
| **Start CTAs** | **One** start path per screen | Hero Start + Suggest + Quick Start + Voice | **Violates** one-CTA rule |
| **Gamification** | None in design | `XPBarView`, level-up overlay | **Violates** clinical tone rule |
| **Agent banners** | Replan / red flag / low confidence | `HomeBannerKind` | **Match** |

**Recommended follow-up (not in this pass):** Restructure populated Home to match design IA; remove duplicate start CTAs and XP bar from Home surface.

---

## Design rules compliance

| Rule | Status |
|------|--------|
| One start-CTA per screen | **Violated** on populated Home |
| Clinical, non-gamified tone | **Violated** (XP on Home) |
| Light + dark every screen | **Mostly yes** (`Theme.swift` adaptive tokens) |
| Third-party logos as letter glyphs | **Mostly yes** |
| Geist + Geist Mono typography | **Yes** |
| Pill buttons, af-card primitives | **Yes** |

---

## Backend alignment (post-fix)

| Feature | BFF / API | iOS (after this pass) |
|---------|-----------|------------------------|
| Readiness % on Home | `GET /v1/planning/days` → `readinessScore` | `HomeViewModel.loadReadiness()` |
| Coach suggest / swap | chat-api suggest via BFF | `SuggestWorkoutView`; player SWAP sheet |
| RPE + injury | `POST /v1/coach/rpe-feedback` | `RPEFeedbackView` grid + notes |
| Program wizard | `POST /v1/programs/*/stream` | Flag enabled (routes in mobile-bff) |
| Library | knowledge/library APIs | `LibraryView` |
| Connections | pairing/Garmin/Telegram/calendar | `ConnectionsHubViewModel` |

---

## Side-by-side review checklist

1. Open `AmakaFlow Hi-fi.html` → Tweaks → light/dark + Prototype jump-to.
2. Run iOS Simulator → `AmakaFlowCompanion` scheme.
3. Compare: Home (empty + populated), Workouts, Player (SWAP), Completion (RPE grid), Library, Settings → Connections.
4. Maestro: `e2e/maestro/flows/golden-path.yaml`
5. XCUITest: Connections hub visual tests (AMA-2103).
