# Pre-deploy validation

AMA-1777. Two scripts that catch the class of bugs that ship to TestFlight
because the unit-test surface (Debug+mocked) misses what only the Release+
production code path hits.

## What's here

### `check-hosts.sh`
Parses `AmakaFlow/Models/Environment.swift`, pulls every URL in the
`case .staging:` and `case .production:` arms, and DNS-resolves each.

```
./scripts/preflight/check-hosts.sh
./scripts/preflight/check-hosts.sh --strict-production
```

Behaviour:
- Staging gaps are **merge-blocking** (exit 1).
- Production gaps **warn but pass** by default — production `*.amakaflow.com`
  hosts aren't stood up yet. Use `--strict-production` once they exist.

### `check-info-plist.sh`
Greps a built `Info.plist` for `$(VAR_NAME)` placeholders that didn't get
substituted, and for empty `<string></string>` values on keys ending in
`_KEY`, `_SECRET`, `_TOKEN`, `_DSN`. Either is the silent-fail pattern that
shipped Bug A (build 25) on 2026-05-06.

```
./scripts/preflight/check-info-plist.sh path/to/AmakaFlowCompanion.app/Info.plist
```

Run after `xcodebuild archive` against the resulting `.app/Info.plist` —
**not** the source file in `AmakaFlowCompanion/AmakaFlowCompanion/Info.plist`,
which legitimately contains `$(...)` markers waiting for substitution.

## CI

`.github/workflows/preflight.yml` runs both jobs:

- `check-hosts` runs on every PR to `main` whose diff touches the iOS source
  or the preflight scripts.
- `check-info-plist` runs on `workflow_dispatch` only (because it needs an
  Xcode build, which is slow and signing-gated).

The future-work item from AMA-1777 is a Release simulator smoke-launch job
that boots the built `.app` and asserts the process survives N seconds —
that catches Bug A end-to-end without needing a TestFlight roundtrip.

## Before you ship

If you're about to click Distribute in Xcode, run locally:

```
./scripts/preflight/check-hosts.sh
xcodebuild ... archive ...
./scripts/preflight/check-info-plist.sh \
  ~/Library/Developer/Xcode/Archives/<date>/<archive>.xcarchive/Products/Applications/AmakaFlowCompanion.app/Info.plist
```

If both pass, the build is at least free of the two classes of bugs that
got us on 2026-05-06.
