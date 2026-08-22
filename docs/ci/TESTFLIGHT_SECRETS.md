# TestFlight CI secrets (AMA-1852, AMA-2267, AMA-2361)

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

**Before creating new certs:** run the hygiene workflow (below) — never hand-pick certificates in the portal UI. If the account is at the limit, revoke the accumulated "Created via API" certs first; do not create new ones until slots are free.

> ⚠️ **Never revoke certificates from the Apple portal UI.** The portal gives no
> indication which certificate is the one persisted in GitHub secrets. Revoking
> the wrong one puts CI back on the cert-minting treadmill (AMA-2361).
> Use `ios-cert-hygiene.yml`, which derives its keep-list from the `.p12`
> secrets themselves and therefore cannot revoke a persisted identity.

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

Import script: `.github/scripts/ci/import-signing-identity.sh` (runs on macOS archive job only). It exits non-zero unless **both** identities land in the CI keychain — a partial import must never fall through to `-allowProvisioningUpdates`.

## Certificate hygiene (AMA-2361) — the permanent process

### Why this exists

`xcodebuild archive` signs this project **for development**: every app target is
`CODE_SIGN_STYLE = Automatic` with no `CODE_SIGN_IDENTITY` override, so the archive
needs *iOS App Development* profiles and therefore a usable Apple Development
certificate. Distribution signing only happens later, at `-exportArchive` with
`method: app-store-connect`.

That makes the persisted **Development** certificate load-bearing. If it stops being
valid in the portal, `-allowProvisioningUpdates` mints a replacement "Created via API"
certificate on the ephemeral runner and the private key dies with the job — so the next
run mints another one. Builds keep passing until the account runs out of certificate
slots, then every run fails at once. That is exactly what happened between 2026-07-15
(persisted Development cert revoked) and build 338 on 2026-07-31.

AMA-2267 persisted the identities. AMA-2361 added the part that was missing: **CI now
asks Apple whether the persisted identities are still valid, and refuses to archive if
they are not.**

### The three guards

| Guard | Where | Behaviour |
|---|---|---|
| Portal verification | `secrets-preflight` job, ~1 min on Ubuntu | Extracts the serials from the `.p12` secrets and matches them against `GET /v1/certificates`. Missing (revoked/deleted) or expired ⇒ hard fail before any macOS minutes are spent. |
| Import assertion | `import-signing-identity.sh` | Exits non-zero unless both `Apple Distribution:` and `Apple Development:` identities are installed. |
| Hygiene workflow | `ios-cert-hygiene.yml` (`workflow_dispatch`) | Lists/verifies/revokes. Keep-list is derived from the `.p12` secrets, so persisted identities can never be revoked. |

### Running the hygiene workflow

```bash
# See everything on the account. KEEP=YES marks the persisted identities.
gh workflow run ios-cert-hygiene.yml --repo Amakaflow/amakaflow-ios-app -f mode=list

# Dry run — print the API-minted certs that would be revoked.
gh workflow run ios-cert-hygiene.yml --repo Amakaflow/amakaflow-ios-app -f mode=revoke-dupes

# Actually free the slots.
gh workflow run ios-cert-hygiene.yml --repo Amakaflow/amakaflow-ios-app -f mode=revoke-dupes -f apply=true
```

`revoke-dupes` only touches certificates whose display name is **`Created via API`** and
whose serial is not in the keep-list. Certificates you created by hand in the portal, and
non-signing certificates (Developer ID, push, Apple Pay), are never touched.

### Re-issuing a persisted signing identity

Do this when the preflight reports `Persisted signing certificate <serial> is NOT in the
Apple Developer portal`, or ahead of the yearly expiry.

1. Free a slot first if the account is at the limit:
   `gh workflow run ios-cert-hygiene.yml -f mode=revoke-dupes -f apply=true`
2. **Keychain Access → Certificate Assistant → Request a Certificate from a Certificate
   Authority** → save the `.certSigningRequest`.
3. [developer.apple.com → Certificates](https://developer.apple.com/account/resources/certificates/list)
   → **+** → *Apple Development* (or *Apple Distribution*) → upload the CSR → download the
   `.cer` → double-click to install.
4. In Keychain Access, export the new identity (certificate **and** private key) as `.p12`.
5. Update the secret and confirm the serial changed:

```bash
gh secret set APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD --repo Amakaflow/amakaflow-ios-app --body "your-export-password"
gh secret set APPLE_DEVELOPMENT_CERTIFICATE_P12 --repo Amakaflow/amakaflow-ios-app -b "$(openssl base64 -A -in ~/Downloads/Development.p12)"

gh workflow run ios-cert-hygiene.yml --repo Amakaflow/amakaflow-ios-app -f mode=verify
```

6. Re-run TestFlight: `gh workflow run ios-testflight.yml --repo Amakaflow/amakaflow-ios-app --ref main`

### Checking an identity locally

```bash
# Is the identity the keychain holds still honoured by Apple?
security find-identity -v -p codesigning   # CSSMERR_TP_CERT_REVOKED ⇒ revoked

# Authoritative answer, with the revocation timestamp:
security find-certificate -c "Apple Development: <name>" -p > /tmp/c.pem
curl -sO https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
openssl x509 -inform DER -in AppleWWDRCAG3.cer -out /tmp/wwdr.pem
openssl ocsp -issuer /tmp/wwdr.pem -cert /tmp/c.pem -url http://ocsp.apple.com/ocsp03-wwdrg301 \
  -header "Host=ocsp.apple.com" -noverify
```

### Known non-fix: pinning the archive to Apple Distribution

Passing `CODE_SIGN_IDENTITY="Apple Distribution"` to `xcodebuild archive` would remove the
Development-certificate dependency entirely, but Xcode rejects it while the targets are on
automatic signing:

> `AmakaFlowCompanion has conflicting provisioning settings. AmakaFlowCompanion is
> automatically signed for development, but a conflicting code signing identity Apple
> Distribution has been manually specified.`

A command-line override also leaks into SPM resource-bundle targets
(`Signing for "GRDB_GRDB" requires a development team`). Removing the Development
certificate from the critical path therefore requires switching the app targets to
**manual signing with App Store provisioning profiles persisted as secrets** — a larger
change, tracked separately.

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
| `AF_CLERK_PASSWORD` | Maestro golden-path sign-in |
| `AF_CLERK_EMAIL` | Reserved for future explicit email override |
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

**Fix:**

1. `gh workflow run ios-cert-hygiene.yml --repo Amakaflow/amakaflow-ios-app -f mode=revoke-dupes -f apply=true` — frees the slots without any risk of revoking a persisted identity. **Do not revoke by hand in the portal UI.**
2. `-f mode=verify` — confirms both persisted identities are still valid in the portal. If one is missing, follow *Re-issuing a persisted signing identity* above; slot cleanup alone will not stop the recurrence.
3. Re-run the workflow (`workflow_dispatch` on Actions tab, or push to `main`).

Since AMA-2361 the archive should never be where you discover this: `secrets-preflight` fails in about a minute when a persisted identity is no longer valid. Hitting the limit *after* a green preflight means something minted a certificate mid-run — attach `archive.log` to the issue.

### `CLERK_PUBLISHABLE_KEY_* does not match the secret value`

xcodebuild silently dropped a build-setting override. Check the **Archive** step env block and compare IPA PlistBuddy output in the workflow log.

### `No profiles for 'com.myamaka…' were found`

Reported as *iOS App Development* profiles even on a Release archive — that is expected, see *Why this exists* above. It follows the certificate-limit error rather than causing it: Xcode could not obtain a Development certificate, so it had nothing to build a profile against. Fix the certificate and the profile error goes with it.

### `Signing certificate is invalid … It may have been revoked or expired`

The persisted identity is no longer honoured by Apple. Confirm with the OCSP snippet above, then follow *Re-issuing a persisted signing identity*. Note the CI runner will **not** report this — a fresh keychain has no revocation cache, so `security find-identity -v` happily lists a revoked certificate as valid. That false green is why the portal preflight exists.

### Post-upload smoke hangs (AMA-2276)

**Historical:** post-upload smoke used to run inside `ios-testflight.yml`; AMA-2280/2283 moved it to a nightly workflow, which was retired 2026-07-08 (see scoreboard section above). Scheduled UI smoke no longer exists; use the `run-maestro` PR label for on-demand flows.

## Verify AMA-1852 / AMA-2267 acceptance

- [x] `ios-testflight.yml` on `main`
- [x] ASC API key secrets wired
- [x] Clerk staging + dev secrets wired
- [x] Build number auto-bump in workflow
- [x] Persisted signing `.p12` secrets wired (AMA-2267)
- [x] Green archive + altool upload on 2 consecutive runs with **zero** new portal certs (verified 2026-07-22 — builds 311 + 312; AMA-2296)
- [x] Portal-verified cert preflight + hygiene workflow (AMA-2361) — the 2026-07-22 check above passed *before* the Development cert was revoked on 2026-07-15+, and nothing re-checked it for two weeks
- [ ] Sentry dSYM upload confirmed on a promoted build (check Sentry release for matching build number)

## Related

- **Release runbook:** `docs/ci/STAGING_TESTFLIGHT_RELEASE.md` (how to cut the next staging TestFlight build)
- Workflow: `.github/workflows/ios-testflight.yml`
- Production readiness gap #3: `docs/architecture/PRODUCTION_READINESS.md`
- Local Release archive debugging: `scripts/sim-build.sh` (Debug only; TestFlight uses Release in CI)
