#!/usr/bin/env python3
"""Guards two defect classes this repo has actually shipped.

1. A flag read outside ``#if DEBUG`` compiles into Release. Three such reads
   existed at 74d2c250, one of which let a UserDefaults key skip the
   mental-model onboarding gate in a shipping build.
2. A flag read straight from the process environment never sees a value that
   Maestro passed as a launch argument. That is why UITEST_MODE,
   UITEST_GARMIN_PUSH_FAIL, and UITEST_START_SCREEN were set by flows and
   never once fired.

Scope is app-target Swift only. Test targets are the callers; they set these
for the app under test and are expected to name them. Only reads count, so a
flag name inside an error message is not a finding.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOLVER = "AmakaFlow/Services/UITestEnvironment.swift"

FLAG = re.compile(r"UITEST_[A-Z0-9_]+|AMA\d{4}_[A-Z0-9_]+")
READ = re.compile(
    r"UITestEnvironment\.|"
    r"ProcessInfo\.processInfo\.environment\[|"
    r"UserDefaults\.standard\.(?:string|bool|object)\(forKey"
)
ENV_READ = re.compile(r'ProcessInfo\.processInfo\.environment\[\s*"([A-Z0-9_]+)"')
IF_DEBUG = re.compile(r"^\s*#if\s+DEBUG\b")
ENDIF = re.compile(r"^\s*#endif\b")
COMMENT = re.compile(r"//.*")


def app_sources():
    out = subprocess.run(
        ["git", "ls-files", "AmakaFlow/*.swift", "AmakaFlowCompanion/*.swift"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.splitlines()
    return [p for p in out if "Tests/" not in p and "UITests/" not in p and p != RESOLVER]


def launch_argument_flags():
    flags = set()
    for path in (ROOT / "e2e" / "maestro").rglob("*.yaml"):
        flags.update(FLAG.findall(path.read_text(errors="replace")))
    return flags


def scan(paths, arg_flags):
    ungated, dead = [], []
    for rel in paths:
        depth = 0
        for n, raw in enumerate((ROOT / rel).read_text(errors="replace").splitlines(), 1):
            line = COMMENT.sub("", raw)
            if IF_DEBUG.match(line):
                depth += 1
                continue
            if ENDIF.match(line):
                depth = max(0, depth - 1)
                continue
            if depth == 0 and READ.search(line) and FLAG.search(line):
                ungated.append(f"{rel}:{n}:{line.strip()}")
            hit = ENV_READ.search(line)
            if hit and hit.group(1) in arg_flags:
                dead.append(f"{rel}:{n}:{line.strip()}")
    return ungated, dead


def main():
    ungated, dead = scan(app_sources(), launch_argument_flags())
    if ungated:
        print("Flag reads outside #if DEBUG. These compile into Release.")
        print("\n".join(ungated))
    if dead:
        print("Flags read from the process environment that flows pass as launch arguments. These never fire.")
        print("\n".join(dead))
    if ungated or dead:
        return 1
    print("ok: flag reads are guarded and read from a source the flows actually populate")
    return 0


if __name__ == "__main__":
    sys.exit(main())
