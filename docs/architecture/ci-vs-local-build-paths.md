# CI vs Local Build Paths

**Status:** active
**Owner:** AMA-1845
**Last updated:** 2026-05-10

## TL;DR

- **CI** runs `xcodebuild` with `-derivedDataPath AmakaFlowCompanion/DerivedData` and `-clonedSourcePackagesDirPath AmakaFlowCompanion/.spm` so `actions/cache` can persist these paths across runs (the cache action requires paths inside the workspace). This is intentional and saves 5–10 minutes per build.
- **Local dev** should NOT pass those flags. Use `scripts/sim-build.sh` (or plain `xcodebuild` from the project) so DerivedData lands in Xcode's default `~/Library/Developer/Xcode/DerivedData` and SPM checkouts in the SDK default. This keeps the working tree small.
- **Local CodeRabbit review** must be run via `scripts/cr-review.sh`, which stashes any in-tree artifact dirs before invoking the CLI. The CR CLI walks the working tree and ignores `.gitignore`; without the stash it OOMs server-side on Xcode-sized trees. See memory `coderabbit-cli-oom-root-cause.md` and AMA-1846 (vendor bug filed).

## Background

CI workflows at `.github/workflows/{pr-ios-tests,preflight,ios-testflight}.yml` pass:

```bash
xcodebuild test \
  -derivedDataPath AmakaFlowCompanion/DerivedData \
  -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm \
  ...
```

…paired with `actions/cache` blocks that persist those paths between runs. These paths are workspace-relative because GitHub Actions cache cannot persist paths outside the workspace.

If a developer copy-pastes these `xcodebuild` invocations locally (or runs `act` or any GHA-equivalent), the artifacts land inside the working tree. They are gitignored (see `.gitignore` lines 13–14), so they don't pollute commits — but tools that walk the working tree (CodeRabbit CLI, Sourcegraph, Spotlight, Time Machine, ripgrep) choke on the 5–10 GB volume.

## Rules

1. **Never run a CI-style `xcodebuild` invocation locally.** Use `scripts/sim-build.sh` for local builds. It does NOT pass `-derivedDataPath`.
2. **If you've already populated in-repo artifacts**, recover space with:
   ```bash
   git clean -fdx build/ AmakaFlowCompanion/DerivedData/ AmakaFlowCompanion/.spm/
   ```
   Quit Xcode first if it's open (it'll re-index from scratch on next launch).
3. **For local CodeRabbit reviews**, always invoke via `scripts/cr-review.sh`. Direct `coderabbit review` will OOM on this repo until the vendor bug (AMA-1846) is fixed.
4. **Do not add `.worktrees/` to any cleanup list.** It contains active git worktrees, not Xcode artifacts. Manage with `git worktree remove`.

## Affected paths

| Path | Owner | Safe to git clean? | Notes |
|------|-------|-------|-------|
| `build/` | xcodebuild output (CI flag) | ✅ when Xcode is closed | gitignored |
| `AmakaFlowCompanion/DerivedData/` | xcodebuild `-derivedDataPath` (CI flag) | ✅ when Xcode is closed | gitignored |
| `AmakaFlowCompanion/.spm/` | xcodebuild `-clonedSourcePackagesDirPath` (CI flag) | ✅ when Xcode is closed | gitignored; SPM will re-resolve on next build |
| `.worktrees/` | `git worktree add` targets | ❌ NEVER | active branches; use `git worktree remove` |

## Related

- AMA-1845 — this doc + `scripts/cr-review.sh`
- AMA-1846 — CR vendor bug (CLI ignores `.gitignore`)
- `docs/architecture/ama-1817-contract-first-postmortem.md` — broader CI/tooling narrative
- Memory: `coderabbit-cli-oom-root-cause.md`
