#!/usr/bin/env python3
"""Record which accessibility identifiers exist at runtime, per screen.

Source is not evidence. An identifier can be spelled correctly in Swift and
still not exist in the tree the tests drive, because a container identifier
without `.accessibilityElement(children: .contain)` collapses its subtree
(AMA-2520). Grepping for `.accessibilityIdentifier` finds those and proves
nothing.

For each probe flow under e2e/maestro/identifier-truth, this navigates to one
screen and dumps the live hierarchy, then writes what was actually observed.
Screens whose probe fails are reported as BLOCKED rather than skipped, so a
screen we cannot reach never reads as a screen with no identifiers.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
PROBE_DIR = REPO_ROOT / "e2e" / "maestro" / "identifier-truth"
OUT_DIR = REPO_ROOT / "docs" / "ui-captures" / "identifier-truth"
BUNDLE_ID = "com.myamaka.AmakaFlowCompanion"

DECLARED = re.compile(r'\.accessibilityIdentifier\(\s*"([^"]+)"')
BUILD_DIRS = frozenset({"DerivedData", ".spm", "SourcePackages", "build", ".build"})


def declared_identifiers() -> dict[str, str]:
    """Literal identifiers in app sources, mapped to where they are declared.

    Interpolated identifiers are skipped on purpose: their runtime value
    depends on data, so absence from a dump proves nothing about them.
    """
    found: dict[str, str] = {}
    for root in (REPO_ROOT / "AmakaFlow", REPO_ROOT / "AmakaFlowCompanion"):
        for path in root.rglob("*.swift"):
            if not path.is_file() or set(path.parts) & BUILD_DIRS:
                continue
            if any("Tests" in part for part in path.parts[:-1]):
                continue
            for line_no, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
                for name in DECLARED.findall(line):
                    if "\\(" in name:
                        continue
                    found.setdefault(name, f"{path.relative_to(REPO_ROOT)}:{line_no}")
    return found


def run(command: list[str], timeout: int) -> subprocess.CompletedProcess | None:
    """None when the command could not run or did not finish.

    A hung driver or a missing maestro binary is a blocked screen, not a
    reason to abandon the remaining probes.
    """
    try:
        return subprocess.run(
            command, capture_output=True, text=True, timeout=timeout, check=False
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        print(f"  {' '.join(command[:3])}: {type(exc).__name__}", file=sys.stderr)
        return None


def observed(udid: str) -> set[str] | None:
    result = run(["maestro", "--device", udid, "hierarchy"], timeout=180)
    if result is None or result.returncode != 0:
        return None
    try:
        tree = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None

    names: set[str] = set()

    def walk(node: dict) -> None:
        identifier = (node.get("attributes") or {}).get("resource-id") or ""
        if identifier:
            names.add(identifier)
        for child in node.get("children") or []:
            walk(child)

    walk(tree)
    return names


def probe(udid: str, flow: pathlib.Path) -> set[str] | None:
    result = run(["maestro", "--device", udid, "test", str(flow)], timeout=600)
    if result is None or result.returncode != 0:
        return None
    return observed(udid)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid", required=True, help="booted simulator udid")
    parser.add_argument("--screens", nargs="*", help="probe names, default all")
    args = parser.parse_args()

    flows = sorted(p for p in PROBE_DIR.glob("*.yaml") if not p.name.startswith("_"))
    if args.screens:
        wanted = set(args.screens)
        flows = [p for p in flows if p.stem in wanted]
    if not flows:
        print("no probe flows matched", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    declared = declared_identifiers()
    seen_anywhere: set[str] = set()
    rows: list[tuple[str, str, int]] = []

    for flow in flows:
        names = probe(args.udid, flow)
        if names is None:
            rows.append((flow.stem, "BLOCKED", 0))
            print(f"{flow.stem}: BLOCKED")
            continue
        (OUT_DIR / f"{flow.stem}.txt").write_text("\n".join(sorted(names)) + "\n")
        rows.append((flow.stem, "CAPTURED", len(names)))
        print(f"{flow.stem}: {len(names)} identifiers")

    # Totals come from every inventory on disk, not just this run's screens.
    # Reading only the current run made a --screens subset overwrite the report
    # with totals that looked like full coverage and were not.
    for inventory in sorted(OUT_DIR.glob("*.txt")):
        stem = inventory.stem
        seen_anywhere |= {
            line for line in inventory.read_text().splitlines() if line
        }
        if stem not in {name for name, _, _ in rows}:
            rows.append((stem, "CAPTURED (earlier run)", len(seen_anywhere & set(
                inventory.read_text().splitlines()
            ))))
    rows.sort()

    unseen = sorted(name for name in declared if name not in seen_anywhere)
    report = [
        "# Identifier truth, per screen",
        "",
        "Generated by scripts/capture-identifiers.py. Every row is what a live",
        "hierarchy dump contained, not what the source declares.",
        "",
        "| screen | status | identifiers observed |",
        "| --- | --- | --- |",
    ]
    report += [f"| {name} | {status} | {count} |" for name, status, count in rows]
    report += [
        "",
        f"{len(declared)} literal identifiers are declared in app sources.",
        f"{len(seen_anywhere)} distinct identifiers were observed across the probes above.",
        "",
        "## Declared but not observed",
        "",
        "Not necessarily broken: a screen no probe visits cannot show its",
        "identifiers. Treat this as the queue to probe next, and only call an",
        "entry shadowed once a probe reaches its screen and it is still absent.",
        "",
    ]
    report += [f"- `{name}` ({declared[name]})" for name in unseen]
    (OUT_DIR / "REPORT.md").write_text("\n".join(report) + "\n")

    print(f"declared {len(declared)}, observed {len(seen_anywhere)}, unobserved {len(unseen)}")
    return 0 if all(status.startswith("CAPTURED") for _, status, _ in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
