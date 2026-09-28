import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "Engine.js" as Engine

// Window Commander engine.
//
// A `service` entry point so the always-on grab handles exist from login
// without opening a panel. The settings UI is the sibling `panel` entry point,
// which receives this object through the host's `service` injection.
//
// It polls `hyprctl -j clients`/`monitors` (Hyprland emits no event when a
// tiled split's ratio changes), computes the boundaries between adjacent tiled
// windows, and draws a grab pill on each split.
//
// Each pill is its own small layer-shell surface positioned on the split. Small
// surfaces are deliberate: an idle touch or click anywhere else lands on the
// window below instead of this overlay, which a full-screen masked surface can
// get wrong for touch input. While a pill is grabbed its surface expands to the
// whole screen so pointer motion keeps arriving for the rest of the drag.
Item {
  id: root

  // Host-injected.
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "com.dchadwick.windowcommander"

  // ------------------------------------------------------------------ config

  property var config: Engine.defaultConfig()
  readonly property string statePath:
    Quickshell.env("HOME") + "/.local/state/omarchy/window-commander.json"

  function setConfig(patch) {
    var next = Engine.normalizeConfig(Object.assign({}, root.config, patch || {}))
    root.config = next
    configFile.setText(JSON.stringify(next, null, 2) + "\n")
    // Mirror into shell.json so the entry carries a readable copy. Reading it
    // back is not offered to third-party panels, so the state file stays the
    // source of truth.
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(root.pluginId, next)
  }

  function resetConfig() { root.setConfig(Engine.defaultConfig()) }

  function setLayout(name, enabled) {
    var layouts = Object.assign({}, root.config.layouts)
    layouts[name] = enabled
    root.setConfig({ layouts: layouts })
  }

  // ------------------------------------------------------------------- state

  property var clients: []
  property var monitors: []
  property string activeAddress: ""
  property var outerGaps: ({ right: 0, bottom: 0 })
  property var layoutByMonitorName: ({})
  property string hoverKey: ""
  property bool dragging: false
  property var drag: null

  readonly property var monMap: Engine.monitorMap(root.monitors)
  readonly property var rects: Engine.windowRects(root.clients, root.monMap, false, true)
  readonly property var switcherRects: Engine.windowRects(root.clients, root.monMap, true, false)
  readonly property var rawBoundaries: root.computeBoundaries()
  readonly property var boundaries:
    (root.dragging && root.drag && root.drag.frozen) ? root.drag.frozen : root.rawBoundaries

  readonly property color pillColor: {
    switch (root.config.color) {
    case "accent": return Color.accent
    case "muted": return Color.muted
    case "urgent": return Color.urgent
    default: return Color.foreground
    }
  }

  function computeBoundaries() {
    var result = []
    if (!root.config.enabled) return result
    for (var key in root.monMap) {
      var m = root.monMap[key]
      var layout = root.layoutByMonitorName[m.name]
      var mine = []
      for (var i = 0; i < root.rects.length; i++)
        if (root.rects[i].monitor === m.id) mine.push(root.rects[i])
      var found = Engine.boundariesForMonitor(mine, m, layout, root.config)
      // A handle never shares an edge with the focus rail: skip boundaries in
      // the band the rail occupies on its edge.
      var fsc = root.config.focusSwitcher
      var info = Engine.railEdge(fsc.dock, m.w, m.h)
      var railOn = fsc.enabled && fsc.dock !== "off" && info !== null
      var keepout = fsc.borderPadding * 2 + Math.max(fsc.pillDepth, 12) + 14
      for (var j = 0; j < found.length; j++) {
        var b = found[j]
        if (railOn) {
          if (info.edge === "right" && b.orientation === "v" && (m.w - b.cx) < keepout) continue
          if (info.edge === "left" && b.orientation === "v" && b.cx < keepout) continue
          if (info.edge === "bottom" && b.orientation === "h" && (m.h - b.cy) < keepout) continue
          if (info.edge === "top" && b.orientation === "h" && b.cy < keepout) continue
        }
        b.pill = Engine.pillRect(b, root.config)
        b.mask = Engine.maskRect(b, root.config)
        result.push(b)
      }
    }
    return result
  }

  function monitorIdForScreen(screenName) {
    for (var i = 0; i < root.monitors.length; i++)
      if (root.monitors[i].name === screenName) return root.monitors[i].id
    return -1
  }

  function pillsFor(monitorId) {
    var out = []
    for (var i = 0; i < root.boundaries.length; i++)
      if (root.boundaries[i].monitor === monitorId) out.push(root.boundaries[i])
    return out
  }

  // A fixed pool of pill surfaces per screen. A stable model avoids recreating
  // windows every poll (boundaries get a fresh array each scan).
  readonly property int maxPills: 16
  readonly property var slotIndices: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

  function pillsForScreen(screen) {
    return root.pillsFor(root.monitorIdForScreen(screen.name))
  }

  // ----------------------------------------------------------- focus switcher

  readonly property int focusedMonitorId:
    (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.id : -1)
  property bool scrubbing: false
  property int scrubIndex: -1
  property int hoverDot: -1

  // The dot the user is pointing at or scrubbing: its window gets highlighted
  // and labelled so the abstract dot maps to a real window.
  readonly property int candidateIndex: root.scrubbing ? root.scrubIndex : root.hoverDot

  function switcherWindows(screen) {
    var id = root.monitorIdForScreen(screen.name)
    var mine = []
    for (var i = 0; i < root.switcherRects.length; i++)
      if (root.switcherRects[i].monitor === id) mine.push(root.switcherRects[i])
    var info = Engine.railEdge(root.config.focusSwitcher.dock, screen.width, screen.height)
    return Engine.orderWindows(mine, info ? info.horizontal : false)
  }

  function switcherGeometry(screen, wins) {
    return Engine.switcherGeom(wins.length, screen.width, screen.height,
                               root.config.focusSwitcher, wins, root.outerGaps)
  }

  function focusWindow(address) {
    if (!address) return
    Quickshell.execDetached(["hyprctl", "eval",
      'hl.dispatch(hl.dsp.focus({window="address:' + address + '"}))'])
  }

  function scrubAt(screen, mx, my) {
    var wins = root.switcherWindows(screen)
    if (wins.length === 0) return
    var idx = Engine.nearestDot(root.switcherGeometry(screen, wins), mx, my)
    if (idx < 0 || idx >= wins.length || idx === root.scrubIndex) return
    root.scrubIndex = idx
    root.focusWindow(wins[idx].address)
  }

  // Mouse wheel over the rail steps focus one window at a time.
  function wheelStep(screen, dir) {
    var wins = root.switcherWindows(screen)
    if (wins.length === 0) return
    var idx = -1
    for (var i = 0; i < wins.length; i++)
      if (wins[i].address === root.activeAddress) { idx = i; break }
    if (idx < 0) idx = dir > 0 ? -1 : wins.length
    var next = Math.max(0, Math.min(wins.length - 1, idx + dir))
    if (next === idx) return
    root.hoverDot = next
    root.focusWindow(wins[next].address)
  }

  // --------------------------------------------------------------- hyprctl IO

  property int pollTick: 0
  readonly property int clientPollMs: 300
  readonly property int monitorEvery: 8

  function refresh() {
    if (!root.config.enabled && !root.config.focusSwitcher.enabled) return
    if (!clientsProc.running) clientsProc.running = true
    if (!activeProc.running) activeProc.running = true
    if (root.pollTick % root.monitorEvery === 0) {
      if (!monitorsProc.running) monitorsProc.running = true
      if (!gapsProc.running) gapsProc.running = true
    }
    root.pollTick++
  }

  function applyActive(raw) {
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      root.activeAddress = (parsed && parsed.address) ? String(parsed.address) : ""
    } catch (e) { root.activeAddress = "" }
  }

  // `hyprctl getoption general:gaps_out` -> "css gap data: T R B L".
  function applyGaps(raw) {
    var m = String(raw || "").match(/(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
    if (!m) return
    root.outerGaps = {
      top: Number(m[1]), right: Number(m[2]),
      bottom: Number(m[3]), left: Number(m[4])
    }
  }

  function applyClients(raw) {
    if (root.dragging) return
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      if (parsed instanceof Array) root.clients = parsed
    } catch (e) {}
  }

  function applyMonitors(raw) {
    if (root.dragging) return
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      if (parsed instanceof Array) root.monitors = parsed
    } catch (e) {}
  }

  Process {
    id: clientsProc
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyClients(text)
    }
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyMonitors(text)
    }
  }

  Process {
    id: activeProc
    command: ["hyprctl", "-j", "activewindow"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyActive(text)
    }
  }

  Process {
    id: gapsProc
    command: ["hyprctl", "getoption", "general:gaps_out"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyGaps(text)
    }
  }

  Timer {
    id: pollTimer
    interval: root.clientPollMs
    repeat: true
    running: root.config.enabled || root.config.focusSwitcher.enabled
    onTriggered: root.refresh()
  }

  Timer {
    id: eventRefresh
    interval: 50
    onTriggered: root.refresh()
  }

  function refreshSoon() { eventRefresh.restart() }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event) return
      if (event.name === "activelayout") {
        var parts = String(event.data || "").split(",")
        if (parts.length >= 2) {
          var next = Object.assign({}, root.layoutByMonitorName)
          next[parts[0]] = parts[1]
          root.layoutByMonitorName = next
        }
      }
      if (event.name === "openwindow" || event.name === "closewindow" ||
          event.name === "movewindow" || event.name === "activewindow" ||
          event.name === "workspace" || event.name === "fullscreen" ||
          event.name === "changefloatingmode" || event.name === "togglegroup" ||
          event.name === "moveintogroup" || event.name === "moveoutofgroup" ||
          event.name === "monitoradded" || event.name === "monitorremoved" ||
          event.name === "configreloaded") {
        root.refreshSoon()
      }
    }
  }

  // ------------------------------------------------------------------ resize

  function axisDelta(orientation, delta) {
    return orientation === "v" ? { dx: Math.round(delta), dy: 0 }
                               : { dx: 0, dy: Math.round(delta) }
  }

  function dispatchResize(address, dx, dy) {
    if (dx === 0 && dy === 0) return
    var lua = 'hl.dispatch(hl.dsp.window.resize({x=' + dx + ',y=' + dy +
              ',relative=true,window="address:' + address + '"}))'
    Quickshell.execDetached(["hyprctl", "eval", lua])
  }

  // Always resize the left/top window of the pair. That window's trailing edge
  // is the split you grabbed, so the divider follows the pointer. Resizing the
  // right/bottom window instead moves its *far* edge (the next split along),
  // which is what made grabbing a left-hand divider resize the wrong side.
  // Focus is never touched.
  function chooseTarget(b) {
    return { address: b.target, sign: 1 }
  }

  function openSettings() {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.pluginId])
  }

  function modifierNames(mouse) {
    var out = []
    if (!mouse) return out
    var m = mouse.modifiers
    if (m & Qt.ShiftModifier) out.push("shift")
    if (m & Qt.ControlModifier) out.push("ctrl")
    if (m & Qt.AltModifier) out.push("alt")
    if (m & Qt.MetaModifier) out.push("super")
    return out
  }

  function beginDrag(b, cursorX, cursorY) {
    if (!root.config.enabled || !b) return
    var cursor = b.orientation === "v" ? cursorX : cursorY
    var boundaryPos = b.orientation === "v" ? b.cx : b.cy
    var target = root.chooseTarget(b)
    root.drag = {
      key: b.key,
      boundary: b,
      monitor: b.monitor,
      orientation: b.orientation,
      target: target.address,
      sign: target.sign,
      other: b.other,
      startCursor: cursor,
      startBoundary: boundaryPos,
      currentPos: boundaryPos,
      appliedPos: boundaryPos,
      frac: b.frac,
      moved: false,
      frozen: root.rawBoundaries
    }
    root.hoverKey = b.key
    root.dragging = true
  }

  function updateDrag(cursorX, cursorY, mouse) {
    if (!root.dragging || !root.drag) return
    var b = root.drag.boundary
    var cursor = b.orientation === "v" ? cursorX : cursorY
    var raw = root.drag.startBoundary + (cursor - root.drag.startCursor)
    var span = b.spanLen > 0 ? b.spanLen : 1
    var frac = (raw - b.spanStart) / span
    frac = Math.max(0.02, Math.min(0.98, frac))

    var mods = root.modifierNames(mouse)
    var free = mods.indexOf(root.config.freeDragModifier) >= 0
    var effFrac = free ? frac : Engine.snapFraction(frac, root.config, b.spanLen)
    var pos = Engine.clampPos(b.spanStart + effFrac * b.spanLen, b.orientation, b, root.config)

    var next = Object.assign({}, root.drag)
    next.currentPos = pos
    next.frac = effFrac
    next.free = free
    next.moved = root.drag.moved || Math.abs(pos - root.drag.startBoundary) > 1
    root.drag = next
  }

  function flushDrag() {
    if (!root.dragging || !root.drag) return
    if (root.config.resizeMode !== "live") return
    if (Math.abs(root.drag.currentPos - root.drag.appliedPos) < 1) return
    var delta = (root.drag.currentPos - root.drag.appliedPos) * root.drag.sign
    var d = root.axisDelta(root.drag.orientation, delta)
    root.dispatchResize(root.drag.target, d.dx, d.dy)
    root.drag = Object.assign({}, root.drag, { appliedPos: root.drag.currentPos })
  }

  Timer {
    interval: 16
    repeat: true
    running: root.dragging && root.config.resizeMode === "live"
    onTriggered: root.flushDrag()
  }

  function endDrag() {
    if (!root.dragging || !root.drag) {
      root.dragging = false
      root.drag = null
      return
    }
    if (root.config.resizeMode === "preview") {
      var delta = (root.drag.currentPos - root.drag.startBoundary) * root.drag.sign
      if (Math.abs(delta) >= 1) {
        var d = root.axisDelta(root.drag.orientation, delta)
        root.dispatchResize(root.drag.target, d.dx, d.dy)
      }
    }
    root.dragging = false
    root.drag = null
    root.hoverKey = ""
    root.refreshSoon()
  }

  function equalize(b) {
    if (!root.config.enabled || !b || !root.config.equalizeOnDoubleClick) return
    var target = root.chooseTarget(b)
    var targetPos = Engine.equalizePosition(b)
    var current = b.orientation === "v" ? b.cx : b.cy
    var delta = (targetPos - current) * target.sign
    if (Math.abs(delta) < 1) return
    var d = root.axisDelta(b.orientation, delta)
    root.dispatchResize(target.address, d.dx, d.dy)
    root.refreshSoon()
  }

  // ------------------------------------------------------------------- config

  FileView {
    id: configFile
    path: root.statePath
    atomicWrites: true
    watchChanges: true
    printErrors: false
    onLoaded: root.config = Engine.normalizeConfig(JSON.parse(text() || "{}"))
    onLoadFailed: root.config = Engine.defaultConfig()
  }

  // ------------------------------------------------------------------ overlay
  //
  // One layer-shell surface per pill, each spanning the whole screen like Dot
  // Commander does. The surface itself never changes size -- only its `mask`
  // (the Wayland input region) does: the pill's box while idle, the whole
  // screen while grabbed. Resizing a surface mid-touch can cancel the touch
  // sequence, which is why the geometry stays fixed.

  Variants {
    model: Quickshell.screens

    Item {
      id: screenHost
      required property var modelData
      readonly property var screenInfo: modelData
      readonly property var pills: root.pillsForScreen(modelData)

      Variants {
        model: root.slotIndices

        PanelWindow {
          id: pillWin
          required property var modelData
          readonly property int slotIndex: modelData
          readonly property var b: (slotIndex < screenHost.pills.length ? screenHost.pills[slotIndex] : null)
          readonly property bool expanded: root.dragging && root.drag && b !== null && root.drag.key === b.key
          readonly property bool hot: b !== null && root.hoverKey === b.key

          screen: screenHost.screenInfo
          visible: root.config.enabled && b !== null
          color: "transparent"
          anchors { top: true; bottom: true; left: true; right: true }
          exclusionMode: ExclusionMode.Ignore
          WlrLayershell.namespace: "com-dchadwick-windowcommander"
          WlrLayershell.layer: WlrLayer.Overlay
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

          // The input region: the pill while idle, the whole screen while this
          // pill is the one being dragged.
          mask: Region {
            x: pillWin.expanded ? 0 : (pillWin.b ? pillWin.b.mask.x : -1)
            y: pillWin.expanded ? 0 : (pillWin.b ? pillWin.b.mask.y : -1)
            width: pillWin.expanded ? Math.max(1, screenHost.screenInfo.width)
                                    : (pillWin.b ? pillWin.b.mask.width : 0)
            height: pillWin.expanded ? Math.max(1, screenHost.screenInfo.height)
                                     : (pillWin.b ? pillWin.b.mask.height : 0)
          }

          // The idle pill: a translucent capsule holding an outline that fills
          // in when grabbed.
          Item {
            id: pillVisual
            visible: !pillWin.expanded && pillWin.b !== null
            x: pillWin.b ? pillWin.b.pill.x : 0
            y: pillWin.b ? pillWin.b.pill.y : 0
            width: pillWin.b ? pillWin.b.pill.w : 0
            height: pillWin.b ? pillWin.b.pill.h : 0
            scale: (pillWin.hot && root.config.enabled) ? 1.12 : 1.0
            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

            Rectangle {
              anchors.fill: parent
              visible: root.config.handleBackground
              radius: Math.min(width, height) / 2
              color: Util.alpha(Color.background, root.config.handleBackgroundOpacity)
            }

            Rectangle {
              anchors.fill: parent
              radius: Math.min(width, height) / 2
              color: pillWin.hot ? root.pillColor : "transparent"
              border.color: root.pillColor
              border.width: Math.max(1, Math.round((pillWin.b ? pillWin.b.thickness : 5) * 0.22))
              opacity: pillWin.hot ? root.config.hoverOpacity : root.config.idleOpacity
              Behavior on opacity { NumberAnimation { duration: 110 } }
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: if (pillWin.b) root.hoverKey = pillWin.b.key
            onExited: if (pillWin.b && root.hoverKey === pillWin.b.key && !root.dragging) root.hoverKey = ""
            onPressed: function(mouse) {
              if (!pillWin.b) return
              if (mouse.button === Qt.RightButton) { root.openSettings(); return }
              root.beginDrag(pillWin.b, mouse.x, mouse.y)
            }
            onPositionChanged: function(mouse) {
              if (!root.dragging || !root.drag || !pillWin.b || root.drag.key !== pillWin.b.key) return
              root.updateDrag(mouse.x, mouse.y, mouse)
            }
            onReleased: function(mouse) {
              if (root.dragging && root.drag && pillWin.b && root.drag.key === pillWin.b.key) root.endDrag()
            }
            onDoubleClicked: if (pillWin.b) root.equalize(pillWin.b)
          }

          // The active drag / preview indicator, drawn across the shared edge.
          Item {
            id: indicator
            visible: pillWin.expanded
            readonly property var d: (visible && root.drag)
              ? root.drag.boundary
              : ({ orientation: "v", hairLow: 0, hairHigh: 0, length: 0, thickness: 0, cx: 0, cy: 0 })
            readonly property real pos: visible ? root.drag.currentPos : 0
            readonly property bool vertical: d.orientation === "v"

            Rectangle {
              visible: indicator.visible
              x: indicator.vertical ? indicator.pos - 1 : indicator.d.hairLow
              y: indicator.vertical ? indicator.d.hairLow : indicator.pos - 1
              width: indicator.vertical ? 2 : (indicator.d.hairHigh - indicator.d.hairLow)
              height: indicator.vertical ? (indicator.d.hairHigh - indicator.d.hairLow) : 2
              color: root.pillColor
              opacity: 0.55
            }

            Rectangle {
              visible: indicator.visible
              x: indicator.vertical ? indicator.pos - indicator.d.thickness / 2
                                    : indicator.d.cx - indicator.d.length / 2
              y: indicator.vertical ? indicator.d.cy - indicator.d.length / 2
                                    : indicator.pos - indicator.d.thickness / 2
              width: indicator.vertical ? indicator.d.thickness : indicator.d.length
              height: indicator.vertical ? indicator.d.length : indicator.d.thickness
              radius: Math.min(width, height) / 2
              color: Color.accent
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------- focus switcher UI
  //
  // One surface on the focused monitor. The mask is the strip of dots while
  // idle and the whole screen while scrubbing, so a finger that wanders off the
  // strip keeps steering focus.

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: switchWin
      required property var modelData
      readonly property var wins: root.switcherWindows(modelData)
      readonly property var geom: root.switcherGeometry(modelData, switchWin.wins)
      readonly property bool onFocused: root.focusedMonitorId === root.monitorIdForScreen(modelData.name)
      readonly property bool active: root.config.focusSwitcher.enabled
        && root.config.focusSwitcher.dock !== "off"
        && switchWin.onFocused && switchWin.wins.length > 1
      readonly property int cand: root.candidateIndex
      readonly property var candWin: (switchWin.cand >= 0 && switchWin.cand < switchWin.wins.length)
        ? switchWin.wins[switchWin.cand] : null
      readonly property var candPos: (switchWin.cand >= 0 && switchWin.cand < switchWin.geom.points.length)
        ? switchWin.geom.points[switchWin.cand] : null

      screen: modelData
      visible: switchWin.active
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "com-dchadwick-windowcommander-switcher"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      mask: Region {
        x: root.scrubbing ? 0 : switchWin.geom.strip.x
        y: root.scrubbing ? 0 : switchWin.geom.strip.y
        width: root.scrubbing ? Math.max(1, modelData.width) : switchWin.geom.strip.width
        height: root.scrubbing ? Math.max(1, modelData.height) : switchWin.geom.strip.height
      }

      // Highlight the candidate window so an abstract dot maps to a real window.
      Rectangle {
        visible: switchWin.candWin !== null
        x: switchWin.candWin ? switchWin.candWin.x : 0
        y: switchWin.candWin ? switchWin.candWin.y : 0
        width: switchWin.candWin ? switchWin.candWin.w : 0
        height: switchWin.candWin ? switchWin.candWin.h : 0
        color: "transparent"
        border.color: Color.accent
        border.width: 2
        radius: Style.cornerRadius > 0 ? Style.cornerRadius : 0
        opacity: 0.7
      }

      // Translucent capsule behind the dots so the rail reads against busy
      // wallpapers.
      Rectangle {
        visible: root.config.focusSwitcher.background
        x: switchWin.geom.bg.x
        y: switchWin.geom.bg.y
        width: switchWin.geom.bg.width
        height: switchWin.geom.bg.height
        radius: Math.min(width, height) / 2
        color: Util.alpha(Color.background, root.config.focusSwitcher.backgroundOpacity)
        border.color: Util.alpha(root.pillColor, 0.12)
        border.width: 1
      }

      Repeater {
        model: switchWin.wins
        delegate: Rectangle {
          required property var modelData
          required property int index
          readonly property bool focusedDot: root.activeAddress === modelData.address
          readonly property bool hotDot: root.scrubIndex === index || root.hoverDot === index
          readonly property var pt: (index < switchWin.geom.points.length ? switchWin.geom.points[index] : null)

          x: pt ? pt.x - switchWin.geom.dotSize / 2 : 0
          y: pt ? pt.y - switchWin.geom.dotSize / 2 : 0
          width: switchWin.geom.dotSize
          height: switchWin.geom.dotSize
          radius: width / 2
          color: focusedDot ? root.pillColor : "transparent"
          border.color: root.pillColor
          border.width: Math.max(1, Math.round(switchWin.geom.dotSize * 0.16))
          opacity: (focusedDot || hotDot) ? root.config.focusSwitcher.activeOpacity
                                          : root.config.focusSwitcher.idleOpacity
          scale: hotDot ? 1.25 : 1.0
          Behavior on opacity { NumberAnimation { duration: 100 } }
          Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
        }
      }

      // Title of the candidate window, beside the active dot.
      Rectangle {
        id: tip
        visible: switchWin.candWin !== null && (switchWin.candWin.title || switchWin.candWin.cls) !== ""
        readonly property var w: switchWin.candWin
        readonly property var pos: switchWin.candPos
        width: Math.min(tipText.implicitWidth + Style.space(16), Style.space(300))
        height: tipText.implicitHeight + Style.space(12)
        radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
        color: Util.alpha(Color.background, 0.9)
        border.color: Util.alpha(root.pillColor, 0.25)
        border.width: 1
        x: {
          if (!pos) return 0
          if (switchWin.geom.horizontal)
            return Math.max(2, Math.min(modelData.width - width - 2, pos.x - width / 2))
          if (switchWin.geom.edge === "left")
            return Math.min(modelData.width - width - 2, pos.x + switchWin.geom.dotSize / 2 + Style.space(10))
          return Math.max(2, pos.x - switchWin.geom.dotSize / 2 - width - Style.space(10))
        }
        y: {
          if (!pos) return 0
          if (switchWin.geom.horizontal) {
            if (switchWin.geom.edge === "top")
              return Math.min(modelData.height - height - 2, pos.y + switchWin.geom.dotSize / 2 + Style.space(10))
            return Math.max(2, pos.y - switchWin.geom.dotSize / 2 - height - Style.space(10))
          }
          return Math.max(2, Math.min(modelData.height - height - 2, pos.y - height / 2))
        }
        Text {
          id: tipText
          anchors.centerIn: parent
          width: parent.width - Style.space(12)
          text: switchWin.candWin ? (switchWin.candWin.title || switchWin.candWin.cls || "") : ""
          color: Color.foreground
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton) { root.openSettings(); return }
          root.scrubbing = true
          root.scrubIndex = -1
          root.scrubAt(switchWin.modelData, mouse.x, mouse.y)
        }
        onPositionChanged: function(mouse) {
          if (root.scrubbing) {
            root.scrubAt(switchWin.modelData, mouse.x, mouse.y)
          } else {
            root.hoverDot = Engine.nearestDot(switchWin.geom, mouse.x, mouse.y)
          }
        }
        onReleased: function(mouse) {
          if (mouse.button === Qt.RightButton) return
          root.scrubbing = false
          root.scrubIndex = -1
        }
        onExited: if (!root.scrubbing) root.hoverDot = -1
        onWheel: function(wheel) {
          root.wheelStep(switchWin.modelData, wheel.angleDelta.y > 0 ? -1 : 1)
        }
      }
    }
  }

  // ---------------------------------------------------------------- IPC / API

  IpcHandler {
    target: "windowcommander"
    function enable(): void { root.setConfig({ enabled: true }) }
    function disable(): void { root.setConfig({ enabled: false }) }
    function toggle(): void { root.setConfig({ enabled: !root.config.enabled }) }
    function refresh(): void { root.refresh() }
    function status(): string {
      return JSON.stringify({
        enabled: root.config.enabled,
        mode: root.config.resizeMode,
        boundaries: root.boundaries.length
      })
    }
  }

  Component.onCompleted: root.refresh()
}
