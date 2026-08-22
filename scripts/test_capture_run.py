#!/usr/bin/env python3
"""Self-test for capture-run.py. Run: python3 scripts/test_capture_run.py

Plain stdlib on purpose. The repo has no Python test runner, and standing one
up for two scripts costs more than it returns.

What is worth testing here is the honesty machinery, not the happy path. Every
failure mode has to end as BLOCKED with a reason. A capture tool that turns a
failure into a pass is the exact defect AMA-2500 keeps finding, so these cases
are the ones that must not silently regress.
"""

from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = pathlib.Path(__file__).resolve().parent / "capture-run.py"
spec = importlib.util.spec_from_file_location("capture_run", SCRIPT)
capture_run = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture_run)


def ok(stdout: str = "") -> subprocess.CompletedProcess:
    return subprocess.CompletedProcess([], 0, stdout, "")


def failed(stdout: str = "") -> subprocess.CompletedProcess:
    return subprocess.CompletedProcess([], 1, stdout, "")


class CaptureOutcomes(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.flow = self.tmp / "today.yaml"
        self.flow.write_text("appId: x\n", encoding="utf-8")

    def test_unreachable_screen_is_blocked_with_the_failing_step(self) -> None:
        with mock.patch.object(capture_run, "run", return_value=failed("Tap on id: library_tab... FAILED")):
            row = capture_run.capture("udid", self.flow, self.tmp)
        self.assertEqual(row["status"], "BLOCKED")
        self.assertIn("FAILED", row["why"])

    def test_probe_that_cannot_run_is_blocked_not_skipped(self) -> None:
        with mock.patch.object(capture_run, "run", return_value=None):
            row = capture_run.capture("udid", self.flow, self.tmp)
        self.assertEqual(row["status"], "BLOCKED")

    def test_reached_screen_with_no_screenshot_is_blocked(self) -> None:
        # The probe passes and the screenshot command "succeeds" without writing
        # a file. Trusting the return code alone would file a CAPTURED row with
        # no image behind it.
        with mock.patch.object(capture_run, "run", side_effect=[ok(), ok()]):
            with mock.patch.object(capture_run, "settled", return_value={"today_tab"}):
                row = capture_run.capture("udid", self.flow, self.tmp)
        self.assertEqual(row["status"], "BLOCKED")
        self.assertIn("screenshot", row["why"])

    def test_screen_that_never_settles_is_blocked(self) -> None:
        # A screen still loading satisfies its probe but must not be captured:
        # this is how a spinner got filed as evidence for the seeded Library.
        with mock.patch.object(capture_run, "run", return_value=ok()):
            with mock.patch.object(capture_run, "settled", return_value=None):
                row = capture_run.capture("udid", self.flow, self.tmp)
        self.assertEqual(row["status"], "BLOCKED")
        self.assertIn("loading", row["why"])

    def test_settled_rejects_a_hierarchy_showing_a_spinner(self) -> None:
        with mock.patch.object(capture_run, "identifiers", return_value={"af_loading_spinner"}):
            with mock.patch.object(capture_run.time, "sleep", lambda _: None):
                self.assertIsNone(capture_run.settled("udid", attempts=2, gap=0))

    def test_settled_returns_a_stable_hierarchy(self) -> None:
        with mock.patch.object(capture_run, "identifiers", return_value={"today_tab"}):
            with mock.patch.object(capture_run.time, "sleep", lambda _: None):
                self.assertEqual(capture_run.settled("udid", attempts=3, gap=0), {"today_tab"})

    def test_reached_screen_with_no_hierarchy_is_blocked(self) -> None:
        def fake_run(command, timeout):
            if "screenshot" in command:
                (self.tmp / "today.png").write_bytes(b"png")
            return ok()

        with mock.patch.object(capture_run, "run", side_effect=fake_run):
            with mock.patch.object(capture_run, "settled", return_value=None):
                row = capture_run.capture("udid", self.flow, self.tmp)
        self.assertEqual(row["status"], "BLOCKED")

    def test_full_success_writes_both_artifacts(self) -> None:
        def fake_run(command, timeout):
            if "screenshot" in command:
                (self.tmp / "today.png").write_bytes(b"png")
            return ok()

        with mock.patch.object(capture_run, "run", side_effect=fake_run):
            with mock.patch.object(capture_run, "settled", return_value={"today_tab"}):
                row = capture_run.capture("udid", self.flow, self.tmp)
        self.assertEqual(row["status"], "CAPTURED")
        self.assertTrue((self.tmp / "today.png").is_file())
        self.assertEqual((self.tmp / "today.ids.txt").read_text(encoding="utf-8"), "today_tab\n")


class Guards(unittest.TestCase):
    def test_run_id_rejects_path_traversal(self) -> None:
        self.assertIsNone(capture_run.RUN_ID.match("../../escape"))
        self.assertIsNone(capture_run.RUN_ID.match("/tmp/run"))
        self.assertIsNotNone(capture_run.RUN_ID.match("run-0-structure"))

    def test_missing_sha_returns_none_rather_than_a_placeholder(self) -> None:
        with mock.patch.object(capture_run, "run", return_value=failed()):
            self.assertIsNone(capture_run.head_sha())

    def test_auth_mode_distinguishes_the_two_identities(self) -> None:
        # The whole point of recording auth mode is that fixtures and the real
        # seeded account prove different things. If both rendered the same
        # string, a manifest could not tell them apart.
        fixtures = capture_run.auth_mode("fixtures")
        seeded = capture_run.auth_mode("seeded")
        self.assertIn("mock identity", fixtures)
        self.assertIn("real Clerk session", seeded)
        self.assertNotEqual(fixtures, seeded)


if __name__ == "__main__":
    unittest.main(verbosity=2)
