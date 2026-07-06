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
  p12_file="$(mktemp -t "${label}.XXXXXX.p12")"
  # shellcheck disable=SC2064
  trap "rm -f '$p12_file'" RETURN
  # Secrets are stored as single-line base64 (openssl base64 -A). macOS BSD
  # base64 --decode requires -A for that format; GNU base64 on preflight accepts
  # both. Use openssl for a consistent decode on GHA macOS runners.
  printf '%s' "$b64" | openssl base64 -d -A > "$p12_file"
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
