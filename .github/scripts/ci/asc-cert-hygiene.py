#!/usr/bin/env python3
"""AMA-2361 — Apple Developer certificate hygiene via the App Store Connect API.

Background: `xcodebuild archive` signs this project for *development* (all app
targets are `CODE_SIGN_STYLE = Automatic` with no identity override), so
`-allowProvisioningUpdates` needs a usable Apple Development certificate. When
the persisted `.p12` identity is missing from the portal — revoked or expired —
Xcode silently mints a fresh "Created via API" certificate on the ephemeral
runner and throws the private key away at the end of the job. Builds keep
passing until the account runs out of certificate slots, at which point every
run fails with "Choose a certificate to revoke".

`verify` turns that silent degradation into a fast, loud failure. `list` and
`revoke-dupes` replace hand-picking certificates in the portal UI, which is how
the persisted Development identity got revoked in the first place (2026-07-15).

Modes:
  list          Print every certificate on the account.
  verify        Exit non-zero unless every expected serial is present and valid.
  revoke-dupes  Revoke API-minted certificates that are not expected serials.
                Dry-run unless --apply is passed.

Auth comes from ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API_ROOT = "https://api.appstoreconnect.apple.com/v1"

# Certificate types this tool is allowed to touch. Anything else on the account
# (Developer ID, Apple Pay, push, MDM…) is out of scope and never revoked.
SIGNING_CERT_TYPES = {
    "DEVELOPMENT",
    "IOS_DEVELOPMENT",
    "DISTRIBUTION",
    "IOS_DISTRIBUTION",
    "MAC_APP_DISTRIBUTION",
    "MAC_INSTALLER_DISTRIBUTION",
}

# Xcode stamps this display name on certificates it mints through the API.
API_MINTED_DISPLAY_NAME = "Created via API"


def normalise_serial(serial: str) -> str:
    """Compare serials without caring about case or leading zeros.

    openssl prints `426201B746C82BA81E2A30D3E5FDC010`; the ASC API is
    inconsistent about zero-padding the same value.
    """
    return serial.strip().upper().lstrip("0").replace(":", "").replace(" ", "")


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)


class AscClient:
    def __init__(self, key_id: str, issuer_id: str, private_key: str) -> None:
        self._key_id = key_id
        self._issuer_id = issuer_id
        self._private_key = private_key

    def _token(self) -> str:
        now = int(time.time())
        return jwt.encode(
            {"iss": self._issuer_id, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
            self._private_key,
            algorithm="ES256",
            headers={"kid": self._key_id, "typ": "JWT"},
        )

    def request(self, method: str, path: str) -> dict:
        url = path if path.startswith("http") else f"{API_ROOT}{path}"
        req = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {self._token()}",
                "Content-Type": "application/json",
            },
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            if exc.code == 401:
                fail(
                    "App Store Connect rejected the API key (401). Check "
                    "APP_STORE_CONNECT_API_KEY_ID / _ISSUER_ID / _PRIVATE_KEY secrets."
                )
            fail(f"ASC API {method} {url} failed ({exc.code}): {detail}")
        except urllib.error.URLError as exc:
            fail(f"ASC API {method} {url} unreachable: {exc.reason}")
        raise AssertionError("unreachable")

    def certificates(self) -> list[dict]:
        # Revoking a certificate in App Store Connect is a DELETE, and revoked
        # certificates drop out of this listing entirely. "Present here" is
        # therefore the same question as "will Xcode accept this identity", which
        # is what `verify` relies on.
        certs: list[dict] = []
        path = "/certificates?limit=200"
        while path:
            page = self.request("GET", path)
            certs.extend(page.get("data") or [])
            path = (page.get("links") or {}).get("next") or ""
        return certs

    def revoke(self, cert_id: str) -> None:
        self.request("DELETE", f"/certificates/{cert_id}")


def describe(cert: dict) -> dict:
    attrs = cert.get("attributes") or {}
    expires_raw = attrs.get("expirationDate") or ""
    expired = False
    if expires_raw:
        try:
            expires = dt.datetime.fromisoformat(expires_raw.replace("Z", "+00:00"))
            expired = expires < dt.datetime.now(dt.timezone.utc)
        except ValueError:
            pass
    return {
        "id": cert.get("id", ""),
        "type": attrs.get("certificateType", ""),
        "name": attrs.get("name", ""),
        "display_name": attrs.get("displayName", ""),
        "serial": attrs.get("serialNumber", ""),
        "expires": expires_raw[:10],
        "expired": expired,
    }


def print_table(rows: list[dict], expected: set[str]) -> None:
    if not rows:
        print("No certificates on the account.")
        return
    print(f"{'TYPE':<26} {'EXPIRES':<11} {'KEEP':<5} {'SERIAL':<34} {'ID':<12} NAME")
    for row in sorted(rows, key=lambda r: (r["type"], r["expires"])):
        keep = "YES" if normalise_serial(row["serial"]) in expected else ""
        flag = " (EXPIRED)" if row["expired"] else ""
        name = row["display_name"] or row["name"]
        print(
            f"{row['type']:<26} {row['expires']:<11} {keep:<5} "
            f"{row['serial']:<34} {row['id']:<12} {name}{flag}"
        )


def load_expected(args: argparse.Namespace) -> set[str]:
    raw: list[str] = list(args.expect_serial or [])
    env_serials = os.environ.get("EXPECTED_CERT_SERIALS", "")
    raw.extend(part for part in env_serials.replace(",", " ").split() if part)
    return {normalise_serial(s) for s in raw if s.strip()}


def mode_verify(rows: list[dict], expected: set[str]) -> int:
    if not expected:
        fail(
            "verify needs at least one expected serial "
            "(--expect-serial or EXPECTED_CERT_SERIALS)."
        )

    by_serial = {normalise_serial(r["serial"]): r for r in rows}
    missing = sorted(expected - by_serial.keys())
    expired = sorted(s for s in expected & by_serial.keys() if by_serial[s]["expired"])

    api_minted = [
        r
        for r in rows
        if r["type"] in SIGNING_CERT_TYPES
        and r["display_name"] == API_MINTED_DISPLAY_NAME
        and normalise_serial(r["serial"]) not in expected
    ]

    for serial in sorted(expected & by_serial.keys()):
        row = by_serial[serial]
        state = "EXPIRED" if row["expired"] else "valid"
        print(f"✅ persisted {row['type']} {row['serial']} present in portal ({state}, exp {row['expires']})")

    if api_minted:
        print(
            f"::warning::{len(api_minted)} API-minted certificate(s) on the account are not "
            "persisted in GitHub secrets. Their private keys died with the runner that "
            "created them. Free the slots with: "
            "gh workflow run ios-cert-hygiene.yml -f mode=revoke-dupes -f apply=true"
        )
        for row in api_minted:
            print(f"   junk: {row['type']} {row['serial']} id={row['id']} exp={row['expires']}")

    if missing or expired:
        for serial in missing:
            print(
                f"::error::Persisted signing certificate {serial} is NOT in the Apple "
                "Developer portal — it was revoked or deleted.",
                file=sys.stderr,
            )
        for serial in expired:
            print(
                f"::error::Persisted signing certificate {serial} expired on "
                f"{by_serial[serial]['expires']}.",
                file=sys.stderr,
            )
        print(
            "::error::Refusing to archive: -allowProvisioningUpdates would mint a new "
            '"Created via API" certificate whose private key dies with this runner, '
            "burning an Apple certificate slot on every run. Re-issue the identity and "
            "update the .p12 secret — see docs/ci/TESTFLIGHT_SECRETS.md "
            "(section: Re-issuing a persisted signing identity).",
            file=sys.stderr,
        )
        return 1

    print("✅ All persisted signing identities are present and valid in the portal.")
    return 0


def mode_revoke_dupes(client: AscClient, rows: list[dict], expected: set[str], apply: bool) -> int:
    if not expected:
        fail(
            "revoke-dupes needs the persisted serials as a keep-list "
            "(--expect-serial or EXPECTED_CERT_SERIALS) so it cannot revoke them."
        )

    known = {normalise_serial(r["serial"]) for r in rows}
    unknown_keep = sorted(expected - known)
    if unknown_keep:
        # The keep-list should describe certificates that actually exist. If it
        # doesn't, the caller passed the wrong serials and the "not in keep-list"
        # test is not trustworthy enough to delete anything.
        fail(
            "Keep-list serials are not present on the account: "
            + ", ".join(unknown_keep)
            + ". Run mode=list first and fix the persisted .p12 secrets before revoking."
        )

    victims = [
        r
        for r in rows
        if r["type"] in SIGNING_CERT_TYPES
        and r["display_name"] == API_MINTED_DISPLAY_NAME
        and normalise_serial(r["serial"]) not in expected
    ]

    if not victims:
        print("✅ No API-minted duplicate certificates to revoke.")
        return 0

    print(f"{len(victims)} API-minted certificate(s) not backed by a GitHub secret:")
    for row in victims:
        print(f"   {row['type']:<26} {row['serial']:<34} id={row['id']} exp={row['expires']}")

    if not apply:
        print("\nDry run — nothing revoked. Re-run with apply=true to revoke the list above.")
        return 0

    failures = 0
    for row in victims:
        serial_norm = normalise_serial(row["serial"])
        if serial_norm in expected:
            # Belt and braces: never delete a persisted identity, whatever the filter did.
            print(f"::error::Refusing to revoke keep-list serial {row['serial']}", file=sys.stderr)
            failures += 1
            continue
        try:
            client.revoke(row["id"])
            print(f"revoked {row['type']} {row['serial']} (id={row['id']})")
        except SystemExit:
            failures += 1
    if failures:
        return 1
    print(f"\n✅ Revoked {len(victims)} API-minted certificate(s).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("list", "verify", "revoke-dupes"), default="list")
    parser.add_argument(
        "--expect-serial",
        action="append",
        help="Serial of a certificate persisted in GitHub secrets. Repeatable. "
        "Also read from EXPECTED_CERT_SERIALS (whitespace or comma separated).",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="revoke-dupes only: actually revoke instead of listing.",
    )
    args = parser.parse_args()

    missing_env = [
        name
        for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY")
        if not os.environ.get(name)
    ]
    if missing_env:
        fail(f"Missing required env: {', '.join(missing_env)}")

    client = AscClient(
        os.environ["ASC_KEY_ID"],
        os.environ["ASC_ISSUER_ID"],
        os.environ["ASC_PRIVATE_KEY"],
    )
    expected = load_expected(args)
    rows = [describe(c) for c in client.certificates()]

    if args.mode == "list":
        print_table(rows, expected)
        return 0
    if args.mode == "verify":
        return mode_verify(rows, expected)
    return mode_revoke_dupes(client, rows, expected, args.apply)


if __name__ == "__main__":
    sys.exit(main())
