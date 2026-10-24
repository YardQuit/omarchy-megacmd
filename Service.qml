// Service.qml: MEGAcmd state and actions for the MEGA bar widget.
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Polls status.py for the account, syncs, backups and transfers, and runs the
// mega-* commands behind the panel's actions. Refreshes quickly while
// `fastRefresh` is set (the panel is open) and every `refreshIntervalSec`
// otherwise. Sends a notification once per problem (sync error, failed
// backup, logout) and when storage use crosses 90% or 95%. Setting
// `previewName` to a file name in fixtures/ shows that saved state instead.
Item {
  id: root

  property var settings: ({})
  property bool fastRefresh: false
  property string previewName: ""

  property bool installed: true
  property bool loggedIn: false
  property string email: ""
  property double usedBytes: 0
  property double totalBytes: 0
  property double usagePercent: 0
  property var syncs: []
  property var backups: []
  property var transfers: ({})
  property string lastError: ""
  property string actionStatus: ""
  property bool loaded: false

  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  // The saved states in fixtures/ are written for the home folder /home/user.
  readonly property string home: previewName !== "" ? "/home/user" : Quickshell.env("HOME")
  readonly property string kind: Model.overallKind({ loggedIn: loggedIn, syncs: syncs, transfers: transfers, usagePercent: usagePercent })
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 10, 3600)
  readonly property string syncFolder: String(setting("syncFolder", "/"))
  readonly property string backupFolder: String(setting("backupFolder", "/Backups"))
  readonly property bool busy: controlProcess.running

  property var _queue: []
  property var _reported: ({})
  property int _storageLevel: 0
  property bool _wasLoggedIn: false

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = previewName !== ""
      ? ["python3", "-I", pluginDir + "/status.py", "--fixture", pluginDir + "/fixtures/" + previewName + ".json"]
      : ["python3", "-I", pluginDir + "/status.py", "20"]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var data = Model.parseStatus(raw)
    if (data.ok === false) {
      lastError = String(data.error || "Could not read MEGA status")
      return
    }
    installed = data.installed !== false
    loggedIn = data.loggedIn === true
    email = String(data.email || "")
    usedBytes = Number(data.usedBytes || 0)
    totalBytes = Number(data.totalBytes || 0)
    usagePercent = Number(data.usagePercent || 0)
    syncs = data.syncs || []
    backups = data.backups || []
    transfers = data.transfers || {}
    lastError = String(data.error || "")
    loaded = true
    reportProblems(data)
  }

  // Shows the MEGA status as of the saved state `name` (see fixtures/), or
  // the live state again when `name` is empty.
  function preview(name) {
    previewName = String(name || "").replace(/[^A-Za-z0-9_-]/g, "")
    _reported = ({})
    _storageLevel = 0
    refresh()
  }

  function notify(title, body, urgency, glyph) {
    var label = previewName !== "" ? " (preview)" : ""
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "MEGA", "-u", urgency, "-g", glyph,
                             title + label, body, "--exec", "omarchy-shell", "yardquit.mega", "open"])
  }

  // Notifies about problems not yet reported; forgets those that cleared.
  function reportProblems(data) {
    var current = Model.problems(data, home)
    var reported = ({})
    for (var i = 0; i < current.length; i++) {
      reported[current[i].key] = true
      if (!_reported[current[i].key]) notify(current[i].title, current[i].body, "critical", Model.ICON_ERROR)
    }
    _reported = reported

    if (_wasLoggedIn && !loggedIn) notify("MEGA logged out", "Syncs and backups have stopped. Log in again from the MEGA panel.", "critical", Model.ICON_OFF)
    _wasLoggedIn = loggedIn

    var level = loggedIn ? Model.storageLevel(usagePercent) : 0
    if (level > _storageLevel)
      notify("MEGA storage " + Math.round(usagePercent) + "% full", Model.usageText(usedBytes, totalBytes, usagePercent),
             level >= 95 ? "critical" : "normal", Model.ICON_CLOUD)
    _storageLevel = level
  }

  // Runs mega-* commands one after another, then refreshes.
  function runCommands(commands) {
    _queue = _queue.concat(commands)
    if (!controlProcess.running) runNext()
  }

  function runNext() {
    if (_queue.length === 0) {
      settleTimer.restart()
      return
    }
    controlProcess.command = _queue[0]
    _queue = _queue.slice(1)
    controlProcess.running = true
  }

  function pauseSync(sync) { if (sync) runCommands([["mega-sync", "--pause", sync.id]]) }
  function resumeSync(sync) { if (sync) runCommands([["mega-sync", "--enable", sync.id]]) }
  function toggleSync(sync) { if (Model.syncPaused(sync)) resumeSync(sync); else pauseSync(sync) }
  function removeSync(sync) { if (sync) runCommands([["mega-sync", "--delete", sync.id]]) }
  function removeBackup(backup) { if (backup) runCommands([["mega-backup", "-d", backup.tag]]) }

  function setAllPaused(paused) {
    var commands = []
    for (var i = 0; i < syncs.length; i++) {
      if (Model.syncPaused(syncs[i]) !== paused)
        commands.push(["mega-sync", paused ? "--pause" : "--enable", syncs[i].id])
    }
    if (commands.length > 0) runCommands(commands)
  }

  function openFolder(path) {
    if (path) Quickshell.execDetached(["uwsm-app", "--", "nautilus", String(path)])
  }

  function openWeb() {
    Qt.openUrlExternally("https://mega.nz/fm")
  }

  function runGuided(script, args) {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation",
                             [pluginDir + "/bin/" + script].concat(args || []).map(function(a) { return "'" + String(a).replace(/'/g, "'\\''") + "'" }).join(" ")])
    guidedRefresh.restart()
  }

  function login() { runGuided("mega-account-login") }
  function addSync() { runGuided("mega-add-sync", [syncFolder]) }
  function addBackup() { runGuided("mega-add-backup", [backupFolder]) }
  function editBackup(backup) { if (backup) runGuided("mega-edit-backup", [backup.tag, backup.period, backup.maxBackups]) }

  Timer {
    interval: root.fastRefresh ? 3000 : root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    // MEGAcmd applies pause/resume asynchronously; poll a little afterwards.
    id: settleTimer
    interval: 1200
    onTriggered: root.refresh()
  }

  Timer {
    // A guided step runs in its own terminal; keep checking while it is open.
    id: guidedRefresh
    property int ticks: 0
    interval: 5000
    repeat: true
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks >= 60) { ticks = 0; stop() }
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 4000
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyStatus(statusOut.text)
      else root.lastError = String(statusErr.text || "Could not read MEGA status").trim()
    }
  }

  Process {
    id: controlProcess
    stdout: StdioCollector { id: controlOut; waitForEnd: true }
    stderr: StdioCollector { id: controlErr; waitForEnd: true }
    onExited: function(exitCode) {
      var output = (String(controlOut.text || "") + String(controlErr.text || "")).trim()
      if (exitCode !== 0 || /\bERR\b/.test(output)) {
        root.actionStatus = output.replace(/^\[[^\]]*ERR\s*/, "").replace(/\]$/, "") || "MEGA command failed"
        actionStatusTimer.restart()
      }
      root.runNext()
    }
  }
}
