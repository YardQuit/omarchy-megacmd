// MegaIcon.qml: cloud glyph with a coloured state badge.
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import qs.Commons
import "Model.js" as Model

// Draws the cloud in `color`, scaled to fill a `size` square, with the badge
// for `kind` (see Model.badgeGlyph) in its lower-right corner in `badgeColor`.
// `ringColor` (usually the bar background) outlines the badge.
Item {
  id: root

  property string kind: "synced"
  property real size: Style.font.body
  property color color: Color.foreground
  property color badgeColor: Color.accent
  property color ringColor: Color.background
  property string fontFamily: Style.font.family

  implicitWidth: size
  implicitHeight: size

  TextMetrics {
    id: cloudMetrics
    font.family: root.fontFamily
    font.pixelSize: 100
    text: Model.ICON_CLOUD
  }

  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
    text: Model.ICON_CLOUD
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: Math.max(1, Math.round(100 * root.size / Math.max(1, cloudMetrics.tightBoundingRect.width, cloudMetrics.tightBoundingRect.height)))
  }

  Rectangle {
    id: badge
    width: Math.round(root.size * 0.72)
    height: width
    radius: width / 2
    color: root.ringColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: -Math.round(width * 0.25)
    anchors.bottomMargin: -Math.round(width * 0.2)

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      text: Model.badgeGlyph(root.kind)
      color: root.badgeColor
      font.family: root.fontFamily
      font.pixelSize: Math.round(badge.width * 0.8)
      font.bold: true
    }
  }
}
