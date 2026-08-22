#!/usr/bin/env python3
"""Find accessibility identifiers that a container identifier hides at runtime.

A SwiftUI view that declares `.accessibilityIdentifier` collapses its subtree
into one element unless it also declares `.accessibilityElement(children:
.contain)`. Identifiers on the descendants then do not exist at runtime, even
though they are right there in the source.

Proven on device: `af_detail_actions` hid `af_detail_pin`, `af_detail_collect`,
`af_detail_towatch` and `af_detail_share`. Adding `children: .contain` to that
one container brought all four back into the hierarchy dump.

Source position alone cannot prove shadowing, because whether a modifier lands
on an ancestor depends on the view tree rather than on indentation. This
reports candidates for a live hierarchy dump to arbitrate.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent

IDENTIFIER = re.compile(r"\.accessibilityIdentifier\(")
CONTAIN = re.compile(r"\.accessibilityElement\(\s*children:\s*\.contain\s*\)")
BLOCK_START = re.compile(r"^\s*(?:@ViewBuilder\s+)?(?:var body|(?:private |fileprivate )?(?:var|func)\s+\w+)")
NAME = re.compile(r'\.accessibilityIdentifier\(\s*"([^"]+)"')


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip())


def describe(line: str) -> str:
    match = NAME.search(line)
    return match.group(1) if match else line.strip()[:60]


def blocks(lines: list[str]) -> list[tuple[int, int]]:
    """Split a file into view-body ranges so scopes never span declarations."""
    starts = [n for n, line in enumerate(lines) if BLOCK_START.match(line)]
    if not starts:
        return [(0, len(lines))]
    bounds = []
    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(lines)
        bounds.append((start, end))
    return bounds


def audit(path: pathlib.Path) -> list[str]:
    lines = path.read_text(errors="replace").splitlines()
    findings = []

    for start, end in blocks(lines):
        marks = [
            (n, indent_of(lines[n]))
            for n in range(start, end)
            if IDENTIFIER.search(lines[n])
        ]
        if len(marks) < 2:
            continue

        for position, (line_no, indent) in enumerate(marks):
            deeper = [
                lines[n] for n, other in marks[:position] if other > indent
            ]
            if not deeper:
                continue
            window = lines[max(start, line_no - 6):line_no + 1]
            if any(CONTAIN.search(text) for text in window):
                continue
            container = describe(lines[line_no])
            names = {describe(text) for text in deeper} - {container}
            if not names:
                # Same identifier at two indents is one conditional modifier
                # chain, not a container over a child.
                continue
            hidden = ", ".join(sorted(names)[:4])
            findings.append(
                f"{display(path)}:{line_no + 1}: "
                f"{describe(lines[line_no])} may hide {hidden}"
            )

    return findings


def display(path: pathlib.Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def sources() -> list[pathlib.Path]:
    roots = [REPO_ROOT / "AmakaFlow", REPO_ROOT / "AmakaFlowCompanion"]
    found = []
    for root in roots:
        for path in root.rglob("*.swift"):
            parts = set(path.parts)
            if parts & {"Tests", "UITests"} or ".spm" in parts:
                continue
            if "Tests" in path.parent.name or "UITests" in path.parent.name:
                continue
            found.append(path)
    return sorted(found)


SELECTOR = re.compile(r'"((?:af_|dd_|builder_v3_|create_|coach-)[A-Za-z0-9_\-]+|[a-z]+_tab|[a-z]+_screen)"')


def automation_identifiers() -> set[str]:
    """Identifiers the Maestro flows and XCUITests actually depend on."""
    used: set[str] = set()
    flows = REPO_ROOT / "e2e" / "maestro"
    if flows.is_dir():
        for path in flows.rglob("*.yaml"):
            text = path.read_text(errors="replace")
            used.update(re.findall(r'id:\s*"([^"]+)"', text))
            used.update(SELECTOR.findall(text))
    for root in (REPO_ROOT / "AmakaFlowCompanion",):
        for path in root.rglob("*.swift"):
            if "UITests" not in str(path):
                continue
            used.update(SELECTOR.findall(path.read_text(errors="replace")))
    return used


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=pathlib.Path)
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument(
        "--impact",
        action="store_true",
        help="only candidates hiding an identifier a flow or XCUITest names",
    )
    args = parser.parse_args()

    paths = args.paths or sources()
    findings = [message for path in paths for message in audit(path)]

    if args.impact:
        used = automation_identifiers()
        findings = [
            message
            for message in findings
            if any(
                name.strip() in used
                for name in message.split(" may hide ", 1)[-1].split(",")
            )
        ]
        print(f"{len(used)} identifiers referenced by automation")

    if not args.quiet:
        for message in findings:
            print(message)
    print(f"checked {len(paths)} files, {len(findings)} candidates")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
