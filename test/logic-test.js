// Run with: node test/logic-test.js
const assert = require("node:assert/strict")
const L = require("../WorkspaceSwitcherLogic.js")

// Visits: most recent first, no duplicates, ignores invalid ids.
let recent = []
for (const id of [1, 3, 5, 3, 2]) recent = L.touchRecent(recent, id)
assert.deepEqual(recent, [2, 3, 5, 1])
assert.deepEqual(L.touchRecent(recent, -1), recent)

// Cards in order of visit, focused first, unvisited by number at the end.
const ws = [1, 2, 3, 5, 7, 8].map((id) => ({ id, focused: id === 3 }))
assert.deepEqual(L.sortByRecent(ws, recent).map((w) => w.id), [3, 2, 5, 1, 7, 8])

// Super + Tab: first Tab selects the previous workspace, Shift + Tab the least
// recent; letting go on the current workspace goes nowhere.
assert.equal(L.cycleSelection(0, 1, 6), 1)
assert.equal(L.cycleSelection(0, -1, 6), 5)
assert.equal(L.commitTarget(true, [{ id: 1, focused: true }], 0), null)
assert.equal(L.commitTarget(false, [{ id: 1 }, { id: 2 }], 1), null)
assert.equal(L.commitTarget(true, [{ id: 1, focused: true }, { id: 2 }], 1).id, 2)

// Hover wins only while over a card.
assert.equal(L.highlightIndex(2, -1), 2)
assert.equal(L.highlightIndex(2, 4), 4)
assert.equal(L.pointerMoved({ x: 0, y: 0 }, 3, 3, 4), false)
assert.equal(L.pointerMoved({ x: 0, y: 0 }, 5, 0, 4), true)

// Terminal labels.
assert.equal(L.windowLabel("foot", "✳ Fix the build", "Foot"), "✳ Fix the build")
assert.equal(L.windowLabel("foot", "me@host:~/code", "Foot"), "~/code")
assert.equal(L.windowLabel("foot", "", "Foot"), "Foot")
assert.equal(L.windowLabel("chromium", "Inbox", "Chromium"), "Chromium")

// App names: reverse-DNS ids answer to their basename, and the ".desktop"
// suffix is never indexed (it would collide as a junk "desktop" key).
const idx = L.appNameIndex([
  { name: "GNU Image Manipulation Program", id: "org.gimp.GIMP" },
  { name: "Firefox Web Browser", id: "firefox.desktop" },
])
assert.equal(idx["desktop"], undefined)
assert.equal(L.appName("gimp", idx), "GNU Image Manipulation Program")
assert.equal(L.appName("firefox", idx), "Firefox Web Browser")
assert.equal(L.appName("soffice.bin", {}), "LibreOffice")

// Input stream parsing: gesture phases, dy on updates only, the cancelled
// marker on ends, key presses, and junk lines (the file starts with "init")
// rejected cleanly.
assert.equal(L.parseSwipe("begin up").phase, "begin")
assert.equal(L.parseSwipe("begin up").dir, "up")
assert.equal(L.parseSwipe("update up -123.45").dy, -123.45)
assert.equal(L.parseSwipe("update down 90.00").dy, 90)
assert.equal(L.parseSwipe("end down").cancelled, false)
assert.equal(L.parseSwipe("end down cancelled").cancelled, true)
assert.equal(L.parseSwipe("end up cancelled").phase, "end")
assert.equal(L.parseSwipe("key next").phase, "key")
assert.equal(L.parseSwipe("key next").name, "next")
assert.equal(L.parseSwipe("key previous").name, "previous")
assert.equal(L.parseSwipe("key commit").name, "commit")
assert.equal(L.parseSwipe("key toggle").name, "toggle")
assert.equal(L.parseSwipe("key close").name, "close")
assert.equal(L.parseSwipe("key bogus"), null)
assert.equal(L.parseSwipe("key"), null)
assert.equal(L.parseSwipe("init"), null)
assert.equal(L.parseSwipe(""), null)
assert.equal(L.parseSwipe(null), null)
assert.equal(L.parseSwipe("update up nan"), null)
assert.equal(L.parseSwipe("update"), null)
assert.equal(L.clamp01(1.5), 1)
assert.equal(L.clamp01(-0.2), 0)
assert.equal(L.clamp01(0.25), 0.25)

// Terminal label details: prompt sigils are decoration, and terminals that
// append their own name ("… — Konsole") lose it before parsing.
assert.equal(L.windowLabel("foot", "me@host:~/code$", "Foot"), "~/code")
assert.equal(L.windowLabel("foot", "me@host:~/code#", "Foot"), "~/code")
assert.equal(L.windowLabel("konsole", "me@host:~/code — Konsole", "Konsole"), "~/code")
assert.equal(L.windowLabel("konsole", "nvim notes.md — Konsole", "Konsole"), "nvim notes.md")

// Display order: plain numbers when set, visit order otherwise. The initial
// highlight starts on the last-visited card however they display, so a tap
// still flips there: ranked [3f, 2, 4, 1] on cards [1, 2, 3, 4] starts on 2.
const cards = [3, 1, 2, 4].map((id) => ({ id, focused: id === 3 }))
assert.deepEqual(L.displayOrder(cards, [2, 4, 1], true).map((w) => w.id), [1, 2, 3, 4])
assert.deepEqual(L.displayOrder(cards, [2, 4, 1], false).map((w) => w.id), [3, 2, 4, 1])
const ranked = L.sortByRecent(cards, [2, 4, 1])
const numeric = L.displayOrder(cards, [2, 4, 1], true)
assert.equal(numeric[L.initialSelection(ranked, numeric, 1)].id, 2)
assert.equal(numeric[L.initialSelection(ranked, numeric, -1)].id, 1)
assert.equal(numeric[L.initialSelection(ranked, numeric, 0)].id, 3)
assert.equal(L.initialSelection(ranked, ranked, 1), 1)
assert.equal(L.initialSelection([], [], 1), 0)

// Capture pump order: the focused card's windows capture first, then the rest
// in card order, and every window gets exactly one slot. Cards keep the order
// they are displayed in.
const pump = [
  { id: 1, focused: false, windows: [{}, {}] },
  { id: 2, focused: true, windows: [{}] },
  { id: 3, focused: false, windows: [{}] },
]
assert.equal(L.assignCaptureOrder(pump), 4)
assert.deepEqual(pump[1].windows.map((w) => w.captureOrder), [0])
assert.deepEqual(pump[0].windows.map((w) => w.captureOrder), [1, 2])
assert.deepEqual(pump[2].windows.map((w) => w.captureOrder), [3])
assert.equal(L.assignCaptureOrder([]), 0)
assert.equal(L.assignCaptureOrder(null), 0)
assert.equal(L.assignCaptureOrder([{ id: 1, focused: true }]), 0)

// Only windows with a capturable toplevel count for the preview wait: the rest
// would keep the sheet waiting for content that can never arrive.
const targets = [
  { id: 1, focused: true, windows: [{ wayland: {} }, { wayland: null }] },
  { id: 2, focused: false, windows: [{ wayland: {} }] },
  { id: 3, focused: false, windows: [] },
]
assert.equal(L.countCaptureTargets(targets), 2)
assert.equal(L.countCaptureTargets([]), 0)
assert.equal(L.countCaptureTargets(null), 0)
assert.equal(L.countCaptureTargets([{ id: 1, windows: [{ wayland: null }] }]), 0)

// Settings: the three switches plus the capture stagger, clamped so a typo
// cannot stall the previews or hammer the compositor.
assert.deepEqual(L.parseSettings(""), {
  gestureOpen: true, accentTint: true, numericOrder: true, captureStaggerMs: 8, previewWaitMs: 0,
})
assert.equal(L.parseSettings('{"captureStaggerMs": 80}').captureStaggerMs, 80)
assert.equal(L.parseSettings('{"captureStaggerMs": 0}').captureStaggerMs, 0)
assert.equal(L.parseSettings('{"captureStaggerMs": 1}').captureStaggerMs, 1)
assert.equal(L.parseSettings('{"captureStaggerMs": -5}').captureStaggerMs, 0)
assert.equal(L.parseSettings('{"captureStaggerMs": 5000}').captureStaggerMs, 500)
assert.equal(L.parseSettings('{"captureStaggerMs": 44.6}').captureStaggerMs, 45)
assert.equal(L.parseSettings('{"captureStaggerMs": "fast"}').captureStaggerMs, 8)
assert.equal(L.parseSettings('{"captureStaggerMs": null}').captureStaggerMs, 8)
assert.equal(L.parseSettings("{oops").captureStaggerMs, 8)
assert.equal(L.parseSettings('{"gestureOpen": false}').gestureOpen, false)
assert.equal(L.parseSettings('{"previewWaitMs": 200}').previewWaitMs, 200)
assert.equal(L.parseSettings('{"previewWaitMs": -5}').previewWaitMs, 0)
assert.equal(L.parseSettings('{"previewWaitMs": 99999}').previewWaitMs, 1000)
assert.equal(L.parseSettings('{"previewWaitMs": "soon"}').previewWaitMs, 0)

// Malformed geometry never poisons the layout: the client is skipped.
const noGeom = L.buildWorkspaces({
  monitors: [{ id: 0, x: 0, y: 0, width: 1920, height: 1080, scale: 1,
    activeWorkspace: { id: 1 }, focused: true }],
  workspaces: [{ id: 1, name: "1", monitorID: 0, windows: 1 }],
  clients: [{ address: "0x1", class: "foot", title: "t", workspace: { id: 1 } }],
}, {}, null)
assert.equal(noGeom[0].windows.length, 0)

// Layout: the chosen column count is the one whose card is largest, within the
// 42% width cap — checked as a property instead of magic numbers.
for (const n of [1, 2, 3, 4, 5, 6, 8, 12]) {
  const fit = L.layoutFor(n, 1200, 800, 10, 20, 16 / 9)
  let best = 0
  for (let cols = 1; cols <= n; ++cols) {
    const rows = Math.ceil(n / cols)
    const byWidth = (1200 - (cols - 1) * 10) / cols
    const byHeight = ((800 - (rows - 1) * 10) / rows - 20) * (16 / 9)
    best = Math.max(best, Math.min(byWidth, byHeight, 1200 * 0.42))
  }
  assert.ok(Math.abs(fit.cardW - best) < 1e-9, `n=${n}: cardW ${fit.cardW} != best ${best}`)
  assert.ok(fit.cardW <= 1200 * 0.42 + 1e-9, `n=${n}: cardW above the width cap`)
  assert.ok(fit.cols >= 1 && fit.cols <= n, `n=${n}: cols out of range`)
}
assert.deepEqual(L.layoutFor(1, 1000, 700, 10, 20, 16 / 9), { cols: 1, cardW: 420 })
assert.equal(L.layoutFor(0, 1000, 700, 10, 20, 16 / 9).cols, 1) // degenerate: one column

// Arrow keys walk the grid and stop at its edges.
assert.equal(L.moveSelection(2, 1, 0, 3, 6), 3)
assert.equal(L.moveSelection(2, -1, 0, 3, 6), 1)
assert.equal(L.moveSelection(2, 0, 1, 3, 6), 5)
assert.equal(L.moveSelection(2, 0, -1, 3, 6), 2)
assert.equal(L.moveSelection(5, 1, 0, 3, 6), 5)
assert.equal(L.moveSelection(0, 0, -1, 3, 6), 0)
assert.equal(L.moveSelection(4, 0, 1, 3, 6), 4)

console.log("ok")
