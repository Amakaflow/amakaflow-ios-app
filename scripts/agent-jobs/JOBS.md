# Agent jobs (AMA-2447)

Versioned, **runner-agnostic** background jobs. Hermes (Mac mini) is the
intended scheduler, but every job here runs identically under launchd,
cron, or by hand — the scheduler supervises; the scripts are the truth.

Design rules (all jobs):

- **Deterministic scripts, models on the outside.** The scripts invoke only
  the toolchain (git/gh/just/xcodebuild/maestro). An LLM (MiniMax for
  volume, Claude for judgment) may *read* their outputs to triage — it
  never sits inside the loop.
- **Idempotent + single-shot** — safe to invoke repeatedly; state files
  make unchanged inputs a no-op (`make-operations-idempotent`).
- **Comment/artifact output only.** No job pushes branches, merges,
  labels, closes PRs/tickets, or touches production. All AMA-2444 hygiene
  rules apply to anything a triage agent authors from these outputs.
- **Fixture/staging credentials only** in the runner's environment. No
  production keys, no prod Supabase, no real user accounts.

## cursor-watch

| | |
|---|---|
| Purpose | Give Cursor cloud agents the compiler loop they lack: build + impacted tests for every new push to a `cursor/*` branch, verdict commented on the PR. Root-cause fix for the invented-signature failures (PRs #600, #604). |
| Trigger | Every 5–10 min (Hermes schedule / launchd interval) |
| Runtime | ~30 s no-op; ~5–15 min per new SHA (warm DerivedData) |
| Model | None (deterministic) |
| Requires | macOS, Xcode, `just`, `gh` authed, simulator |
| State | `$STATE_DIR` (default `~/.amakaflow/cursor-watch`) — last SHA per branch |
| Output | One PR comment per new SHA (`<!-- cursor-watch -->` marker) |
| Escalation | None. Failing verdicts are the Cursor agent's (or reviewer's) signal, not this job's problem. |

## nightly-qa-matrix

| | |
|---|---|
| Purpose | Nightly full-suite evidence run: build, entire unit suite, all Maestro flows. v1 = everything that exists; the AMA-2446 scenario matrix grows into it automatically. |
| Trigger | Nightly (e.g. 03:00 local) on main |
| Runtime | 30–60 min |
| Model | None (deterministic). Triage of `summary.md` → MiniMax; ticket-worthy findings escalate to Claude, filed per AMA-2444 rules. |
| Requires | macOS, Xcode, `just`, simulator; `maestro` optional (stage skips cleanly) |
| Output | `$OUTPUT_DIR/<stamp>/` — build/tests/maestro logs, `TestResults.xcresult`, maestro junit, `summary.md` digest |
| Exit | 0 green · 1 failures (digest still written) · 2 setup error |
| Escalation | Digest → Telegram daily (production-readiness-digest pattern); repeated same-test failures → regression ticket, `Part of AMA-2446`. |

Both support `--dry-run` (prints the plan, executes nothing) — use it to
verify wiring on a new runner before scheduling.
