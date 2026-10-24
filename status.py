#!/usr/bin/env python3
# status.py: print the MEGAcmd account, sync, backup and transfer state as JSON.
# SPDX-License-Identifier: GPL-3.0-or-later
"""Collect MEGAcmd's state for the MEGA bar widget.

Runs the mega-* client commands (which talk to the running MEGAcmd engine)
and prints one JSON object on stdout:

    {"ok", "loggedIn", "email", "usedBytes", "totalBytes", "usagePercent",
     "syncs": [...], "backups": [...], "transfers": {...}, "error"}

Usage: status.py [TIMEOUT_SECONDS]
       status.py --fixture FILE   (print a saved state instead, for previews and tests)
"""

import json
import re
import shutil
import subprocess
import sys

SYNC_COLUMNS = ["ID", "LOCALPATH", "REMOTEPATH", "RUN_STATE", "STATUS", "ERROR", "SIZE", "FILES", "DIRS"]
WIDE_PATHS = "--path-display-size=4096"
ROW_SPLIT = re.compile(r"\s{2,}")


def run(args, timeout):
    """Run a mega-* command and return (exit code, combined output)."""
    try:
        done = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, ""
    return done.returncode, (done.stdout or "") + (done.stderr or "")


def parse_storage(text):
    """Return (used, total, percent) in bytes from `mega-df` output."""
    match = re.search(r"USED STORAGE:.*?([\d.]+)%\s+of\s+(\d+)", text)
    if not match:
        return 0, 0, 0.0
    percent = float(match.group(1))
    total = int(match.group(2))
    return int(total * percent / 100), total, percent


def parse_syncs(text):
    """Return the syncs listed by `mega-sync` with a "|" column separator."""
    syncs = []
    for line in text.splitlines():
        parts = line.split("|")
        if len(parts) != len(SYNC_COLUMNS) or parts[0] == "ID":
            continue
        row = dict(zip(SYNC_COLUMNS, (p.strip() for p in parts)))
        syncs.append({
            "id": row["ID"],
            "local": row["LOCALPATH"],
            "remote": row["REMOTEPATH"],
            "runState": row["RUN_STATE"],
            "status": row["STATUS"],
            "error": "" if row["ERROR"] in ("", "NO") else row["ERROR"],
            "size": re.sub(r"\s+", " ", row["SIZE"]),
            "files": int(row["FILES"] or 0),
            "dirs": int(row["DIRS"] or 0),
        })
    return syncs


def split_backup_row(line):
    """Split a backup table row (TAG LOCALPATH REMOTEPARENTPATH STATUS)."""
    match = re.match(r"^(\d+)\s+(.*\S)\s{2,}(/.*\S)\s{2,}(\S+)\s*$", line)
    if not match:
        return None
    return {"tag": match.group(1), "local": match.group(2), "remote": match.group(3), "state": match.group(4)}


def parse_backups(details, history):
    """Combine `mega-backup -l` and `mega-backup -h` output into one list."""
    backups = {}
    order = []
    current = None
    for line in details.splitlines():
        row = split_backup_row(line)
        if row:
            row.update({"maxBackups": 0, "period": "", "next": "", "lastName": "", "lastDate": "", "lastStatus": ""})
            backups[row["tag"]] = row
            order.append(row["tag"])
            current = row
            continue
        if current is None:
            continue
        stripped = line.strip()
        if stripped.startswith("Max Backups:"):
            current["maxBackups"] = int(stripped.split(":", 1)[1].strip() or 0)
        elif stripped.startswith("Period:"):
            current["period"] = stripped.split(":", 1)[1].strip().strip('"')
        elif stripped.startswith("Next backup scheduled for:"):
            current["next"] = stripped.split(":", 1)[1].strip()

    current = None
    in_history = False
    for line in history.splitlines():
        row = split_backup_row(line)
        if row:
            current = backups.get(row["tag"])
            in_history = False
            continue
        if "HISTORY OF BACKUPS" in line:
            in_history = True
            continue
        if not (current and in_history) or line.strip().startswith("NAME"):
            continue
        entry = re.match(r"^\s+(.*\S)\s{2,}(\w{3}, .*?\d{4} \d\d:\d\d:\d\d [+-]\d{4})\s+(\S+)", line)
        if entry:
            # History lists oldest first; keep the newest.
            current["lastName"], current["lastDate"], current["lastStatus"] = entry.groups()

    return [backups[tag] for tag in order]


def parse_transfers(text):
    """Return download and upload counts and progress from `mega-transfers --summary`."""
    lines = [l for l in text.splitlines() if l.strip()]
    if len(lines) < 2 or "NUM DOWNLOADS" not in lines[0]:
        return {"downloads": 0, "uploads": 0, "downloaded": "", "downloadTotal": "", "uploaded": "", "uploadTotal": "",
                "downloadPercent": 0.0, "uploadPercent": 0.0}
    values = ROW_SPLIT.split(lines[1].strip())
    # NUM, DONE, TOTAL, % for downloads, then the same for uploads.
    values = [re.sub(r"\s+", " ", v) for v in values]
    if len(values) < 8:
        values += [""] * (8 - len(values))

    def number(text):
        try:
            return float(text.rstrip("%"))
        except ValueError:
            return 0.0

    return {
        "downloads": int(number(values[0])), "downloaded": values[1], "downloadTotal": values[2],
        "downloadPercent": number(values[3]),
        "uploads": int(number(values[4])), "uploaded": values[5], "uploadTotal": values[6],
        "uploadPercent": number(values[7]),
    }


def print_fixture(path):
    """Print the saved state in PATH, after checking it is a JSON object."""
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: not a JSON object")
    print(json.dumps(data))


def main():
    """Print the collected state as JSON; exit 0 even when logged out."""
    if len(sys.argv) == 3 and sys.argv[1] == "--fixture":
        print_fixture(sys.argv[2])
        return
    timeout = float(sys.argv[1]) if len(sys.argv) > 1 else 20
    status = {"ok": True, "installed": shutil.which("mega-whoami") is not None, "loggedIn": False, "email": "",
              "usedBytes": 0, "totalBytes": 0, "usagePercent": 0.0,
              "syncs": [], "backups": [], "transfers": parse_transfers(""), "error": ""}
    if not status["installed"]:
        print(json.dumps(status))
        return

    code, out = run(["mega-whoami"], timeout)
    match = re.search(r"Account e-mail:\s*(\S+)", out)
    if code == 124:
        status["error"] = "MEGAcmd is busy"
    if not match:
        print(json.dumps(status))
        return
    status["loggedIn"] = True
    status["email"] = match.group(1)

    _, out = run(["mega-df"], timeout)
    status["usedBytes"], status["totalBytes"], status["usagePercent"] = parse_storage(out)

    _, out = run(["mega-sync", "--col-separator=|", "--output-cols=" + ",".join(SYNC_COLUMNS)], timeout)
    status["syncs"] = parse_syncs(out)

    _, details = run(["mega-backup", "-l", WIDE_PATHS], timeout)
    _, history = run(["mega-backup", "-h", WIDE_PATHS], timeout)
    status["backups"] = parse_backups(details, history)

    _, out = run(["mega-transfers", "--summary"], timeout)
    status["transfers"] = parse_transfers(out)

    print(json.dumps(status))


if __name__ == "__main__":
    main()
