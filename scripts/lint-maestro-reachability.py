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


def walk_strings(node: object):
    if isinstance(node, dict):
        for key, value in node.items():
            yield str(key)
            yield from walk_strings(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk_strings(item)
    elif node is not None:
        yield str(node)


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
    for value in walk_strings(steps):
        if value in AUTHED_IDS or value.startswith(AUTHED_ID_PREFIXES):
            found.add(value)
    return found


def runs_signin_helper(text: str) -> bool:
    return SIGNIN_HELPER in text


def audit(path: pathlib.Path) -> str | None:
    text = path.read_text()
    documents = load_documents(path)
    steps = [doc for doc in documents if isinstance(doc, list)]
    steps = steps[0] if steps else []

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
    if runs_signin_helper(text):
        return None

    targets = authed_targets(steps)
    if not targets:
        return None

    listed = ", ".join(sorted(targets)[:4])
    return (
        f"{path.relative_to(REPO_ROOT)}: clearState with no session flag and no "
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
