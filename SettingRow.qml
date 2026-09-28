import QtQuick
import qs.Commons

// One settings row: label + description on the left, a control on the right.
// Declare the control as a child; it is placed in the right-hand slot.
Item {
  id: row

  property string title: ""
  property string subtitle: ""
  default property alias control: slot.data

  implicitHeight: Math.max(Style.spacing.controlHeight, labels.height)
  width: parent ? parent.width : 0

  Column {
    id: labels
    anchors.left: parent.left
    anchors.right: slot.left
    anchors.rightMargin: Style.spacing.xxl
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xxs

    Text {
      width: parent.width
      text: row.title
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: row.subtitle
      visible: text !== ""
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  Item {
    id: slot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: childrenRect.width
    implicitHeight: childrenRect.height
  }
}
