# test_status.py: tests for status.py's parsing of MEGAcmd output.
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for the MEGAcmd output parsers in status.py.

Run from the repository root with:  python3 -m unittest discover -s tests
"""

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

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


class SyncTests(unittest.TestCase):
    TEXT = ("ID|LOCALPATH|REMOTEPATH|RUN_STATE|STATUS|ERROR|SIZE|FILES|DIRS\n"
            "abc|/home/user/My Notes|/Sync/My Notes|Running|Synced|NO|1.50 MB|12|3\n"
            "def|/home/user/Code|/Sync/Code|Disabled|NONE|Local path not found|0.00   B|0|0\n")

    def test_rows_keep_paths_with_spaces(self):
        syncs = status.parse_syncs(self.TEXT)
        self.assertEqual([s["local"] for s in syncs], ["/home/user/My Notes", "/home/user/Code"])
        self.assertEqual(syncs[0]["remote"], "/Sync/My Notes")

    def test_no_error_is_empty_and_errors_are_kept(self):
        syncs = status.parse_syncs(self.TEXT)
        self.assertEqual(syncs[0]["error"], "")
        self.assertEqual(syncs[1]["error"], "Local path not found")

    def test_sizes_and_counts_are_normalised(self):
        syncs = status.parse_syncs(self.TEXT)
        self.assertEqual(syncs[1]["size"], "0.00 B")
        self.assertEqual((syncs[0]["files"], syncs[0]["dirs"]), (12, 3))

    def test_header_and_noise_are_skipped(self):
        self.assertEqual(status.parse_syncs("ID|LOCALPATH\nsomething else\n"), [])


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
    HISTORY = (
        "TAG   LOCALPATH                         REMOTEPARENTPATH            STATUS\n"
        "42    /home/user/Family Photos          /Backups                    ACTIVE\n"
        "   -- HISTORY OF BACKUPS --\n"
        "  NAME                                         DATE                                  STATUS  FILES FOLDERS\n"
        "  Family Photos_bk_20261023020000              Fri, 23 Oct 2026 02:00:00 +0200     COMPLETE      9       1\n"
        "  Family Photos_bk_20261024020000              Sat, 24 Oct 2026 02:00:00 +0200   INCOMPLETE      4       1\n")

    def test_details_are_read(self):
        (backup,) = status.parse_backups(self.DETAILS, "")
        self.assertEqual(backup["tag"], "42")
        self.assertEqual(backup["local"], "/home/user/Family Photos")
        self.assertEqual(backup["remote"], "/Backups")
        self.assertEqual(backup["maxBackups"], 7)
        self.assertEqual(backup["period"], "0 0 2 * * *")
        self.assertEqual(backup["next"], "Sun, 25 Oct 2026 02:00:00 +0100")

    def test_newest_history_entry_wins(self):
        (backup,) = status.parse_backups(self.DETAILS, self.HISTORY)
        self.assertEqual(backup["lastName"], "Family Photos_bk_20261024020000")
        self.assertEqual(backup["lastStatus"], "INCOMPLETE")

    def test_no_backups(self):
        self.assertEqual(status.parse_backups("No backup configured.", ""), [])


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
