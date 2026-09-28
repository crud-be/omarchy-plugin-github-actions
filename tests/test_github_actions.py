import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock
from datetime import datetime, timezone
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import github_actions as ga


class GithubActionsTests(unittest.TestCase):
    def test_dispatch_inputs_parses_types_and_bare_on_key(self):
        document = yaml.safe_load(
            """
on:
  push:
  workflow_dispatch:
    inputs:
      env:
        type: choice
        required: true
        options: [staging, production]
        default: staging
      dry_run:
        type: boolean
        default: true
      note:
        description: Release note
"""
        )
        dispatch, inputs = ga.dispatch_inputs(document)
        self.assertTrue(dispatch)
        self.assertEqual([i["key"] for i in inputs], ["env", "dry_run", "note"])
        self.assertEqual(inputs[0]["options"], ["staging", "production"])
        self.assertIs(inputs[1]["default"], True)
        self.assertEqual(inputs[2]["type"], "string")
        self.assertEqual(inputs[2]["description"], "Release note")

    def test_dispatch_inputs_list_string_and_missing(self):
        self.assertEqual(ga.dispatch_inputs({"on": ["push", "workflow_dispatch"]}), (True, []))
        self.assertEqual(ga.dispatch_inputs({"on": "workflow_dispatch"}), (True, []))
        self.assertEqual(ga.dispatch_inputs(yaml.safe_load("on: {workflow_dispatch: }")), (True, []))
        self.assertEqual(ga.dispatch_inputs({"on": {"push": None}}), (False, []))

    def test_running_workflows(self):
        runs = [
            {"workflow_id": 1, "status": "in_progress"},
            {"workflow_id": 2, "status": "completed"},
            {"workflow_id": 3, "status": "queued"},
        ]
        self.assertEqual(ga.running_workflows(runs), {1, 3})

    def test_workflows_sorted_by_last_run(self):
        runs = [
            {"workflow_id": 2, "created_at": "2026-09-28T10:00:00Z"},
            {"workflow_id": 1, "created_at": "2026-09-27T10:00:00Z"},
            {"workflow_id": 2, "created_at": "2026-09-20T10:00:00Z"},
        ]
        last = ga.last_run_times(runs)
        self.assertEqual(last[2], "2026-09-28T10:00:00Z")
        workflows = [{"name": n, "lastRun": last.get(i, "")} for i, n in [(3, "b"), (1, "x"), (4, "A"), (2, "y")]]
        self.assertEqual([w["name"] for w in ga.by_last_run(workflows)], ["y", "x", "A", "b"])

    def test_run_summary_and_age(self):
        now = datetime(2026, 9, 28, 12, 0, tzinfo=timezone.utc)
        self.assertEqual(ga.age("2026-09-28T09:30:00Z", now), "2h")
        self.assertEqual(ga.age("2026-09-28T11:59:30Z", now), "now")
        summary = ga.run_summary({"status": "in_progress", "conclusion": None, "head_branch": "main", "display_title": "Fix", "run_number": 7})
        self.assertTrue(summary["running"])
        self.assertEqual(summary["conclusion"], "")
        self.assertEqual((summary["title"], summary["number"]), ("Fix", 7))

    def test_saved_lists_round_trip(self):
        with tempfile.TemporaryDirectory() as directory, mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": directory}):
            self.assertEqual(ga.load_list("repos.json"), [])
            with mock.patch("sys.stdin", io.StringIO('["crud-be/dicta"]\n')), redirect_stdout(io.StringIO()):
                ga.main(["github_actions.py", "set-repos"])
            self.assertEqual(ga.load_list("repos.json"), ["crud-be/dicta"])


if __name__ == "__main__":
    unittest.main()
