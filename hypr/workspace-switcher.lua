-- Omarchy Workspace Switcher - Hyprland wiring for the
-- io.github.antoniowav.workspace-switcher plugin.
--
-- One include is all the switcher needs on the Hyprland side. Put this in
-- ~/.config/hypr/hyprland.lua (or an input.lua included from it):
--
--   local p = os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.antoniowav.workspace-switcher/hypr/workspace-switcher.lua"
--   local f = io.open(p, "r"); if f then f:close(); dofile(p) end
--
-- Every input - key presses and three-finger gestures - is streamed as one
-- line per event to
--
--   $XDG_RUNTIME_DIR/omarchy-workspace-switcher-swipe
--
-- which the plugin tails. Nothing is taken over at runtime and nothing needs
-- restoring on unload: with the plugin removed the lines are simply ignored.
--
-- Knobs: change the two values below (or set them before the dofile).
--   SWITCHER_MOD      "SUPER" keeps Super+Tab for the overview (default) and
--                     leaves Alt+Tab to window cycling. "ALT" moves the
--                     overview to Alt+Tab and leaves Super+Tab to Hyprland
--                     (useful if you want to keep Omarchy's own Super+Tab).
--   HORIZONTAL_SWIPE  true also registers the 3-finger horizontal workspace
--                     swipe. Leave false if your config already has one, or
--                     you will get a duplicate gesture.

-- Guards and knobs -----------------------------------------------------------
if _G.__omarchy_workspace_switcher_wired then return end
_G.__omarchy_workspace_switcher_wired = true

local SWITCHER_MOD = _G.OMARCHY_SWITCHER_MOD or "SUPER"
local HORIZONTAL_SWIPE = _G.OMARCHY_SWITCHER_HORIZONTAL_SWIPE == true

local RUNTIME = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local STREAM = RUNTIME .. "/omarchy-workspace-switcher-swipe"

-- Stream writer --------------------------------------------------------------
local swipe_dy = 0
local last_line = ""
-- Append, never truncate in place (except at the size cap): the plugin tails
-- this file, and a truncate+rewrite of similar length is invisible to `tail -f`
-- - a shrink to zero IS seen and resets it. The plugin empties the file itself
-- once a gesture has been over for a moment; the cap only bounds growth when
-- no plugin is tailing (disabled/removed).
local stream_bytes = 0
local function swipe_write(line, dedupe)
    if dedupe == nil then dedupe = true end
    if dedupe and line == last_line then return end
    last_line = line
    local mode = "a"
    if stream_bytes > 65536 then
        mode = "w"
        stream_bytes = 0
    end
    local f = io.open(STREAM, mode)
    if f then
        if f:write(line, "\n") then stream_bytes = stream_bytes + #line + 1 end
        f:close()
    end
end

-- Key presses must each land (hold-Tab cycling repeats the bind), so they
-- bypass the update-dedupe: consecutive identical key lines are distinct
-- presses.
local function key_write(name)
    swipe_write("key " .. name, false)
end

-- Gestures -------------------------------------------------------------------
local function swipe_action(dir)
    return {
        start = function(e)
            swipe_dy = 0
            last_line = ""
            swipe_write("begin " .. dir)
        end,
        update = function(e)
            swipe_dy = swipe_dy + e.delta.y
            swipe_write(string.format("update %s %.2f", dir, swipe_dy))
        end,
        -- Hyprland 0.56.2 reads the gesture's release callback from the table
        -- key "finish" (LuaBindingsConfigRules.cpp reads start/update/finish).
        -- An "end" key is silently ignored, which leaves the overview
        -- following the fingers forever with no release.
        finish = function(e)
            swipe_write("end " .. dir .. ((e and e.cancelled) and " cancelled" or ""))
        end,
    }
end

if HORIZONTAL_SWIPE then
    hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
end

-- disable_inhibit: while the overview is open it holds a wayland shortcuts
-- inhibitor (Hyprland skips every keybind and gesture for the focused
-- surface), which would kill the close-swipe too - these two are exempt so the
-- overview can still be swiped away.
hl.gesture({ fingers = 3, direction = "up",   action = swipe_action("up"),   disable_inhibit = true })
hl.gesture({ fingers = 3, direction = "down", action = swipe_action("down"), disable_inhibit = true })

-- Keys -----------------------------------------------------------------------
-- These ride the same stream the gestures do, which keeps the shell's flaky
-- GlobalShortcut routing out of the path entirely. Lua-function binds survive
-- config reloads natively and need no runtime rebind dance.
hl.bind(SWITCHER_MOD .. " + Tab", function() key_write("next") end,
    { description = "Switch workspace (hold " .. SWITCHER_MOD .. ", release to commit)" })
hl.bind(SWITCHER_MOD .. " + SHIFT + Tab", function() key_write("previous") end,
    { description = "Switch workspace backwards (hold " .. SWITCHER_MOD .. ")" })

-- Letting go of the modifier commits the cycled choice. Release + transparent
-- (the Tab bind shadows the press) + non_consuming (apps still see the key)
-- + ignore_mods (fires with Shift held). No description: internal machinery.
local modkeys = (SWITCHER_MOD == "ALT") and { "Alt_L", "Alt_R" } or { "Super_L", "Super_R" }
for _, key in ipairs(modkeys) do
    local bind = SWITCHER_MOD .. " + " .. key
    hl.bind(bind, function() key_write("commit") end,
        { release = true, transparent = true, non_consuming = true, ignore_mods = true })
end

-- Create the stream at config load: the config runs before the shell mounts, so
-- the plugin's watcher attaches to a file that already exists.
swipe_write("init")
