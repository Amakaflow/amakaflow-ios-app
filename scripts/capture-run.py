#!/usr/bin/env python3
"""Capture one AMA-2505 run: screenshot plus accessibility evidence per screen.

Built on the AMA-2503 probes rather than baseline-capture.yaml. That flow
navigates by 17 screen coordinates (`8%,10%`, `50%,35%`), and a coordinate tap
succeeds whether or not the intended control is under it — so it can produce a
screenshot that looks like evidence while showing the wrong screen. The probes
navigate by accessibility identifier, so a screen that cannot be reached fails
loudly instead of capturing something else.

Each screen yields three artifacts:

* the screenshot, which is what a person compares against the design
* the identifier inventory, which is what automation compares against
* a manifest row recording the build, device and status behind both

A screen whose probe fails is recorded BLOCKED with the failing step. It is
never silently skipped, because a missing row reads as "not audited" while a
skipped one reads as "nothing there".
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
import time

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
PROBE_DIRS = {
    "fixtures": REPO_ROOT / "e2e" / "maestro" / "identifier-truth",
    "seeded": REPO_ROOT / "e2e" / "maestro" / "seeded",
}
CAPTURES = REPO_ROOT / "docs" / "ui-captures"
MANIFESTS = CAPTURES / "manifests"
# A run id becomes a directory name. Without this, `../../x` writes evidence
# outside docs/ui-captures.
RUN_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def run(command: list[str], timeout: int) -> subprocess.CompletedProcess | None:
    try:
        return subprocess.run(
            command, capture_output=True, text=True, timeout=timeout, check=False
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        print(f"  {' '.join(command[:3])}: {type(exc).__name__}", file=sys.stderr)
        return None


def head_sha() -> str | None:
    """None when git cannot say. Evidence filed under an unverifiable build is
    worse than no evidence: it cannot be tied back to what was running, and a
    second failed run would overwrite the first under the same placeholder."""
    result = run(["git", "-C", str(REPO_ROOT), "rev-parse", "--short", "HEAD"], 30)
    if not result or result.returncode != 0 or not result.stdout.strip():
        return None
    return result.stdout.strip()


def device_name(udid: str) -> str:
    result = run(["xcrun", "simctl", "list", "devices", "-j"], 60)
    if not result or result.returncode != 0:
        return udid
    try:
        catalogue = json.loads(result.stdout)
    except json.JSONDecodeError:
        return udid
    for runtime, devices in catalogue.get("devices", {}).items():
        for device in devices:
            if device.get("udid") == udid:
                return f"{device.get('name', udid)} · {runtime.rsplit('.', 1)[-1]}"
    return udid


def auth_mode(probes: str) -> str:
    """Which identity produced this evidence, because it bounds what it proves.

    The probes use AF_SESSION_IDENTITY, a mock identity with no backend token,
    so screens render fixture data. That is deterministic and right for a
    structure map. It is NOT the seeded design-capture account AMA-2505
    specifies for the data-bearing runs, and a manifest that did not say so
    would overstate what was audited.
    """
    if probes == "seeded":
        return "persisted real Clerk session, baseline+clerk_test@amakaflow.dev"
    launch = (PROBE_DIRS["fixtures"] / "_launch.yaml").read_text(
        encoding="utf-8", errors="replace"
    )
    if "AF_SESSION_IDENTITY" in launch:
        return "mock identity + fixtures — NOT the seeded staging account"
    return "unknown"


def identifiers(udid: str) -> set[str] | None:
    result = run(["maestro", "--device", udid, "hierarchy"], timeout=180)
    if result is None or result.returncode != 0:
        return None
    try:
        tree = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
    names: set[str] = set()

    def walk(node: dict) -> None:
        found = (node.get("attributes") or {}).get("resource-id") or ""
        if found:
            names.add(found)
        for child in node.get("children") or []:
            walk(child)

    walk(tree)
    return names


def failing_step(output: str) -> str:
    for line in output.splitlines():
        if "FAILED" in line:
            return line.strip()[:120]
    return "probe did not complete"


def settled(udid: str, attempts: int = 6, gap: float = 2.0) -> set[str] | None:
    """Wait until the hierarchy stops changing, then return it.

    A screen can satisfy its probe while still loading: the root marker exists
    before the content does. Screenshotting at that moment files a spinner as
    evidence, which is the exact failure this whole audit exists to catch — and
    it did happen, on the seeded Library, before this guard existed.

    Two identical consecutive dumps mean the screen stopped changing. None
    means it never settled, which is a BLOCKED capture, not a CAPTURED one.
    """
    previous: set[str] | None = None
    for _ in range(attempts):
        current = identifiers(udid)
        if current is None:
            return None
        if previous is not None and current == previous and not loading(current):
            return current
        previous = current
        time.sleep(gap)
    return None


def loading(names: set[str]) -> bool:
    return any("loading" in name.lower() or "spinner" in name.lower() for name in names)


def capture(udid: str, flow: pathlib.Path, out_dir: pathlib.Path) -> dict:
    result = run(["maestro", "--device", udid, "test", str(flow)], timeout=600)
    if result is None:
        return {"screen": flow.stem, "status": "BLOCKED", "why": "probe did not run"}
    if result.returncode != 0:
        return {
            "screen": flow.stem,
            "status": "BLOCKED",
            "why": failing_step(result.stdout + result.stderr),
        }

    names = settled(udid)
    if names is None:
        return {
            "screen": flow.stem,
            "status": "BLOCKED",
            "why": "screen reached but never finished loading",
        }

    shot = out_dir / f"{flow.stem}.png"
    taken = run(["xcrun", "simctl", "io", udid, "screenshot", str(shot)], 120)
    if taken is None or taken.returncode != 0 or not shot.is_file():
        return {
            "screen": flow.stem,
            "status": "BLOCKED",
            "why": "screen reached but screenshot failed",
        }

    (out_dir / f"{flow.stem}.ids.txt").write_text(
        "\n".join(sorted(names)) + "\n", encoding="utf-8"
    )
    return {
        "screen": flow.stem,
        "status": "CAPTURED",
        "why": f"{len(names)} identifiers",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid", required=True)
    parser.add_argument("--run", required=True, help="run id, e.g. run-0-structure")
    parser.add_argument("--screens", nargs="+")
    parser.add_argument(
        "--probes",
        choices=sorted(PROBE_DIRS),
        default="fixtures",
        help="fixtures = mock identity, seeded = persisted real session",
    )
    args = parser.parse_args()

    if not RUN_ID.match(args.run):
        print(f"invalid --run {args.run!r}: use letters, digits, dot, dash, underscore", file=sys.stderr)
        return 1

    sha = head_sha()
    if sha is None:
        print("cannot resolve HEAD — refusing to file evidence against an unknown build", file=sys.stderr)
        return 1

    out_dir = CAPTURES / sha / args.run
    out_dir.mkdir(parents=True, exist_ok=True)
    MANIFESTS.mkdir(parents=True, exist_ok=True)

    probe_dir = PROBE_DIRS[args.probes]
    flows = sorted(p for p in probe_dir.glob("*.yaml") if not p.name.startswith("_"))
    if args.screens is not None:
        wanted = set(args.screens)
        missing = sorted(wanted - {p.stem for p in flows})
        if missing:
            # Dropping an unknown name and exiting 0 would report a complete run
            # while silently omitting a screen someone asked for.
            print(f"no probe flow for: {', '.join(missing)}", file=sys.stderr)
            return 1
        flows = [p for p in flows if p.stem in wanted]
    if not flows:
        print("no probe flows matched", file=sys.stderr)
        return 1

    rows = []
    for flow in flows:
        row = capture(args.udid, flow, out_dir)
        rows.append(row)
        print(f"{row['screen']}: {row['status']} — {row['why']}")

    captured = sum(1 for row in rows if row["status"] == "CAPTURED")
    manifest = [
        f"# Capture manifest — {args.run}",
        "",
        f"- build: `{sha}`",
        f"- device: {device_name(args.udid)}",
        f"- artifacts: `docs/ui-captures/{sha}/{args.run}/`",
        f"- auth: {auth_mode(args.probes)}",
        "",
        "Navigation is by accessibility identifier, not screen coordinates, so a",
        "screen that cannot be reached is recorded BLOCKED rather than",
        "screenshotting whatever happened to be on screen.",
        "",
        "| Screen | Status | Evidence |",
        "| --- | --- | --- |",
    ]
    manifest += [
        f"| `{row['screen']}` | {row['status']} | {row['why']} |" for row in rows
    ]
    manifest += ["", f"{captured} of {len(rows)} screens captured."]
    (MANIFESTS / f"{args.run}.md").write_text("\n".join(manifest) + "\n", encoding="utf-8")

    print(f"{captured}/{len(rows)} captured — manifest at docs/ui-captures/manifests/{args.run}.md")
    return 0 if captured == len(rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
