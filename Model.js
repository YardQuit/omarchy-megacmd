// Model.js: display helpers for the MEGA bar widget.
// SPDX-License-Identifier: GPL-3.0-or-later
.pragma library

// Nerd Font glyphs (Material Design) for the bar icon and rows.
var ICON_CLOUD = "󰅟"
var ICON_ERROR = "󰧠"
var ICON_OFF = "󰅤"
var ICON_BACKUP = "󰁯"

// Parses the JSON printed by status.py. Returns {ok: false, error} on bad input.
function parseStatus(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    return data && typeof data === "object" ? data : { ok: false, error: "Empty status" }
  } catch (e) {
    return { ok: false, error: "Unreadable status: " + e }
  }
}

// Formats a byte count with binary units, e.g. "2.51 TB".
function formatBytes(bytes) {
  var value = Number(bytes || 0)
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var i = 0
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024
    i += 1
  }
  return (i === 0 ? value.toFixed(0) : value.toFixed(value >= 100 ? 0 : value >= 10 ? 1 : 2)) + " " + units[i]
}

// "2.51 TB of 3.00 TB (84%)", or "" when the total is unknown.
function usageText(used, total, percent) {
  if (!total) return ""
  return formatBytes(used) + " of " + formatBytes(total) + " (" + Math.round(Number(percent || 0)) + "%)"
}

// True when a sync is paused or otherwise not running.
function syncPaused(sync) {
  var state = String(sync && sync.runState || "")
  return state === "Disabled" || state === "Suspended"
}

// True when at least one of `syncs` is running, so "pause all" applies;
// otherwise "resume all" does.
function anyRunning(syncs) {
  var list = syncs || []
  for (var i = 0; i < list.length; i++)
    if (!syncPaused(list[i])) return true
  return false
}

// Identifies a sync ("sync:<id>") or backup ("backup:<tag>") across
// refreshes, unlike its row number; "" when `item` is missing.
function itemKey(kind, item) {
  if (!item) return ""
  return kind + ":" + (kind === "sync" ? item.id : item.tag)
}

// One of "error", "paused", "syncing", "synced" for a sync row.
function syncKind(sync) {
  if (!sync) return "synced"
  if (sync.error) return "error"
  if (syncPaused(sync)) return "paused"
  var status = String(sync.status || "")
  if (status === "Synced") return "synced"
  if (status === "Failed" || status === "Error") return "error"
  return "syncing"
}

// Second line of a sync row, e.g. "Synced · 947 files · 157.51 MB".
function syncMeta(sync) {
  if (!sync) return ""
  var parts = []
  var kind = syncKind(sync)
  if (kind === "error") parts.push("Error: " + sync.error)
  else if (kind === "paused") parts.push("Paused")
  else parts.push(String(sync.status || "Syncing"))
  parts.push(Number(sync.files || 0).toLocaleString(Qt.locale(), "f", 0) + " files")
  if (sync.size) parts.push(sync.size)
  return parts.join(" · ")
}

// Shortens a path under the home folder to "~/…".
function homePath(path, home) {
  var value = String(path || "")
  var base = String(home || "")
  if (base && (value === base || value.indexOf(base + "/") === 0)) return "~" + value.substring(base.length)
  return value
}

// Readable backup schedule from MEGAcmd's period string.
function periodText(period) {
  var value = String(period || "").trim()
  var cron = value.split(/\s+/)
  if (cron.length === 6) {
    var time = ("0" + cron[2]).slice(-2) + ":" + ("0" + cron[1]).slice(-2)
    if (cron[3] === "*" && cron[4] === "*" && cron[5] === "*") return "Daily at " + time
    if (cron[3] === "*" && cron[4] === "*") return "Weekly at " + time
    return value
  }
  var match = value.match(/^(\d+)([dhms])$/)
  if (match) {
    var names = { d: "day", h: "hour", m: "minute", s: "second" }
    var n = Number(match[1])
    return "Every " + (n === 1 ? "" : n + " ") + names[match[2]] + (n === 1 ? "" : "s")
  }
  return value
}

// Second line of a backup row, e.g. "Daily at 02:00 · keeps 14 · last COMPLETE".
function backupMeta(backup) {
  if (!backup) return ""
  var parts = [periodText(backup.period)]
  if (backup.maxBackups) parts.push("keeps " + backup.maxBackups)
  if (backup.lastStatus) parts.push("last " + String(backup.lastStatus).toLowerCase())
  else parts.push("no backup yet")
  return parts.join(" · ")
}

// Transfer summary, e.g. "6,838 downloads · 6.35 GB of 42.49 GB (15%)", or "".
function transfersText(transfers) {
  if (!transfers) return ""
  var parts = []
  if (transfers.downloads > 0)
    parts.push(transfers.downloads.toLocaleString(Qt.locale(), "f", 0) + " down · " + transfers.downloaded + " of " +
               transfers.downloadTotal + " (" + Math.round(transfers.downloadPercent) + "%)")
  if (transfers.uploads > 0)
    parts.push(transfers.uploads.toLocaleString(Qt.locale(), "f", 0) + " up · " + transfers.uploaded + " of " +
               transfers.uploadTotal + " (" + Math.round(transfers.uploadPercent) + "%)")
  return parts.join("\n")
}

// Overall state for the bar icon, most serious first: "stopped" (the MEGAcmd
// engine is not running), "off" (logged out), "error", "warning" (storage 90%
// or more), "paused", "syncing", "synced".
function overallKind(status) {
  if (status && status.running === false) return "stopped"
  if (!status || !status.loggedIn) return "off"
  var syncs = status.syncs || []
  var transfers = status.transfers || {}
  var anyRunning = false
  for (var i = 0; i < syncs.length; i++) {
    var kind = syncKind(syncs[i])
    if (kind === "error") return "error"
    if (kind !== "paused") anyRunning = true
  }
  if (storageLevel(status.usagePercent) > 0) return "warning"
  if (syncs.length > 0 && !anyRunning) return "paused"
  for (var j = 0; j < syncs.length; j++)
    if (syncKind(syncs[j]) === "syncing") return "syncing"
  if ((transfers.downloads || 0) + (transfers.uploads || 0) > 0) return "syncing"
  return "synced"
}

// Short phrase for the panel header.
function overallText(kind) {
  if (kind === "stopped") return "MEGAcmd is not running"
  if (kind === "off") return "Not logged in"
  if (kind === "error") return "A sync needs attention"
  if (kind === "warning") return "Storage almost full"
  if (kind === "paused") return "Syncing paused"
  if (kind === "syncing") return "Syncing"
  return "Up to date"
}

// Backup run states that mean the backup did not complete.
var FAILED_BACKUP = /INCOMPLETE|ABORTED|MISCARRIED|FAILED/

// True when a backup's last run did not complete.
function backupFailed(backup) {
  return FAILED_BACKUP.test(String(backup && backup.lastStatus || ""))
}

// Storage warning level for a usage percentage: 0, 90 or 95.
function storageLevel(percent) {
  var value = Number(percent || 0)
  if (value >= 95) return 95
  if (value >= 90) return 90
  return 0
}

// Current problems worth a notification, each {key, title, body}. The key
// identifies the problem, so the same problem is only reported once. The
// texts name no folder: they go to the notification command as arguments,
// which other local accounts can read, and the panel the notification opens
// shows the folder.
function problems(status) {
  var list = []
  if (!status || !status.loggedIn) return list
  var syncs = status.syncs || []
  for (var i = 0; i < syncs.length; i++) {
    if (syncKind(syncs[i]) !== "error") continue
    var reason = syncs[i].error || syncs[i].status
    list.push({
      key: "sync:" + syncs[i].id + ":" + reason,
      title: "MEGA sync stopped",
      body: reason + ". Open the MEGA panel to see which folder."
    })
  }
  var backups = status.backups || []
  for (var j = 0; j < backups.length; j++) {
    if (!backupFailed(backups[j])) continue
    list.push({
      key: "backup:" + backups[j].tag + ":" + backups[j].lastName,
      title: "MEGA backup " + String(backups[j].lastStatus).toLowerCase(),
      body: "Last run " + backups[j].lastDate + ". Open the MEGA panel to see which folder."
    })
  }
  return list
}

// Small badge drawn on the cloud for an overall state.
function badgeGlyph(kind) {
  if (kind === "error" || kind === "warning") return ""
  if (kind === "off" || kind === "stopped") return ""
  if (kind === "paused") return ""
  if (kind === "syncing") return ""
  return ""
}

// Theme colour name for a state's badge: red, orange, yellow, blue or green.
function badgeColorName(kind) {
  if (kind === "error") return "red"
  if (kind === "warning" || kind === "off" || kind === "stopped") return "orange"
  if (kind === "paused") return "yellow"
  if (kind === "syncing") return "blue"
  return "green"
}

// TEXT with "&", "<" and ">" escaped, for notification bodies, which the
// notification daemon renders as styled text.
function escapeMarkup(text) {
  return String(text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}
