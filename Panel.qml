import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Engine.js" as Engine

// Window Commander settings. Opened with:
//   omarchy-shell shell toggle com.dchadwick.windowcommander
// The engine itself lives in Service.qml; this only edits its config, which is
// applied to the live handles immediately.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  readonly property var c: (root.service ? root.service.config : Engine.defaultConfig())

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function close() { root.opened = false }
  function toggle() { root.opened ? root.close() : root.open("{}") }

  function set(patch) { if (root.service) root.service.setConfig(patch) }
  function reset() { if (root.service) root.service.resetConfig() }

  function setFS(patch) {
    var fs = Object.assign({}, root.c.focusSwitcher, patch)
    root.set({ focusSwitcher: fs })
  }

  PanelWindow {
    id: win
    visible: root.opened
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "com-dchadwick-windowcommander-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(560), parent.width - Style.gapsOut * 4)
      height: Math.min(Style.space(660), parent.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelGap

      MouseArea { anchors.fill: parent; onClicked: {} }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        anchors.margins: Style.spacing.panelGap
        focus: root.opened
        onCloseRequested: root.close()

        ColumnLayout {
          anchors.fill: parent
          spacing: Style.spacing.panelGap

          // Header -------------------------------------------------------
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.md

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.xxs
              Text {
                Layout.fillWidth: true
                text: "Window Commander"
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                Layout.fillWidth: true
                text: "Grab a pill on any tiled split to resize. " +
                      (root.service ? root.service.boundaries.length : 0) + " split(s) now."
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            ToggleSwitch {
              checked: root.c.enabled === true
              foreground: Color.menu.text
              accent: Color.accent
              Layout.alignment: Qt.AlignVCenter
              onToggled: root.set({ enabled: !(root.c.enabled === true) })
            }
          }

          PanelSeparator { Layout.fillWidth: true; foreground: Color.menu.text }

          // Scrollable body ---------------------------------------------
          Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: body.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: body
              width: scroller.width
              spacing: Style.spacing.lg

              PanelSectionHeader { text: "Appearance"; foreground: Color.menu.text; fontFamily: Style.font.family }

              SettingRow {
                title: "Handle length"
                subtitle: "How far the pill runs along the split."
                Row {
                  spacing: Style.spacing.md
                  PanelSlider {
                    width: Style.space(170)
                    minimum: 16; maximum: 240; step: 1; integer: true
                    value: root.c.handleLength
                    fillColor: Color.accent; knobColor: Color.accent
                    onMoved: function(v) { root.set({ handleLength: Math.round(v) }) }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(40)
                    text: Math.round(root.c.handleLength || 0) + "px"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              SettingRow {
                title: "Idle opacity"
                subtitle: "Resting visibility of the handles."
                Row {
                  spacing: Style.spacing.md
                  PanelSlider {
                    width: Style.space(170)
                    minimum: 0; maximum: 1; step: 0.01
                    value: root.c.idleOpacity
                    fillColor: Color.accent; knobColor: Color.accent
                    onMoved: function(v) { root.set({ idleOpacity: v }) }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(40)
                    text: Math.round((root.c.idleOpacity || 0) * 100) + "%"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              SettingRow {
                title: "Hover opacity"
                subtitle: "Visibility while pointed at or grabbed."
                Row {
                  spacing: Style.spacing.md
                  PanelSlider {
                    width: Style.space(170)
                    minimum: 0; maximum: 1; step: 0.01
                    value: root.c.hoverOpacity
                    fillColor: Color.accent; knobColor: Color.accent
                    onMoved: function(v) { root.set({ hoverOpacity: v }) }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(40)
                    text: Math.round((root.c.hoverOpacity || 0) * 100) + "%"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              SettingRow {
                title: "Colour"
                subtitle: "Theme role used for the handles."
                ButtonGroup {
                  options: [
                    { value: "foreground", label: "Text" },
                    { value: "accent", label: "Accent" },
                    { value: "muted", label: "Muted" },
                    { value: "urgent", label: "Urgent" }
                  ]
                  value: String(root.c.color || "foreground")
                  foreground: Color.menu.text
                  accent: Color.accent
                  focusable: false
                  onChanged: function(v) { root.set({ color: v }) }
                }
              }

              SettingRow {
                title: "Handle padding"
                subtitle: "Margin between the pill and the window borders."
                Row {
                  spacing: Style.spacing.md
                  PanelSlider {
                    width: Style.space(170)
                    minimum: 0; maximum: 12; step: 1; integer: true
                    value: root.c.handlePadding
                    fillColor: Color.accent; knobColor: Color.accent
                    onMoved: function(v) { root.set({ handlePadding: Math.round(v) }) }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(40)
                    text: Math.round(root.c.handlePadding || 0) + "px"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              SettingRow {
                title: "Handle background"
                subtitle: "Translucent capsule behind each pill."
                ToggleSwitch {
                  checked: root.c.handleBackground === true
                  foreground: Color.menu.text
                  accent: Color.accent
                  onToggled: root.set({ handleBackground: !(root.c.handleBackground === true) })
                }
              }

              SettingRow {
                title: "Handle background opacity"
                subtitle: "How solid the capsule behind each pill is."
                Row {
                  spacing: Style.spacing.md
                  PanelSlider {
                    width: Style.space(170)
                    enabled: root.c.handleBackground === true
                    minimum: 0; maximum: 1; step: 0.01
                    value: root.c.handleBackgroundOpacity
                    fillColor: Color.accent; knobColor: Color.accent
                    onMoved: function(v) { root.set({ handleBackgroundOpacity: v }) }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(40)
                    text: Math.round((root.c.handleBackgroundOpacity || 0) * 100) + "%"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              PanelSeparator { width: parent.width; foreground: Color.menu.text }

              PanelSectionHeader { text: "Behaviour"; foreground: Color.menu.text; fontFamily: Style.font.family }

              SettingRow {
                title: "Resize mode"
                subtitle: "Live follows the cursor; preview commits on release."
                ButtonGroup {
                  options: [
                    { value: "live", label: "Live" },
                    { value: "preview", label: "Preview" }
                  ]
                  value: String(root.c.resizeMode || "live")
                  foreground: Color.menu.text
                  accent: Color.accent
                  focusable: false
                  onChanged: function(v) { root.set({ resizeMode: v }) }
                }
              }

              SettingRow {
                title: "Magnetic snapping"
                subtitle: "Pull the boundary toward thirds and halves."
                ToggleSwitch {
                  checked: root.c.snapping === true
                  foreground: Color.menu.text
                  accent: Color.accent
                  onToggled: root.set({ snapping: !(root.c.snapping === true) })
                }
              }

              SettingRow {
                title: "Snap strength"
                subtitle: "How close before a preset captures the boundary."
                Row {
                  spacing: Style.spacing.md
                  PanelSlider {
                    width: Style.space(170)
                    enabled: root.c.snapping === true
                    minimum: 0; maximum: 40; step: 1; integer: true
                    value: root.c.snapThreshold
                    fillColor: Color.accent; knobColor: Color.accent
                    onMoved: function(v) { root.set({ snapThreshold: Math.round(v) }) }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(40)
                    text: Math.round(root.c.snapThreshold || 0) + "px"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              SettingRow {
                title: "Free-drag modifier"
                subtitle: "Hold this to ignore snapping and place freely."
                ButtonGroup {
                  options: [
                    { value: "none", label: "None" },
                    { value: "shift", label: "Shift" },
                    { value: "ctrl", label: "Ctrl" },
                    { value: "alt", label: "Alt" },
                    { value: "super", label: "Super" }
                  ]
                  value: String(root.c.freeDragModifier || "shift")
                  foreground: Color.menu.text
                  accent: Color.accent
                  focusable: false
                  onChanged: function(v) { root.set({ freeDragModifier: v }) }
                }
              }

              SettingRow {
                title: "Equalize on double-click"
                subtitle: "Double-click a handle to split 50/50."
                ToggleSwitch {
                  checked: root.c.equalizeOnDoubleClick === true
                  foreground: Color.menu.text
                  accent: Color.accent
                  onToggled: root.set({ equalizeOnDoubleClick: !(root.c.equalizeOnDoubleClick === true) })
                }
              }

              PanelSeparator { width: parent.width; foreground: Color.menu.text }

              PanelSectionHeader { text: "Layouts"; foreground: Color.menu.text; fontFamily: Style.font.family }

              SettingRow {
                title: "Dwindle"
                subtitle: "Handles on dwindle splits."
                ToggleSwitch {
                  checked: root.c.layouts && root.c.layouts.dwindle === true
                  foreground: Color.menu.text
                  accent: Color.accent
                  onToggled: if (root.service) root.service.setLayout("dwindle", !(root.c.layouts.dwindle === true))
                }
              }

              SettingRow {
                title: "Master"
                subtitle: "Handles on master layout splits."
                ToggleSwitch {
                  checked: root.c.layouts && root.c.layouts.master === true
                  foreground: Color.menu.text
                  accent: Color.accent
                  onToggled: if (root.service) root.service.setLayout("master", !(root.c.layouts.master === true))
                }
              }

              SettingRow {
                title: "Scrolling"
                subtitle: "Handles between columns in the scrolling layout."
                ToggleSwitch {
                  checked: root.c.layouts && root.c.layouts.scrolling === true
                  foreground: Color.menu.text
                  accent: Color.accent
                  onToggled: if (root.service) root.service.setLayout("scrolling", !(root.c.layouts.scrolling === true))
                }
              }

              PanelSeparator { width: parent.width; foreground: Color.menu.text }

              PanelSectionHeader { text: "Focus switcher"; foreground: Color.menu.text; fontFamily: Style.font.family }

              SettingRow {
                title: "Focus dots"
                subtitle: "A dot per window; tap or scrub to switch."
                ToggleSwitch {
                  checked: root.c.focusSwitcher && root.c.focusSwitcher.enabled === true
                  foreground: Color.menu.text
                  accent: Color.accent
                  onToggled: root.setFS({ enabled: !(root.c.focusSwitcher.enabled === true) })
                }
              }

              SettingRow {
                title: "Dock"
                subtitle: "Where the rail sits. ✕ turns it off."
                Grid {
                  id: dockGrid
                  columns: 3
                  rowSpacing: Style.spacing.xs
                  columnSpacing: Style.spacing.xs
                  readonly property var cells: [
                    { d: "top-left", g: "◤" }, { d: "top-center", g: "▲" }, { d: "top-right", g: "◥" },
                    { d: "mid-left", g: "◀" }, { d: "off", g: "✕" }, { d: "mid-right", g: "▶" },
                    { d: "bottom-left", g: "◣" }, { d: "bottom-center", g: "▼" }, { d: "bottom-right", g: "◢" }
                  ]
                  Repeater {
                    model: dockGrid.cells
                    delegate: Button {
                      required property var modelData
                      text: modelData.g
                      selected: root.c.focusSwitcher.dock === modelData.d
                      foreground: Color.menu.text
                      accent: Color.accent
                      focusable: false
                      horizontalPadding: Style.spacing.sm
                      verticalPadding: Style.spacing.xs
                      onClicked: root.setFS({ dock: modelData.d })
                    }
                  }
                }
              }

              SettingRow {
                title: "Pill depth"
                subtitle: "Capsule thickness; the dots grow with it. 0 fits the gap."
                Row {
                  spacing: Style.spacing.md
                  PanelSlider {
                    width: Style.space(170)
                    minimum: 0; maximum: 64; step: 1; integer: true
                    value: root.c.focusSwitcher.pillDepth
                    fillColor: Color.accent; knobColor: Color.accent
                    onMoved: function(v) { root.setFS({ pillDepth: Math.round(v) }) }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(48)
                    text: root.c.focusSwitcher.pillDepth > 0
                          ? Math.round(root.c.focusSwitcher.pillDepth) + "px"
                          : "auto"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              SettingRow {
                title: "Dot inset"
                subtitle: "Space between each dot and the capsule edge."
                Row {
                  spacing: Style.spacing.md
                  PanelSlider {
                    width: Style.space(170)
                    minimum: 0; maximum: 10; step: 1; integer: true
                    value: root.c.focusSwitcher.dotInset
                    fillColor: Color.accent; knobColor: Color.accent
                    onMoved: function(v) { root.setFS({ dotInset: Math.round(v) }) }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(40)
                    text: Math.round(root.c.focusSwitcher.dotInset || 0) + "px"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              SettingRow {
                title: "Spacing"
                subtitle: "Gap between dots."
                Row {
                  spacing: Style.spacing.md
                  PanelSlider {
                    width: Style.space(170)
                    minimum: 0; maximum: 48; step: 1; integer: true
                    value: root.c.focusSwitcher.spacing
                    fillColor: Color.accent; knobColor: Color.accent
                    onMoved: function(v) { root.setFS({ spacing: Math.round(v) }) }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(40)
                    text: Math.round(root.c.focusSwitcher.spacing || 0) + "px"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              SettingRow {
                title: "Edge margin"
                subtitle: "Distance of the dots from the screen edge."
                Row {
                  spacing: Style.spacing.md
                  PanelSlider {
                    width: Style.space(170)
                    minimum: 8; maximum: 96; step: 1; integer: true
                    value: root.c.focusSwitcher.margin
                    fillColor: Color.accent; knobColor: Color.accent
                    onMoved: function(v) { root.setFS({ margin: Math.round(v) }) }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(40)
                    text: Math.round(root.c.focusSwitcher.margin || 0) + "px"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              SettingRow {
                title: "Rail gap"
                subtitle: "Extra space beyond the window's outer gap."
                Row {
                  spacing: Style.spacing.md
                  PanelSlider {
                    width: Style.space(170)
                    minimum: 0; maximum: 16; step: 1; integer: true
                    value: root.c.focusSwitcher.borderPadding
                    fillColor: Color.accent; knobColor: Color.accent
                    onMoved: function(v) { root.setFS({ borderPadding: Math.round(v) }) }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(40)
                    text: Math.round(root.c.focusSwitcher.borderPadding || 0) + "px"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              SettingRow {
                title: "Rail background"
                subtitle: "Translucent capsule behind the dots."
                ToggleSwitch {
                  checked: root.c.focusSwitcher.background === true
                  foreground: Color.menu.text
                  accent: Color.accent
                  onToggled: root.setFS({ background: !(root.c.focusSwitcher.background === true) })
                }
              }

              SettingRow {
                title: "Background opacity"
                subtitle: "How solid the capsule behind the dots is."
                Row {
                  spacing: Style.spacing.md
                  PanelSlider {
                    width: Style.space(170)
                    enabled: root.c.focusSwitcher.background === true
                    minimum: 0; maximum: 1; step: 0.01
                    value: root.c.focusSwitcher.backgroundOpacity
                    fillColor: Color.accent; knobColor: Color.accent
                    onMoved: function(v) { root.setFS({ backgroundOpacity: v }) }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(40)
                    text: Math.round((root.c.focusSwitcher.backgroundOpacity || 0) * 100) + "%"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Item { width: 1; height: Style.spacing.md }

              PanelActionButton {
                iconText: "󰕌"
                tooltipText: "Reset all settings"
                foreground: Color.menu.text
                bordered: true
                onClicked: root.reset()
              }
            }
          }

          // Footer -------------------------------------------------------
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.md
            Text {
              Layout.fillWidth: true
              text: "Omarchy Shell plugin · com.dchadwick.windowcommander"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              Layout.alignment: Qt.AlignVCenter
            }
            Button {
              text: "Close"
              foreground: Color.menu.text
              accent: Color.accent
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.close()
            }
          }
        }
      }
    }
  }
}
