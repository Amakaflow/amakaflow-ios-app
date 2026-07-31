#!/usr/bin/env python3
"""AMA-2361 — safety net for asc-cert-hygiene.py.

`revoke-dupes` deletes Apple Developer certificates, and revoking the wrong one
is exactly the failure this tooling exists to prevent (the persisted Development
identity was revoked by hand on 2026-07-15, after which every TestFlight run
minted a throwaway certificate until the account hit its slot limit). These
tests pin the keep-list guarantees and the verify-mode exit codes.

No network: the ASC client is stubbed. Run with `python3 <this file>`.
"""

from __future__ import annotations

import importlib.util
import io
import os
import sys
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

SCRIPT = Path(__file__).with_name("asc-cert-hygiene.py")
_spec = importlib.util.spec_from_file_location("asc_cert_hygiene", SCRIPT)
assert _spec and _spec.loader
hygiene = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(hygiene)

# Real serials from the AMA-2361 incident, so the fixtures match the shape of
# what the portal actually returns.
KEEP_DIST = "4E78D36AA006660BB214ADED850F9D83"
KEEP_DEV = "426201B746C82BA81E2A30D3E5FDC010"
EXPECTED = {hygiene.normalise_serial(KEEP_DIST), hygiene.normalise_serial(KEEP_DEV)}

_failures: list[str] = []


def cert(
    cert_type: str,
    serial: str,
    display_name: str,
    expires: str = "2027-07-06T19:07:27.000+00:00",
    cert_id: str | None = None,
) -> dict:
    return {
        "id": cert_id or f"id-{serial[:6]}",
        "attributes": {
            "certificateType": cert_type,
            "serialNumber": serial,
            "displayName": display_name,
            "name": f"{cert_type} {serial}",
            "expirationDate": expires,
        },
    }


def rows(certs: list[dict]) -> list[dict]:
    return [hygiene.describe(c) for c in certs]


class StubClient:
    """Records revocations instead of calling Apple."""

    def __init__(self) -> None:
        self.revoked: list[str] = []

    def revoke(self, cert_id: str) -> None:
        self.revoked.append(cert_id)


def run(fn, *args) -> tuple[int, str]:
    out, err = io.StringIO(), io.StringIO()
    try:
        with redirect_stdout(out), redirect_stderr(err):
            code = fn(*args)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else 1
    return code, out.getvalue() + err.getvalue()


def check(name: str, condition: bool, detail: str = "") -> None:
    print(f"{'PASS' if condition else 'FAIL'}  {name}")
    if not condition:
        _failures.append(f"{name}{': ' + detail if detail else ''}")


def test_serial_normalisation() -> None:
    # ASC and openssl disagree about zero-padding and case for the same serial.
    check("normalise strips leading zeros", hygiene.normalise_serial("0656D6") == "656D6")
    check("normalise uppercases", hygiene.normalise_serial("abc") == "ABC")
    check("normalise strips colons", hygiene.normalise_serial("AB:CD") == "ABCD")


def test_verify_healthy() -> None:
    healthy = rows(
        [
            cert("DISTRIBUTION", KEEP_DIST, "David Christopher Andrews"),
            cert("DEVELOPMENT", KEEP_DEV, "David Christopher Andrews"),
        ]
    )
    code, out = run(hygiene.mode_verify, healthy, EXPECTED)
    check("verify passes when both persisted certs are present", code == 0, out)


def test_verify_revoked_development_cert() -> None:
    """The AMA-2361 incident: revoked certs vanish from the portal listing."""
    account = rows(
        [
            cert("DISTRIBUTION", KEEP_DIST, "David Christopher Andrews"),
            cert("DEVELOPMENT", "AAAA1111", hygiene.API_MINTED_DISPLAY_NAME),
            cert("DEVELOPMENT", "BBBB2222", hygiene.API_MINTED_DISPLAY_NAME),
        ]
    )
    code, out = run(hygiene.mode_verify, account, EXPECTED)
    check("verify fails when the persisted dev cert is gone", code == 1, out)
    check("verify names the missing serial", hygiene.normalise_serial(KEEP_DEV) in out, out)
    check("verify reports the API-minted junk", "junk: DEVELOPMENT AAAA1111" in out, out)
    check("verify points at the hygiene workflow", "ios-cert-hygiene.yml" in out, out)


def test_verify_expired() -> None:
    account = rows(
        [
            cert("DISTRIBUTION", KEEP_DIST, "x", expires="2020-01-01T00:00:00.000+00:00"),
            cert("DEVELOPMENT", KEEP_DEV, "x"),
        ]
    )
    code, out = run(hygiene.mode_verify, account, EXPECTED)
    check("verify fails on an expired persisted cert", code == 1, out)
    check("verify reports the expiry date", "expired on 2020-01-01" in out, out)


def test_verify_requires_keep_list() -> None:
    healthy = rows([cert("DISTRIBUTION", KEEP_DIST, "x")])
    code, out = run(hygiene.mode_verify, healthy, set())
    check("verify refuses to run without expected serials", code == 1, out)


def _mixed_account() -> list[dict]:
    return rows(
        [
            cert("DISTRIBUTION", KEEP_DIST, "David Christopher Andrews", cert_id="keep-dist"),
            cert("DEVELOPMENT", KEEP_DEV, "David Christopher Andrews", cert_id="keep-dev"),
            cert("DEVELOPMENT", "AAAA1111", hygiene.API_MINTED_DISPLAY_NAME, cert_id="junk1"),
            cert("DEVELOPMENT", "BBBB2222", hygiene.API_MINTED_DISPLAY_NAME, cert_id="junk2"),
            cert("DISTRIBUTION", "CCCC3333", hygiene.API_MINTED_DISPLAY_NAME, cert_id="junk3"),
            cert("DEVELOPMENT", "DDDD4444", "Made by hand in the portal", cert_id="handmade"),
            cert(
                "DEVELOPER_ID_APPLICATION",
                "EEEE5555",
                hygiene.API_MINTED_DISPLAY_NAME,
                cert_id="developer-id",
            ),
        ]
    )


def test_revoke_dry_run() -> None:
    client = StubClient()
    code, out = run(hygiene.mode_revoke_dupes, client, _mixed_account(), EXPECTED, False)
    check("dry run exits 0", code == 0, out)
    check("dry run revokes nothing", client.revoked == [], str(client.revoked))
    check("dry run says so", "Dry run" in out, out)


def test_revoke_apply() -> None:
    client = StubClient()
    code, out = run(hygiene.mode_revoke_dupes, client, _mixed_account(), EXPECTED, True)
    check("apply exits 0", code == 0, out)
    check(
        "apply revokes exactly the API-minted non-keep certs",
        sorted(client.revoked) == ["junk1", "junk2", "junk3"],
        str(client.revoked),
    )
    check("apply never revokes the persisted distribution cert", "keep-dist" not in client.revoked)
    check("apply never revokes the persisted development cert", "keep-dev" not in client.revoked)
    check("apply never revokes hand-made certs", "handmade" not in client.revoked)
    check("apply never revokes non-signing cert types", "developer-id" not in client.revoked)


def test_revoke_refuses_stale_keep_list() -> None:
    """Wrong serials in ⇒ the not-in-keep-list test cannot be trusted."""
    client = StubClient()
    account = rows([cert("DEVELOPMENT", "AAAA1111", hygiene.API_MINTED_DISPLAY_NAME, cert_id="junk1")])
    code, out = run(hygiene.mode_revoke_dupes, client, account, EXPECTED, True)
    check("refuses to revoke when the keep-list is absent from the account", code == 1, out)
    check("revokes nothing in that case", client.revoked == [], str(client.revoked))


def test_revoke_refuses_empty_keep_list() -> None:
    client = StubClient()
    code, out = run(hygiene.mode_revoke_dupes, client, _mixed_account(), set(), True)
    check("refuses to revoke with an empty keep-list", code == 1, out)
    check("revokes nothing with an empty keep-list", client.revoked == [], str(client.revoked))


def test_revoke_clean_account() -> None:
    client = StubClient()
    account = rows(
        [
            cert("DISTRIBUTION", KEEP_DIST, "x", cert_id="keep-dist"),
            cert("DEVELOPMENT", KEEP_DEV, "x", cert_id="keep-dev"),
        ]
    )
    code, out = run(hygiene.mode_revoke_dupes, client, account, EXPECTED, True)
    check("clean account exits 0", code == 0, out)
    check("clean account revokes nothing", client.revoked == [], str(client.revoked))


def test_load_expected_from_env() -> None:
    class Args:
        expect_serial = None

    os.environ["EXPECTED_CERT_SERIALS"] = f"{KEEP_DIST} {KEEP_DEV}"
    check("keep-list reads whitespace-separated env", hygiene.load_expected(Args()) == EXPECTED)
    os.environ["EXPECTED_CERT_SERIALS"] = f"{KEEP_DIST},{KEEP_DEV}"
    check("keep-list reads comma-separated env", hygiene.load_expected(Args()) == EXPECTED)
    os.environ.pop("EXPECTED_CERT_SERIALS", None)


def main() -> int:
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print()
    if _failures:
        print(f"{len(_failures)} failure(s):")
        for failure in _failures:
            print(f" - {failure}")
        return 1
    print("asc-cert-hygiene: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
