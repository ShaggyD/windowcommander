# Window Commander

Grab-a-pill window resizing and a focus switcher for [Omarchy](https://omarchy.org),
built for touch-first tablets and mice alike.

- A short rounded handle sits on every tiled split. Drag it to resize the two
  windows it separates, double-click it to equalize them 50/50, and hold a
  modifier to place the boundary freely. Idle handles are drawn as an outline
  and fill in when you grab them.
- A column (or row) of dots shows every window on the current workspace. The
  focused window's dot is solid; the rest are outlines. Tap a dot to focus that
  window, or drag across the dots to scrub through them.

Built for Hyprland's Lua-configured Omarchy (Hyprland 0.55+). It rides on the
Omarchy shell (Quickshell), takes no root, and runs no background daemon.

```
╔═══════════════╤═══════════════╗ ╷
║               ┃               ║ ●  ← focused dot (solid)
║             ▬▬┃▬▬             ║ ○  ← other windows (outline)
║               ┃               ║ ○
╚═══════════════╧═══════════════╝ ╵
```

## What it does

### Resize handles

- **Drag to resize.** Press a pill and drag; the split follows your pointer.
- **Fits any gap, with padding.** The pill's thickness is the gap minus the
  Handle padding on both sides, so it always sits inside the gap with a margin
  off both window borders, whatever your gaps are set to. The pill's ends are
  padded off the window corners the same way.
- **Translucent capsule** behind each pill (optional, with its own opacity), so
  the handles stay legible over busy wallpapers.
- **No focus stealing.** Grabbing a handle never changes focus, and it always
  resizes the left/top window of the split so the divider you grabbed is the one
  that follows the pointer.
- **Never on the rail's edge.** A handle is not drawn on the screen edge where
  the focus rail sits, and windows that are only a sliver on the monitor (a
  scrolling-layout neighbour mostly off screen) get no handle at all, so nothing
  collides with the dots.
- **Magnetic snapping.** The boundary is pulled to 1/3, 1/2 and 2/3 while you
  drag. Hold the free-drag modifier (Shift by default) to ignore the presets.
- **Double-click to equalize** the split to a clean 50/50.
- **Live or preview.** Live resizes as you drag; preview draws the target
  boundary and commits a single resize on release.
- **All tiled layouts.** Dwindle, master and the scrolling layout; each can be
  turned off independently.
- **Theme aware**, and **click-through**: each handle is its own tiny layer
  surface, so every pixel that is not a handle behaves exactly as if the plugin
  were not there.

### Focus switcher

- **One dot per window** on the focused monitor's visible workspace, in spatial
  order.
- **Dock it anywhere on the perimeter.** A 3×3 picker: eight spots around the
  edge — top/mid/bottom × left/center/right — or off. Edge-centre docks run
  vertically on the sides and horizontally on top/bottom; corner docks run along
  the longer side automatically. A top dock tucks below the Omarchy bar.
- **Solid = focused, outline = other.**
- **Sits in the outer gap**, aligned with the window edge, so it reads as a slim
  side bar (or bottom bar) rather than floating over window content.
- **One size control.** Pill depth sets the capsule's thickness, and the dots
  grow with it (`pillDepth − 2 × Dot inset`). `0` fits the outer gap; larger
  grows the capsule past the gap.
- **Lines up with the window.** The capsule's outer edge sits the same distance
  from the screen edge as the window's outer edge (`general:gaps_out`, plus any
  Rail gap), so the space to the screen edge matches the space beside the window,
  and the rail extends inward over the window edge.
- **Translucent capsule** behind the dots (optional, with its own opacity) so
  the rail stays legible over busy wallpapers.
- **Generous spacing** between dots, adjustable in the settings panel.
- **Tap a dot** to focus that window, **scrub** along the dots to move focus
  continuously, or **scroll the mouse wheel** over the rail to step one window
  at a time. Hovering or scrubbing **highlights the candidate window** and shows
  its title so the dot maps to a real window.
- Turn it off entirely from the settings panel (Dock → ✕) or the Focus dots
  toggle.

## Requirements

- Omarchy with shell plugin support (Quickshell) on the Hyprland Lua config.
- Nothing else. No root, no network, no daemon.

## Install

```bash
git clone <repo-url> ~/.config/omarchy/plugins/com.dchadwick.windowcommander
omarchy plugin enable com.dchadwick.windowcommander
```

`omarchy plugin enable` adds the plugin to the `plugins` array in
`~/.config/omarchy/shell.json`. To do it by hand:

```json
"plugins": [
  { "id": "com.dchadwick.windowcommander" }
]
```

The shell picks up `shell.json` on save. If a change does not appear, run
`omarchy restart shell` (the shell caches compiled plugin QML by URL).

## Usage

| Action | Result |
|---|---|
| Drag a pill | Resize the split it sits on |
| Double-click a pill | Equalize the two windows 50/50 |
| Hold the free-drag modifier while dragging | Ignore snapping, place freely |
| Tap a focus dot | Focus that window |
| Drag across focus dots | Scrub focus through the windows |
| Scroll the wheel over the rail | Focus the next/previous window |
| `omarchy-shell shell toggle com.dchadwick.windowcommander` | Open the settings panel |

Settings live at `~/.local/state/omarchy/window-commander.json` and are mirrored
into the plugin's `shell.json` entry. The settings panel edits them live.

### Opening the settings

- **Bar icon** — tap **WC** in the bar. Add it with
  `omarchy bar put com.dchadwick.windowcommander` if it is not there yet.
- **Right-click** a resize handle or the dot rail.
- **Dot Commander** — add the "Window Commander" slice from the pie editor's
  catalog (it sits in the **System** section).
- From the **Omarchy menu**: search "Window Commander" (also "resize",
  "focus switcher" or "wc").
- From a terminal:

  ```bash
  omarchy-shell shell toggle com.dchadwick.windowcommander
  ```

## Command line

```bash
omarchy-shell windowcommander toggle     # enable/disable the handles
omarchy-shell windowcommander enable
omarchy-shell windowcommander disable
omarchy-shell windowcommander refresh    # force a geometry re-scan
omarchy-shell windowcommander status     # JSON: enabled, mode, split count
```

## Conflicts

### hyprgrass (must be removed)

[hyprgrass](https://github.com/horriblename/hyprgrass) is a touch-gesture plugin
that processes touches globally, above layer surfaces. It fights a touch-first
window manager: dragging a dot, a pill, or a window makes hyprgrass pan the
workspace or move a window instead. There is no setting that fixes it cleanly, so
hyprgrass needs to go:

1. Remove its config and binds from `~/.config/hypr/input.lua` (the
   `plugin.hyprgrass` block and the `if hl.plugin.hyprgrass then … end` block).
2. Remove the startup reload from `~/.config/hypr/autostart.lua`
   (`o.exec_on_start("hyprpm reload -n")`).
3. Uninstall it:
   ```bash
   hyprpm remove hyprgrass     # answer Y
   # if it refuses (root-owned state): sudo chown -R "$USER" /var/cache/hyprpm && hyprpm remove hyprgrass
   hyprpm purge-cache
   ```

If you leave `plugin.hyprgrass.*` set with the plugin gone, Hyprland reports
`unknown config key` errors, which is the symptom to watch for.

Hyprland's own `gestures.workspace_swipe_touch` (native touch workspace swiping)
can also make a single touch pan the screen; it is off after removing the block
above. Re-add it deliberately if you want it:

```lua
hl.config({ gestures = { workspace_swipe_touch = true } })
```

## How it works

- A `service` entry point polls `hyprctl -j clients` / `monitors` /
  `activewindow` (Hyprland emits no event when a tiled ratio changes) and
  computes the shared edges between adjacent tiled windows and the focus order
  of the windows on the focused monitor.
- Each handle is its own full-screen layer-shell surface whose input **mask**
  (the Wayland input region) is just the handle while idle and the whole screen
  while grabbed — the same technique Dot Commander uses for its dot. The
  switcher is one more such surface, masked to the strip of dots while idle.
  Nothing outside those regions is ever captured, so idle touches and clicks
  pass through untouched.
- Resizing applies relative pixel resizes through
  `hyprctl eval 'hl.dispatch(hl.dsp.window.resize({ x = dx, y = dy, relative = true, window = "address:0x…" }))'`.
  Focusing a dot uses `hl.dsp.focus({ window = "address:0x…" })`.
- Maximized windows get no resize handle but do get a focus dot; true fullscreen
  windows are skipped.

### Limits

- Up to 15 handles per monitor (one mask surface each).
- Floating and grouped windows are not decorated.
- A monitor's layout is learned from Hyprland's `activelayout` event; an unknown
  layout is treated as enabled.

## Development

The shell caches compiled plugin QML (and imported JS) by URL. A structural
change usually applies after `omarchy restart shell`; if a change to `Engine.js`
seems to be ignored, the on-disk qmlcache is stale — clear it and restart:

```bash
rm -rf ~/.cache/quickshell/qmlcache && omarchy restart shell
```

Watch the log with:

```bash
journalctl --user -f | grep -i windowcommander
```

## License

MIT. See [LICENSE](LICENSE).
