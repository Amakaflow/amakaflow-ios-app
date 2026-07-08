# TestFlight CI secrets (AMA-1852, AMA-2267)

Setup guide for `.github/workflows/ios-testflight.yml` — auto-upload to TestFlight on every `main` push that touches app code.

## Required GitHub secrets

Configure at **Settings → Secrets and variables → Actions** on `Amakaflow/amakaflow-ios-app`.

| Secret | Purpose | Status |
|--------|---------|--------|
| `APP_STORE_CONNECT_API_KEY_ID` | ASC API key ID (10 chars) | Required |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | ASC issuer UUID | Required |
| `APP_STORE_CONNECT_API_PRIVATE_KEY` | Raw `.p8` PEM contents (include `BEGIN/END` lines) | Required |
| `CLERK_PUBLISHABLE_KEY_STAGING` | Baked into Release IPA; v1 uses staging as production | Required |
| `CLERK_PUBLISHABLE_KEY_DEV` | solid-chicken-50 dev key in Info.plist | Required (workflow falls back to public default if unset) |
| `APPLE_KEYCHAIN_PASSWORD` | Ephemeral CI keychain unlock password (any strong random string) | Required (AMA-2267) |
| `APPLE_DISTRIBUTION_CERTIFICATE_P12` | Base64-encoded `.p12` export of **one** Apple Distribution cert | Required (AMA-2267) |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | Export password for the Distribution `.p12` | Required (AMA-2267) |
| `APPLE_DEVELOPMENT_CERTIFICATE_P12` | Base64-encoded `.p12` export of **one** Apple Development cert | Required (AMA-2267) |
| `APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD` | Export password for the Development `.p12` | Required (AMA-2267) |

### Create the App Store Connect API key

1. [App Store Connect](https://appstoreconnect.apple.com) → **Users and Access** → **Integrations** → **App Store Connect API**.
2. Generate a key with **Admin** or **App Manager** role.
3. Download the `.p8` once — Apple does not let you download it again.
4. Set three secrets:
   - `APP_STORE_CONNECT_API_KEY_ID` = Key ID from the table
   - `APP_STORE_CONNECT_API_KEY_ISSUER_ID` = Issuer ID at top of the page
   - `APP_STORE_CONNECT_API_PRIVATE_KEY` = entire file contents

```bash
# Example (run from the directory containing AuthKey_XXXXXXXXXX.p8)
gh secret set APP_STORE_CONNECT_API_KEY_ID --repo Amakaflow/amakaflow-ios-app --body "XXXXXXXXXX"
gh secret set APP_STORE_CONNECT_API_KEY_ISSUER_ID --repo Amakaflow/amakaflow-ios-app --body "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
gh secret set APP_STORE_CONNECT_API_PRIVATE_KEY --repo Amakaflow/amakaflow-ios-app < AuthKey_XXXXXXXXXX.p8
```

### Persisted signing identities (AMA-2267)

CI imports **one** Apple Distribution + **one** Apple Development certificate (with private keys) into an ephemeral runner keychain before archive/export. This stops each run from minting new "Created via API" certs and hitting Apple's slot limit.

**Before creating new certs:** check [Certificates](https://developer.apple.com/account/resources/certificates/list). If the account is at the limit, **revoke accumulated "Created via API" Development/Distribution certs first** — do not create new ones until slots are free.

#### One-time cert creation (founder, on a Mac with Keychain Access)

1. Open **Keychain Access** → **Certificate Assistant** → **Request a Certificate from a Certificate Authority** → save a `.certSigningRequest` to disk.
2. [developer.apple.com → Certificates](https://developer.apple.com/account/resources/certificates/list) → **+**:
   - Create **Apple Distribution** (App Store Connect) — download `.cer`, double-click to install.
   - Create **Apple Development** — download `.cer`, double-click to install.
3. In Keychain Access, export each identity (cert + private key) as `.p12` with a strong export password. **Never commit `.p12` files or passwords to git.**
4. Base64-encode and store as GitHub secrets:

```bash
# Distribution (use -b with openssl -A — single-line base64, no paste corruption)
gh secret set APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD --repo Amakaflow/amakaflow-ios-app --body "your-export-password"
gh secret set APPLE_DISTRIBUTION_CERTIFICATE_P12 --repo Amakaflow/amakaflow-ios-app -b "$(openssl base64 -A -in ~/Downloads/Distribution.p12)"

# Development
gh secret set APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD --repo Amakaflow/amakaflow-ios-app --body "your-export-password"
gh secret set APPLE_DEVELOPMENT_CERTIFICATE_P12 --repo Amakaflow/amakaflow-ios-app -b "$(openssl base64 -A -in ~/Downloads/Certificates.p12)"

# CI keychain password (any strong random string — not the p12 export password)
gh secret set APPLE_KEYCHAIN_PASSWORD --repo Amakaflow/amakaflow-ios-app --body "$(openssl rand -base64 32)"
```

5. After wiring secrets, run **two consecutive** `workflow_dispatch` builds and confirm **zero** new certificates appear in the Apple portal.

Import script: `.github/scripts/ci/import-signing-identity.sh` (runs on macOS archive job only).

### Clerk publishable keys

v1 ships against **staging** Clerk (see workflow header — `CLERK_PUBLISHABLE_KEY_PRODUCTION` = staging secret).

```bash
gh secret set CLERK_PUBLISHABLE_KEY_STAGING --repo Amakaflow/amakaflow-ios-app --body "pk_test_…"
gh secret set CLERK_PUBLISHABLE_KEY_DEV --repo Amakaflow/amakaflow-ios-app --body "pk_test_c29saWQtY2hpY2tlbi01MC5jbGVyay5hY2NvdW50cy5kZXYk"
```

Dev key is the public solid-chicken-50 instance (same as `scripts/sim-build.sh`).

## Optional secrets (post-upload golden-path smoke)

| Secret | Purpose |
|--------|---------|
| `UITEST_CLERK_PASSWORD` | Maestro golden-path sign-in |
| `UITEST_CLERK_EMAIL` | Reserved for future explicit email override |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | Page on smoke failure |
| `LINEAR_API_KEY` | Create P1 on smoke failure |
| `SENTRY_AUTH_TOKEN` | Used by Xcode “Upload Debug Symbols to Sentry” build phase |

## Preflight

The workflow runs a **Secrets preflight** job before archive. It fails fast with a link to this doc if required secrets are missing, malformed, or if `.p12` blobs are not valid base64.

## Build numbers

CI sets `CURRENT_PROJECT_VERSION = 100 + github.run_number` so TestFlight build numbers stay above the last manual upload (build 39) without committing `pbxproj` bumps.

## Build tags (AMA-2281)

After a successful altool upload, CI pushes a git tag:

- Pattern: `testflight/buildNNN` (e.g. `testflight/build261`)
- Points at: the commit that was built (`github.sha`)
- Purpose: anchor for **What to Test** diffing on the next release

List tags:

```bash
git fetch --tags origin
git tag -l 'testflight/build*' --sort=-version:refname | head
```

## What to Test automation (AMA-2281, absorbs AMA-2270)

After upload, CI sets TestFlight **What to Test** via the App Store Connect API (`betaBuildLocalizations.whatsNew`), using the same `APP_STORE_CONNECT_API_*` secrets as altool.

**Source text:** merge commit subjects since the previous `testflight/build*` tag:

```bash
git log <prev-tag-sha>..HEAD --merges --pretty='- %s'
```

`[AMA-XXXX]` prefixes are stripped; output is truncated at ~4000 characters. Script: `.github/scripts/ci/set-testflight-notes.sh`.

If notes cannot be set, the workflow **fails** after a successful upload (incomplete release).

## SHA-guarded dispatch (AMA-2281)

Stale `workflow_dispatch` runs against an old commit can burn ~10 minutes before failing. Pass `expected_sha` to abort in seconds when `origin/main` HEAD differs.

**GitHub Actions UI:** Run workflow → branch `main` → set **expected_sha** to the current main SHA.

**CLI:**

```bash
SHA=$(git rev-parse origin/main)
gh workflow run ios-testflight.yml --repo Amakaflow/amakaflow-ios-app --ref main -f "expected_sha=${SHA}"
```

**Wrong SHA (validation):** dispatch with a deliberately wrong SHA — the **Dispatch SHA guard** job should fail in under 1 minute.

Omit `expected_sha` for ad-hoc re-runs when you intentionally want to build whatever is on `main` at run time (no guard).

## Nightly Maestro smoke scoreboard (RETIRED 2026-07-08)

The nightly smoke workflow was removed at 0/10 green nights. GHA sims ran Maestro UI steps at ~8–20 s each; Clerk sign-in alone exceeded the per-flow timeout, so every run died mid-login without testing the app (run 28937274287 evidence). Coverage now: daily-driver dogfooding (AMA-2272) + on-demand `run-maestro` PR label. See `docs/ci/PIPELINE.md`.

## Troubleshooting

### `Your account has reached the maximum number of certificates`

Apple Developer accounts allow a limited number of **Development** and **Distribution** certificates. Before AMA-2267, CI `-allowProvisioningUpdates` minted a new Development cert on every ephemeral runner because the private key was lost between runs.

**Fix (manual, ~5 min):**

1. [developer.apple.com](https://developer.apple.com/account/resources/certificates/list) → **Certificates**.
2. Revoke **duplicate** "Created via API" **Development** and **Distribution** certificates (keep the two identities exported to GitHub secrets).
3. Ensure persisted `.p12` secrets are wired (see above) so CI reuses them instead of minting new certs.
4. Re-run the workflow (`workflow_dispatch` on Actions tab, or push to `main`).

The workflow error message now names **Development** vs **Distribution** when the limit trips.

### `CLERK_PUBLISHABLE_KEY_* does not match the secret value`

xcodebuild silently dropped a build-setting override. Check the **Archive** step env block and compare IPA PlistBuddy output in the workflow log.

### `No profiles for 'com.myamaka…' were found`

Usually precedes the certificate-limit error. Fixing certificates/profiles in the Developer portal resolves both. With persisted certs imported, `-allowProvisioningUpdates` should refresh profiles without creating new identities.

### Post-upload smoke hangs (AMA-2276)

**Historical:** post-upload smoke used to run inside `ios-testflight.yml`; AMA-2280/2283 moved it to a nightly workflow, which was retired 2026-07-08 (see scoreboard section above). Scheduled UI smoke no longer exists; use the `run-maestro` PR label for on-demand flows.

## Verify AMA-1852 / AMA-2267 acceptance

- [x] `ios-testflight.yml` on `main`
- [x] ASC API key secrets wired
- [x] Clerk staging + dev secrets wired
- [x] Build number auto-bump in workflow
- [ ] Persisted signing `.p12` secrets wired (AMA-2267)
- [ ] Green archive + altool upload on 2 consecutive runs with **zero** new portal certs
- [ ] Sentry dSYM upload confirmed on a promoted build (check Sentry release for matching build number)

## Related

- **Release runbook:** `docs/ci/STAGING_TESTFLIGHT_RELEASE.md` (how to cut the next staging TestFlight build)
- Workflow: `.github/workflows/ios-testflight.yml`
- Production readiness gap #3: `docs/architecture/PRODUCTION_READINESS.md`
- Local Release archive debugging: `scripts/sim-build.sh` (Debug only; TestFlight uses Release in CI)
