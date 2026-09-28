import QtQuick
import qs.Ui

// Bar button that opens the Window Commander settings panel. Add it to the bar
// with:  omarchy bar put com.dchadwick.windowcommander
BarWidget {
  id: root
  moduleName: "com.dchadwick.windowcommander"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "WC"
    onPressed: function(button) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle com.dchadwick.windowcommander")
    }
  }
}
