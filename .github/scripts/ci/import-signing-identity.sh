#!/usr/bin/env bash
# AMA-2267 — Import persisted Apple Distribution + Development identities into a
# CI keychain so xcodebuild reuses them instead of minting new certs each run.
# Expects base64-encoded .p12 blobs + passwords from GitHub secrets (never log values).
set -euo pipefail

KEYCHAIN_NAME="${KEYCHAIN_NAME:-build.keychain-db}"
KEYCHAIN_PASSWORD="${APPLE_KEYCHAIN_PASSWORD:?APPLE_KEYCHAIN_PASSWORD required}"

import_p12() {
  local b64="$1"
  local password="$2"
  local label="$3"
  local p12_file
  local clean_b64
  local size

  # macOS mktemp requires XXXXXX at end of template (not .p12 suffix after X's).
  p12_file="$(mktemp "${TMPDIR:-/tmp}/amaka-${label}.XXXXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -f '$p12_file'" RETURN

  clean_b64="$(printf '%s' "$b64" | tr -d '[:space:]')"
  if [ -z "$clean_b64" ]; then
    echo "::error::${label}: GitHub secret is empty. Re-upload from docs/ci/TESTFLIGHT_SECRETS.md"
    exit 1
  fi

  if ! printf '%s' "$clean_b64" | openssl base64 -d -A > "$p12_file" 2>/dev/null; then
    echo "::error::${label}: base64 decode failed. Re-upload: openssl base64 -A -in YourCert.p12 | gh secret set APPLE_${label^^}_CERTIFICATE_P12 --repo Amakaflow/amakaflow-ios-app"
    exit 1
  fi

  size="$(wc -c < "$p12_file" | tr -d ' ')"
  if [ "$size" -lt 500 ]; then
    echo "::error::${label}: decoded p12 is only ${size} bytes (expected ~3000+). Secret is corrupt — re-upload the .p12 secret."
    exit 1
  fi

  if ! openssl pkcs12 -info -in "$p12_file" -noout -passin "pass:${password}" -legacy >/dev/null 2>&1; then
    # Fallback: macOS Keychain import (handles legacy RC2 p12 from Keychain Access export).
    if ! security import "$p12_file" -k "$KEYCHAIN_NAME" -P "$password" \
      -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/xcodebuild \
      -A 2>/tmp/"${label}"-import.err; then
      if grep -qi "MAC verification failed\|password" /tmp/"${label}"-import.err; then
        echo "::error::${label}: wrong export password in APPLE_${label^^}_CERTIFICATE_PASSWORD."
      else
        echo "::error::${label}: import failed — re-upload APPLE_${label^^}_CERTIFICATE_P12 via GitHub UI (paste from: openssl base64 -A -in YourCert.p12 | pbcopy)."
      fi
      cat /tmp/"${label}"-import.err >&2
      exit 1
    fi
    rm -f "$p12_file" /tmp/"${label}"-import.err
    trap - RETURN
    return 0
  fi

  echo "Importing ${label} identity (${size} bytes)..."
  security import "$p12_file" -k "$KEYCHAIN_NAME" -P "$password" \
    -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/xcodebuild \
    -A

  rm -f "$p12_file"
  trap - RETURN
}

echo "Creating CI keychain: ${KEYCHAIN_NAME}"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
security default-keychain -s "$KEYCHAIN_NAME"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
security set-keychain-settings -lut 7200 "$KEYCHAIN_NAME"

import_p12 "${APPLE_DISTRIBUTION_CERTIFICATE_P12:?APPLE_DISTRIBUTION_CERTIFICATE_P12 required}" \
  "${APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD:?APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD required}" \
  distribution
import_p12 "${APPLE_DEVELOPMENT_CERTIFICATE_P12:?APPLE_DEVELOPMENT_CERTIFICATE_P12 required}" \
  "${APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD:?APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD required}" \
  development

security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"

# Prepend CI keychain so codesign finds the imported identities first.
existing_keychains="$(security list-keychains -d user | sed 's/^[[:space:]]*"\(.*\)".*/\1/' | tr '\n' ' ')"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN_NAME" $existing_keychains

echo "Imported signing identities (public metadata only):"
security find-identity -v -p codesigning "$KEYCHAIN_NAME"
