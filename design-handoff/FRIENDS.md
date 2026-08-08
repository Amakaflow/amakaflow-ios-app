# FRIENDS.md — Friends & workout sharing v1 (AMA-2389)

> Ticket (full spec + validation): [AMA-2389](https://linear.app/amakaflow/issue/AMA-2389/friends-and-workout-sharing-v1-add-friends-send-from-share-receive-via)
> Spec of record: `amakaflow-docs/docs/superpowers/specs/2026-08-08-friends-workout-sharing-design.md` (PR #68)
> Reference source: `reference/screens-friends.jsx` (FR — flows) + `reference/screens-friends2.jsx` (FR2 — Share/＋/dup ports) + `reference/screens-friends3.jsx` (FP — Profile origin + manage/remove)
> Ground truth: `screenshots/rig-friends-panels.jpg` (9 panels)
> Live rig (panels 1, 2, 6 interactive): https://claude.ai/design/p/2ff39626-7f9e-440a-8182-7b19aa44227f?file=hifi%2Frig-friends.html

**One sentence:** add friends (mutual-accept), send library workouts from the workout screen's **existing Share tile**, receive via a new **From friends** source in the ＋ Add-workout sheet, and flag duplicates on save — sharing, not social.

## Placement — build INTO the shipped screens, do not invent surfaces

| Door | Where | What changes |
|---|---|---|
| Send | Workout detail action row (Pin/Collect/To-watch/**Share**) | Share opens a sheet: "Send to a friend" (friend select + counted CTA) on top, "Share elsewhere — link, Messages…" (current system share) below |
| Receive | ＋ Add-workout sheet | New row, shipped anatomy (icon circle + title + sub): **From friends** · "<names> sent you workouts" + lime waiting badge. After Build from scratch |
| Manage | **Profile screen** (final placement — supersedes Settings) | **Friends** row between the week dots and the needs-attention card, This-week row anatomy (`Friends · 3 FRIENDS · 2 WORKOUTS WAITING` + lime badge) → list / add / requests |
| Today | — | NOTHING standing. Arrival = DD Toast + badges only |

## Build order

1. **Backend/BFF seams first, behind a protocol** (endpoints land separately): `Friendship` (request/accept/decline/cancel/remove/list — decline/cancel/remove are SILENT, no notification event) and `WorkoutShare` (send/list/mark-seen/save/dismiss). Shares carry an **immutable workoutSnapshot** + `lineageId` (stable across re-shares; seeded from the origin source id when the workout came from a reel/URL) + optional note.
2. **Profile Friends row + friends screens** (row port in `screens-friends3.jsx` FPProfileScreen; add / list / requests copy in `screens-friends.jsx`). **Manage/remove** (`FPManageScreen`): header Edit pill toggles the AMA-2375-style edit mode — red ⊖ per row → INLINE confirm card "Remove <name>? They won't be notified. Workouts you saved from them stay yours. You can add them again any time." [Remove / Cancel]. Removal emits NO notification event; re-add allowed. Privacy contract card verbatim: *"Friends can send you workouts — they can't see your history, stats or gym. Remove anyone any time; they aren't notified."* Unique @handle required — confirm Clerk username covers it; else a claim step on first Friends visit.
3. **Share sheet upgrade** (`screens-friends2.jsx` FR2DetailScreen): friend multi-select, gated counted CTA `Send to N friends`, honesty line "They get a copy — your original stays yours; their edits don't touch it." Send = DD Toast push-morph (ToastHost, #534) — never claim Sent before the API confirms. System share row unchanged below.
4. **＋ sheet From friends row + review list** (FR2AddScreen + FRInboxScreen): unread lime-bordered cards `FROM <NAME> · NEW` w/ note + Look inside / Not for me (silent dismiss); handled cards dim `SAVED ✓`. Badge count = unhandled shares; identical on Profile Friends row and ＋ row; decrements on save AND dismiss.
5. **Received detail + Save** (FRSavedScreen): read-only structure preview (band + numbered rows), snapshot rule copy, **Save to Library** → normal workout with `From <name>` in the attribution card (`sourceType: friend`). Everything existing (collections, watch-ready, editor) must just work on it.
6. **Dedupe on open** (FR2DupScreen): match = same `lineageId` OR same normalized title + structure fingerprint (block count, exercise sequence, set scheme hash). Strong match → amber **"You already have this one"** card: **Open yours ›** (navigate to existing) / **Save copy anyway** (title + ` (from <name>)`) / Not for me. Title-only similarity → NO flag. Never silently dedupe or drop.

## Hard rules

- Friendship is mutual-accept; every negative action (decline/cancel/dismiss/remove) is silent.
- A share is a snapshot copy — edits never cross between sender and receiver, in either direction.
- v1 exposes NO history, stats, gym, library browsing, feed, comments, or presence to friends.
- Toasts follow the DD Toast honesty rule: pending morph, success only on confirmed API result.

## a11y IDs

`af_share_sheet` · `af_share_friend_row_<handle>` · `af_share_send` · `af_share_system` · `af_add_from_friends` (+ `_badge`) · `af_friends_profile_row` · `af_friends_edit` · `af_friends_remove_<handle>` (+ `_confirm`) · `af_friends_list` · `af_friends_add` · `af_friends_request_accept|decline|cancel` · `af_friends_invite_link` · `af_recv_row_<id>` · `af_recv_look|dismiss` · `af_recv_dup_card` · `af_recv_dup_open|copy` · `af_recv_save`

## Validation gate (details in the ticket)

- Unit: friendship state machine (silent negatives, re-request allowed); snapshot immutability both directions; dedupe matrix (lineage / fingerprint / title-only-no-flag / copy suffix / open-yours nav); gated CTA; idempotent save; badge parity + decrement rules.
- ⚠ Maestro: sheets need the `.large`-detent-under-`UITEST_*` workaround (iOS 26.1 medium-detent a11y gap). Flows: Share→send→toast morph; ＋→From friends→save→in library; dup→Open yours.
- Two-account dogfood (the real gate): A↔B request/accept → share w/ note → badge → save w/ attribution → cross-edits don't propagate → re-share shows dup card → remove is silent.
- Visual: 9 rig-parity shots vs `screenshots/rig-friends-panels.jpg`. Placement panels must match the SHIPPED views (Profile anatomy, detail action row, ＋ sheet anatomy) — build against the real screens, not the mockups.

## Out of scope

Feed/visibility · browsing friends' libraries · comments/reactions · groups · program sharing · APNs push · blocking.
