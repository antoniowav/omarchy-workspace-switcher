import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "WorkspaceSwitcherLogic.js" as Logic

// Workspace Switcher: every workspace that has windows (plus the visible ones)
// as a card, in order of visit (current first), with its windows drawn at
// their real positions as previews.
//
// Input rides one stream: $XDG_RUNTIME_DIR/omarchy-workspace-switcher-swipe
// (/tmp when the shell has no runtime dir), one line per
// event, written by gesture callbacks and Lua-function key binds in
// hyprland.lua (gesture phases as "begin/update/end" lines, keys as
// "key next/previous/commit/toggle/close"). The plugin tails the file — no
// runtime key takeover, nothing to restore on unload, and the shell's
// GlobalShortcut routing (flaky on quickshell 0.2.1: per-instance dead
// subsets) is never in the path. GlobalShortcuts are still registered as
// secondary triggers where they work.
// The logic lives in WorkspaceSwitcherLogic.js.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string appId: "io.github.antoniowav.workspace-switcher"
  property bool destroying: false

  property bool opened: false
  property bool queryWanted: false
  property var workspaces: []
  property int selectedIndex: 0
  // Opened by Super + Tab: letting go of Super goes to the selected workspace.
  property bool cycling: false
  // Tabs pressed while the overview is still opening.
  property int pendingSteps: 0
  // Super let go while the overview was still opening: switch without showing it.
  property bool commitPending: false
  // Workspace ids, most recently focused first; the cards follow this order.
  property var recent: []
  // The card under the pointer, once the pointer has moved since opening; the
  // highlight follows it and falls back to the keyboard's selection.
  property int hoveredIndex: -1
  property var pointerStart: null
  property bool pointerArmed: false
  readonly property int highlighted: Logic.highlightIndex(selectedIndex, hoveredIndex)
  property var targetScreen: null

  readonly property int gap: Style.space(22)
  readonly property int labelHeight: Style.space(28)
  readonly property real cardAspect: 16 / 9

  // Setting: wash the backdrop with a whisper of the theme's popup-border
  // color (the edge on bluetooth/sound flyouts), so the overview feels part
  // of the theme. Off = plain theme background. Light/dark follows the theme
  // either way: every color here resolves from the active theme at runtime.
  property bool accentTint: true

  // Setting: cards always display in number order (1, 2, 3, …) instead of
  // order of visit. Tap-Super+Tab still flips to the workspace you were on
  // before — the highlight just starts there; further Tabs walk the cards
  // as displayed. Off = cards follow order of visit, current first.
  property bool numericOrder: true

  // Setting: a three-finger swipe up opens the overview following the
  // fingers (the same begin/update/end engine the horizontal workspace
  // swipe uses), and up or down while it is open closes it the same way.
  // The swipe itself is streamed by lines in hyprland.lua; off = the stream
  // is ignored and the swipes do nothing (base behavior).
  property bool gestureOpen: true

  // Setting: how long the sheet may wait for its previews before revealing,
  // in milliseconds. 0 reveals immediately and the previews fill in as they
  // land (each capture is a round trip through the compositor, ~0.1-0.2 s);
  // a larger value holds the sheet back until either every preview has
  // content or the wait runs out, so the sheet appears already populated.
  property int previewWaitMs: 0

  // Setting: how long the capture pump waits between two window previews, in
  // milliseconds (0 = every preview captures at once). Captures ride the cheap
  // dmabuf path, so a small gap keeps the open animation smooth (measured 9 of
  // ~10 samples either way) while the previews still start landing within
  // ~0.1 s; only a shell forced onto the shm screencopy path (QS_DISABLE_DMABUF)
  // needs the larger values, where each capture costs the compositor a full
  // readback.
  property int captureStaggerMs: 8

  // Settings and input live in files, watched live:
  //   ~/.config/omarchy/workspace-switcher.json  (the settings above)
  //   $XDG_RUNTIME_DIR/omarchy-workspace-switcher-swipe   (one line per input event)
  readonly property string settingsPath: Quickshell.env("HOME") + "/.config/omarchy/workspace-switcher.json"
  // The input stream lives in the session runtime dir when there is one (it is
  // 0700 and per-session, so no other local user or session can inject lines);
  // /tmp stays as the fallback for a shell started without XDG_RUNTIME_DIR.
  readonly property string swipeDir: Quickshell.env("XDG_RUNTIME_DIR") !== "" ? Quickshell.env("XDG_RUNTIME_DIR") : "/tmp"
  readonly property string swipePath: swipeDir + "/omarchy-workspace-switcher-swipe"

  // Preview captures are handed out by the pump below: captureCount is how
  // many windows this open has, captureArmed how many of them may capture yet.
  // Each capture rides the cheap dmabuf transport, but still costs the
  // compositor an offscreen render and a texture import here, so they are
  // spread over consecutive frames of the opening animation
  // (captureStaggerMs) instead of landing in one; the previews appear as the
  // sheet opens, within ~0.1-0.2 s.
  property int captureArmed: 0
  property int captureCount: 0
  // Previews that have content, how many of them can have any (a window with
  // no capturable toplevel never will), and whether the sheet may reveal yet
  // (the previewWaitMs gate above; always true with the setting off).
  property int captureLanded: 0
  property int captureTargets: 0
  property bool revealReady: true

  // How far the overview is showing, 0 (hidden) to 1 (fully open). While a
  // swipe drags it the value follows the fingers directly; otherwise it
  // animates, so opens and closes glide.
  property real sheetReveal: 0
  // True while the fingers (not an animation) are dragging the sheet.
  property bool swipeFollowing: false
  // "" | "opening" | "closing" — what an in-progress swipe is doing.
  property string swipeMode: ""
  // Finger travel (in the swipe stream's units) that fully reveals the sheet.
  readonly property real swipeTravel: 320
  // A swipe that revealed less than this snaps back; more commits (30%).
  readonly property real swipeCommitRatio: 0.3

  onGestureOpenChanged: {
    if (!gestureOpen && swipeFollowing) {
      swipeFollowing = false
      swipeMode = ""
      sheetReveal = opened ? 1 : 0
    }
  }

  // The sheet glides on its own, but never fights the fingers.
  Behavior on sheetReveal {
    enabled: !root.swipeFollowing
    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
  }
  readonly property color backdropColor: {
    var base = Color.background
    if (!root.accentTint) return Qt.alpha(base, 0.88)
    var b = Color.popups.border
    return Qt.rgba(base.r + (b.r - base.r) * 0.15, base.g + (b.g - base.g) * 0.15,
      base.b + (b.b - base.b) * 0.15, 0.88)
  }

  // Window previews composite over this bed. Transparent terminals stay
  // readable in light themes because the bed stays dark there; in dark themes
  // it is the theme surface itself. Opaque windows cover it fully.
  readonly property color previewBed: {
    var bg = Color.menu.background
    var luminance = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b
    return luminance > 0.5 ? "#101315" : bg
  }

  function focusedScreen() {
    var monitorName = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; ++i) {
      if (String(screens[i].name || "") === monitorName)
        return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  function open() {
    targetScreen = focusedScreen()
    queryWanted = true
    queryWatchdog.restart()
    if (!stateQuery.running)
      stateQuery.running = true
  }

  function toggle() {
    if (opened) {
      close()
      return
    }
    cycling = false
    // A query that failed earlier may have left these behind; they would
    // turn this open into a silent workspace switch instead of the overview.
    commitPending = false
    pendingSteps = 0
    open()
  }

  // Super + Tab (step 1) and Super + Shift + Tab (step -1). The first one
  // opens the overview with the previous workspace (or, backwards, the least
  // recent) already selected, so a quick Super + Tab flips between the last two.
  function cycle(step) {
    cycling = true
    if (opened) {
      selectedIndex = Logic.cycleSelection(highlighted, step, workspaces.length)
      hoveredIndex = -1
    } else if (queryWanted) {
      pendingSteps += step
    } else {
      pendingSteps = step
      open()
    }
  }

  // Super was let go: go to the selected workspace. Letting go before the
  // overview has drawn still goes there, once it knows the workspaces.
  function commit() {
    if (!cycling) return
    if (!opened && queryWanted) {
      commitPending = true
      return
    }
    cycling = false
    var ws = Logic.commitTarget(opened, workspaces, highlighted)
    if (ws) {
      goToWorkspace(ws)
    } else {
      close()
    }
  }

  function close() {
    opened = false
    workspaces = []
    queryWanted = false
    queryWatchdog.stop()
    cycling = false
    pendingSteps = 0
    commitPending = false
    hoveredIndex = -1
    selectedIndex = 0
    captureArmed = 0
    captureCount = 0
    captureLanded = 0
    captureTargets = 0
    revealReady = true
    previewWait.stop()
    // The fingers' authority ends with the overview: swipe lines still in
    // flight are ignored once swipeFollowing is false, so closing can never
    // again leave a half-revealed sheet — or its input-stealing layer —
    // behind, whatever route the close took.
    swipeFollowing = false
    swipeMode = ""
    sheetReveal = 0
  }

  function pointerOver(index, position) {
    if (!pointerArmed) {
      if (!pointerStart) {
        pointerStart = { x: position.x, y: position.y }
        return
      }
      if (!Logic.pointerMoved(pointerStart, position.x, position.y, 4)) return
      pointerArmed = true
    }
    hoveredIndex = index
  }

  function pointerLeft(index) {
    if (hoveredIndex === index) hoveredIndex = -1
  }

  // One line of the input stream (see Logic.parseSwipe): gesture phases from
  // the Lua gesture callbacks, key presses from the Lua-function binds. Keys
  // act whatever gestureOpen says (that setting only governs swipes); a
  // gesture the compositor cancelled (finger count changed mid-swipe and the
  // like) reverts instead of committing.
  function onSwipeLine(line) {
    var event = Logic.parseSwipe(line)
    if (!event) return

    if (event.phase === "key") {
      if (event.name === "next") cycle(1)
      else if (event.name === "previous") cycle(-1)
      else if (event.name === "commit") commit()
      else if (event.name === "toggle") toggle()
      else if (event.name === "close") close()
      return
    }
    if (!gestureOpen) return

    if (event.phase === "begin") {
      if (swipeFollowing) return
      if (opened) {
        swipeMode = "closing"
      } else if (event.dir === "up") {
        swipeMode = "opening"
        cycling = false
        commitPending = false
        pendingSteps = 0
        sheetReveal = 0
        open()
      } else {
        // A downward swipe from closed has nothing to reveal. Ignoring it
        // keeps the panel — and with it the exclusive-keyboard layer and the
        // shortcuts inhibitor — from being mapped, invisible and input-dead,
        // for the whole length of the drag.
        return
      }
      swipeFollowing = true
    } else if (event.phase === "update" && swipeFollowing) {
      if (swipeMode === "opening") {
        // Up is negative dy in screen coordinates.
        sheetReveal = Logic.clamp01(-event.dy / swipeTravel)
      } else if (swipeMode === "closing") {
        sheetReveal = Logic.clamp01(1 - Math.abs(event.dy) / swipeTravel)
      }
    } else if (event.phase === "end" && swipeFollowing) {
      swipeFollowing = false
      var mode = swipeMode
      swipeMode = ""
      if (event.cancelled) {
        if (mode === "opening") close()
        else sheetReveal = opened ? 1 : 0
        return
      }
      if (mode === "opening") {
        if (sheetReveal >= swipeCommitRatio) sheetReveal = 1
        else close()
      } else if (mode === "closing") {
        // Mirror of opening: 30 % of the travel commits either way (the
        // sheet is then 70 % revealed). Comparing against the ratio itself
        // made closing need 70 % of the travel.
        if (sheetReveal <= 1 - swipeCommitRatio) close()
        else sheetReveal = 1
      } else {
        sheetReveal = opened ? 1 : 0
      }
    }
  }

  function dispatch(lua) {
    close()
    Qt.callLater(function() {
      Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(" + lua + ")"])
    })
  }

  function goToWorkspace(ws) {
    // Workspace ids come from hyprctl's JSON; only a finite number ever reaches
    // the Lua expression (a window address is regex-validated in the logic).
    var id = ws ? Number(ws.id) : NaN
    if (!isFinite(id)) {
      close()
      return
    }
    dispatch('hl.dsp.focus({ workspace = "' + id + '" })')
  }

  function focusWindow(address) {
    dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
  }

  function finishQuery(text) {
    queryWatchdog.stop()
    if (!queryWanted) return
    queryWanted = false

    var state
    try {
      state = JSON.parse(String(text || "{}"))
    } catch (error) {
      console.warn("io.github.antoniowav.workspace-switcher: failed to parse hyprctl output:", error)
      close()
      return
    }

    var toplevelByAddress = ({})
    var toplevels = Hyprland.toplevels && Hyprland.toplevels.values ? Hyprland.toplevels.values : []
    for (var i = 0; i < toplevels.length; ++i) {
      var topAddress = Logic.normalizeAddress(toplevels[i].address)
      if (topAddress) toplevelByAddress[topAddress] = toplevels[i]
    }

    var entries = DesktopEntries.applications && DesktopEntries.applications.values
      ? DesktopEntries.applications.values : []
    var list = Logic.buildWorkspaces(state, Logic.appNameIndex(entries), function(address) {
      var top = toplevelByAddress[address]
      return top ? top.wayland : null
    })
    if (list.length === 0) {
      close()
      return
    }
    var ranked = Logic.sortByRecent(list, recent)
    list = Logic.displayOrder(list, recent, root.numericOrder)

    var selected = Logic.initialSelection(ranked, list, pendingSteps)
    pendingSteps = 0
    if (commitPending) {
      var target = Logic.commitTarget(true, list, selected)
      close()
      if (target) goToWorkspace(target)
      return
    }

    // Number the previews for the capture pump (focused workspace first, then
    // the cards as displayed) before the cards are built, so every delegate
    // reads its final slot on its first evaluation; captures then start with
    // the pump, as soon as the cards exist.
    captureCount = Logic.assignCaptureOrder(list)
    captureTargets = Logic.countCaptureTargets(list)
    captureArmed = root.captureStaggerMs > 0 ? 0 : captureCount
    captureLanded = 0
    previewWait.stop()
    revealReady = root.previewWaitMs <= 0 || captureTargets === 0
    if (!revealReady) previewWait.restart()
    workspaces = list
    selectedIndex = selected
    hoveredIndex = -1
    pointerStart = null
    pointerArmed = false
    opened = true
    // While a swipe is dragging the sheet, the fingers own the reveal; with
    // the preview wait on, the reveal is held back until revealReady.
    if (!swipeFollowing && revealReady) sheetReveal = 1
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function moveSelection(dx, dy) {
    selectedIndex = Logic.moveSelection(highlighted, dx, dy, grid.cols, workspaces.length)
    hoveredIndex = -1
  }

  function noteFocusedWorkspace() {
    recent = Logic.touchRecent(recent, Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1)
  }

  Component.onCompleted: {
    noteFocusedWorkspace()
    // The input stream file must exist before tail can follow it; the gesture
    // lines in hyprland.lua (re)create it on every swipe anyway. The retry
    // starts the tail after the touch has had a moment to land.
    Quickshell.execDetached(["touch", swipePath])
    swipeWatchRetry.start()
  }

  Timer {
    id: swipeWatchRetry
    interval: 400
    onTriggered: swipeTail.running = true
  }

  Component.onDestruction: {
    destroying = true
  }

  // Fires on workspace and monitor focus changes alike. A visit counts once
  // focus has stayed for a moment: going to a workspace on the other monitor
  // briefly focuses the one already showing there, which isn't a visit.
  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { visitTimer.restart() }
  }

  Timer {
    id: visitTimer
    interval: 200
    onTriggered: root.noteFocusedWorkspace()
  }

  // The settings. The parse is a binding on the FileView's text, so it re-runs
  // whenever the file reloads (FileView's onLoaded only fires on the first
  // load — it is a property-change handler, not the signal). A missing file or
  // malformed JSON means the defaults above (both settings features on).
  property var settings: Logic.parseSettings(settingsFile.text())
  onSettingsChanged: {
    gestureOpen = settings.gestureOpen
    accentTint = settings.accentTint
    numericOrder = settings.numericOrder
    captureStaggerMs = settings.captureStaggerMs
    previewWaitMs = settings.previewWaitMs
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  // The input stream written (appended) by the gesture callbacks and the
  // Lua-function key binds in hyprland.lua, tailed live: each appended line
  // is one event, in order. The file is emptied by the plugin after input
  // has been idle for a moment — truncating in place there is what `tail
  // -f` can see, unlike rewrites. If the tail dies the stream is dead and
  // every gesture after it would be silently lost, so it is respawned (the
  // swipe file is touched first: a tail on a missing file exits immediately).
  Process {
    id: swipeTail
    command: ["tail", "-n", "0", "-f", root.swipePath]
    running: false
    onExited: {
      if (root.destroying) return
      Quickshell.execDetached(["touch", root.swipePath])
      swipeWatchRetry.start()
    }
    stdout: SplitParser {
      onRead: function(line) {
        root.onSwipeLine(line)
        // Ids resolve lexically, not as root properties: root.swipeIdle is
        // undefined and the call silently kills the rest of this handler.
        swipeIdle.restart()
        swipeWatchdog.restart()
      }
    }
  }

  // If the stream stops mid-gesture — the tail dies, the Lua write fails —
  // the fingers' authority must not outlive the gesture: this long after the
  // last line, the sheet reverts (never commits), so an interrupted follow
  // can't leave the exclusive-keyboard layer mapped and the input dead.
  Timer {
    id: swipeWatchdog
    interval: 5000
    running: root.swipeFollowing
    onTriggered: {
      if (!root.swipeFollowing) return
      root.swipeFollowing = false
      var mode = root.swipeMode
      root.swipeMode = ""
      if (mode === "opening") root.close()
      else root.sheetReveal = root.opened ? 1 : 0
    }
  }

  Timer {
    id: swipeIdle
    interval: 3000
    onTriggered: swipeTruncate.running = true
  }

  // Hands the previews their capture source, one window per tick (or all at
  // once with captureStaggerMs 0): captures are cheap on the dmabuf path, but
  // spreading them over the open animation's frames keeps the animation smooth
  // (at 8 ms the live reveal renders 9 of ~10 possible samples with gaps of
  // 25-37 ms; landing everything in one frame gives bigger gaps and hatches
  // it). A sheet the fingers are dragging closed takes no new captures at all.
  // The pump stops at captureCount and close() resets it, so a cancelled open
  // cannot leave it running.
  Timer {
    id: capturePump
    interval: root.captureStaggerMs
    repeat: true
    running: root.opened && root.swipeMode !== "closing"
      && root.captureArmed < root.captureCount
    onTriggered: root.captureArmed += 1
  }

  // The preview wait: reveals as soon as every preview has content, or when
  // previewWaitMs runs out, whichever comes first.
  Timer {
    id: previewWait
    interval: root.previewWaitMs
    onTriggered: root.revealReady = true
  }

  onRevealReadyChanged: {
    if (root.revealReady && root.opened && !root.swipeFollowing) root.sheetReveal = 1
  }

  // A state query that never comes back — the compositor busy, the process
  // killed — must not leave the switcher wedged with queryWanted set, where
  // the next Super + Tab only queues steps and nothing ever appears.
  Timer {
    id: queryWatchdog
    interval: 2000
    onTriggered: {
      if (!root.queryWanted) return
      console.warn("io.github.antoniowav.workspace-switcher: hyprctl state query timed out")
      root.close()
      stateQuery.running = false
    }
  }

  // Empties the swipe stream in place, 3s after the last line of a gesture:
  // `truncate -s 0`, never a rewrite — the tail sees the shrink and resets,
  // while a replaced file would leave it watching a dead inode. (A FileView
  // with setText("") was tried here first and never wrote the file at all.)
  Process {
    id: swipeTruncate
    command: ["truncate", "-s", "0", root.swipePath]
    running: false
  }

  Process {
    id: stateQuery
    command: ["sh", "-c",
      'printf \'{"monitors":%s,"workspaces":%s,"clients":%s}\' '
      + '"$(hyprctl monitors -j)" "$(hyprctl workspaces -j)" "$(hyprctl clients -j)"']
    running: false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishQuery(text)
    }
  }

  GlobalShortcut {
    appid: "io.github.antoniowav.workspace-switcher"
    name: "toggle"
    description: "Open or close the workspace overview"
    onPressed: root.toggle()
  }

  GlobalShortcut {
    appid: "io.github.antoniowav.workspace-switcher"
    name: "next"
    description: "Open the workspace overview, or select the next workspace"
    onPressed: root.cycle(1)
  }

  GlobalShortcut {
    appid: "io.github.antoniowav.workspace-switcher"
    name: "previous"
    description: "Open the workspace overview, or select the previous workspace"
    onPressed: root.cycle(-1)
  }

  // Hyprland sends this one from a release binding, as a release; commit() is
  // idempotent, so handling the release alone is enough.
  GlobalShortcut {
    appid: "io.github.antoniowav.workspace-switcher"
    name: "commit"
    description: "Go to the selected workspace if Super + Tab opened the overview"
    onReleased: root.commit()
  }

  GlobalShortcut {
    appid: "io.github.antoniowav.workspace-switcher"
    name: "close"
    description: "Close the workspace overview"
    // Unconditional: close() is idempotent, and a half-revealed sheet (opened
    // by a gesture whose query hasn't finished) has opened=false but must
    // still be closable from outside.
    onPressed: root.close()
  }

  PanelWindow {
    id: panel
    visible: root.opened || root.swipeFollowing || root.sheetReveal > 0.001
    onVisibleChanged: {
      if (visible) keyCatcher.forceActiveFocus()
    }
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "workspace-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // While the overview shows, it holds a keyboard-shortcuts inhibitor on
    // its surface: Hyprland then skips every keybind, mousebind and trackpad
    // gesture for the focused surface (KeybindManager.cpp / TrackpadGestures
    // gestureUpdate), so Super+digit workspace jumps, Super+Ctrl+arrows and
    // the 3-finger horizontal workspace swipe can't change the desktop under
    // the overview. The overview's own input is unaffected: Esc/arrows/Return
    // arrive as plain keys, Tab and letting go of Super are handled below,
    // and the open/close swipes register disable_inhibit in hyprland.lua.
    ShortcutInhibitor {
      window: panel
      enabled: panel.visible
    }

    Rectangle {
      anchors.fill: parent
      color: root.backdropColor
      opacity: root.sheetReveal
    }

    // Clicking the backdrop closes the overview.
    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_Escape: root.close(); break
        case Qt.Key_Left: root.moveSelection(-1, 0); break
        case Qt.Key_Right: root.moveSelection(1, 0); break
        case Qt.Key_Up: root.moveSelection(0, -1); break
        case Qt.Key_Down: root.moveSelection(0, 1); break
        case Qt.Key_Return:
        case Qt.Key_Enter:
          if (root.workspaces[root.highlighted]) root.goToWorkspace(root.workspaces[root.highlighted])
          break
        // With the shortcuts inhibitor up, Super + Tab (further presses while
        // the overview is open) and Shift + Tab arrive here as plain keys —
        // cycle the same way the stream binds do from closed. Shift + Tab
        // actually arrives as Backtab (XKB maps it to ISO_Left_Tab, Qt to
        // Qt.Key_Backtab, measured: key 16777218), so it needs its own case or
        // the backwards walk is dead while the overview is open, where the
        // stream bind is muted. Alt + Tab and Ctrl + Tab are left alone: those
        // are window/app-level bindings (Alt + Tab cycles windows) and moving
        // the workspace highlight under the overview would be surprising.
        case Qt.Key_Tab:
          if (event.modifiers & (Qt.AltModifier | Qt.ControlModifier)) return
          root.cycle(event.modifiers & Qt.ShiftModifier ? -1 : 1)
          break
        case Qt.Key_Backtab:
          root.cycle(-1)
          break
        default: return
        }
        event.accepted = true
      }

      Keys.onReleased: function(event) {
        switch (event.key) {
        // Letting go of Super commits, as the release bind does when the
        // overview was opened from closed (the inhibitor has it muted now).
        // The Super keysym arrives as Qt.Key_Meta on Linux (XKB Super->Meta
        // mapping); the others cover different keyboard/mapping variants.
        case Qt.Key_Meta:
        case Qt.Key_Super_L:
        case Qt.Key_Super_R:
          root.commit()
          break
        default: return
        }
        event.accepted = true
      }
    }

    Item {
      id: area
      anchors.fill: parent
      anchors.margins: Style.space(48)
      opacity: root.sheetReveal
      scale: 0.92 + 0.08 * root.sheetReveal

      readonly property var fit: Logic.layoutFor(root.workspaces.length, width, height, root.gap, root.labelHeight, root.cardAspect)

      Grid {
        id: grid
        readonly property int cols: area.fit.cols
        anchors.centerIn: parent
        columns: cols
        spacing: root.gap

        Repeater {
          model: root.workspaces

          delegate: Item {
            id: card
            required property int index
            required property var modelData

            // Preview content is counted once for the preview wait, even if a
            // capture context is ever torn down and rebuilt.
            property bool counted: false
            readonly property bool selected: index === root.highlighted
            width: area.fit.cardW
            height: width / root.cardAspect + root.labelHeight
            // The other cards dim slightly, so the highlighted one stands out.
            opacity: selected ? 1 : 0.7

            HoverHandler {
              onPointChanged: if (hovered) root.pointerOver(card.index, point.scenePosition)
              onHoveredChanged: if (!hovered) root.pointerLeft(card.index)
            }

            // "Current" marks the workspace you are on, whatever is highlighted.
            // It follows the workspace's name, so it can't be read as the
            // neighbouring card's.
            Rectangle {
              id: currentTag
              visible: card.modelData.focused
              anchors { left: label.right; leftMargin: Style.space(8); verticalCenter: label.verticalCenter }
              width: currentText.implicitWidth + Style.space(16)
              height: currentText.implicitHeight + Style.space(6)
              radius: height / 2
              color: Color.accent

              Text {
                id: currentText
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "Current"
                color: Color.background
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Text {
              id: label
              textFormat: Text.PlainText
              anchors { left: parent.left; top: parent.top }
              width: Math.min(implicitWidth, parent.width - (currentTag.visible ? currentTag.width + Style.space(8) : 0))
              height: root.labelHeight
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
              text: card.modelData.name + "  ·  " + (card.modelData.windows.length === 0
                ? "empty"
                : card.modelData.windows
                    .map(function(w) { return w.label })
                    .filter(function(app, i, apps) { return apps.indexOf(app) === i })
                    .join(", "))
              color: card.selected ? Color.accent : Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              font.bold: card.modelData.focused
            }

            Rectangle {
              id: screenFrame
              anchors { left: parent.left; right: parent.right; top: label.bottom; bottom: parent.bottom }
              radius: Style.cornerRadius
              color: Color.menu.background
              border.width: card.selected ? Math.max(3, Style.normalBorderWidth * 2) : Math.max(1, Style.normalBorderWidth)
              border.color: card.selected ? Color.accent : Color.menu.border
              clip: true

              // Empty space in the card goes to the workspace.
              MouseArea {
                anchors.fill: parent
                onClicked: root.goToWorkspace(card.modelData)
              }

              // The workspace's monitor, letterboxed into the card.
              Item {
                id: screenArea
                readonly property real monAspect: card.modelData.monitor.w / card.modelData.monitor.h
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height * monAspect)
                height: width / monAspect

                Repeater {
                  model: card.modelData.windows

                  delegate: Rectangle {
                    id: win
                    required property var modelData

                    x: modelData.x * screenArea.width
                    y: modelData.y * screenArea.height
                    width: Math.max(8, modelData.w * screenArea.width)
                    height: Math.max(8, modelData.h * screenArea.height)
                    radius: Math.max(2, Style.cornerRadius / 2)
                    // Solid while the preview is missing, so windows without
                    // screencopy content read as tiles instead of holes;
                    // near-clear under a live preview, where the bed behind
                    // it does the compositing.
                    color: preview.hasContent ? Qt.alpha(Color.menu.text, 0.08) : Color.menu.background
                    border.width: 1
                    border.color: winMouse.containsMouse ? Color.accent : Qt.alpha(Color.menu.text, 0.18)
                    clip: true

                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      width: parent.width - Style.space(8)
                      text: win.modelData.app
                      color: Color.menu.text
                      opacity: preview.hasContent ? 0 : 0.6
                      horizontalAlignment: Text.AlignHCenter
                      elide: Text.ElideRight
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.caption
                    }

                    // Opaque bed directly under the live preview, so transparent
                    // windows (terminals with a see-through background) read
                    // as solid tiles instead of ghosts. Hidden without content,
                    // where the app-name placeholder shows instead.
                    Rectangle {
                      anchors.fill: preview
                      visible: preview.hasContent
                      color: root.previewBed
                    }

                    ScreencopyView {
                      id: preview
                      anchors.fill: parent
                      anchors.margins: 1
                      // null until the capture pump reaches this window.
                      captureSource: win.modelData.captureOrder >= 0
                          && win.modelData.captureOrder < root.captureArmed
                          && win.modelData.wayland ? win.modelData.wayland : null
                      paintCursor: false
                      // One frame per open, handed over by the capture pump above.
                      live: false
                      // quickshell 0.2.1 wraps a dmabuf capture without the
                      // texture's alpha flag (QSGOpenGLTexture::fromNative
                      // takes no TextureHasAlphaChannel), so the capture would
                      // be drawn unblended and a translucent window's
                      // transparent pixels would punch a hole through the
                      // whole panel surface. An item opacity below 1 makes the
                      // scene graph blend the capture instead, 0.5% of the bed
                      // mixing in where the window is transparent — measured
                      // pixel-identical to the shm path for a 45%-opacity
                      // blurred window, and ~45 ms earlier than routing the
                      // capture through a layer (which is the other way to get
                      // a blended composite). The real fix belongs upstream:
                      // pass QQuickWindow::TextureHasAlphaChannel for alpha
                      // dmabuf formats.
                      opacity: hasContent ? 0.995 : 0
                      onHasContentChanged: {
                        if (!hasContent || card.counted) return
                        card.counted = true
                        root.captureLanded += 1
                        if (root.captureLanded >= root.captureTargets) root.revealReady = true
                      }
                      constraintSize: Qt.size(Math.max(1, width), Math.max(1, height))
                    }

                    // App name on every window, so tiled windows can be told apart.
                    Rectangle {
                      visible: preview.hasContent && win.width > Style.space(40)
                      anchors { left: parent.left; bottom: parent.bottom; margins: Style.space(4) }
                      width: Math.min(nameText.implicitWidth + Style.space(12), parent.width - Style.space(8))
                      height: nameText.implicitHeight + Style.space(4)
                      radius: height / 2
                      color: Qt.alpha(Color.menu.background, 0.85)

                      Text {
                        id: nameText
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        width: parent.width - Style.space(12)
                        horizontalAlignment: Text.AlignHCenter
                        text: win.modelData.label
                        color: Color.menu.text
                        elide: Text.ElideRight
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    MouseArea {
                      id: winMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      onClicked: root.focusWindow(win.modelData.address)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
