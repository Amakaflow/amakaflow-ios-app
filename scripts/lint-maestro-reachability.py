#!/usr/bin/env python3
"""Fail when a Maestro flow asserts against a screen it cannot reach.

A flow that wipes state and never authenticates lands on the sign-in screen.
Any step afterwards that targets an authenticated surface can never match, so
the flow is asserting against a screen it never reaches.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

import yaml

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
FLOW_ROOT = REPO_ROOT / "e2e" / "maestro"

# Flags that establish a session. Kept in sync with `LaunchConfig.session()`.
SESSION_FLAGS = frozenset({"AF_SESSION_CLERK_EMAIL", "AF_SESSION_IDENTITY"})

# Demo hosts replace the root view before the auth gate is consulted, so a flow
# that sets one never reaches the sign-in screen at all.
DEMO_HOST_FLAGS = frozenset({"AF_DEMO_ACTUALS_HUB", "AF_DEMO_CREATE_WITH_AI"})

# Surfaces that only exist once a session is established. A flow reaching for
# one of these without a session is asserting against the sign-in screen.
AUTHED_IDS = frozenset(
    {
        "library_tab",
        "today_tab",
        "profile_tab",
        "coach_tab",
        "devices_screen",
    }
)
AUTHED_ID_PREFIXES = ("af_library_", "af_workout_detail_", "af_start_", "af_today_")

SIGNIN_HELPER = "_lib/clerk-signin.yaml"


class DuplicateKeyLoader(yaml.SafeLoader):
    """`yaml.SafeLoader` keeps the last of a repeated key and says nothing.

    A repeated launch argument is how the AF_ rename collapsed two distinct
    flags into one name without any check noticing.
    """

    def construct_mapping(self, node, deep=False):
        seen = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=deep)
            if key in seen:
                raise yaml.YAMLError(f"duplicate key {key!r}")
            seen.add(key)
        return super().construct_mapping(node, deep)


def load_documents(path: pathlib.Path) -> list[object]:
    try:
        documents = yaml.load_all(path.read_text(), Loader=DuplicateKeyLoader)
        return [doc for doc in documents if doc is not None]
    except yaml.YAMLError as exc:
        raise SystemExit(f"{path}: {exc}") from exc


# Commands whose target must be on screen for the step to succeed. A command
# outside this set is not evidence of reaching a surface: `assertNotVisible`
# passes precisely when its target is absent, so treating it as a target would
# fail the eleven flows that legitimately assert a tab is hidden.
REACHING_COMMANDS = frozenset(
    {
        "tapOn",
        "doubleTapOn",
        "longPressOn",
        "assertVisible",
        "extendedWaitUntil",
        "scrollUntilVisible",
        "waitForAnimationToEnd",
        "copyTextFrom",
    }
)


def identifiers_in(node: object):
    """Yield selector strings, ignoring keys so a command name is never a target."""
    if isinstance(node, dict):
        for value in node.values():
            yield from identifiers_in(value)
    elif isinstance(node, list):
        for item in node:
            yield from identifiers_in(item)
    elif node is not None:
        yield str(node)


def commands(documents: list[object]) -> list[object]:
    """Every command across every list document, not just the first.

    A Maestro file may hold several command documents. ama-2286 keeps its
    forced-failure scenario in a second one, so reading only the first would
    let a missing session flag through the gate.
    """
    return [step for doc in documents if isinstance(doc, list) for step in doc]


def launch_blocks(steps: list[object]) -> list[dict]:
    blocks = []
    for step in steps:
        if isinstance(step, dict) and "launchApp" in step:
            block = step["launchApp"]
            blocks.append(block if isinstance(block, dict) else {})
        elif step == "launchApp":
            blocks.append({})
    return blocks


def authed_targets(steps: list[object]) -> set[str]:
    found = set()
    for step in steps:
        if not isinstance(step, dict):
            continue
        for command, payload in step.items():
            if command not in REACHING_COMMANDS:
                continue
            for value in identifiers_in(payload):
                if value in AUTHED_IDS or value.startswith(AUTHED_ID_PREFIXES):
                    found.add(value)
    return found


def runs_signin_helper(steps: list[object]) -> bool:
    """Only a real runFlow counts. Scanning raw text let a comment silence this."""
    for step in steps:
        if not isinstance(step, dict):
            continue
        target = step.get("runFlow")
        if isinstance(target, dict):
            target = target.get("file")
        if isinstance(target, str) and SIGNIN_HELPER in target:
            return True
    return False


def display(path: pathlib.Path) -> str:
    """Repo-relative when possible, so an explicit path argument still prints."""
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def audit(path: pathlib.Path) -> str | None:
    steps = commands(load_documents(path))

    blocks = launch_blocks(steps)
    if not blocks:
        return None

    clears_state = any(block.get("clearState") is True for block in blocks)
    if not clears_state:
        return None

    declared_flags: set[str] = set()
    for block in blocks:
        arguments = block.get("arguments")
        if isinstance(arguments, dict):
            declared_flags.update(str(key) for key in arguments)

    if declared_flags & SESSION_FLAGS or declared_flags & DEMO_HOST_FLAGS:
        return None
    if runs_signin_helper(steps):
        return None

    targets = authed_targets(steps)
    if not targets:
        return None

    listed = ", ".join(sorted(targets)[:4])
    return (
        f"{display(path)}: clearState with no session flag and no "
        f"{SIGNIN_HELPER}, but targets authenticated surfaces ({listed})"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=pathlib.Path)
    args = parser.parse_args()

    paths = args.paths or sorted(FLOW_ROOT.rglob("*.yaml"))
    failures = [message for path in paths if (message := audit(path))]

    for message in failures:
        print(f"error: {message}", file=sys.stderr)

    print(f"checked {len(paths)} flows, {len(failures)} unreachable")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
