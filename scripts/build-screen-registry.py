#!/usr/bin/env python3
"""Generate the screen registry and design-artifact index from evidence.

Both documents are hand-maintained in most repos and rot within a release.
The columns that rot are the evidence ones: which screens a capture actually
reached, and which design artifact still has authority. Those are derivable,
so they are generated here and the judgement columns are left for a human.

Evidence sources, all read at run time:

* `docs/ui-captures/identifier-truth/*.txt` — screens a probe reached, from
  AMA-2503. A screen with an inventory is reachable by automation; one
  without is not, whatever the design docs claim.
* the design-parity matrix in amakaflow-docs — the surface list and the
  contract ticket per surface.
* the rig and screens artifacts in amakaflow-docs — classified by the rule
  the matrix already locked: an artifact a live ticket cites is Canonical, a
  superseded version is Legacy, anything uncited is Unknown.

Nothing here invents a screen. A row exists because a file does.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
PROBES = REPO_ROOT / "docs" / "ui-captures" / "identifier-truth"
OUT_DIR = REPO_ROOT / "docs" / "product"
CITATIONS = OUT_DIR / "artifact-citations.tsv"
DESIGN_STATUS = OUT_DIR / "screen-design-status.tsv"
CAPTURES = REPO_ROOT / "docs" / "ui-captures"

MATRIX_ROW = re.compile(r"^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|")
VERSIONED = re.compile(r"^(?P<stem>.*?)(?P<version>\d*)$")
# Only artifact-shaped tokens count. Matching any lowercase word let prose
# in a target cell promote an uncited artifact to Canonical, and Canonical
# is what establishes current UI.
ARTIFACT_TOKEN = re.compile(r"(?:rig|screens)-[a-z0-9-]+")
TITLE = re.compile(r"<title>([^<]+)</title>", re.IGNORECASE)
JSDOC = re.compile(r"/\*\*(.*?)\*/", re.DOTALL)


def matrix_surfaces(matrix: pathlib.Path) -> list[dict[str, str]]:
    rows = []
    for line in matrix.read_text(encoding="utf-8", errors="replace").splitlines():
        match = MATRIX_ROW.match(line)
        if not match:
            continue
        surface, target, ticket, verdict = (part.strip() for part in match.groups())
        if surface in {"Surface", ""} or set(surface) <= {"-", ":"}:
            continue
        rows.append(
            {"surface": surface, "target": target, "ticket": ticket, "verdict": verdict}
        )
    return rows


def design_status() -> dict[str, dict[str, str]]:
    """What each screen is meant to look like, and whether it is there yet.

    Hand-maintained: this is the only place a person states intent. Without it
    a capture of a screen awaiting redesign reads as a defect list, which is
    how the run-1 onboarding observations nearly became tickets for a screen
    that is about to be replaced.
    """
    if not DESIGN_STATUS.is_file():
        return {}
    rows: dict[str, dict[str, str]] = {}
    for line in DESIGN_STATUS.read_text(encoding="utf-8").splitlines()[1:]:
        if line.startswith("#") or not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        rows[parts[0].strip()] = {
            "artifact": parts[1].strip(),
            "ticket": parts[2].strip(),
            "status": parts[3].strip(),
            "note": parts[4].strip() if len(parts) > 4 else "",
        }
    return rows


def captured_screens() -> dict[str, str]:
    """Screens with a committed screenshot, mapped to where it lives."""
    found: dict[str, str] = {}
    if not CAPTURES.is_dir():
        return found
    for shot in sorted(CAPTURES.rglob("*.png")):
        if "unknown-artifacts" in shot.parts:
            continue
        found.setdefault(shot.stem, str(shot.relative_to(REPO_ROOT)))
    return found


def probed_screens() -> dict[str, int]:
    if not PROBES.is_dir():
        return {}
    return {
        path.stem: len([line for line in path.read_text(encoding="utf-8").splitlines() if line])
        for path in sorted(PROBES.glob("*.txt"))
    }


def artifacts(design_root: pathlib.Path) -> list[pathlib.Path]:
    if not design_root.is_dir():
        return []
    found = [
        path
        for pattern in ("rig*.html", "screens-*.jsx")
        for path in design_root.rglob(pattern)
        if path.is_file()
    ]
    return sorted(found, key=lambda p: p.name)


RENDERED = re.compile(r"screens-[a-z0-9-]+\.jsx")


def rendered_by_canonical(paths: list[pathlib.Path], cited: set[str]) -> dict[str, str]:
    """Screens a cited rig renders, mapped to the rig that renders them.

    The parity matrix cites rigs, and each rig renders a screens-*.jsx. Those
    screens are the source of a cited artifact, not uncited files, so authority
    propagates through the reference instead of stopping at the rig.
    """
    inherited: dict[str, str] = {}
    for path in paths:
        if path.suffix != ".html" or path.name.rsplit(".", 1)[0] not in cited:
            continue
        for name in RENDERED.findall(path.read_text(encoding="utf-8", errors="replace")):
            inherited.setdefault(name, path.name)
    return inherited


def ticket_citations() -> dict[str, tuple[str, str]]:
    """Artifacts a Linear ticket names, mapped to that ticket.

    The parity matrix lists 19 surfaces and is not the only place a design is
    cited. Most rigs are named by the ticket that commissioned them, in the
    description or an attachment, and those tickets never reach the matrix.
    Reading the matrix alone reported them as uncited.

    Checked in rather than queried at run time so the classification is
    reproducible offline and reviewable in a diff.
    """
    if not CITATIONS.is_file():
        return {}
    cited: dict[str, tuple[str, str]] = {}
    for line in CITATIONS.read_text(encoding="utf-8").splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) < 3 or not parts[0].strip():
            continue
        cited[parts[0].strip()] = (parts[1].strip(), parts[2].strip())
    return cited


def describe(path: pathlib.Path) -> str:
    """The rig's own <title>, which is what makes an entry recognisable.

    A filename says nothing to a reader deciding whether an artifact still has
    authority. Every rig already carries a written description; use it.
    """
    text = path.read_text(encoding="utf-8", errors="replace")
    if path.suffix == ".html":
        # No head slice: these rigs inline a large style block before <title>,
        # so a truncated read silently found nothing.
        match = TITLE.search(text)
        return match.group(1).strip() if match else "—"

    # Every screens-*.jsx opens with a JSDoc block naming what it holds. It is
    # the only description these files carry, and reading it is what turns a
    # bare filename into something a person can classify.
    block = JSDOC.search(text)
    if not block:
        return "—"
    lines = [
        line.strip().lstrip("*").strip()
        for line in block.group(1).splitlines()
    ]
    summary = " ".join(line for line in lines if line)
    return summary[:150].replace("|", "·") or "—"


def classify(
    paths: list[pathlib.Path], cited: set[str], root: pathlib.Path
) -> list[tuple[str, str, str]]:
    """Canonical when a live ticket cites it, Legacy when a newer sibling exists."""
    inherited = rendered_by_canonical(paths, cited)
    by_ticket = ticket_citations()
    by_stem: dict[str, list[tuple[int, pathlib.Path]]] = {}
    for path in paths:
        base = path.name.rsplit(".", 1)[0]
        match = VERSIONED.match(base)
        stem = match.group("stem")
        version = int(match.group("version") or 0)
        by_stem.setdefault(stem, []).append((version, path))

    rows = []
    for stem, entries in by_stem.items():
        newest = max(version for version, _ in entries)
        for version, path in sorted(entries):
            name = str(path.relative_to(root))
            if version < newest:
                # Supersession beats every citation source. A newer sibling on
                # disk is stronger evidence of what is current than an older
                # ticket or a rig that renders several versions at once.
                verdict = "Legacy"
                why = f"superseded by {stem}{newest}"
            elif path.name.rsplit(".", 1)[0] in cited:
                verdict = "Canonical"
                why = "cited by a live contract ticket in the parity matrix"
            elif path.name in by_ticket:
                ticket, state = by_ticket[path.name]
                verdict = "Canonical"
                why = f"cited by {ticket} ({state})"
            elif path.name in inherited:
                verdict = "Canonical"
                why = f"rendered by {inherited[path.name]}, which a live ticket cites"
            elif "DISPOSABLE" in describe(path).upper():
                # Several prototypes label themselves DISPOSABLE in their own
                # header. That is the author's classification; take it.
                verdict = "Deprecated"
                why = "the file's own header marks it DISPOSABLE"
            else:
                verdict = "Unknown"
                why = "no ticket and no matrix row cites it — classify before relying on it"
            shot = OUT_DIR / "unknown-artifacts" / f"{path.stem}.png"
            look = (
                f"[png](unknown-artifacts/{path.stem}.png)" if shot.is_file() else "—"
            )
            rows.append((name, describe(path), verdict, why, look))
    return sorted(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--docs-repo", type=pathlib.Path, required=True)
    args = parser.parse_args()

    matrix = args.docs_repo / "docs" / "superpowers" / "design-parity-matrix.md"
    if not matrix.is_file():
        print(f"parity matrix not found at {matrix}", file=sys.stderr)
        return 1

    surfaces = matrix_surfaces(matrix)
    probed = probed_screens()
    captures = captured_screens()
    intent = design_status()
    cited = {
        token
        for row in surfaces
        for token in ARTIFACT_TOKEN.findall(row["target"])
    }
    design_root = args.docs_repo / "design"

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    registry = [
        "# Screen registry v1",
        "",
        "Generated by `scripts/build-screen-registry.py`. Regenerate rather than",
        "hand-edit the evidence columns; they are derived from files on disk.",
        "",
        "`Runtime evidence` is the identifier inventory captured by AMA-2503's",
        "probes. A surface with no inventory has not been reached by automation,",
        "which is a fact about our tooling, not a claim about the screen.",
        "",
        "| Screen | Area | Evidence in app | Design of record | Ticket | Design status | Note |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]

    for name in sorted(set(probed) | set(captures) | set(intent)):
        design = intent.get(name, {})
        evidence = []
        if name in probed:
            evidence.append(f"{probed[name]} identifiers")
        if name in captures:
            evidence.append(f"[screenshot]({pathlib.Path('../..') / captures[name]})")
        registry.append(
            f"| `{name}` | runtime | {'; '.join(evidence) or 'none'} "
            f"| {design.get('artifact') or '—'} | {design.get('ticket') or '—'} "
            f"| {design.get('status') or 'UNKNOWN'} | {design.get('note') or '—'} |"
        )

    for row in surfaces:
        if row["surface"].lower().replace(" ", "-") in probed:
            continue
        registry.append(
            f"| {row['surface']} | design surface | none | {row['target']} "
            f"| {row['ticket']} | {row['verdict']} | from the parity matrix |"
        )

    registry += [
        "",
        f"{len(probed)} rows carry runtime evidence. "
        f"{len(surfaces)} design surfaces come from the parity matrix.",
        "",
        "Two granularities on purpose. A `runtime` row is a screen automation has",
        "actually reached; a `design surface` row is a target the matrix names.",
        "Reconciling the two is AMA-2508's job, and this table is where that",
        "happens.",
        "",
        "This is short of the 40-80 rows AMA-2504 asked for, and padding it would",
        "defeat the point. State rows (loading, empty, error) get added as the",
        "AMA-2505 capture runs actually reach them, so the count grows with",
        "evidence rather than ahead of it.",
        "",
        "Status values: TODO, CAPTURED, RECONCILED, CANONICAL, BLOCKED, OUT_OF_SCOPE.",
        "Only CANONICAL establishes current intended UI.",
    ]
    (OUT_DIR / "screen-registry.md").write_text("\n".join(registry) + "\n", encoding="utf-8")

    found = artifacts(design_root)
    index = [
        "# Design artifact index",
        "",
        "Generated by `scripts/build-screen-registry.py` from the artifacts in",
        "amakaflow-docs, using the rule the parity matrix already locked: an",
        "artifact a live contract ticket cites is the target; one no ticket cites",
        "is historical and carries no authority.",
        "",
        "Only **Canonical** establishes current UI.",
        "",
        "`Look` links a rendered capture where one exists, so an entry can be",
        "recognised on sight. Motion rigs animate, so a still catches them",
        "mid-transition and can look emptier than they are.",
        "",
        "| Artifact | What it is | Look | Classification | Why |",
        "| --- | --- | --- | --- | --- |",
    ]
    index += [
        f"| `{name}` | {title} | {look} | {verdict} | {why} |"
        for name, title, verdict, why, look in classify(found, cited, design_root)
    ]
    index += ["", f"{len(found)} artifacts classified."]
    (OUT_DIR / "design-artifact-index.md").write_text("\n".join(index) + "\n", encoding="utf-8")

    print(f"registry: {len(probed)} captured, {len(surfaces)} matrix surfaces")
    print(f"artifact index: {len(found)} artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
