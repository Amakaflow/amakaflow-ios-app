#!/usr/bin/env bash
# AMA-2267 — Import persisted Apple Distribution + Development identities into a
# CI keychain so xcodebuild reuses them instead of minting new certs each run.
# Expects base64-encoded .p12 blobs + passwords from GitHub secrets (never log values).
set -euo pipefail

KEYCHAIN_NAME="${KEYCHAIN_NAME:-build.keychain-db}"
KEYCHAIN_PASSWORD="${APPLE_KEYCHAIN_PASSWORD:?APPLE_KEYCHAIN_PASSWORD required}"

# Strip anything that is not base64 alphabet (handles UI paste BOM/spaces/newlines).
clean_b64() {
  printf '%s' "$1" | tr -cd 'A-Za-z0-9+/='
}

import_p12() {
  local b64="$1"
  local password="$2"
  local label="$3"
  local secret_name="$4"
  local p12_file
  local cleaned
  local size
  local magic

  p12_file="$(mktemp "${TMPDIR:-/tmp}/amaka-${label}.XXXXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -f '$p12_file'" RETURN

  cleaned="$(clean_b64 "$b64")"
  if [ -z "$cleaned" ]; then
    echo "::error::${secret_name} is empty. Run: gh secret set ${secret_name} --repo Amakaflow/amakaflow-ios-app -b \"\$(openssl base64 -A -in ~/Downloads/YourCert.p12)\""
    exit 1
  fi

  if ! printf '%s' "$cleaned" | openssl base64 -d -A > "$p12_file" 2>/dev/null; then
    echo "::error::${secret_name} is not valid base64. Run: gh secret set ${secret_name} --repo Amakaflow/amakaflow-ios-app -b \"\$(openssl base64 -A -in ~/Downloads/YourCert.p12)\""
    exit 1
  fi

  size="$(wc -c < "$p12_file" | tr -d ' ')"
  magic="$(xxd -p -l 2 "$p12_file" 2>/dev/null || echo "??")"
  if [ "$size" -lt 500 ] || [ "$magic" != "3082" ]; then
    echo "::error::${secret_name} decodes to ${size} bytes (header ${magic}); expected ~3000+ bytes starting 3082. Secret is corrupt — re-set with gh -b command from docs/ci/TESTFLIGHT_SECRETS.md"
    exit 1
  fi

  # GitHub secrets sometimes include a trailing newline from UI paste.
  password="${password//$'\r'/}"
  while [ "${password%$'\n'}" != "$password" ]; do password="${password%$'\n'}"; done

  # Keychain Access exports legacy RC2 PKCS#12. GHA macOS security(1) rejects them
  # with "Unknown format in import" even when bytes/size are valid (run #158).
  local modern_p12="${p12_file}.modern"
  if openssl pkcs12 -in "$p12_file" -passin "pass:${password}" -legacy \
      -export -out "$modern_p12" -passout "pass:${password}" 2>/tmp/"${label}"-rewrap.err; then
    mv "$modern_p12" "$p12_file"
    size="$(wc -c < "$p12_file" | tr -d ' ')"
    echo "Re-wrapped ${label} PKCS#12 for CI keychain (${size} bytes)."
  elif grep -qi "Mac verify error\|invalid password\|password" /tmp/"${label}"-rewrap.err; then
    echo "::error::Wrong password in ${secret_name%_P12}_PASSWORD (openssl pkcs12 MAC verify failed)."
    cat /tmp/"${label}"-rewrap.err >&2
    exit 1
  else
    echo "::warning::${label}: PKCS#12 re-wrap skipped; attempting direct import."
    rm -f "$modern_p12"
  fi

  echo "Importing ${label} (${size} bytes)..."
  if ! security import "$p12_file" -k "$KEYCHAIN_NAME" -P "$password" \
    -f pkcs12 \
    -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/xcodebuild \
    -A 2>/tmp/"${label}"-import.err; then
    if grep -qi "MAC verification failed\|password" /tmp/"${label}"-import.err; then
      echo "::error::Wrong password in ${secret_name%_P12}_PASSWORD (MAC verification failed)."
    else
      echo "::error::security import failed for ${secret_name}."
      cat /tmp/"${label}"-import.err >&2
    fi
    exit 1
  fi

  rm -f "$p12_file" /tmp/"${label}"-import.err
  trap - RETURN
}

echo "Creating CI keychain: ${KEYCHAIN_NAME}"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
security default-keychain -s "$KEYCHAIN_NAME"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
security set-keychain-settings -lut 7200 "$KEYCHAIN_NAME"

import_p12 "${APPLE_DISTRIBUTION_CERTIFICATE_P12:?}" \
  "${APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD:?}" \
  distribution "APPLE_DISTRIBUTION_CERTIFICATE_P12"
import_p12 "${APPLE_DEVELOPMENT_CERTIFICATE_P12:?}" \
  "${APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD:?}" \
  development "APPLE_DEVELOPMENT_CERTIFICATE_P12"

security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"

existing_keychains="$(security list-keychains -d user | sed 's/^[[:space:]]*"\(.*\)".*/\1/' | tr '\n' ' ')"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN_NAME" $existing_keychains

echo "Imported signing identities (public metadata only):"
security find-identity -v -p codesigning "$KEYCHAIN_NAME"
