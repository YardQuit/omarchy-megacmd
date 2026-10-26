# test_model.py: tests for the notification texts Model.js builds.
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for Model.js: the notifications the widget sends by itself and the
state its panel actions are decided on.

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

# Loads Model.js without its QML ".pragma library" line, calls the function
# named in argv[2] with the JSON array of arguments read from standard input,
# and prints the result as JSON. Qt.locale() stands in as Node's default
# locale, so numbers are grouped as in English ("1,200").
RUNNER = """
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(process.argv[1], "utf8").replace(/^\\.pragma library$/m, "");
const context = { Qt: { locale: function() { return undefined; } } };
vm.runInNewContext(source, context);
const args = JSON.parse(fs.readFileSync(0, "utf8"));
process.stdout.write(JSON.stringify(context[process.argv[2]](...args)));
"""


def call(function, *args):
    """Returns what Model.js's FUNCTION gives for ARGS."""
    result = subprocess.run(["node", "-e", RUNNER, str(ROOT / "Model.js"), function],
                            input=json.dumps(args), capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def fixture(name):
    """The saved status in fixtures/NAME."""
    return json.loads((ROOT / "fixtures" / name).read_text())


def problems(name):
    """Returns the problems Model.problems() reports for a fixture, and the fixture."""
    status = fixture(name)
    return call("problems", status), status


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

    def test_markup_in_a_notification_text_is_shown_as_text(self):
        # Notification bodies are rendered as styled text; an error text from
        # MEGAcmd must not turn into formatting.
        self.assertEqual(call("escapeMarkup", 'a <b>bold</b> & "x"'), 'a &lt;b&gt;bold&lt;/b&gt; &amp; "x"')


@unittest.skipUnless(shutil.which("node"), "Node is not installed")
class ActionStateTests(unittest.TestCase):
    def test_all_paused_with_storage_nearly_full_can_still_be_resumed(self):
        status = fixture("storage-95.json")
        for sync in status["syncs"]:
            sync["runState"] = "Disabled"
        self.assertEqual(call("overallKind", status), "warning")
        self.assertFalse(call("anyRunning", status["syncs"]))

    def test_one_running_sync_means_pause_all(self):
        self.assertTrue(call("anyRunning", fixture("paused.json")["syncs"] + [{"runState": "Running"}]))

    def test_removal_is_keyed_by_id_not_by_row(self):
        syncs = fixture("ok.json")["syncs"]
        self.assertEqual(call("itemKey", "sync", syncs[1]), "sync:" + syncs[1]["id"])
        self.assertEqual(call("itemKey", "backup", {"tag": "7"}), "backup:7")
        self.assertEqual(call("itemKey", "sync", None), "")

    def test_transfers_are_summarised_per_direction(self):
        transfers = {"downloads": 1200, "downloaded": "1.20 GB", "downloadTotal": "4.80 GB", "downloadPercent": 25.0,
                     "uploads": 3, "uploaded": "10.00 MB", "uploadTotal": "20.00 MB", "uploadPercent": 50.4}
        self.assertEqual(call("transfersText", transfers).split("\n"),
                         ["1,200 down · 1.20 GB of 4.80 GB (25%)", "3 up · 10.00 MB of 20.00 MB (50%)"])
        self.assertEqual(call("transfersText", dict(transfers, downloads=0, uploads=0)), "")

    def test_a_stopped_engine_has_its_own_state(self):
        status = dict(fixture("ok.json"), running=False, loggedIn=False)
        self.assertEqual(call("overallKind", status), "stopped")
        self.assertEqual(call("overallText", "stopped"), "MEGAcmd is not running")


if __name__ == "__main__":
    unittest.main()
