// Panel.qml: MEGA bar widget with sync and backup panel.
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Bar icon showing MEGAcmd's overall state, and a keyboard-navigable panel to
// pause, resume, add and remove syncs and backups. Enter runs a row's main
// action; "o" opens its folder, "s" opens a backup's settings, "x" twice
// removes it, "r" refreshes.
//
// IPC target "yardquit.mega": open, close, toggle, refresh, status, and
// preview NAME / live to show a saved state from fixtures/.
Panel {
  id: root
  moduleName: "yardquit.mega"
  ipcTarget: "yardquit.mega"
  manageIpc: false

  property bool cursorActive: false
  property int cursorIndex: 0
  property string pendingRemove: ""

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string kind: mega.kind
  // Theme colours by name, for the state badges (see Model.badgeColorName).
  readonly property var stateColors: ({
    red: themeColors.red, orange: themeColors.orange, yellow: themeColors.yellow,
    blue: themeColors.blue, green: themeColors.green
  })
  readonly property color badgeColor: stateColors[Model.badgeColorName(kind)]
  readonly property color panelBackground: Commons.Color.background

  // Keyboard targets in display order: "header", "sync:N", "addSync",
  // "backup:N", "addBackup", "web", or "login" when logged out.
  readonly property var targets: {
    if (!mega.loggedIn) return ["login"]
    var list = ["header"]
    for (var i = 0; i < mega.syncs.length; i++) list.push("sync:" + i)
    list.push("addSync")
    for (var j = 0; j < mega.backups.length; j++) list.push("backup:" + j)
    list.push("addBackup", "web")
    return list
  }
  readonly property string cursorTarget: targets[Math.max(0, Math.min(cursorIndex, targets.length - 1))]

  function hasCursor(target) {
    return cursorActive && cursorTarget === target
  }

  function setCursor(target) {
    var index = targets.indexOf(target)
    if (index < 0) return
    cursorActive = true
    cursorIndex = index
  }

  function moveCursor(dy) {
    cursorActive = true
    cursorIndex = Math.max(0, Math.min(targets.length - 1, cursorIndex + dy))
    pendingRemove = ""
  }

  function itemFor(target) {
    var parts = String(target).split(":")
    if (parts[0] === "sync") return mega.syncs[Number(parts[1])]
    if (parts[0] === "backup") return mega.backups[Number(parts[1])]
    return null
  }

  function activate(target) {
    var parts = String(target).split(":")
    if (target === "login") mega.login()
    else if (target === "header") mega.setAllPaused(mega.kind !== "paused")
    else if (parts[0] === "sync") mega.toggleSync(itemFor(target))
    else if (parts[0] === "backup") mega.editBackup(itemFor(target))
    else if (target === "addSync") mega.addSync()
    else if (target === "addBackup") mega.addBackup()
    else if (target === "web") mega.openWeb()
  }

  function openTarget(target) {
    var item = itemFor(target)
    if (item) mega.openFolder(item.local)
  }

  // Removing asks twice: the first request arms it, the second removes.
  function requestRemove(target) {
    var item = itemFor(target)
    if (!item) return
    if (pendingRemove !== target) {
      pendingRemove = target
      removeDisarm.restart()
      return
    }
    pendingRemove = ""
    if (String(target).indexOf("sync:") === 0) mega.removeSync(item)
    else mega.removeBackup(item)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    pendingRemove = ""
    if (panelFlick) panelFlick.contentY = 0
    mega.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: mega
    settings: root.settings
    fastRefresh: root.opened
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { mega.refresh(); return "ok" }
    function status(): string { return Model.overallText(root.kind) }
    function preview(name: string): string { mega.preview(name); return "preview " + name }
    function live(): string { mega.preview(""); return "live" }
  }

  Timer {
    id: removeDisarm
    interval: 4000
    onTriggered: root.pendingRemove = ""
  }

  ThemePalette { id: themeColors }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        MegaIcon {
          anchors.centerIn: parent
          size: Style.font.body
          kind: root.kind
          color: root.barForeground
          badgeColor: root.badgeColor
          ringColor: root.bar ? root.bar.background : Commons.Color.background
          fontFamily: root.fontFamily
        }
      }
    }
    tooltipText: mega.loggedIn ? "MEGA: " + Model.overallText(root.kind) : "MEGA: not logged in"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) mega.setAllPaused(mega.kind !== "paused")
      else if (buttonCode === Qt.MiddleButton) mega.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activate(root.cursorTarget)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") mega.refresh()
        else if (t === "o" || t === "O") root.openTarget(root.cursorTarget)
        else if ((t === "s" || t === "S") && String(root.cursorTarget).indexOf("backup:") === 0) mega.editBackup(root.itemFor(root.cursorTarget))
        else if (t === "x" || t === "X") root.requestRemove(root.cursorTarget)
        else if (t === "p" || t === "P") mega.setAllPaused(mega.kind !== "paused")
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.hasCursor("header")

            PanelHero {
              id: hero
              width: parent.width
              title: "MEGA"
              meta: mega.loggedIn ? Model.overallText(root.kind) : (mega.installed ? "Not logged in" : "MEGAcmd is not installed")
              detail: mega.email
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconComponent: Component {
                MegaIcon {
                  size: Style.font.display
                  kind: root.kind
                  color: root.foreground
                  badgeColor: root.badgeColor
                  ringColor: root.panelBackground
                  fontFamily: root.fontFamily
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: syncSwitch
                  visible: mega.loggedIn && mega.syncs.length > 0
                  checked: root.kind !== "paused"
                  busy: mega.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) root.setCursor("header") }
                  onToggled: mega.setAllPaused(root.kind !== "paused")

                  PanelToolTip {
                    visible: syncSwitch.containsMouse
                    text: root.kind === "paused" ? "Resume all syncing" : "Pause all syncing"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: mega.actionStatus !== "" || mega.lastError !== ""
            width: parent.width
            text: mega.actionStatus !== "" ? mega.actionStatus : mega.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          ActionRow {
            visible: !mega.loggedIn
            width: parent.width
            target: "login"
            glyph: "󰌆"
            title: "Log in to MEGA"
            meta: "Opens a terminal for your email, password and 2FA code"
          }

          Column {
            visible: mega.loggedIn
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair {
              label: "Stored"
              value: Model.usageText(mega.usedBytes, mega.totalBytes, mega.usagePercent)
              valueColor: Model.storageLevel(mega.usagePercent) > 0 ? root.urgent : root.foreground
            }

            Text {
              textFormat: Text.PlainText
              visible: text !== ""
              width: parent.width
              text: Model.transfersText(mega.transfers)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }

          PanelSeparator { visible: mega.loggedIn; foreground: root.foreground }

          Column {
            visible: mega.loggedIn
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader { text: "SYNC FOLDERS"; foreground: root.foreground; fontFamily: root.fontFamily }

            Repeater {
              model: mega.syncs
              ItemRow {
                required property var modelData
                required property int index
                width: parent.width
                target: "sync:" + index
                iconKind: Model.syncKind(modelData)
                title: Model.homePath(modelData.local, mega.home) + "  ↔  " + modelData.remote
                meta: Model.syncMeta(modelData)
                toggleGlyph: Model.syncPaused(modelData) ? "󰐊" : "󰏤"
                toggleTip: Model.syncPaused(modelData) ? "Resume" : "Pause"
              }
            }

            ActionRow {
              width: parent.width
              target: "addSync"
              glyph: "󰐕"
              title: "Add sync…"
              meta: "Keep a local folder and a MEGA folder the same"
            }
          }

          PanelSeparator { visible: mega.loggedIn; foreground: root.foreground }

          Column {
            visible: mega.loggedIn
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader { text: "BACKUPS"; foreground: root.foreground; fontFamily: root.fontFamily }

            Repeater {
              model: mega.backups
              ItemRow {
                required property var modelData
                required property int index
                width: parent.width
                target: "backup:" + index
                glyph: Model.ICON_BACKUP
                glyphColor: Model.backupFailed(modelData) ? root.stateColors.red : (modelData.lastStatus ? root.stateColors.green : root.foreground)
                title: Model.homePath(modelData.local, mega.home) + "  →  " + modelData.remote
                meta: Model.backupMeta(modelData)
                toggleGlyph: ""
              }
            }

            ActionRow {
              width: parent.width
              target: "addBackup"
              glyph: "󰐕"
              title: "Add backup…"
              meta: "Scheduled, versioned copies of a local folder in MEGA"
            }
          }

          PanelSeparator { visible: mega.loggedIn; foreground: root.foreground }

          ActionRow {
            visible: mega.loggedIn
            width: parent.width
            target: "web"
            glyph: "󰖟"
            title: "Open mega.nz"
            meta: "Files, shares and account settings in the browser"
          }
        }
      }
    }
  }

  // A row with a single action, such as "Add sync…".
  component ActionRow: CursorSurface {
    id: actionRow
    property string target: ""
    property string glyph: ""
    property string title: ""
    property string meta: ""

    hasCursor: root.hasCursor(target)
    foreground: root.foreground
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(actionRow.target)
      onClicked: root.activate(actionRow.target)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: actionRow.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: actionContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.meta
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  // A sync or backup row with its own buttons.
  component ItemRow: CursorSurface {
    id: itemRow
    property string target: ""
    property string iconKind: ""
    property string glyph: ""
    property color glyphColor: root.foreground
    property string title: ""
    property string meta: ""
    property string toggleGlyph: ""
    property string toggleTip: ""
    readonly property bool armed: root.pendingRemove === target

    hasCursor: root.hasCursor(target)
    foreground: root.foreground
    implicitHeight: itemContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: root.setCursor(itemRow.target)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      MegaIcon {
        visible: itemRow.iconKind !== ""
        size: Style.font.icon
        kind: itemRow.iconKind
        color: root.foreground
        badgeColor: root.stateColors[Model.badgeColorName(itemRow.iconKind)]
        ringColor: root.panelBackground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        visible: itemRow.iconKind === ""
        textFormat: Text.PlainText
        text: itemRow.glyph
        color: itemRow.glyphColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: itemContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: itemRow.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideMiddle
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: itemRow.armed ? "Press remove again to stop it (files stay where they are)" : itemRow.meta
          color: itemRow.armed ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        visible: itemRow.toggleGlyph !== ""
        iconText: itemRow.toggleGlyph
        tooltipText: itemRow.toggleTip
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.activate(itemRow.target)
      }

      PanelActionButton {
        visible: String(itemRow.target).indexOf("backup:") === 0
        iconText: "󰒓"
        tooltipText: "Schedule and versions"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: mega.editBackup(root.itemFor(itemRow.target))
      }

      PanelActionButton {
        iconText: "󰉋"
        tooltipText: "Open folder"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.openTarget(itemRow.target)
      }

      PanelActionButton {
        iconText: "󰆴"
        tooltipText: itemRow.armed ? "Click again to remove" : "Remove"
        foreground: itemRow.armed ? root.urgent : root.foreground
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.requestRemove(itemRow.target)
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    property color valueColor: root.foreground

    width: parent.width
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: parent.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    Text {
      textFormat: Text.PlainText
      text: parent.value
      color: parent.valueColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }
}
