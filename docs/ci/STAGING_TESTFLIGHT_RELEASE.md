# Staging TestFlight release runbook (AMA-2259)

How to cut the next **staging-configured** TestFlight build for founder/device validation.

## What ships

Release/TestFlight builds default to **staging** at runtime:

- Mobile BFF: `https://mobile-bff.staging.amakaflow.com`
- Chat API: `https://chat-api-whkq.onrender.com`
- Clerk: staging publishable key (injected from GitHub secret at archive time)

See `AmakaFlow/Models/Environment.swift` — Release builds return `.staging` until production DNS is live.

## Prerequisites (one-time / when broken)

| Requirement | Where |
|-------------|-------|
| Apple Developer PLA accepted | [developer.apple.com/account](https://developer.apple.com/account) → Agreements (Account Holder) |
| ASC API key in GitHub secrets | `docs/ci/TESTFLIGHT_SECRETS.md` |
| Clerk staging publishable key secret | `CLERK_PUBLISHABLE_KEY_STAGING` on `Amakaflow/amakaflow-ios-app` |
| Internal testers | App Store Connect → TestFlight → Internal Testing |

If archive fails with **PLA Update available** or **No profiles found**, accept the PLA first — profile creation is blocked until then.

## Cut a build (normal path)

Every merge to `main` that touches app code triggers `.github/workflows/ios-testflight.yml` automatically.

1. Merge your PR to `main` (or push directly).
2. Open [Actions → iOS TestFlight Upload](https://github.com/Amakaflow/amakaflow-ios-app/actions/workflows/ios-testflight.yml).
3. Wait for **Archive + Upload to TestFlight** to finish green (~15–25 min).
4. Wait for App Store Connect processing (~5–30 min). Build appears under TestFlight → Builds.
5. Internal testers receive the update in the TestFlight app.

### Skip an upload

Include `[skip-testflight]` anywhere in the merge commit message. The workflow still runs preflight/contract gates but skips archive/upload.

### Manual re-run (no code change)

Actions tab → **iOS TestFlight Upload** → **Run workflow** → branch `main` → Run.

Use after fixing Apple account/signing issues without a new merge.

## Version and build numbers

| Field | Source | How to bump |
|-------|--------|-------------|
| **Marketing version** (`CFBundleShortVersionString`) | `MARKETING_VERSION` in `project.pbxproj` | Edit in Xcode target settings or pbxproj; commit before merge |
| **Build number** (`CFBundleVersion`) | CI only | **Do not commit.** Workflow sets `CURRENT_PROJECT_VERSION = 100 + github.run_number` at archive time |

CI build numbers monotonically increase per workflow run and stay above legacy manual uploads (build 39). To verify the build number for a run, check the workflow log step **Compute build number** or the **Inspect IPA Info.plist** step.

## Verify the uploaded IPA (CI)

The workflow inspects the exported IPA before `altool` upload:

- Clerk keys in Info.plist match GitHub secrets (non-empty, no `$(` placeholders)
- For v1, `CLERK_PUBLISHABLE_KEY_PRODUCTION` == staging secret (staging-is-production posture)

Local Debug sim builds use `scripts/sim-build.sh` — not the same as the Release IPA path.

## Post-upload checks

1. **ASC processing** — build status moves from Processing → Ready to Test.
2. **Golden-path smoke** — workflow job `golden-path-smoke` runs Maestro on a sim build of the same commit (post-upload alert, not a PR gate).
3. **Founder device smoke** — install from TestFlight on a physical device; record results on the Linear issue (see checklist in AMA-2259).

## Internal tester setup

1. App Store Connect → **Users and Access** — ensure tester has App Store Connect access.
2. **TestFlight → Internal Testing** — add the tester to the internal group for AmakaFlow Companion (`com.myamaka.AmakaFlowCompanion`).
3. Tester installs **TestFlight** from the App Store and accepts the invite.

## Troubleshooting

See `docs/ci/TESTFLIGHT_SECRETS.md` for:

- Certificate limit errors
- Clerk key mismatch in IPA inspection
- Missing provisioning profiles

## Related

- Workflow: `.github/workflows/ios-testflight.yml`
- Secrets setup: `docs/ci/TESTFLIGHT_SECRETS.md`
- Production readiness gap tracker: `docs/architecture/PRODUCTION_READINESS.md`
