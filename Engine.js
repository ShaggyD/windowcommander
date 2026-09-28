.pragma library

// Window Commander — pure geometry, configuration and snapping helpers.
//
// Everything here is deliberately free of QML/Quickshell types so it can be
// unit-reasoned about and reused by both the service (engine + handles) and the
// settings panel. The service feeds it `hyprctl -j clients` / `-j monitors`
// JSON and gets back split boundaries in monitor-local logical coordinates.

var DEFAULTS = {
  enabled: true,

  // Handle appearance (logical px).
  handleLength: 64,        // pill length along the boundary (a short grab bar)
  handleMinThickness: 3,   // thickness floor when the inter-window gap is tiny
  handlePadding: 3,        // margin between the pill and the window borders
  gripPadding: 8,          // invisible extra grab area around the pill
  idleOpacity: 0.3,        // resting opacity
  hoverOpacity: 0.95,      // opacity while hovered / pressed
  handleBackground: true,  // translucent capsule behind each pill
  handleBackgroundOpacity: 0.5,
  color: "foreground",     // theme token: foreground | accent | muted | urgent

  // Focus switcher: one dot per window on the focused monitor's workspace.
  focusSwitcher: {
    enabled: true,
    dock: "mid-right",     // 3x3 perimeter: top/mid/bottom x left/center/right, or off
    pillDepth: 0,          // capsule thickness; 0 = fit the outer gap, else explicit
    dotInset: 2,           // space between each dot and the capsule edge
    spacing: 20,           // generous gap so the dots read as a rail
    margin: 30,            // fallback distance from the edge (no window geometry)
    idleOpacity: 0.35,
    activeOpacity: 1.0,
    background: true,      // translucent capsule behind the dots
    backgroundOpacity: 0.5,
    borderPadding: 0       // extra space beyond the window's outer gap (gaps_out)
  },

  // Behaviour.
  resizeMode: "live",      // live | preview
  snapping: true,          // magnetic snap to snapRatios while dragging
  snapRatios: [0.3333, 0.5, 0.6667],
  snapThreshold: 10,       // px of pull before a preset captures the boundary
  freeDragModifier: "shift", // held: ignore snapping (free positioning)
  equalizeOnDoubleClick: true,
  minOverlap: 28,          // shared edge must be at least this long to get a pill

  // Layouts to decorate. Unknown layout names are treated as enabled.
  layouts: {
    dwindle: true,
    master: true,
    scrolling: true
  }
};

function clone(value) {
  if (value === null || typeof value !== "object")
    return value;
  if (value instanceof Array) {
    var arr = [];
    for (var i = 0; i < value.length; i++) arr.push(clone(value[i]));
    return arr;
  }
  var out = {};
  for (var k in value) out[k] = clone(value[k]);
  return out;
}

function defaultConfig() {
  return clone(DEFAULTS);
}

function numberOr(value, fallback) {
  var n = Number(value);
  return isFinite(n) ? n : fallback;
}

function boolOr(value, fallback) {
  return typeof value === "boolean" ? value : fallback;
}

function stringOr(value, fallback) {
  return (typeof value === "string" && value.length > 0) ? value : fallback;
}

// Accepts a partial/possibly-corrupt config and returns a complete, sane one.
function normalizeConfig(raw) {
  var cfg = defaultConfig();
  if (!raw || typeof raw !== "object") return cfg;

  cfg.enabled = boolOr(raw.enabled, cfg.enabled);
  cfg.handleLength = Math.max(16, Math.min(320, numberOr(raw.handleLength, cfg.handleLength)));
  cfg.handleMinThickness = Math.max(1, Math.min(24, numberOr(raw.handleMinThickness, cfg.handleMinThickness)));
  cfg.handlePadding = Math.max(0, Math.min(16, numberOr(raw.handlePadding, cfg.handlePadding)));
  cfg.gripPadding = Math.max(0, Math.min(64, numberOr(raw.gripPadding, cfg.gripPadding)));
  cfg.idleOpacity = Math.max(0, Math.min(1, numberOr(raw.idleOpacity, cfg.idleOpacity)));
  cfg.hoverOpacity = Math.max(0, Math.min(1, numberOr(raw.hoverOpacity, cfg.hoverOpacity)));
  cfg.handleBackground = boolOr(raw.handleBackground, cfg.handleBackground);
  cfg.handleBackgroundOpacity = Math.max(0, Math.min(1, numberOr(raw.handleBackgroundOpacity, cfg.handleBackgroundOpacity)));
  cfg.color = stringOr(raw.color, cfg.color);

  var mode = stringOr(raw.resizeMode, cfg.resizeMode);
  cfg.resizeMode = (mode === "preview") ? "preview" : "live";

  cfg.snapping = boolOr(raw.snapping, cfg.snapping);
  if (raw.snapRatios instanceof Array && raw.snapRatios.length > 0) {
    var ratios = [];
    for (var i = 0; i < raw.snapRatios.length; i++) {
      var r = numberOr(raw.snapRatios[i], -1);
      if (r > 0 && r < 1) ratios.push(r);
    }
    if (ratios.length > 0) cfg.snapRatios = ratios;
  }
  cfg.snapThreshold = Math.max(0, Math.min(64, numberOr(raw.snapThreshold, cfg.snapThreshold)));
  cfg.freeDragModifier = stringOr(raw.freeDragModifier, cfg.freeDragModifier);
  cfg.equalizeOnDoubleClick = boolOr(raw.equalizeOnDoubleClick, cfg.equalizeOnDoubleClick);
  cfg.minOverlap = Math.max(4, Math.min(400, numberOr(raw.minOverlap, cfg.minOverlap)));

  if (raw.layouts && typeof raw.layouts === "object") {
    cfg.layouts.dwindle = boolOr(raw.layouts.dwindle, cfg.layouts.dwindle);
    cfg.layouts.master = boolOr(raw.layouts.master, cfg.layouts.master);
    cfg.layouts.scrolling = boolOr(raw.layouts.scrolling, cfg.layouts.scrolling);
  }

  var fs = raw.focusSwitcher;
  if (fs && typeof fs === "object") {
    cfg.focusSwitcher.enabled = boolOr(fs.enabled, cfg.focusSwitcher.enabled);
    var dock = stringOr(fs.dock, "");
    if (!dock) {
      // Migrate the old `position` (right | bottom | off).
      var oldPos = stringOr(fs.position, "");
      dock = (oldPos === "bottom") ? "bottom-center" : (oldPos === "off") ? "off" : "mid-right";
    }
    var docks = ["top-left", "top-center", "top-right", "mid-left", "mid-right",
                 "bottom-left", "bottom-center", "bottom-right", "off"];
    if (docks.indexOf(dock) < 0) dock = "mid-right";
    cfg.focusSwitcher.dock = dock;
    cfg.focusSwitcher.pillDepth = Math.max(0, Math.min(80, numberOr(fs.pillDepth, cfg.focusSwitcher.pillDepth)));
    cfg.focusSwitcher.dotInset = Math.max(0, Math.min(10, numberOr(fs.dotInset, cfg.focusSwitcher.dotInset)));
    cfg.focusSwitcher.spacing = Math.max(0, Math.min(48, numberOr(fs.spacing, cfg.focusSwitcher.spacing)));
    cfg.focusSwitcher.margin = Math.max(0, Math.min(200, numberOr(fs.margin, cfg.focusSwitcher.margin)));
    cfg.focusSwitcher.idleOpacity = Math.max(0, Math.min(1, numberOr(fs.idleOpacity, cfg.focusSwitcher.idleOpacity)));
    cfg.focusSwitcher.activeOpacity = Math.max(0, Math.min(1, numberOr(fs.activeOpacity, cfg.focusSwitcher.activeOpacity)));
    cfg.focusSwitcher.background = boolOr(fs.background, cfg.focusSwitcher.background);
    cfg.focusSwitcher.backgroundOpacity = Math.max(0, Math.min(1, numberOr(fs.backgroundOpacity, cfg.focusSwitcher.backgroundOpacity)));
    cfg.focusSwitcher.borderPadding = Math.max(0, Math.min(10, numberOr(fs.borderPadding, cfg.focusSwitcher.borderPadding)));
  }
  return cfg;
}

function layoutEnabled(config, layoutName) {
  if (!layoutName) return true;
  var key = String(layoutName).toLowerCase();
  if (Object.prototype.hasOwnProperty.call(config.layouts, key))
    return config.layouts[key] === true;
  return true;
}

// hyprctl -j monitors -> { id: geometry }. `x`/`y` and the derived width/height
// are logical (client `at` coordinates are global logical px; monitor `width`
// and `height` are physical, hence the /scale).
function monitorMap(monitors) {
  var map = {};
  if (!(monitors instanceof Array)) return map;
  for (var i = 0; i < monitors.length; i++) {
    var m = monitors[i];
    if (!m || typeof m.id !== "number") continue;
    var scale = (typeof m.scale === "number" && m.scale > 0) ? m.scale : 1;
    var special = m.specialWorkspace;
    map[m.id] = {
      id: m.id,
      name: String(m.name || ""),
      x: numberOr(m.x, 0),
      y: numberOr(m.y, 0),
      w: Math.round(numberOr(m.width, 0) / scale),
      h: Math.round(numberOr(m.height, 0) / scale),
      activeWs: (m.activeWorkspace && typeof m.activeWorkspace.id === "number") ? m.activeWorkspace.id : -1,
      specialWs: (special && special.name) ? numberOr(special.id, -1) : -1
    };
  }
  return map;
}

// Tiled, visible, unfullscreen leaf windows on each monitor's visible
// workspace, converted to monitor-local coordinates. `includeMaximized` keeps
// maximized windows (fullscreen mode 1) -- the focus switcher wants those, but
// the resize handles do not. `requireVisible` drops windows that are only a
// sliver on this monitor (a scrolling-layout neighbour mostly off screen),
// which would otherwise produce a handle hard against the screen edge.
function windowRects(clients, monMap, includeMaximized, requireVisible) {
  var rects = [];
  if (!(clients instanceof Array)) return rects;
  for (var i = 0; i < clients.length; i++) {
    var c = clients[i];
    if (!c || !c.at || !c.size) continue;
    if (!c.mapped || c.hidden) continue;
    if (c.floating) continue;
    var fs = c.fullscreen ? c.fullscreen : 0;
    if (includeMaximized) {
      if (fs === 2 || fs === 3) continue;
    } else if (fs !== 0) {
      continue;
    }
    if (c.grouped && c.grouped.length > 0) continue;
    var m = monMap[c.monitor];
    if (!m) continue;
    var ws = (c.workspace && typeof c.workspace.id === "number") ? c.workspace.id : -1;
    if (ws !== m.activeWs && ws !== m.specialWs) continue;

    var rx = numberOr(c.at[0], 0) - m.x;
    var ry = numberOr(c.at[1], 0) - m.y;
    var rw = numberOr(c.size[0], 0);
    var rh = numberOr(c.size[1], 0);
    if (requireVisible) {
      var visW = Math.min(rx + rw, m.w) - Math.max(rx, 0);
      var visH = Math.min(ry + rh, m.h) - Math.max(ry, 0);
      if (visW < 24 || visH < 24) continue;
    }

    rects.push({
      address: String(c.address || ""),
      cls: String(c.class || ""),
      title: String(c.title || ""),
      monitor: c.monitor,
      x: rx, y: ry, w: rw, h: rh
    });
  }
  return rects;
}

function pillLength(overlap, config) {
  // The pill is a short grab bar centred on the split (iPad style), not a bar
  // spanning the whole shared edge. `handleLength` is the target; a very short
  // shared edge caps it, and `handlePadding` keeps the ends off the window
  // corners.
  var pad = numberOr(config.handlePadding, 3);
  return Math.max(1, Math.min(config.handleLength, overlap - pad * 2));
}

// A pill sits in the gap between the two windows, a little thinner than the gap
// after `handlePadding` on both sides, so it never touches either window's
// border, whatever the gaps are set to (or zero, in which case it falls back to
// the minimum).
function gapThickness(gap, config) {
  var pad = numberOr(config.handlePadding, 3);
  var fit = Math.round(gap) - pad * 2;
  return Math.max(config.handleMinThickness, Math.min(24, fit));
}

// All adjacent leaf pairs on one monitor, as draggable boundaries.
// `a` (the window that gets the relative resize) is always the left/top one.
function boundariesFor(rects, monitor, config) {
  var out = [];
  var maxGap = 64;
  for (var i = 0; i < rects.length; i++) {
    for (var j = 0; j < rects.length; j++) {
      if (i === j) continue;
      var a = rects[i];
      var b = rects[j];

      if (a.x < b.x) {
        var gapX = b.x - (a.x + a.w);
        if (gapX >= -2 && gapX <= maxGap) {
          var oy0 = Math.max(a.y, b.y);
          var oy1 = Math.min(a.y + a.h, b.y + b.h);
          var overlapV = oy1 - oy0;
          if (overlapV >= config.minOverlap) {
            var boundaryX = (a.x + a.w + b.x) / 2;
            var spanStartX = a.x;
            var spanLenX = (b.x + b.w) - a.x;
            out.push({
              key: "v:" + a.address + ":" + b.address,
              orientation: "v",
              monitor: monitor.id,
              target: a.address,
              other: b.address,
              cx: boundaryX,
              cy: (oy0 + oy1) / 2,
              length: pillLength(overlapV, config),
              thickness: gapThickness(gapX, config),
              gap: gapX,
              spanStart: spanStartX,
              spanLen: spanLenX,
              frac: spanLenX > 0 ? (boundaryX - spanStartX) / spanLenX : 0.5,
              hairLow: oy0,
              hairHigh: oy1
            });
          }
        }
      }

      if (a.y < b.y) {
        var gapY = b.y - (a.y + a.h);
        if (gapY >= -2 && gapY <= maxGap) {
          var ox0 = Math.max(a.x, b.x);
          var ox1 = Math.min(a.x + a.w, b.x + b.w);
          var overlapH = ox1 - ox0;
          if (overlapH >= config.minOverlap) {
            var boundaryY = (a.y + a.h + b.y) / 2;
            var spanStartY = a.y;
            var spanLenY = (b.y + b.h) - a.y;
            out.push({
              key: "h:" + a.address + ":" + b.address,
              orientation: "h",
              monitor: monitor.id,
              target: a.address,
              other: b.address,
              cx: (ox0 + ox1) / 2,
              cy: boundaryY,
              length: pillLength(overlapH, config),
              thickness: gapThickness(gapY, config),
              gap: gapY,
              spanStart: spanStartY,
              spanLen: spanLenY,
              frac: spanLenY > 0 ? (boundaryY - spanStartY) / spanLenY : 0.5,
              hairLow: ox0,
              hairHigh: ox1
            });
          }
        }
      }
    }
  }
  return out;
}

function boundariesForMonitor(rects, monitor, layoutName, config) {
  if (!config.enabled) return [];
  if (!layoutEnabled(config, layoutName)) return [];
  return boundariesFor(rects, monitor, config);
}

// The pill's on-screen rectangle, in monitor-local coords, clipped to bounds.
function pillRect(boundary, config) {
  var t = boundary.thickness;
  var len = boundary.length;
  var x, y, w, h;
  if (boundary.orientation === "v") {
    w = t;
    h = len;
    x = boundary.cx - t / 2;
    y = boundary.cy - len / 2;
  } else {
    w = len;
    h = t;
    x = boundary.cx - len / 2;
    y = boundary.cy - t / 2;
  }
  return { x: x, y: y, w: w, h: h };
}

// The input-mask rectangle for a pill: the visible pill plus grab padding.
function maskRect(boundary, config) {
  var r = pillRect(boundary, config);
  var p = config.gripPadding;
  return {
    x: Math.round(r.x - p),
    y: Math.round(r.y - p),
    width: Math.round(r.w + p * 2),
    height: Math.round(r.h + p * 2)
  };
}

// Snap a fraction to the nearest preset when within `threshold` pixels.
function snapFraction(frac, config, spanLen) {
  if (!config.snapping) return frac;
  var best = frac;
  var bestDist = config.snapThreshold;
  var span = spanLen > 0 ? spanLen : 1;
  for (var i = 0; i < config.snapRatios.length; i++) {
    var preset = config.snapRatios[i];
    var dist = Math.abs(frac - preset) * span;
    if (dist <= bestDist) {
      bestDist = dist;
      best = preset;
    }
  }
  return best;
}

function clampPos(pos, orientation, boundary, config) {
  // Keep the boundary from being dragged entirely off either window.
  var pad = 12;
  var lo = boundary.spanStart + pad;
  var hi = boundary.spanStart + boundary.spanLen - pad;
  if (hi <= lo) return pos;
  return Math.max(lo, Math.min(hi, pos));
}

function equalizePosition(boundary) {
  return boundary.spanStart + boundary.spanLen * 0.5;
}

function ratioLabel(frac) {
  if (Math.abs(frac - 1 / 3) < 0.02) return "1/3";
  if (Math.abs(frac - 0.5) < 0.02) return "1/2";
  if (Math.abs(frac - 2 / 3) < 0.02) return "2/3";
  if (Math.abs(frac - 0.25) < 0.02) return "1/4";
  if (Math.abs(frac - 0.75) < 0.02) return "3/4";
  return Math.round(frac * 100) + "%";
}

// ------------------------------------------------------------- focus switcher

// Windows for the switcher, spatially ordered for the rail's orientation:
// rows for a vertical rail, columns for a horizontal one.
function orderWindows(rects, horizontal) {
  var list = rects.slice();
  list.sort(function(a, b) {
    var primary = horizontal ? (a.x - b.x) : (a.y - b.y);
    if (primary !== 0) return primary;
    return horizontal ? (a.y - b.y) : (a.x - b.x);
  });
  return list;
}

// Parse a dock id into its vertical and horizontal halves. The perimeter set:
//   top-left    top-center    top-right
//   mid-left                  mid-right
//   bottom-left bottom-center bottom-right
// Returns null for "off"/unknown.
function parseDock(dock) {
  switch (dock) {
  case "top-left": return { v: "top", h: "left" };
  case "top-center": return { v: "top", h: "center" };
  case "top-right": return { v: "top", h: "right" };
  case "mid-left": return { v: "mid", h: "left" };
  case "mid-right": return { v: "mid", h: "right" };
  case "bottom-left": return { v: "bottom", h: "left" };
  case "bottom-center": return { v: "bottom", h: "center" };
  case "bottom-right": return { v: "bottom", h: "right" };
  default: return null;
  }
}

// The screen edge a dock sits on, and whether the rail runs horizontally.
// Corners pick the longer side; edge midpoints are fixed.
function railEdge(dock, screenWidth, screenHeight) {
  var p = parseDock(dock);
  if (!p) return null;
  var horizontal;
  if (p.v === "mid") horizontal = false;
  else if (p.h === "center") horizontal = true;
  else horizontal = screenWidth >= screenHeight;
  if (horizontal) return { edge: p.v === "top" ? "top" : "bottom", horizontal: true };
  return { edge: p.h === "left" ? "left" : "right", horizontal: false };
}

// Dot centres, the rail capsule and the input strip that covers it.
//
// `pillDepth` is the single size control: it sets the capsule's cross-axis
// thickness, and the dot diameter is derived from it (`pillDepth - 2 *
// dotInset`). 0 fits the edge's outer gap; anything larger grows the capsule
// past the gap. The capsule's screen-edge side lines up with the window's edge
// on that side, so the space to the screen edge matches the space beside the
// window, and the capsule extends inward from there over the window.
function switcherGeom(count, screenWidth, screenHeight, cfg, windows, outerGaps) {
  var empty = {
    dotSize: 3, points: [],
    strip: { x: 0, y: 0, width: 0, height: 0 },
    bg: { x: 0, y: 0, width: 0, height: 0 },
    horizontal: false, edge: "right"
  };
  if (count <= 0) return empty;
  var p = parseDock(cfg.dock);
  if (!p) return empty;

  var margin = numberOr(cfg.margin, 30);
  var borderPad = numberOr(cfg.borderPadding, 0);
  var inset = numberOr(cfg.dotInset, 2);   // dot edge to capsule edge
  var depth = numberOr(cfg.pillDepth, 0);  // 0 = auto-fit the gap
  var alongPad = 6;                        // dot edge to capsule end
  var og = outerGaps || {};

  var horizontal;
  if (p.v === "mid") horizontal = false;
  else if (p.h === "center") horizontal = true;
  else horizontal = screenWidth >= screenHeight;   // corners: the longer side

  var screenCross = horizontal ? screenHeight : screenWidth;
  var screenAlong = horizontal ? screenWidth : screenHeight;
  var edge = horizontal ? (p.v === "top" ? "top" : "bottom")
                        : (p.h === "left" ? "left" : "right");

  function gapFor(e) {
    if (e === "top") return numberOr(og.top, 0);
    if (e === "bottom") return numberOr(og.bottom, 0);
    if (e === "left") return numberOr(og.left, 0);
    return numberOr(og.right, 0);
  }
  var crossGap = gapFor(edge);

  // Along-edge alignment and its margins.
  var align, alongStartMargin, alongEndMargin;
  if (horizontal) {
    align = p.h === "left" ? "start" : p.h === "right" ? "end" : "center";
    alongStartMargin = numberOr(og.left, 0);
    alongEndMargin = numberOr(og.right, 0);
  } else {
    align = p.v === "top" ? "start" : p.v === "bottom" ? "end" : "center";
    alongStartMargin = numberOr(og.top, 0);
    alongEndMargin = numberOr(og.bottom, 0);
  }

  // The window's edge line on this side. Measured for top/bottom so it lands
  // below the bar; derived from the outer gap for left/right (scrolling windows
  // can be off-screen, making their measured edge unreliable there).
  var crossLine;
  if (horizontal) {
    var edgeCoord = null;
    if (windows && windows.length) {
      for (var w = 0; w < windows.length; w++) {
        var c = (p.v === "top") ? windows[w].y : (windows[w].y + windows[w].h);
        if (edgeCoord === null) edgeCoord = c;
        else edgeCoord = (p.v === "top") ? Math.min(edgeCoord, c) : Math.max(edgeCoord, c);
      }
    }
    crossLine = (edgeCoord === null) ? (p.v === "top" ? crossGap : screenCross - crossGap) : edgeCoord;
  } else {
    crossLine = (edge === "left") ? crossGap : screenCross - crossGap;
  }

  // Capsule thickness.
  var capsuleCross;
  if (depth > 0) capsuleCross = Math.max(depth, 3 + inset * 2);
  else if (crossGap > 0) capsuleCross = Math.max(3 + inset * 2, crossGap - borderPad * 2);
  else capsuleCross = 12;

  // Cross-axis centre: explicit depth anchors the screen-edge side at the
  // window edge; auto centres the capsule in the gap.
  var outerSign = (edge === "right" || edge === "bottom") ? 1 : -1; // toward screen edge
  var railCross = (depth > 0)
    ? crossLine - outerSign * capsuleCross / 2
    : crossLine + outerSign * (crossGap > 0 ? crossGap / 2 : margin);
  railCross = Math.min(railCross, screenCross - capsuleCross / 2 - 1);
  railCross = Math.max(railCross, capsuleCross / 2 + 1);

  // Overflow: shrink spacing first, then the dots, so a long rail of windows
  // still fits between the edge margins.
  var dot = Math.max(3, capsuleCross - inset * 2);
  var spacing = numberOr(cfg.spacing, 20);
  var availAlong = Math.max(0, screenAlong - alongStartMargin - alongEndMargin);
  var span = count * dot + Math.max(0, count - 1) * spacing;
  if (count > 1 && span + alongPad * 2 > availAlong) {
    var minSpacing = 2;
    var room = Math.max(0, availAlong - alongPad * 2);
    if (dot * count + (count - 1) * minSpacing <= room) {
      spacing = Math.max(minSpacing, (room - dot * count) / (count - 1));
    } else {
      spacing = minSpacing;
      dot = Math.max(3, (room - (count - 1) * spacing) / count);
    }
    span = count * dot + (count - 1) * spacing;
  }
  var capsuleAlong = span + alongPad * 2;
  var alongStart;
  if (align === "center") alongStart = (screenAlong - capsuleAlong) / 2;
  else if (align === "start") alongStart = alongStartMargin;
  else alongStart = screenAlong - capsuleAlong - alongEndMargin;
  alongStart = Math.max(0, alongStart);

  var points = [], bg;
  if (horizontal) {
    for (var i = 0; i < count; i++)
      points.push({ x: alongStart + alongPad + i * (dot + spacing) + dot / 2, y: railCross });
    bg = {
      x: Math.round(alongStart),
      y: Math.round(railCross - capsuleCross / 2),
      width: Math.round(capsuleAlong),
      height: Math.round(capsuleCross)
    };
  } else {
    for (var j = 0; j < count; j++)
      points.push({ x: railCross, y: alongStart + alongPad + j * (dot + spacing) + dot / 2 });
    bg = {
      x: Math.round(railCross - capsuleCross / 2),
      y: Math.round(alongStart),
      width: Math.round(capsuleCross),
      height: Math.round(capsuleAlong)
    };
  }

  var m = 6;
  var strip = { x: bg.x - m, y: bg.y - m, width: bg.width + m * 2, height: bg.height + m * 2 };
  return { dotSize: dot, points: points, strip: strip, bg: bg, horizontal: horizontal, edge: edge };
}

function nearestDot(geom, mx, my) {
  var best = -1, bestDist = Infinity;
  for (var i = 0; i < geom.points.length; i++) {
    var dx = mx - geom.points[i].x;
    var dy = my - geom.points[i].y;
    var dist = dx * dx + dy * dy;
    if (dist < bestDist) { bestDist = dist; best = i; }
  }
  return best;
}
