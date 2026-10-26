# test_model.py: tests for the notification texts Model.js builds.
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for Model.problems(), the notifications the widget sends by itself.

Model.js is a QML JavaScript library; these tests load it in Node, so they
are skipped where Node is not installed.

Run from the repository root with:  python3 -m unittest discover -s tests
"""

import json
import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOME = "/home/user"

# Loads Model.js without its QML ".pragma library" line and prints, as JSON,
# the problems it reports for the status read from standard input.
RUNNER = """
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(process.argv[1], "utf8").replace(/^\\.pragma library$/m, "");
const context = {};
vm.runInNewContext(source, context);
const status = JSON.parse(fs.readFileSync(0, "utf8"));
process.stdout.write(JSON.stringify(context.problems(status)));
"""


def problems(fixture):
    """Returns the problems Model.problems() reports for a fixture, and the fixture."""
    status = json.loads((ROOT / "fixtures" / fixture).read_text())
    result = subprocess.run(["node", "-e", RUNNER, str(ROOT / "Model.js")],
                            input=json.dumps(status), capture_output=True, text=True, check=True)
    return json.loads(result.stdout), status


def local_paths(status):
    """Every local folder a status names, absolute and in its ~/ form."""
    paths = [entry["local"] for entry in status.get("syncs", []) + status.get("backups", [])]
    return paths + ["~" + path[len(HOME):] for path in paths if path.startswith(HOME + "/")]


@unittest.skipUnless(shutil.which("node"), "Node is not installed")
class NotificationTests(unittest.TestCase):
    def assert_no_local_path(self, found, status):
        for problem in found:
            for path in local_paths(status):
                self.assertNotIn(path, problem["title"])
                self.assertNotIn(path, problem["body"])

    def test_sync_error_is_reported_without_its_folder(self):
        found, status = problems("sync-error.json")
        failed = [s for s in status["syncs"] if s["error"]]
        self.assertEqual(len(found), len(failed))
        self.assertEqual(found[0]["title"], "MEGA sync stopped")
        self.assertIn(failed[0]["error"], found[0]["body"])
        self.assert_no_local_path(found, status)

    def test_failed_backup_is_reported_without_its_folder(self):
        found, status = problems("backup-failed.json")
        self.assertGreaterEqual(len(found), 1)
        self.assertTrue(all(p["title"].startswith("MEGA backup ") for p in found))
        self.assert_no_local_path(found, status)

    def test_healthy_status_reports_nothing(self):
        found, _ = problems("ok.json")
        self.assertEqual(found, [])


if __name__ == "__main__":
    unittest.main()
