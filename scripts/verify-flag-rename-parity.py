#!/usr/bin/env python3
"""Differential proof that the wire-name rename changed no flow's resolved state.

A rename across forty-odd producer files is only acceptable if it is provable.
``LaunchConfig.decode`` is pure, so both sides can be run for real: this
compiles the decoder from the pre-rename revision and the decoder from the
working tree into two host executables, extracts every producer's flag block
from each revision, and diffs the resolved config.

Any flow whose resolved config changes is reported. The dead flags did nothing
before the rename, so the flows that carried them are expected to differ only
by the disappearance of a state they never actually had; each such diff names
what the flow claimed versus what it had.

Simulator-free. Runs in seconds.

Usage: scripts/verify-flag-rename-parity.py [base-ref]
"""
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DECODER = "AmakaFlow/Services/LaunchConfig.swift"
HOST = ROOT / "scripts" / "parity" / "main.swift"
DEFAULT_BASE = "feature/ama-2502-launch-config"

FLAG = re.compile(r"(?:UITEST|AMA\d{4}|AF)_[A-Z0-9_]+")


# --- producer extraction -----------------------------------------------------

def _maestro(text, rel):
    """`launchApp: arguments:` blocks. iOS surfaces these as argv and as
    app-defaults keys, so a record carries both; never as environment."""
    out, lines = [], text.splitlines()
    for i, line in enumerate(lines):
        if not re.match(r"^\s*arguments:\s*$", line):
            continue
        indent = len(line) - len(line.lstrip())
        pairs = {}
        for row in lines[i + 1:]:
            if not row.strip() or row.lstrip().startswith("#"):
                continue
            if len(row) - len(row.lstrip()) <= indent:
                break
            hit = re.match(r"^\s*([A-Za-z0-9_]+)\s*:\s*(.*?)\s*$", row)
            if not hit:
                break
            pairs[hit.group(1)] = hit.group(2).strip('"\'')
        if pairs:
            out.append((f"{rel}:{i + 1}", _argv_record(pairs)))
    return out


def _argv_record(pairs):
    argv = []
    for key, value in pairs.items():
        argv += [f"-{key}", value]
    return {"argv": argv, "defaults": dict(pairs), "env": {}}


def _swift(text, rel):
    """XCUITest `launchEnvironment` dictionaries and element assignments.
    These arrive only as process environment."""
    out, lines = [], text.splitlines()
    literal = {}
    start = None
    depth = 0
    for i, line in enumerate(lines):
        hit = re.search(r'launchEnvironment\s*\[\s*"([A-Z0-9_]+)"\s*\]\s*=\s*(.+?)\s*$', line)
        if hit:
            out.append((f"{rel}:{i + 1}", {"argv": [], "defaults": {},
                                           "env": {hit.group(1): _swift_value(hit.group(2))}}))
            continue
        if re.search(r"launchEnvironment\s*(?::\s*\[String\s*:\s*String\])?\s*=\s*\[", line):
            start, depth, literal = i + 1, 0, {}
        if start is None:
            continue
        depth += line.count("[") - line.count("]")
        for key, value in re.findall(r'"([A-Z0-9_]+)"\s*:\s*(.+?)\s*,?\s*$', line):
            literal[key] = _swift_value(value)
        if depth <= 0:
            if literal:
                out.append((f"{rel}:{start}", {"argv": [], "defaults": {}, "env": literal}))
            start = None
    return out


def _swift_value(raw):
    raw = raw.strip().rstrip(",").strip()
    if raw.startswith('"') and raw.endswith('"'):
        return raw[1:-1]
    return "<expr>"


def _shell(text, rel):
    """`simctl launch … -FLAG value` becomes argv plus defaults the same way
    Maestro's arguments do; `SIMCTL_CHILD_FLAG=value` becomes environment."""
    args, env = {}, {}
    for key, value in re.findall(r'SIMCTL_CHILD_((?:UITEST|AMA\d{4}|AF)_[A-Z0-9_]+)=([^\s\\]+|\'[^\']*\'|"[^"]*")', text):
        env[key] = value.strip('"\'')
    for key, value in re.findall(r'\s-((?:UITEST|AMA\d{4}|AF)_[A-Z0-9_]+)\s+(\'[^\']*\'|"[^"]*"|[^\s\\]+)', text):
        args[key] = value.strip('"\'')
    if not args and not env:
        return []
    record = _argv_record(args)
    record["env"] = env
    return [(rel, record)]


def producers(read):
    """read(rel) -> text or None. Returns {key: record}."""
    found = {}
    for rel in tracked():
        text = read(rel)
        if text is None or not FLAG.search(text):
            continue
        if rel.startswith("e2e/maestro/") and rel.endswith(".yaml"):
            items = _maestro(text, rel)
        elif "UITests/" in rel and rel.endswith(".swift"):
            items = _swift(text, rel)
        elif rel.startswith("scripts/") and rel.endswith(".sh"):
            items = _shell(text, rel)
        else:
            continue
        found.update(dict(items))
    return found


def tracked():
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True,
                         text=True, check=True).stdout.splitlines()
    return [p for p in out if p.endswith((".yaml", ".swift", ".sh"))]


# --- decoders ----------------------------------------------------------------

def build(workdir, name, decoder_source):
    src = workdir / f"{name}.swift"
    src.write_text(decoder_source)
    binary = workdir / name
    subprocess.run(
        ["swiftc", "-DDEBUG", "-O", "-o", str(binary), str(src), str(HOST)],
        check=True, cwd=workdir,
    )
    return binary


def resolve(binary, records):
    payload = "\n".join(
        json.dumps({"name": key, **record}) for key, record in sorted(records.items())
    )
    out = subprocess.run([str(binary)], input=payload, capture_output=True,
                         text=True, check=True).stdout
    return dict(line.split("\t", 1) for line in out.splitlines() if "\t" in line)


def at_ref(ref, rel):
    result = subprocess.run(["git", "show", f"{ref}:{rel}"], cwd=ROOT,
                            capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else None


def here(rel):
    path = ROOT / rel
    return path.read_text(errors="replace") if path.exists() else None


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_BASE
    if shutil.which("swiftc") is None:
        print("swiftc not found", file=sys.stderr)
        return 2

    legacy_source = at_ref(base, DECODER)
    if legacy_source is None:
        print(f"no {DECODER} at {base}", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory() as tmp:
        workdir = Path(tmp)
        legacy_bin = build(workdir, "legacy", legacy_source)
        new_bin = build(workdir, "new", here(DECODER))

        legacy = resolve(legacy_bin, producers(lambda rel: at_ref(base, rel)))
        new = resolve(new_bin, producers(here))

    keys = sorted(set(legacy) | set(new))
    diffs = [(k, legacy.get(k, "<absent>"), new.get(k, "<absent>"))
             for k in keys if legacy.get(k) != new.get(k)]

    print(f"{len(keys)} launch sites compared against {base}")
    for key, was, now in diffs:
        print(f"\n{key}")
        print(f"  was {was}")
        print(f"  now {now}")
        for field in _fields(was, now):
            print(f"  ! {field}")
    if not diffs:
        print("identical: every producer resolves to the same LaunchConfig")
    else:
        print(f"\n{len(diffs)} launch sites differ")
    return 0


def _fields(was, now):
    def split(line):
        return dict(part.split("=", 1) for part in re.findall(r"\S+=(?:\[[^\]]*\]|\S*)", line))
    old, new = split(was), split(now)
    return [f"{k}: {old.get(k, '-')} -> {new.get(k, '-')}"
            for k in sorted(set(old) | set(new)) if old.get(k) != new.get(k)]


if __name__ == "__main__":
    sys.exit(main())
