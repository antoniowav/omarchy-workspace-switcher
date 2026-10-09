# Changelog

Everything below is new on top of the 1.0.0 release (commits `ee12dfa` /
`92a5c73`) or a fix for a defect in it. Versions 1.1.0–1.4.4 were developed by
[IsseyShiitake](https://github.com/IsseyShiitake) in a fork and adopted here.

Versions 1.3.0, 1.4.0, 1.4.1 and 1.4.2 were developed and verified on the live
install but landed in a single commit together with 1.4.3, so only the states in
the table have their own commit.

| version | where | date | headline |
|---|---|---|---|
| 1.0.0 | `92a5c73` | 2026-10-06 | base plugin |
| 1.1.0 | `69795e9` | 2026-10-08 | key arrangement, accent tint, review fixes |
| 1.2.0 | `25821ad` | 2026-10-08 | finger-following 3F swipe, live settings, file-stream input |
| 1.3.0 – 1.4.3 | `e3abd92` | 2026-10-09 | all input on one stream, overview muting, alpha-correct previews |
| 1.4.4 | `6619e28` | 2026-10-09 | wiring ships with the plugin, stream moves to `$XDG_RUNTIME_DIR` |
| 1.4.5 | `b29c9a2` | 2026-10-09 | no duplicate Super + Tab bind, symmetric swipe-to-close |

## Implementations (new since 1.0.0)

1. **Key arrangement, and it is a choice** (1.1.0; inverted in 1.3.0; switchable
   since 1.4.4) — the overview can be driven from `Super + Tab`, or from
   `Alt + Tab` while `Super + Tab` is left to Hyprland, by setting
   `OMARCHY_SWITCHER_MOD` before the wiring include. The plugin itself binds
   nothing: it only acts on what the wiring file streams.
2. **File-stream input architecture** (1.2.0, completed in 1.3.0) — every input
   event (key presses and gesture phases) is one line appended to
   `$XDG_RUNTIME_DIR/omarchy-workspace-switcher-swipe`, which the plugin tails.
   The earlier runtime key takeover (`applyBindings`, `restoreScripts`, owner
   token, rebind timer, `configreloaded` hook, `restoreScript`) was removed
   entirely: nothing to restore on unload, nothing to break on a config reload.
3. **Finger-following three-finger swipe** (1.2.0; hardened through 1.4.3) —
   the sheet follows the fingers (backdrop opacity and card scale), commits past
   30 % of the travel, reverts on cancel, closes on up *or* down while open; a
   5 s stream watchdog never commits a stale gesture, the tail auto-respawns, and
   the stream truncates itself when idle with a 64 KB cap on the Lua writer.
4. **Live settings file** (1.2.0) — `~/.config/omarchy/workspace-switcher.json`
   is re-read on save; no shell restart, and the plugin never writes it.
5. **Numeric card order with display-independent tap-flip** (`d906c77`) —
   `numericOrder` shows cards 1, 2, 3… while a tap still selects the workspace
   you came from, mapped onto however the cards are displayed.
6. **Theme-following visuals** (1.1.0 → 1.4.3) — accent-tinted backdrop
   (`accentTint`), solid tiles for windows without preview content, an opaque
   preview bed so translucent windows read as tiles instead of ghosts, per-window
   name chips and a "Current" tag.
7. **The desktop cannot change under the overview** (1.4.0) — a Wayland
   keyboard-shortcuts inhibitor on the overview layer, with `disable_inhibit`
   exemptions for the open/close swipes, and the keys the inhibitor mutes ridden
   through the layer instead (Tab / Shift+Tab cycle, releasing the modifier
   commits).
8. **Preview capture pipeline** (1.4.2, 1.4.3) — previews are captured in
   focused-card-first order, handed out one per tick (`captureStaggerMs`) so the
   opening animation keeps its frames, optionally held back until they are all
   in (`previewWaitMs`), and rendered alpha-correctly on the dmabuf transport
   (see bugfix 9).
9. **Terminal and app labelling coverage** (1.1.0 → 1.3.0) — the terminal class
   list grew from five entries to thirteen (Konsole, GNOME Terminal, xterm,
   WezTerm, Terminator, …), with Claude Code session names, shell-prompt
   directories and per-window labels.
10. **Wiring that ships with the plugin** (1.4.4) — the Hyprland gestures, key
    binds and release commit live in
    [`hypr/workspace-switcher.lua`](hypr/workspace-switcher.lua), pulled into the
    user's config with one include, guarded against double loading, with knobs
    for the key arrangement and the horizontal workspace swipe.
11. **Documentation and tests** — rewritten README (install, toggles, settings,
    known gaps) and a Node test suite covering ordering, selection, layout,
    arrow-key movement, capture order/targets and settings parsing.

## Bugfixes

Defects in the 1.0.0 plugin or its dependencies. Fixes for problems the 1.1–1.4 work
itself introduced during development are deliberately not part of this list; they
are recorded in the commit messages.

1. **Crash / NaN layout on clients without numeric geometry** (1.1.0) —
   `buildWorkspaces` used `c.at[0]` and `c.size[0]` unguarded; such clients are
   now skipped instead of poisoning every card's geometry.
2. **State-machine wedge on a failed query** (1.1.0, hardened in 1.4.2) —
   1.0.0 returned from `finishQuery` on a JSON parse failure and on an empty
   workspace list without closing, and had no timeout at all, so a hung `hyprctl`
   left the switcher unable to open. Now it closes cleanly and a 2 s watchdog
   clears the query.
3. **"Silent teleport" to another workspace** (1.1.0) — stale `commitPending` /
   `pendingSteps` from a cancelled open turned a later toggle into an immediate
   workspace switch; `toggle()` now clears them.
4. **Junk `desktop` app-name key** (1.1.0) — 1.0.0 indexed desktop-entry ids
   with their `.desktop` suffix, which leaked into class lookups.
5. **Wrong app names** (1.1.0) — reverse-DNS ids (`org.gimp.GIMP`) were not
   matched by bare class names, and `soffice.bin` was not recognised as
   LibreOffice.
6. **Wrong terminal labels** (1.1.0) — shell-prompt sigils (`$`, `#`, `%`) and
   terminal-appended titles ("… — Konsole") were shown as window content.
7. **Unload clobbered the user's own key bindings** (1.3.0) — 1.0.0's
   `restoreScript` rewrote the machine's binds with Omarchy stock on unload; the
   whole runtime-takeover design it belonged to is gone.
8. **Unreliable key delivery** (1.3.0) — 1.0.0's mechanism depended on
   quickshell 0.2.1 `GlobalShortcut`s, which silently drop per-instance subsets;
   input now rides the file stream, and the global shortcuts remain only as
   unbound secondary triggers.
9. **Translucent previews showed the desktop through the panel** (1.4.1
   diagnosis, 1.4.3 fix) — quickshell 0.2.1 wraps dmabuf capture textures
   without their alpha flag (`QSGOpenGLTexture::fromNative` takes no
   `TextureHasAlphaChannel`), so captures were drawn unblended and transparent
   pixels punched holes through the whole panel surface (measured: 52–93 % of the
   affected pixels identical to the bare desktop). The plugin now draws each
   preview through a QML layer / at `opacity: 0.995`, measured pixel-identical
   to the correct shm path, which keeps the cheap dmabuf transport. The
   `QS_DISABLE_DMABUF=1` workaround this replaced is no longer needed and should
   not be set.
10. **Super + Tab fired twice** (1.4.5) — the wiring bound `SUPER + Tab` without
    unbinding Omarchy's stock "Next workspace" bind, and Hyprland keeps both, so
    each press jumped a workspace and opened the overview. It now unbinds first.
11. **Swipe-to-close needed 70 % of the travel** (1.4.5) — closing compared the
    reveal against the commit ratio itself; it now closes at `1 - ratio`, so
    both directions commit at 30 %.
