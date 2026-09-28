import sys
import unittest
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

    def test_latest_runs_keeps_newest_per_workflow(self):
        runs = [{"id": 3, "workflow_id": 1}, {"id": 2, "workflow_id": 2}, {"id": 1, "workflow_id": 1}]
        latest = ga.latest_runs(runs)
        self.assertEqual(latest[1]["id"], 3)
        self.assertEqual(latest[2]["id"], 2)

    def test_run_summary_and_ago(self):
        now = datetime(2026, 9, 28, 12, 0, tzinfo=timezone.utc)
        self.assertEqual(ga.ago("2026-09-28T09:30:00Z", now), "2h ago")
        self.assertEqual(ga.ago("2026-09-28T11:59:30Z", now), "just now")
        summary = ga.run_summary({"status": "in_progress", "conclusion": None, "head_branch": "main"})
        self.assertTrue(summary["running"])
        self.assertEqual(summary["conclusion"], "")
        self.assertIsNone(ga.run_summary(None))


if __name__ == "__main__":
    unittest.main()
