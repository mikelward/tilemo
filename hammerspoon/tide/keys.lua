-- tide's key map (SPEC.md §7.2), and which modifiers stand for Super.
--
-- With Karabiner's rule loaded, physical Win+key arrives as
-- Ctrl+Option+Command+key, so Option keeps its text gestures. Without it,
-- Super falls back to plain Option: every key still works, but Option's own
-- meanings (word delete, word moves, accents) go to tide (SPEC.md §7.1).

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
    -- Super+Return goes to a workspace by name, Super+Shift+Return moves
    -- the window to one; Alt+Tab swaps with the master (M.karabiner_only,
    -- SPEC.md §7.2).
    { key = "return", action = "go_to" },
    { key = "return", shift = true, action = "move_to" },
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
    -- tide's Super+Alt+F, which Super can't have here: Super's chord holds
    -- Option already (SPEC.md §7.2). The Floating settings, filled in for
    -- the focused window.
    { key = "i", shift = true, action = "float_rule" },
    -- With Karabiner's rule, physical Win+Backspace arrives as Super+F19:
    -- on some Macs something below Hammerspoon takes the chord on
    -- Backspace itself, and a chord on a key no keyboard here has gets
    -- through, as the Super tap's F20 does (SPEC.md §7.2).
    { key = "delete", karabiner_key = "f19", action = "close" },
    -- Super+Z, not Super+Delete, which a PC keyboard may send as Backspace
    -- (SPEC.md §6.7).
    { key = "z", action = "minimize" },
    { key = "r", shift = true, action = "resize_mode" },
    -- Left and Right go between windows, across displays at the edge;
    -- PgUp and PgDn between workspaces (SPEC.md §7.2).
    { key = "left", action = "select", arg = -1 },
    { key = "right", action = "select", arg = 1 },
    { key = "left", shift = true, action = "move_side", arg = -1 },
    { key = "right", shift = true, action = "move_side", arg = 1 },
    { key = "pageup", action = "step", arg = -1 },
    { key = "pagedown", action = "step", arg = 1 },
    { key = "pageup", shift = true, action = "move_ws", arg = -1 },
    { key = "pagedown", shift = true, action = "move_ws", arg = 1 },
}

-- App keys (tide's, conf hyprland.lua). Each brings the app's window, and
-- its workspace, forward; with none, it launches the app. `bundle` finds
-- the app's windows and launches it by bundle ID; `run` is one of tide's
-- helpers, run through runenv for the login environment (SPEC.md §7.2).
-- `new` opens a new window every time instead, as tide's terminal key does.
-- `home_app` marks one of the home workspace's apps, which launches from home without
-- asking for a workspace (SPEC.md §7.2).
-- `does` is what the settings window's Shortcuts list says it does, in
-- conf's words for the same key.
M.APPS = {
    { key = "t", does = "Terminal", spec = { bundle = "net.kovidgoyal.kitty", new = true } },
    { key = "w", does = "Terminal on the workstation", spec = { run = "terminal_on_workstation" } },
    { key = "g", does = "Browser", spec = { run = "browser1" } },
    { key = "g", shift = true, does = "Browser, third profile", spec = { run = "browser3" } },
    { key = "f", does = "Browser, second profile", spec = { run = "browser2" } },
    { key = "c", does = "Google Chat", spec = { run = "google-chat", home_app = true } },
    { key = "c", shift = true, does = "Google Calendar", spec = { run = "google-calendar", home_app = true } },
    { key = "h", does = "Home folder", spec = { run = "home" } },
    { key = "i", does = "IRC", spec = { run = "irc" } },
    { key = "m", does = "Google Meet", spec = { run = "google-meet" } },
    { key = "n", does = "Notepad", spec = { run = "notepad" } },
    { key = "r", does = "Remote desktop", spec = { run = "remote-desktop" } },
    { key = "y", does = "YouTube Music", spec = { run = "youtube-music", home_app = true } },
    { key = "e", does = "Files", spec = { run = "kitty -e yazi" } },
}
for _, a in ipairs(M.APPS) do
    M.map[#M.map + 1] = { key = a.key, shift = a.shift, action = "app", arg = a.spec, does = a.does }
end

-- tide's session keys: lock, and log out.
M.map[#M.map + 1] = { key = "l", action = "lock" }
M.map[#M.map + 1] = { key = "e", shift = true, action = "logout" }

-- The switcher, each key on its own tab (SPEC.md §9). Karabiner's rule
-- sends a lone Super tap as Super+F20, which opens the launcher, as
-- Super+Space does and tide's and tileco's taps do.
M.map[#M.map + 1] = { key = "space", action = "launcher", arg = "launch" }
M.map[#M.map + 1] = { key = "f20", action = "launcher", arg = "launch" }
M.map[#M.map + 1] = { key = "a", action = "launcher", arg = "attention" }
M.map[#M.map + 1] = { key = "space", shift = true, action = "dashboard" }
-- Super+V: the picker, on its Clipboard tab (SPEC.md §7.2), V as in
-- paste: Return pastes the row where you were. Terminal on the VM, which
-- it was, has no key now; the switcher finds it.
M.map[#M.map + 1] = { key = "v", action = "picker", arg = "clipboard" }
-- Super+Shift+V: its Fill tab, your snippets and Bitwarden's logins, one
-- row per field; Return types it where you were (SPEC.md §9.1).
M.map[#M.map + 1] = { key = "v", shift = true, action = "picker", arg = "fill", does = "Snippets and passwords" }
-- Super+;: its Characters tab, emoji and symbols by name, as tide's. Not
-- Windows's Super+., which is the next layout here.
M.map[#M.map + 1] = { key = ";", action = "picker", arg = "characters", does = "Emoji and characters" }
-- Super+Tab flips between home and the workspace you used last, and
-- Super+End goes to the last one other than home (SPEC.md §7.2).
M.map[#M.map + 1] = { key = "tab", action = "flip" }
M.map[#M.map + 1] = { key = "end", action = "last" }
-- tide's mic-mute key: the microphone, everywhere (SPEC.md §7.2).
M.map[#M.map + 1] = { key = "m", shift = true, action = "mic_mute" }
-- Super+S: keep awake; Super+P: presenter mode, Do Not Disturb and keep
-- awake together (SPEC.md §10).
M.map[#M.map + 1] = { key = "s", action = "keep_awake" }
M.map[#M.map + 1] = { key = "p", action = "presenter" }
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

-- Mission Control's and App Exposé's own keys, plain Control, not Super:
-- the overview, of every workspace or this one (SPEC.md §6.9). macOS
-- holds them until setup-macos turns off symbolic hotkeys 32 and 33, and
-- until then they fail to register without a word (SPEC.md §7.3).
M.overview = {
    { mods = { "ctrl" }, key = "up", action = "overview", arg = "all" },
    { mods = { "ctrl" }, key = "down", action = "overview", arg = "current" },
}

-- macOS's own screenshot keys, so tide needs no Screen Recording
-- permission of its own (SPEC.md §10). They save the shot to Screenshot's
-- folder, and tide copies it to the clipboard from there (shots.lua). A
-- window is the region picker with Space pressed, as macOS has no key for
-- it.
M.SCREENSHOT = {
    screen = { mods = { "cmd", "shift" }, key = "3" },
    region = { mods = { "cmd", "shift" }, key = "4" },
    window = { mods = { "cmd", "shift" }, key = "4", ["then"] = "space" },
}

-- Super+1…9: the Nth workspace in bar order, so Super+1 is home, as
-- Super+Home is; Super+Shift+1…9 sends the window there (SPEC.md §7.2).
-- Super+0 (arg 0) is the last workspace on the bar.
for i = 0, 9 do
    M.map[#M.map + 1] = { key = tostring(i), action = "nth", arg = i }
    M.map[#M.map + 1] = { key = tostring(i), shift = true, action = "send_nth", arg = i }
end

-- Keys bound only with Karabiner's rule, which makes them from physical
-- keys: Alt+Tab arrives as Control+Option+Shift+Tab, a combination nothing
-- else uses. Without the rule, physical Alt+Tab is Ctrl+Tab, every app's
-- next tab, so swap with the master has no key (SPEC.md §7.2).
M.karabiner_only = {
    { mods = { "ctrl", "alt", "shift" }, key = "tab", action = "swap_master", label = "Alt+Tab" },
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

-- What each action does, for the settings window's Shortcuts list (SPEC.md
-- §15), in conf's words for tide's same key: a string, or a function of
-- the binding's `arg`. An app key says its own (M.APPS' `does`).
local function by_sign(less, more)
    return function(arg)
        return (arg or 0) < 0 and less or more
    end
end
local SCREENSHOTS = { screen = "Screenshot", window = "Screenshot of the window", region = "Screenshot of a region" }
local TABS = {
    launch = "The switcher, on Launch",
    workspaces = "The switcher, on Workspaces",
    attention = "The switcher, on Attention",
}
M.DOES = {
    focus = by_sign("Focus up the stack", "Focus down the stack"),
    move = by_sign("Move up the stack", "Move down the stack"),
    go_to = "Go to a workspace, by name",
    move_to = "Move the window to a workspace, by name",
    mfact = by_sign("Shrink the master", "Grow the master"),
    nmaster = by_sign("Remove a master", "Add a master"),
    cycle = by_sign("Previous layout", "Next layout"),
    monocle = "Monocle",
    maximize = "Maximize",
    fullscreen = "Full screen",
    restore = "Restore",
    toggle_float = "Float or tile",
    float_rule = "Float rules for the window",
    close = "Close the window",
    minimize = "Minimize the window",
    resize_mode = "Resize mode",
    step = by_sign("Previous workspace", "Next workspace"),
    select = by_sign("Select the window to the left", "Select the window to the right"),
    move_side = by_sign("Move the window left", "Move the window right"),
    move_ws = by_sign("Move the window to the previous workspace", "Move the window to the next workspace"),
    lock = "Lock",
    logout = "Log out",
    launcher = function(arg)
        return TABS[arg]
    end,
    dashboard = "Dashboard",
    overview = function(arg)
        return arg == "current" and "Overview of this workspace" or "Overview of every workspace"
    end,
    picker = "Clipboard and characters",
    flip = "Home, or the workspace used last",
    last = "The workspace used last, other than home",
    mic_mute = "Mute the microphone",
    keep_awake = "Keep awake on or off",
    presenter = "Presenter mode",
    home = "Home",
    screenshot = function(arg)
        return SCREENSHOTS[arg]
    end,
    nth = function(arg)
        if arg == 0 then
            return "The last workspace on the bar"
        end
        return "Workspace " .. tostring(arg) .. " on the bar"
    end,
    send_nth = function(arg)
        if arg == 0 then
            return "Send the window to the last workspace on the bar"
        end
        return "Send the window to workspace " .. tostring(arg) .. " on the bar"
    end,
    swap_master = "Swap with the master",
}

-- What a binding does, or "" when nothing says, which the list shows as
-- "no description", as tide's does.
function M.does(b)
    if type(b.does) == "string" then
        return b.does
    end
    local d = M.DOES[b.action]
    if type(d) == "function" then
        d = d(b.arg)
    end
    return type(d) == "string" and d or ""
end

-- Keys whose Hammerspoon names aren't what's on the key. A Mac's delete
-- is Backspace, a PC keyboard's Insert arrives as Help and its Print as
-- F13 (SPEC.md §7.2).
local KEY_NAMES = {
    ["return"] = "Return", space = "Space", tab = "Tab", escape = "Escape", delete = "Backspace",
    forwarddelete = "Delete", help = "Insert", pageup = "PgUp", pagedown = "PgDn", home = "Home",
    ["end"] = "End", up = "Up", down = "Down", left = "Left", right = "Right", f13 = "Print",
}
local MOD_NAMES = { { "cmd", "Cmd" }, { "ctrl", "Ctrl" }, { "alt", "Alt" }, { "shift", "Shift" } }

-- A key as it's printed on the keyboard: "J" for j, "PgUp" for pageup.
function M.key_label(key)
    if KEY_NAMES[key] then
        return KEY_NAMES[key]
    end
    if #key == 1 then
        return key:upper()
    end
    return key:sub(1, 1):upper() .. key:sub(2)
end

-- A binding's keys as tide shows them, "Super+Shift+J": Super for a key
-- from M.map, whichever modifiers stand for it, and a plain key's own
-- modifiers. The Super tap is Super+F20 only on the way in (SPEC.md §7.2).
function M.keys_label(b, mods, super)
    if b.label then
        return b.label
    end
    local parts = {}
    if super then
        if b.key == "f20" and not b.shift then
            return "Tap Super"
        end
        parts[1] = "Super"
        if b.shift then
            parts[2] = "Shift"
        end
    else
        local held = {}
        for _, m in ipairs(mods) do
            held[m] = true
        end
        for _, m in ipairs(MOD_NAMES) do
            if held[m[1]] then
                parts[#parts + 1] = m[2]
            end
        end
    end
    parts[#parts + 1] = M.key_label(b.key)
    return table.concat(parts, "+")
end

-- Every binding to register for this Super, each with its modifiers, and
-- its `keys` and `does` for the Shortcuts list. The plain Print keys come
-- first, and a later binding on a chord already taken is left out, in
-- `skipped` as { chord, keys, does, why }: with Super on Option, Super+Print
-- is Alt+Print, which stays tide's window screenshot (Shift+Print still
-- takes a region). The overview's Ctrl+Up and Ctrl+Down come next. With
-- Karabiner's Super, its own combinations come too.
function M.bindings(super)
    local out, seen, skipped = {}, {}, {}
    local function add(mods, b, is_super)
        local sorted = {}
        for i, m in ipairs(mods) do
            sorted[i] = m
        end
        table.sort(sorted)
        local chord = table.concat(sorted, "+") .. "+" .. b.key
        local label, does = M.keys_label(b, mods, is_super), M.does(b)
        if seen[chord] then
            skipped[#skipped + 1] = {
                chord = chord,
                keys = label,
                does = does,
                why = "the same keys as " .. seen[chord].keys .. " (" .. seen[chord].does .. ")",
            }
            return
        end
        seen[chord] = { keys = label, does = does ~= "" and does or "no description" }
        out[#out + 1] = {
            mods = mods, key = b.key, action = b.action, arg = b.arg, repeating = b.repeating,
            keys = label, does = does,
        }
    end
    for _, b in ipairs(M.plain) do
        add(b.mods, b, false)
    end
    for _, b in ipairs(M.overview) do
        add(b.mods, b, false)
    end
    for _, b in ipairs(M.map) do
        local mods = M.mods(super, b)
        if super == M.KARABINER and b.karabiner_key then
            -- Shown as the key you press, bound as the one Karabiner sends.
            local sent = {}
            for k, v in pairs(b) do
                sent[k] = v
            end
            sent.key, sent.label = b.karabiner_key, M.keys_label(b, mods, true)
            add(mods, sent, true)
        else
            add(mods, b, true)
        end
    end
    if super == M.KARABINER then
        for _, b in ipairs(M.karabiner_only) do
            add(b.mods, b, false)
        end
    end
    return out, skipped
end

-- What resize mode's keys do, for the Shortcuts list.
local function resize_does(d)
    if d[1] < 0 then
        return "Narrower"
    elseif d[1] > 0 then
        return "Wider"
    elseif d[2] < 0 then
        return "Shorter"
    end
    return "Taller"
end

-- The settings window's Shortcuts list (SPEC.md §15), as tide's Keyboard
-- page has its own (tide SPEC.md §16): `bound`, the bindings that
-- registered, in M.bindings' order, then resize mode's, each as { keys,
-- does, submap }; and `failed`, each a key that didn't, as { keys, does,
-- why }.
function M.shortcuts(bound, failed)
    local binds = {}
    for _, b in ipairs(bound) do
        binds[#binds + 1] = { keys = b.keys, does = b.does, submap = "" }
    end
    for _, b in ipairs(M.resize) do
        binds[#binds + 1] = { keys = M.key_label(b.key), does = resize_does(b.d), submap = "Resize mode" }
    end
    for _, k in ipairs(M.resize_exit) do
        binds[#binds + 1] = { keys = M.key_label(k), does = "Leave resize mode", submap = "Resize mode" }
    end
    local out = {}
    for i, f in ipairs(failed or {}) do
        out[i] = { keys = f.keys, does = f.does, why = f.why }
    end
    return { binds = binds, failed = out }
end

-- tide doctor's line for the keys that didn't register, or nil.
function M.failed_notice(failed)
    if #(failed or {}) == 0 then
        return nil
    end
    local parts = {}
    for i, f in ipairs(failed) do
        parts[i] = f.keys .. (f.does ~= "" and " (" .. f.does .. ")" or "") .. ": " .. f.why
    end
    return "These keys didn't register, so they do nothing: " .. table.concat(parts, "; ")
        .. ". The settings window's Keyboard shortcuts list them."
end

-- The description prefixes that mark tide's Karabiner rule: its own, and
-- the ones it had as tilemo and timo, so rules installed before a rename
-- still count.
M.RULE_PREFIXES = { "tide:", "tilemo:", "timo:" }

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

-- tide's rule in the selected Karabiner profile, if it has one. Each
-- profile keeps its own rules, so a rule left in another profile doesn't
-- count.
local function our_rule(config)
    for _, p in ipairs(type(config) == "table" and config.profiles or {}) do
        if p.selected then
            local cm = p.complex_modifications or {}
            for _, r in ipairs(cm.rules or {}) do
                if is_our_rule(r.description) then
                    return r
                end
            end
            return nil
        end
    end
    return nil
end

local function profile_has_rule(config)
    return our_rule(config) ~= nil
end

local function same_set(list, want)
    if type(list) ~= "table" or #list ~= #want then
        return false
    end
    local have = {}
    for _, v in ipairs(list) do
        have[v] = true
    end
    for _, v in ipairs(want) do
        if not have[v] then
            return false
        end
    end
    return true
end

-- What conf's tide rule does that an older copy of it didn't, each with
-- what's lost without it. Karabiner runs the copy it made when the rule was
-- enabled, so pulling conf changes nothing until the rule is removed and
-- added again.
M.RULE_FEATURES = {
    {
        what = "Alt+Tab (swap with the master)",
        -- Physical Alt+Tab, sent as Ctrl+Option+Shift+Tab (keys.karabiner_only).
        has = function(m)
            local f, t = m.from or {}, (m.to or {})[1] or {}
            return f.key_code == "tab" and same_set((f.modifiers or {}).mandatory, { "left_option" })
                and t.key_code == "tab" and same_set(t.modifiers, { "left_option", "left_command", "shift" })
        end,
    },
    {
        what = "the lone Super tap (the launcher)",
        -- The tap, sent as Super+F20.
        has = function(m)
            local a = (m.to_if_alone or {})[1] or {}
            return (m.from or {}).key_code == "left_command" and a.key_code == "f20"
        end,
    },
    {
        what = "Super+Backspace (close the window)",
        -- Physical Win+Backspace, sent as Ctrl+Option+Command+F19 (M.map).
        has = function(m)
            local f, t = m.from or {}, (m.to or {})[1] or {}
            return f.key_code == "delete_or_backspace" and same_set((f.modifiers or {}).mandatory, { "left_command" })
                and t.key_code == "f19" and same_set(t.modifiers, { "left_option", "left_command", "left_control" })
        end,
    },
    {
        what = "Super+Z (minimize)",
        -- Physical Win+Z, sent as Ctrl+Option+Command+Z.
        has = function(m)
            local f, t = m.from or {}, (m.to or {})[1] or {}
            return f.key_code == "z" and same_set((f.modifiers or {}).mandatory, { "left_command" })
                and t.key_code == "z" and same_set(t.modifiers, { "left_option", "left_command", "left_control" })
        end,
    },
}

-- What the installed tide rule is missing, as M.RULE_FEATURES' `what`s,
-- in order; empty if it's up to date or there's no rule (karabiner_ready
-- says that). Read from karabiner.json, as karabiner_ready reads it.
function M.rule_gaps(read, home, decode)
    local text = read(home .. "/.config/karabiner/karabiner.json")
    local rule = text and our_rule(decode(text))
    local out = {}
    if not rule then
        return out
    end
    for _, feature in ipairs(M.RULE_FEATURES) do
        local found = false
        for _, m in ipairs(rule.manipulators or {}) do
            found = found or feature.has(m)
        end
        if not found then
            out[#out + 1] = feature.what
        end
    end
    return out
end

-- What a stale rule costs, said once per change, in a notification and by
-- tide.doctor(). tide brings Karabiner's copy up to date with conf's
-- file itself (karabiner.lua), so a copy still missing something means the
-- file is out of date too.
function M.gaps_notice(gaps)
    return "tide's Karabiner rule is out of date, so " .. table.concat(gaps, " and ")
        .. (#gaps == 1 and " doesn't" or " don't") .. " work. Update conf: git pull in your conf"
        .. " checkout and run confinst, and tide brings Karabiner's copy of the \"" .. M.RULE_PREFIXES[1]
        .. "\" rule up to date."
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

-- Whether Karabiner is running with tide's rule loaded. `read` returns a
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

-- What the fallback costs, said once when tide starts without Karabiner.
M.FALLBACK_NOTICE = "Karabiner isn't running with tide's rules, so tide's keys"
    .. " are on Option. Option+Backspace, Option+arrows and Option accents"
    .. " now belong to tide. Install conf's Karabiner rules to get them back."

return M
