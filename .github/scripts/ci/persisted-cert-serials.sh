#!/usr/bin/env bash
# AMA-2361 — Print the certificate serial numbers held in the persisted .p12
# GitHub secrets, so CI can ask the Apple portal whether those exact identities
# are still valid (and so cert hygiene knows what it must never revoke).
#
# Only public certificate metadata is emitted — never the key material.
# Writes "SERIAL SERIAL" to stdout, and one "TYPE SERIAL SUBJECT" line per
# identity to stderr for human-readable logs.
set -euo pipefail

: "${APPLE_DISTRIBUTION_CERTIFICATE_P12:?APPLE_DISTRIBUTION_CERTIFICATE_P12 required}"
: "${APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD:?APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD required}"
: "${APPLE_DEVELOPMENT_CERTIFICATE_P12:?APPLE_DEVELOPMENT_CERTIFICATE_P12 required}"
: "${APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD:?APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD required}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

serial_of() {
  local b64="$1"
  local password="$2"
  local label="$3"
  local p12="$WORK_DIR/${label}.p12"
  local pem="$WORK_DIR/${label}.pem"

  printf '%s' "$b64" | tr -cd 'A-Za-z0-9+/=' | openssl base64 -d -A > "$p12" 2>/dev/null || {
    echo "::error::${label} .p12 secret is not valid base64." >&2
    return 1
  }

  # GitHub secrets pasted through the UI often carry a trailing newline.
  password="${password//$'\r'/}"
  while [ "${password%$'\n'}" != "$password" ]; do password="${password%$'\n'}"; done

  # Keychain Access exports legacy RC2-encrypted PKCS#12; OpenSSL 3 needs the
  # legacy provider for those, but rejects -legacy on some builds. Try both.
  if ! openssl pkcs12 -in "$p12" -nokeys -passin "pass:${password}" -out "$pem" 2>/dev/null; then
    if ! openssl pkcs12 -in "$p12" -nokeys -legacy -passin "pass:${password}" -out "$pem" 2>/dev/null; then
      echo "::error::Could not read ${label} .p12 — wrong password or corrupt secret. Re-set per docs/ci/TESTFLIGHT_SECRETS.md" >&2
      return 1
    fi
  fi

  local serial subject
  serial="$(openssl x509 -in "$pem" -noout -serial | cut -d= -f2)"
  subject="$(openssl x509 -in "$pem" -noout -subject | sed -E 's/.*CN ?= ?([^,\/]+).*/\1/')"
  if [ -z "$serial" ]; then
    echo "::error::Could not extract a serial number from the ${label} .p12." >&2
    return 1
  fi
  echo "${label} ${serial} ${subject}" >&2
  printf '%s' "$serial"
}

DIST_SERIAL="$(serial_of "$APPLE_DISTRIBUTION_CERTIFICATE_P12" "$APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD" distribution)"
DEV_SERIAL="$(serial_of "$APPLE_DEVELOPMENT_CERTIFICATE_P12" "$APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD" development)"

printf '%s %s\n' "$DIST_SERIAL" "$DEV_SERIAL"
