-- tide's key map (SPEC.md §7.2), and which modifiers stand for Super.
--
-- With Karabiner's rule loaded, physical Win+key arrives as
-- Ctrl+Option+Command+key, so Option keeps its text gestures. Without it,
-- Super falls back to plain Option: every key still works, but Option's own
-- meanings (word delete, word moves, accents) go to tilemo (SPEC.md §7.1).

local M = {}

M.KARABINER = { "ctrl", "alt", "cmd" }
M.OPTION = { "alt" }

-- Each binding: Super plus `key`, with Shift if `shift`, calling the
-- window manager's `action` with `arg`. `repeating` keys repeat while held.
M.map = {
    { key = "j", action = "focus", arg = 1 },
    { key = "k", action = "focus", arg = -1 },
    { key = "j", shift = true, action = "move", arg = 1 },
    { key = "k", shift = true, action = "move", arg = -1 },
    -- Super+Return moves the window to a workspace by name; Alt+Tab swaps
    -- with the master (M.karabiner_only, SPEC.md §7.2).
    { key = "return", action = "move_to" },
    { key = "\\", action = "mfact", arg = 1, repeating = true },
    { key = "/", action = "mfact", arg = -1, repeating = true },
    { key = "=", action = "nmaster", arg = 1 },
    { key = "-", action = "nmaster", arg = -1 },
    { key = ".", action = "cycle", arg = 1 },
    { key = ",", action = "cycle", arg = -1 },
    { key = "`", action = "monocle" },
    { key = "o", action = "monocle" },
    { key = "up", action = "maximize" },
    { key = "up", shift = true, action = "fullscreen" },
    { key = "down", action = "restore" },
    { key = "f", shift = true, action = "toggle_float" },
    -- A PC keyboard's Insert arrives as the Mac's Help key.
    { key = "help", action = "toggle_float" },
    { key = "delete", action = "close" },
    { key = "r", shift = true, action = "resize_mode" },
    { key = "left", action = "step", arg = -1 },
    { key = "right", action = "step", arg = 1 },
    { key = "pageup", action = "step", arg = -1 },
    { key = "pagedown", action = "step", arg = 1 },
    { key = "left", shift = true, action = "carry", arg = -1 },
    { key = "right", shift = true, action = "carry", arg = 1 },
}

-- App keys (tide's, conf hyprland.lua). Each brings the app's window, and
-- its workspace, forward; with none, it launches the app. `bundle` finds
-- the app's windows and launches it by bundle ID; `run` is one of tide's
-- helpers, run through runenv for the login environment (SPEC.md §7.2).
-- `new` opens a new window every time instead, as tide's terminal key does.
-- `home_app` marks one of the home workspace's apps, which launches from home without
-- asking for a workspace (SPEC.md §7.2).
M.APPS = {
    { key = "t", spec = { bundle = "net.kovidgoyal.kitty", new = true } },
    { key = "w", spec = { run = "terminal_on_workstation" } },
    { key = "g", spec = { run = "browser1" } },
    { key = "g", shift = true, spec = { run = "browser3" } },
    { key = "f", spec = { run = "browser2" } },
    { key = "c", spec = { run = "google-calendar", home_app = true } },
    { key = "c", shift = true, spec = { run = "google-chat", home_app = true } },
    { key = "h", spec = { run = "home" } },
    { key = "i", spec = { run = "irc" } },
    { key = "m", spec = { run = "google-meet" } },
    { key = "n", spec = { run = "notepad" } },
    { key = "r", spec = { run = "remote-desktop" } },
    { key = "y", spec = { run = "youtube-music", home_app = true } },
    { key = "e", spec = { run = "kitty -e yazi" } },
}
for _, a in ipairs(M.APPS) do
    M.map[#M.map + 1] = { key = a.key, shift = a.shift, action = "app", arg = a.spec }
end

-- tide's session keys: lock, and log out.
M.map[#M.map + 1] = { key = "l", action = "lock" }
M.map[#M.map + 1] = { key = "e", shift = true, action = "logout" }

-- The switcher, each key on its own tab (SPEC.md §9). Karabiner's rule
-- sends a lone Super tap as Super+F20, for the Workspaces tab.
M.map[#M.map + 1] = { key = "space", action = "launcher", arg = "launch" }
M.map[#M.map + 1] = { key = "f20", action = "launcher", arg = "workspaces" }
M.map[#M.map + 1] = { key = "a", action = "launcher", arg = "attention" }
M.map[#M.map + 1] = { key = "space", shift = true, action = "dashboard" }
-- Super+Tab flips between home and the workspace you used last, and
-- Super+End goes to the last one other than home (SPEC.md §7.2).
M.map[#M.map + 1] = { key = "tab", action = "flip" }
M.map[#M.map + 1] = { key = "end", action = "last" }
-- tide's mic-mute key: the microphone, everywhere (SPEC.md §7.2).
M.map[#M.map + 1] = { key = "m", shift = true, action = "mic_mute" }
-- Super+Home: "in" (SPEC.md §6.1).
M.map[#M.map + 1] = { key = "home", action = "home" }
-- Super+Print: a region, as Shift+Print is (SPEC.md §7.2).
M.map[#M.map + 1] = { key = "f13", action = "screenshot", arg = "region" }

-- tide's Print keys, without Super. A PC keyboard's Print arrives as F13
-- (SPEC.md §7.2).
M.plain = {
    { mods = {}, key = "f13", action = "screenshot", arg = "screen" },
    { mods = { "alt" }, key = "f13", action = "screenshot", arg = "window" },
    { mods = { "shift" }, key = "f13", action = "screenshot", arg = "region" },
}

-- macOS's own screenshot keys, so tilemo needs no Screen Recording
-- permission of its own (SPEC.md §10). They save the shot to Screenshot's
-- folder, and tilemo copies it to the clipboard from there (shots.lua). A
-- window is the region picker with Space pressed, as macOS has no key for
-- it.
M.SCREENSHOT = {
    screen = { mods = { "cmd", "shift" }, key = "3" },
    region = { mods = { "cmd", "shift" }, key = "4" },
    window = { mods = { "cmd", "shift" }, key = "4", ["then"] = "space" },
}

-- Super+1…9 and Super+Shift+1…9 are gone, now that workspaces have names
-- (SPEC.md §7.2).

-- Keys bound only with Karabiner's rule, which makes them from physical
-- keys: Alt+Tab arrives as Control+Option+Shift+Tab, a combination nothing
-- else uses. Without the rule, physical Alt+Tab is Ctrl+Tab, every app's
-- next tab, so swap with the master has no key (SPEC.md §7.2).
M.karabiner_only = {
    { mods = { "ctrl", "alt", "shift" }, key = "tab", action = "swap_master" },
}

-- Resize mode (tide's): each key grows or shrinks the focused float by
-- 40 px; Esc or Return leaves.
M.resize = {
    { key = "h", d = { -40, 0 } },
    { key = "l", d = { 40, 0 } },
    { key = "k", d = { 0, -40 } },
    { key = "j", d = { 0, 40 } },
    { key = "left", d = { -40, 0 } },
    { key = "right", d = { 40, 0 } },
    { key = "up", d = { 0, -40 } },
    { key = "down", d = { 0, 40 } },
}
M.resize_exit = { "escape", "return" }

-- The modifier list for one binding.
function M.mods(super, binding)
    local out = {}
    for _, m in ipairs(super) do
        out[#out + 1] = m
    end
    if binding.shift then
        out[#out + 1] = "shift"
    end
    return out
end

-- Every binding to register for this Super, each with its modifiers. The
-- plain Print keys come first, and a later binding on a chord already taken
-- is left out: with Super on Option, Super+Print is Alt+Print, which stays
-- tide's window screenshot (Shift+Print still takes a region). With
-- Karabiner's Super, its own combinations come too.
function M.bindings(super)
    local out, seen, skipped = {}, {}, {}
    local function add(mods, b)
        local sorted = {}
        for i, m in ipairs(mods) do
            sorted[i] = m
        end
        table.sort(sorted)
        local chord = table.concat(sorted, "+") .. "+" .. b.key
        if seen[chord] then
            skipped[#skipped + 1] = chord
            return
        end
        seen[chord] = true
        out[#out + 1] = { mods = mods, key = b.key, action = b.action, arg = b.arg, repeating = b.repeating }
    end
    for _, b in ipairs(M.plain) do
        add(b.mods, b)
    end
    for _, b in ipairs(M.map) do
        add(M.mods(super, b), b)
    end
    if super == M.KARABINER then
        for _, b in ipairs(M.karabiner_only) do
            add(b.mods, b)
        end
    end
    return out, skipped
end

-- The description prefixes that mark tilemo's Karabiner rule: its own, and
-- the one it had as timo, so rules installed before the rename still count.
M.RULE_PREFIXES = { "tilemo:", "timo:" }

local function is_our_rule(description)
    if type(description) ~= "string" then
        return false
    end
    for _, prefix in ipairs(M.RULE_PREFIXES) do
        if description:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

-- Whether the selected Karabiner profile has tilemo's rule. Each profile keeps
-- its own rules, so a rule left in another profile doesn't count.
local function profile_has_rule(config)
    for _, p in ipairs(type(config) == "table" and config.profiles or {}) do
        if p.selected then
            local cm = p.complex_modifications or {}
            for _, r in ipairs(cm.rules or {}) do
                if is_our_rule(r.description) then
                    return true
                end
            end
            return false
        end
    end
    return false
end

-- Whether exactly Super's modifiers are held, Shift aside, in Hammerspoon's
-- flags table ({ cmd = true, alt = true, ... }).
function M.is_super(super, flags)
    local want = {}
    for _, m in ipairs(super or {}) do
        want[m] = true
    end
    for _, m in ipairs({ "cmd", "alt", "ctrl" }) do
        if (flags[m] or false) ~= (want[m] or false) then
            return false
        end
    end
    return true
end

-- Whether Super is held with nothing else, not even Shift or Fn: the start
-- of a lone Super tap.
function M.super_alone(super, flags)
    return M.is_super(super, flags) and not flags.shift and not flags.fn
end

-- Whether every one of Super's modifiers is held, whatever else is: holding
-- a chord that includes Super pauses focus follows mouse.
function M.super_held(super, flags)
    if not super or #super == 0 then
        return false
    end
    for _, m in ipairs(super) do
        if not flags[m] then
            return false
        end
    end
    return true
end

-- Whether Karabiner is running with tilemo's rule loaded. `read` returns a
-- file's text or nil, `decode` turns JSON into a table or nil, and
-- `running` says whether a process name is live; all come from the adapter,
-- so this tests without a Mac.
function M.karabiner_ready(read, running, home, decode)
    local text = read(home .. "/.config/karabiner/karabiner.json")
    if not text or not profile_has_rule(decode(text)) then
        return false
    end
    -- The service's process name changed in Karabiner-Elements 15
    -- (unverified); either counts.
    return running("Karabiner-Core-Service") or running("karabiner_grabber")
end

function M.super(read, running, home, decode)
    if M.karabiner_ready(read, running, home, decode) then
        return M.KARABINER, true
    end
    return M.OPTION, false
end

-- What the fallback costs, said once when tilemo starts without Karabiner.
M.FALLBACK_NOTICE = "Karabiner isn't running with tilemo's rules, so tilemo's keys"
    .. " are on Option. Option+Backspace, Option+arrows and Option accents"
    .. " now belong to tilemo. Install conf's Karabiner rules to get them back."

return M
