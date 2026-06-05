# TestFlight CI secrets (AMA-1852)

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

The workflow runs a **Secrets preflight** job before archive. It fails fast with a link to this doc if required secrets are missing or the `.p8` is malformed.

## Build numbers

CI sets `CURRENT_PROJECT_VERSION = 100 + github.run_number` so TestFlight build numbers stay above the last manual upload (build 39) without committing `pbxproj` bumps.

## Troubleshooting

### `Your account has reached the maximum number of certificates`

Apple Developer accounts allow a limited number of distribution certificates. CI `-allowProvisioningUpdates` tries to create new ones when profiles are missing.

**Fix (manual, ~5 min):**

1. [developer.apple.com](https://developer.apple.com/account/resources/certificates/list) → **Certificates**.
2. Revoke **expired** or **duplicate** “Apple Distribution” / “iOS Distribution” certificates you no longer use (keep the one matching your last successful manual TestFlight upload if unsure).
3. Re-run the workflow (`workflow_dispatch` on Actions tab, or push an empty commit to `main`).

If the error persists, ensure the ASC API key role can manage certificates and that bundle IDs `com.myamaka.AmakaFlowCompanion` (+ extensions: Share, Watch, Live Activity) have App Store distribution profiles in **Profiles**.

### `CLERK_PUBLISHABLE_KEY_* does not match the secret value`

xcodebuild silently dropped a build-setting override. Check the **Archive** step env block and compare IPA PlistBuddy output in the workflow log.

### `No profiles for 'com.myamaka…' were found`

Usually precedes the certificate-limit error. Fixing certificates/profiles in the Developer portal resolves both.

## Verify AMA-1852 acceptance

- [x] `ios-testflight.yml` on `main`
- [x] ASC API key secrets wired
- [x] Clerk staging + dev secrets wired
- [x] Build number auto-bump in workflow
- [ ] Green archive + altool upload on 2 consecutive `main` merges
- [ ] Sentry dSYM upload confirmed on a promoted build (check Sentry release for matching build number)

## Related

- Workflow: `.github/workflows/ios-testflight.yml`
- Production readiness gap #3: `docs/architecture/PRODUCTION_READINESS.md`
- Local Release archive debugging: `scripts/sim-build.sh` (Debug only; TestFlight uses Release in CI)
