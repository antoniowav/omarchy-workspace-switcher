# Workspace Switcher

Super + Tab for Omarchy workspaces, with a three-finger swipe that opens the
overview under your fingers.

- **Tap Super + Tab** to flip to the workspace you were on before. Tap it again to flip back.
- **Hold Super and press Tab** to see every workspace — number order by default,
  order of visit with a setting off — with live previews of its windows. Each
  Tab steps one card along in the order the cards are displayed (Shift + Tab
  steps back), and letting
  go of Super switches to it. Previews are visible as the sheet opens (each is
  one frame, captured as it appears, and they land within ~0.1-0.2 s; with
  `previewWaitMs` set the sheet waits for them instead and appears already
  populated).
- **Swipe up with three fingers** to open the overview following your fingers
  (the same engine the horizontal workspace swipe uses); release past 30% of
  the travel to open, below to snap back. While it is open, a three-finger
  swipe up **or** down closes it the same way; swiping down while it is
  closed does nothing.
- Click a window to focus it, or click empty space in a card to go to that workspace.
  The arrow keys and Return work too, and Escape closes it.
- While the overview is showing it holds a keyboard-shortcuts inhibitor, so
  nothing can change the desktop under it: Super+digit workspace jumps,
  Super+Ctrl+arrows and the three-finger horizontal workspace swipe are muted
  for as long as it is open. Be aware that the inhibitor is all-or-nothing:
  **every** Hyprland keybind is skipped for that surface, so volume, brightness
  and media keys (XF86…) do nothing for the moment the overview is up. The
  open/close swipes are exempt (they register `disable_inhibit`), and Tab,
  Shift + Tab, the arrows, Return, Escape and letting go of Super keep working
  because the overview handles them itself.
- Each window is labelled with its app's name. Terminals show what they are doing
  instead: a Claude Code session's name (as the top bar shows it), the folder of a
  shell prompt, or the running program's title. Transparent terminals composite
  over a solid bed, so they read as tiles, not ghosts.

![Workspace Switcher](preview.png)

## Install

Two steps: add the plugin, then include its Hyprland wiring (one `dofile`).

```bash
omarchy plugin add https://github.com/antoniowav/omarchy-workspace-switcher --enable
```

In `~/.config/hypr/hyprland.lua` (or an `input.lua` included from it):

```lua
-- Workspace switcher wiring: the three-finger up/down gestures, Super+Tab /
-- Super+Shift+Tab and the Super-release commit. Set OMARCHY_SWITCHER_MOD = "ALT"
-- before this to put the overview on Alt+Tab and leave Super+Tab to Hyprland.
local ws_wiring = os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.antoniowav.workspace-switcher/hypr/workspace-switcher.lua"
local ws_file = io.open(ws_wiring, "r")
if ws_file then ws_file:close() dofile(ws_wiring) end
```

Then `hyprctl reload` (or re-login). The wiring ships inside the plugin, so it
travels with it and your config stays a single include.

**Stock Omarchy already binds `Super + Tab`** (next/previous workspace, in
`default/hypr/bindings/tiling.lua`) — the include rebinds it, which is the point
of the switcher. If you would rather keep Omarchy's tiling binds, set
`OMARCHY_SWITCHER_MOD = "ALT"` before the include: the overview moves to
Alt + Tab, and you can put window cycling back on Super + Tab.

The plugin itself needs no restart.

## Keys and touchpad gestures

All input rides one stream: `$XDG_RUNTIME_DIR/omarchy-workspace-switcher-swipe`
(`/tmp` only if the shell was started without a runtime dir), one line per event,
written by the wiring file's gesture callbacks and Lua-function key binds and
tailed live by the plugin. No runtime key takeover, nothing to restore on unload,
nothing that breaks on a config reload — and because the stream lives in the
session runtime dir (mode 0700) no other local user or session can inject lines
into it.

The wiring itself ships in the plugin as
[`hypr/workspace-switcher.lua`](hypr/workspace-switcher.lua), pulled in by the one
include in Install:

| wiring | what it does |
|---|---|
| three-finger up / down | open the overview following the fingers; up **or** down while open closes it. Registered `disable_inhibit` so the close-swipe survives the overview's own shortcuts inhibitor. |
| `Super + Tab` / `Super + Shift + Tab` | cycle forward / back while held; the first press opens the overview on the previous workspace |
| release of `Super_L` / `Super_R` | commit the highlighted workspace (transparent, non-consuming: apps still see Super) |

Two knobs, set before the include: `_G.OMARCHY_SWITCHER_MOD = "ALT"` moves the
keys to Alt + Tab and leaves Super + Tab to Hyprland;
`_G.OMARCHY_SWITCHER_HORIZONTAL_SWIPE = true` also registers the three-finger
horizontal workspace swipe (leave it off if your config already has one, or you
get a duplicate gesture).

The rationale for a file stream instead of compositor-side key handling: the
gestures use the same begin/update/finish callback engine the horizontal
workspace swipe rides (Hyprland 0.56's `gesture` keyword), but a global dispatch
carries no payload — so the callbacks stream each event to the plugin through the
file. It also keeps the shell's GlobalShortcut routing out of the path: on
quickshell 0.2.1 those silently drop per-instance subsets. Five
`GlobalShortcut`s (`toggle`, `next`, `previous`, `commit`, `close`) are still
registered as unbound secondary triggers for anything that wants them.

The plugin does not add the wiring for you: Hyprland cannot remove a gesture once
it is added, and you may already use these swipes or Super + Tab for something
else. With the plugin's `gestureOpen` setting off, or the plugin disabled, the
gesture lines are written and ignored; the key lines are ignored too, and
Super + Tab does whatever your own config binds there.

## How it changes your key bindings

It doesn't, at runtime: the keys it uses are the Lua binds the include
registers, in your own config. Nothing is taken over, and disabling the plugin
(or removing it) needs no cleanup — the stream lines are simply ignored.

| Keys | With the binds + plugin |
|---|---|
| Super + Tab | Flip to the previous workspace, or hold Super to cycle |
| Super + Shift + Tab | Cycle backwards |
| Letting go of Super | Switch to the selected workspace (only after Super + Tab) |

Letting go of Super is passed on to apps as usual. Alt + Tab is never used in
the default arrangement: whatever you have bound there (window cycling, …) works
exactly as before, with the plugin enabled or disabled. With
`OMARCHY_SWITCHER_MOD = "ALT"` it is the other way round — the overview takes
Alt + Tab and Super + Tab is left alone.

Anything else that binds the same keys conflicts with the include: Omarchy's own
stock `Super + Tab` bind, and other plugins that bind it in their config. Keep
only one — the include is loaded last in your config, so it wins, but if you want
Omarchy's tiling binds back use the `ALT` arrangement above.

## What you can switch on or off

Nothing here is imposed: the plugin binds no keys by itself, and every knob is
independent of the others.

| what | how | default |
|---|---|---|
| **The key arrangement** (Super + Tab vs Alt + Tab) | set `OMARCHY_SWITCHER_MOD` before the wiring include — `"ALT"` moves the overview to Alt + Tab and leaves `Super + Tab` to Hyprland, `"SUPER"` is the other way round | `"SUPER"` |
| **Three-finger horizontal workspace swipe** | `OMARCHY_SWITCHER_HORIZONTAL_SWIPE = true` before the include | off, so it never duplicates one you already have |
| **Three-finger up/down gestures** | the `gestureOpen` setting (`false`: the swipes are ignored; the keys and globals still work) | `true` |
| **Backdrop tint** | `accentTint` | `true` |
| **Card order** | `numericOrder` (`false`: order of visit, current first) | `true` (1, 2, 3 …) |
| **Preview capture spacing** | `captureStaggerMs` (`0` = every preview at once) | `8` ms |
| **Whether the sheet waits for its previews** | `previewWaitMs` (`200` ≈ appear already populated) | `0` (reveal at once, previews land within ~0.1–0.2 s) |
| **The whole plugin** | `omarchy plugin disable io.github.antoniowav.workspace-switcher` | enabled |
| **Just the wiring** | comment out the include in your config | included |

Not switchable: while the overview is up it holds a keyboard-shortcuts inhibitor,
which mutes **every** Hyprland keybind — volume, brightness and media keys
included — for as long as it is showing. That is what stops the desktop changing
underneath it. Tab, Shift + Tab, the arrows, Return, Escape and releasing the
modifier still work, because the overview handles them itself (see the bullet
list above).

## Configuration

Five settings in `~/.config/omarchy/workspace-switcher.json`, on top of the
wiring knobs in the section above. A missing file, a missing key or malformed
JSON all mean the defaults shown below (booleans on, `captureStaggerMs` 8,
`previewWaitMs` 0). Editing the file applies live, without a shell restart, and
the plugin never writes it:

```json
{
  "gestureOpen": true,
  "accentTint": true,
  "numericOrder": true,
  "captureStaggerMs": 8,
  "previewWaitMs": 0
}
```

- `gestureOpen` (default `true`) — the three-finger swipe stream is followed
  (see Touchpad gestures above). `false` reverts to the base plugin: the
  swipes do nothing and the overview opens only from Super + Tab or the
  `toggle` global.
- `accentTint` (default `true`) washes the backdrop with a whisper of the
  theme's popup-border color (the edge on bluetooth/sound flyouts), light or
  dark as the active theme is. `false` reverts to the plain theme background.
- `numericOrder` (default `true`) displays the cards in number order
  (1, 2, 3, …) instead of order of visit. A tap still flips to the workspace
  you were on before — the highlight just starts there; further Tabs walk the
  cards as displayed. `false` reverts to visit-ordered cards, current first.
- `previewWaitMs` (default `0`, clamped to 0–1000; `200` is a good value if you would rather the sheet appear already populated) — how long the sheet may
  wait for its previews before revealing itself. `0` reveals at once and the
  previews fill in as they land: the sheet is up ~40 ms after the key press,
  the first preview is there ~0.1 s later and the last within ~0.2 s, so the
  cards show their window name for a moment. `200` (say) holds the sheet back
  until every preview has content or the wait runs out — the sheet then
  appears already populated and its animation is perfectly smooth, at the cost
  of appearing ~0.17 s later. Measured on 7 windows: `0` → reveal at ~40 ms,
  previews 90–225 ms; `200` → reveal at ~170–200 ms with 7/7 previews ready
  and animation samples one frame apart.
- `captureStaggerMs` (default `8`, clamped to 0–500) — the gap between two
  window previews being captured, so the whole batch does not land on one
  frame of the opening animation. `0` captures everything at once: the
  previews are as early as they can be, at the cost of the animation's first
  ~0.1 s. Larger values are gentler on slow machines and slower to fill.

Workspaces you haven't visited since the shell started are listed last, in
number order. The order starts fresh when the shell restarts.

## Requirements

Omarchy 4 (Quattro) with its Quickshell shell and Hyprland 0.56 or later. No
other dependencies. The plugin runs `hyprctl` to read your workspaces and windows
and to switch workspaces; the keys and gestures come from the wiring file you
include in your own config (see Install), never from the plugin. It needs no
network access and no privileges.

**Known quickshell 0.2.1 issue (worked around here):** on the dmabuf screencopy
path the texture wrapper is format-blind (`QSGOpenGLTexture::fromNative` without
`TextureHasAlphaChannel`), so `ScreencopyView` renders unblended — transparent
pixels of the captured window punch a hole through the whole panel surface and
the live desktop shows through the card. Measured on a 45 %-opacity blurred
Konsole: 52–93 % of the affected preview's pixels were pixel-identical to the
bare desktop. The plugin draws each preview at `opacity: 0.995`, which makes the
scene graph blend the capture instead (half a percent of the bed mixes in where
the window is transparent); that was pixel-verified identical to the shm capture
path, needs no offscreen buffer, and is ~45 ms faster to appear than the other
workaround (routing the capture through a QML layer, which also works). dmabuf
matters because the shm fallback makes the *compositor* copy every capture
synchronously into shared memory inside one output-commit callback
(full-resolution `glReadPixels` — see Hyprland's `CScreenshareFrame::copyShm`),
which stalls the whole desktop and used to make the opening animation render in
two or three jumps. Do **not** set `QS_DISABLE_DMABUF=1` for this plugin any
more; if you do (another consumer needs it, say), raise `captureStaggerMs` to
~40 and expect the previews to fill in progressively instead.

The real fix belongs upstream in quickshell: pass
`QQuickWindow::TextureHasAlphaChannel` when the imported dmabuf format has an
alpha channel (the same thing its Vulkan path already does for XRGB formats).

## Tested configuration and known gaps

Developed and verified against: **Omarchy 4 shell**, **quickshell 0.2.1**
(Fedora build `0.2.1^git20260209.dacfa9d`, Qt 6.11.2), **Hyprland 0.56.2**, a
single 2880×1800 display at scale 2, Fedora 44.

Verified by testing: both open paths (stream key bind, three-finger swipe) and
every close path (Escape, backdrop click, Super release, swipe), the shortcuts
inhibitor and its swipe exemptions, live settings reload, the capture pump and
`previewWaitMs`, and the alpha-correct previews (pixel-compared against the shm
capture transport).

Not verified by testing — reasoned from source, or untested hardware:

- **Hold-`Super` Tab-repeat through the overview's exclusive-keyboard layer.**
  Discrete synthetic presses work; a real key repeat has not been measured. If
  repeats don't reach the layer on some setup, hold-cycling degrades to one step
  per press (the stream binds used while closed are unaffected).
- **Super-release commit** depends on Qt mapping the XKB Super keysym to
  `Qt.Key_Meta`; `Meta`, `Super_L` and `Super_R` are all handled, but only this
  Qt build was exercised.
- **Other trackpads** — `swipeTravel` (320 px) and the 30 % commit threshold
  were tuned on this one. Nothing breaks elsewhere; the feel differs.
- **Other versions** — quickshell ≠ 0.2.1, Hyprland ≠ 0.56.2 and non-Omarchy
  shells are untested. The plugin imports `qs.Commons`/`qs.Ui`, so it is
  Omarchy-only by design; the wiring file depends on 0.56's `gesture` keyword
  and its `finish` release callback.
- **Multi-monitor** — the overview targets the focused monitor and the geometry
  maths is per-monitor, but only a single-monitor setup was exercised. Special
  (negative-id) workspaces and unmapped/hidden clients are excluded by design,
  and a client whose monitor is missing from `hyprctl` falls back to a
  1920×1080 fraction grid.
- **Plugin code changes need a shell restart** — Omarchy's plugin watcher
  exists, but it did not reload this plugin for a file edit during testing.
- **`omarchy plugin update` overwrites a modified checkout** — the plugin lives
  as a git checkout under `~/.config/omarchy/plugins/`, so keep changes
  committed and pushed rather than edited in place.

The alpha note under Requirements is specific to quickshell 0.2.1: if a future
version passes the texture's alpha flag itself, this plugin's workaround becomes
a harmless no-op rather than a problem.

## Remove

```bash
omarchy plugin remove io.github.antoniowav.workspace-switcher
```

Also remove the include block from `~/.config/hypr/hyprland.lua` (or
`input.lua`). Nothing else to undo: the stream file in `$XDG_RUNTIME_DIR` is
deleted with the session and would simply be ignored.

## Changes

Every implementation and bugfix since 1.0.0 is listed in
[CHANGELOG.md](CHANGELOG.md), with the version each landed in.

## Thanks

Versions 1.1.0–1.4.4 — the finger-following swipe, the input stream, overview
muting, alpha-correct previews and the bugfixes in the changelog — were
contributed by [IsseyShiitake](https://github.com/IsseyShiitake).

## Development

The logic is in `WorkspaceSwitcherLogic.js` and is tested with `node test/logic-test.js`.

## License

MIT. See [LICENSE](LICENSE).
