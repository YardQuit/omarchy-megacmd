# test_status.py: tests for status.py's parsing of MEGAcmd output.
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for the MEGAcmd output parsers in status.py.

Run from the repository root with:  python3 -m unittest discover -s tests
"""

import contextlib
import importlib.util
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("status", ROOT / "status.py")
status = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(status)


class StorageTests(unittest.TestCase):
    def test_used_bytes_come_from_percentage_and_total(self):
        text = ("Cloud drive:          1234...56789 in  10 file(s) and   2 folder(s)\n"
                "USED STORAGE:         1099...11776                  50.00% of 2199023255552\n")
        self.assertEqual(status.parse_storage(text), (1099511627776, 2199023255552, 50.0))

    def test_missing_storage_line_gives_zeroes(self):
        self.assertEqual(status.parse_storage("Not logged in."), (0, 0, 0.0))


def sync_table(*rows):
    """MEGAcmd's sync table with the given rows, in the columns status.py asks for."""
    return "\n".join(status.SEPARATOR.join(row) for row in [status.SYNC_COLUMNS, *rows]) + "\n"


class SyncTests(unittest.TestCase):
    TEXT = sync_table(
        ["abc", "/home/user/My Notes", "/Sync/My Notes", "Running", "Synced", "NO", "1.50 MB", "12", "3"],
        ["d-f_9", "/home/user/Code", "/Sync/Code", "Disabled", "NONE", "Local path not found", "0.00   B", "0", "0"])

    def test_rows_keep_paths_with_spaces(self):
        syncs, unreadable = status.parse_syncs(self.TEXT)
        self.assertEqual([s["local"] for s in syncs], ["/home/user/My Notes", "/home/user/Code"])
        self.assertEqual(syncs[0]["remote"], "/Sync/My Notes")
        self.assertEqual(unreadable, 0)

    def test_no_error_is_empty_and_errors_are_kept(self):
        syncs, _ = status.parse_syncs(self.TEXT)
        self.assertEqual(syncs[0]["error"], "")
        self.assertEqual(syncs[1]["error"], "Local path not found")

    def test_sizes_and_counts_are_normalised(self):
        syncs, _ = status.parse_syncs(self.TEXT)
        self.assertEqual(syncs[1]["size"], "0.00 B")
        self.assertEqual((syncs[0]["files"], syncs[0]["dirs"]), (12, 3))

    def test_header_and_blank_lines_are_skipped(self):
        self.assertEqual(status.parse_syncs(sync_table() + "\n"), ([], 0))

    def test_a_pipe_in_a_folder_name_keeps_the_sync(self):
        syncs, unreadable = status.parse_syncs(sync_table(
            ["abc", "/home/user/A|B", "/Shared/A|B", "Running", "Synced", "NO", "1 B", "1", "0"]))
        self.assertEqual([s["local"] for s in syncs], ["/home/user/A|B"])
        self.assertEqual(unreadable, 0)

    def test_a_line_break_in_a_folder_name_cannot_pose_as_a_sync(self):
        # A shared folder named "x<newline>--delete..." splits its row in two;
        # neither half may become a sync whose ID reaches mega-sync as an option.
        name = "/Shared/x\n--delete" + status.SEPARATOR + "/home/user" + status.SEPARATOR + "/evil"
        syncs, unreadable = status.parse_syncs(sync_table(
            ["abc", "/home/user/Shared", name, "Running", "Failed", "fake error", "1 B", "0", "0"],
            ["ok1", "/home/user/A", "/A", "Running", "Synced", "NO", "1 B", "0", "0"]))
        self.assertEqual([s["id"] for s in syncs], ["ok1"])
        self.assertEqual(unreadable, 2)

    def test_an_id_or_local_path_that_could_be_an_option_is_refused(self):
        syncs, unreadable = status.parse_syncs(sync_table(
            ["--delete", "/home/user/A", "/A", "Running", "Synced", "NO", "1 B", "0", "0"],
            ["abc", "--help", "/A", "Running", "Synced", "NO", "1 B", "0", "0"]))
        self.assertEqual((syncs, unreadable), ([], 2))

    def test_counts_that_are_not_numbers_do_not_break_the_status(self):
        syncs, _ = status.parse_syncs(sync_table(
            ["abc", "/home/user/A", "/A", "Running", "Synced", "NO", "1 B", "many", "-"]))
        self.assertEqual((syncs[0]["files"], syncs[0]["dirs"]), (0, 0))


class BackupTests(unittest.TestCase):
    DETAILS = (
        "TAG   LOCALPATH                         REMOTEPARENTPATH            STATUS\n"
        "42    /home/user/Family Photos          /Backups                    ACTIVE\n"
        "  Max Backups:   7\n"
        '  Period:         "0 0 2 * * *"\n'
        "  Next backup scheduled for: Sun, 25 Oct 2026 02:00:00 +0100\n"
        "   -- CURRENT/LAST BACKUP --\n"
        "  FILES UP/TOT     FOLDERS CREATED           PROGRESS     \n"
        "       1/1                0            6.00/6.00  B  0.00%\n")
    LISTING = DETAILS + (
        "   -- HISTORY OF BACKUPS --\n"
        "  NAME                                         DATE                                  STATUS  FILES FOLDERS\n"
        "  Family Photos_bk_20261023020000              Fri, 23 Oct 2026 02:00:00 +0200     COMPLETE      9       1\n"
        "  Family Photos_bk_20261024020000              Sat, 24 Oct 2026 02:00:00 +0200   INCOMPLETE      4       1\n")

    def test_details_are_read(self):
        (backup,) = status.parse_backups(self.DETAILS)
        self.assertEqual(backup["tag"], "42")
        self.assertEqual(backup["local"], "/home/user/Family Photos")
        self.assertEqual(backup["remote"], "/Backups")
        self.assertEqual(backup["maxBackups"], 7)
        self.assertEqual(backup["period"], "0 0 2 * * *")
        self.assertEqual(backup["next"], "Sun, 25 Oct 2026 02:00:00 +0100")

    def test_details_are_kept_once_the_history_follows(self):
        (backup,) = status.parse_backups(self.LISTING)
        self.assertEqual((backup["maxBackups"], backup["period"]), (7, "0 0 2 * * *"))

    def test_newest_history_entry_wins(self):
        (backup,) = status.parse_backups(self.LISTING)
        self.assertEqual(backup["lastName"], "Family Photos_bk_20261024020000")
        self.assertEqual(backup["lastStatus"], "INCOMPLETE")

    def test_no_backups(self):
        self.assertEqual(status.parse_backups("No backup configured."), [])

    def test_max_backups_that_is_not_a_number_does_not_break_the_status(self):
        (backup,) = status.parse_backups(self.DETAILS.replace("Max Backups:   7", "Max Backups:   lots"))
        self.assertEqual(backup["maxBackups"], 0)

    def test_a_backup_whose_local_path_is_not_absolute_is_ignored(self):
        details = self.DETAILS.replace("/home/user/Family Photos", "-x Family Photos")
        self.assertEqual(status.parse_backups(details), [])


class TransferTests(unittest.TestCase):
    def test_summary_is_read(self):
        text = ("   NUM DOWNLOADS  DOWNLOADED       TOTAL    %             NUM UPLOADS    UPLOADED       TOTAL    %   \n"
                "             120     1.20 GB     4.80 GB  25.00%                    3   10.00 MB    20.00 MB  50.00%\n")
        transfers = status.parse_transfers(text)
        self.assertEqual(transfers["downloads"], 120)
        self.assertEqual((transfers["downloaded"], transfers["downloadTotal"]), ("1.20 GB", "4.80 GB"))
        self.assertEqual(transfers["downloadPercent"], 25.0)
        self.assertEqual((transfers["uploads"], transfers["uploadPercent"]), (3, 50.0))

    def test_no_transfers(self):
        transfers = status.parse_transfers("No transfers.")
        self.assertEqual((transfers["downloads"], transfers["uploads"]), (0, 0))


class EngineTests(unittest.TestCase):
    def collect(self, running):
        """Runs status.py's main() with MEGAcmd installed; returns its JSON and the commands run."""
        calls = []
        def fake_run(args, timeout):
            calls.append(args[0])
            return 0, ""
        out = io.StringIO()
        with mock.patch.object(status.shutil, "which", return_value="/usr/bin/mega-whoami"), \
             mock.patch.object(status, "engine_running", return_value=running), \
             mock.patch.object(status, "run", side_effect=fake_run), \
             mock.patch.object(sys, "argv", ["status.py"]), contextlib.redirect_stdout(out):
            status.main()
        return json.loads(out.getvalue()), calls

    def test_a_stopped_engine_is_reported_and_not_started(self):
        # Every mega-* client starts the engine when it is not running, so
        # none may run while it is stopped.
        data, calls = self.collect(running=False)
        self.assertEqual(calls, [])
        self.assertFalse(data["running"])
        self.assertFalse(data["loggedIn"])

    def test_a_running_engine_is_asked_for_its_state(self):
        data, calls = self.collect(running=True)
        self.assertTrue(data["running"])
        self.assertEqual(calls[0], "mega-whoami")


class FixtureTests(unittest.TestCase):
    def test_every_fixture_is_printed_unchanged(self):
        for path in sorted((ROOT / "fixtures").glob("*.json")):
            with self.subTest(fixture=path.name):
                done = subprocess.run([sys.executable, "-I", str(ROOT / "status.py"), "--fixture", str(path)],
                                      capture_output=True, text=True, check=True)
                self.assertEqual(json.loads(done.stdout), json.loads(path.read_text()))

    def test_a_fixture_must_be_an_object(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json") as handle:
            handle.write("[1, 2]")
            handle.flush()
            done = subprocess.run([sys.executable, "-I", str(ROOT / "status.py"), "--fixture", handle.name],
                                  capture_output=True, text=True)
        self.assertNotEqual(done.returncode, 0)


if __name__ == "__main__":
    unittest.main()
