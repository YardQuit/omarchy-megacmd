// StateBadge.qml: round badge showing a MEGA state glyph.
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import qs.Commons
import "Model.js" as Model

// Draws the glyph for `kind` (see Model.badgeGlyph) in `badgeColor` on a disc
// of `ringColor` (usually the background behind the icon), which separates it
// from the icon it sits on. Set `width`; the badge is round.
Rectangle {
  id: root

  property string kind: "synced"
  property color badgeColor: Color.accent
  property color ringColor: Color.background
  property string fontFamily: Style.font.family

  height: width
  radius: width / 2
  color: ringColor

  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
    text: Model.badgeGlyph(root.kind)
    color: root.badgeColor
    font.family: root.fontFamily
    font.pixelSize: Math.round(root.width * 0.8)
    font.bold: true
  }
}
