local t = require("t")
local keys = require("tide.keys")

local HOME = "/home/user"
local CONFIG = HOME .. "/.config/karabiner/karabiner.json"

-- Files hold Lua tables standing in for parsed JSON, so decode passes them
-- through.
local function env(files, procs)
    return function(p)
        return files[p]
    end, function(n)
        return procs[n] or false
    end
end

local function decode(x)
    return x
end

local function profiles(...)
    return { profiles = { ... } }
end

local function profile(selected, ...)
    return { selected = selected, complex_modifications = { rules = { ... } } }
end

t.test("with Karabiner running and tide's rule loaded, Super is Ctrl+Option+Command", function()
    local read, running = env({ [CONFIG] = profiles(profile(true, { description = "tide: Win to Super" })) },
        { ["Karabiner-Core-Service"] = true })
    local super, ok = keys.super(read, running, HOME, decode)
    t.eq(ok, true)
    t.eq(super, { "ctrl", "alt", "cmd" })
end)

t.test("a rule still described as timo's, from before the rename, counts too", function()
    local read, running = env({ [CONFIG] = profiles(profile(true, { description = "timo: Win to Super" })) },
        { ["Karabiner-Core-Service"] = true })
    t.eq(select(2, keys.super(read, running, HOME, decode)), true)
end)

t.test("a rule whose description only mentions tide later doesn't count", function()
    local read, running = env({ [CONFIG] = profiles(profile(true, { description = "not tide: x" })) },
        { ["Karabiner-Core-Service"] = true })
    t.eq(select(2, keys.super(read, running, HOME, decode)), false)
end)

t.test("without Karabiner's rule, Super falls back to Option", function()
    local read, running = env({ [CONFIG] = profiles(profile(true)) }, { ["Karabiner-Core-Service"] = true })
    local super, ok = keys.super(read, running, HOME, decode)
    t.eq(ok, false)
    t.eq(super, { "alt" })
end)

t.test("with the rule but Karabiner not running, Super falls back to Option", function()
    local read, running = env({ [CONFIG] = profiles(profile(true, { description = "tide: x" })) }, {})
    t.eq(select(2, keys.super(read, running, HOME, decode)), false)
end)

t.test("the rule only counts in the selected profile", function()
    local read, running = env({
        [CONFIG] = profiles(profile(false, { description = "tide: x" }), profile(true, { description = "other" })),
    }, { ["Karabiner-Core-Service"] = true })
    t.eq(select(2, keys.super(read, running, HOME, decode)), false)
end)

t.test("an unreadable config means no rule", function()
    local read, running = env({ [CONFIG] = "not json" }, { ["Karabiner-Core-Service"] = true })
    t.eq(select(2, keys.super(read, running, HOME, function()
        return nil
    end)), false)
end)

t.test("Shift adds to Super's modifiers", function()
    t.eq(keys.mods({ "alt" }, { key = "j", shift = true }), { "alt", "shift" })
    t.eq(keys.mods({ "alt" }, { key = "j" }), { "alt" })
end)

t.test("no two bindings share keys", function()
    local seen = {}
    for _, b in ipairs(keys.map) do
        local k = (b.shift and "shift+" or "") .. b.key
        t.eq(seen[k], nil, k)
        seen[k] = true
    end
end)

t.test("every binding names an action the window manager has", function()
    local wm = require("tide.wm")
    for _, b in ipairs(keys.map) do
        t.eq(type(wm.actions[b.action]), "function", b.action)
    end
end)

t.test("super_alone wants Super and nothing else, Shift and Fn included", function()
    t.eq(keys.super_alone({ "alt" }, { alt = true }), true)
    t.eq(keys.super_alone({ "alt" }, { alt = true, shift = true }), false)
    t.eq(keys.super_alone({ "alt" }, { alt = true, fn = true }), false)
    t.eq(keys.super_alone({ "alt" }, { alt = true, cmd = true }), false)
end)

t.test("super_held counts Super held as part of a bigger chord", function()
    t.eq(keys.super_held({ "alt" }, { alt = true, cmd = true }), true)
    t.eq(keys.super_held({ "alt" }, { alt = true, ctrl = true }), true)
    t.eq(keys.super_held({ "alt" }, { cmd = true }), false)
    t.eq(keys.super_held(keys.KARABINER, { ctrl = true, alt = true }), false)
    t.eq(keys.super_held(keys.KARABINER, { ctrl = true, alt = true, cmd = true, shift = true }), true)
end)

t.test("is_super wants exactly Super's modifiers, Shift aside", function()
    t.eq(keys.is_super({ "alt" }, { alt = true }), true)
    t.eq(keys.is_super({ "alt" }, { alt = true, shift = true }), true)
    t.eq(keys.is_super({ "alt" }, { alt = true, cmd = true }), false)
    t.eq(keys.is_super({ "alt" }, {}), false)
    t.eq(keys.is_super(keys.KARABINER, { ctrl = true, alt = true, cmd = true }), true)
    t.eq(keys.is_super(keys.KARABINER, { alt = true }), false)
end)

t.test("the Print keys take macOS's own screenshots, saved to Screenshot's folder", function()
    local kinds = {}
    for _, b in ipairs(keys.plain) do
        t.eq(b.key, "f13")
        t.eq(b.action, "screenshot")
        kinds[table.concat(b.mods, "+")] = b.arg
    end
    t.eq(kinds[""], "screen")
    t.eq(kinds["alt"], "window")
    t.eq(kinds["shift"], "region")
    local super_print
    for _, b in ipairs(keys.map) do
        if b.key == "f13" then
            super_print = b.arg
        end
    end
    t.eq(super_print, "region")
    for kind, k in pairs(keys.SCREENSHOT) do
        -- Without Ctrl, macOS saves the shot to a file; tide copies it
        -- to the clipboard from there (shots.lua).
        t.eq(table.concat(k.mods, "+"), "cmd+shift", kind)
    end
    t.eq(keys.SCREENSHOT.screen.key, "3")
    t.eq(keys.SCREENSHOT.region.key, "4")
    t.eq(keys.SCREENSHOT.window.key, "4")
    t.eq(keys.SCREENSHOT.window["then"], "space")
end)

t.test("with Super on Option, Alt+Print stays the window screenshot", function()
    local list, skipped = keys.bindings(keys.OPTION)
    local count = 0
    for _, b in ipairs(list) do
        if b.key == "f13" and #b.mods == 1 and b.mods[1] == "alt" then
            count = count + 1
            t.eq(b.arg, "window")
        end
    end
    t.eq(count, 1, "one binding on Alt+Print")
    t.eq(#skipped, 1)
    t.eq(skipped[1].chord, "alt+f13")
    t.eq(skipped[1].keys, "Super+Print")
    t.eq(skipped[1].does, "Screenshot of a region")
    t.eq(skipped[1].why, "the same keys as Alt+Print (Screenshot of the window)")
end)

-- The binding registered for `keys`, as the Shortcuts list names them.
local function labeled(list, label)
    for _, b in ipairs(list) do
        if b.keys == label then
            return b
        end
    end
end

t.test("each binding says its keys as they're printed on the keyboard, and what it does", function()
    local list = keys.bindings(keys.KARABINER)
    local want = {
        ["Super+J"] = "Focus down the stack",
        ["Super+Shift+K"] = "Move up the stack",
        ["Super+\\"] = "Grow the master",
        ["Super+/"] = "Shrink the master",
        ["Super+Backspace"] = "Close the window",
        ["Super+Insert"] = "Float or tile",
        ["Super+PgUp"] = "Previous workspace",
        ["Super+PgDn"] = "Next workspace",
        ["Super+Shift+PgUp"] = "Move the window to the previous workspace",
        ["Super+Shift+PgDn"] = "Move the window to the next workspace",
        ["Super+Left"] = "Select the window to the left",
        ["Super+Right"] = "Select the window to the right",
        ["Super+Shift+Left"] = "Move the window left",
        ["Super+Shift+Right"] = "Move the window right",
        ["Super+T"] = "Terminal",
        ["Super+Shift+G"] = "Browser, third profile",
        ["Super+Space"] = "The switcher, on Launch",
        ["Tap Super"] = "The switcher, on Launch",
        ["Super+3"] = "Workspace 3 on the bar",
        ["Super+Shift+3"] = "Send the window to workspace 3 on the bar",
        ["Super+0"] = "The last workspace on the bar",
        ["Super+Shift+0"] = "Send the window to the last workspace on the bar",
        ["Print"] = "Screenshot",
        ["Alt+Print"] = "Screenshot of the window",
        ["Shift+Print"] = "Screenshot of a region",
        ["Super+Print"] = "Screenshot of a region",
        ["Alt+Tab"] = "Swap with the master",
    }
    for label, does in pairs(want) do
        local b = labeled(list, label)
        t.eq(b and b.does, does, label)
    end
end)

t.test("every binding has a description, and no two the same keys", function()
    for _, super in ipairs({ keys.KARABINER, keys.OPTION }) do
        local seen = {}
        for _, b in ipairs((keys.bindings(super))) do
            t.eq(b.does ~= "", true, b.keys .. " has a description")
            t.eq(seen[b.keys], nil, b.keys .. " is listed once")
            seen[b.keys] = true
        end
    end
end)

t.test("Alt+Tab is listed only with Karabiner, which makes it", function()
    t.eq(labeled((keys.bindings(keys.KARABINER)), "Alt+Tab") ~= nil, true)
    t.eq(labeled((keys.bindings(keys.OPTION)), "Alt+Tab"), nil)
end)

t.test("an action nothing describes says so with an empty description", function()
    t.eq(keys.does({ action = "nothing such" }), "")
    t.eq(keys.does({ action = "close", does = "Its own" }), "Its own")
end)

t.test("the Shortcuts list is what registered, in order, then resize mode's keys", function()
    local list, skipped = keys.bindings(keys.OPTION)
    local s = keys.shortcuts({ list[1], list[2] }, skipped)
    t.eq(s.binds[1], { keys = "Print", does = "Screenshot", submap = "" })
    t.eq(s.binds[2], { keys = "Alt+Print", does = "Screenshot of the window", submap = "" })
    t.eq(s.binds[3], { keys = "H", does = "Narrower", submap = "Resize mode" })
    t.eq(s.binds[#s.binds], { keys = "Return", does = "Leave resize mode", submap = "Resize mode" })
    t.eq(#s.binds, 2 + #keys.resize + #keys.resize_exit)
    t.eq(s.failed, { {
        keys = "Super+Print",
        does = "Screenshot of a region",
        why = "the same keys as Alt+Print (Screenshot of the window)",
    } })
end)

t.test("doctor names each key that didn't register, and says nothing with none", function()
    t.eq(keys.failed_notice({}), nil)
    t.eq(keys.failed_notice({ { keys = "Super+T", does = "Terminal", why = "macOS refused it" } }),
        "These keys didn't register, so they do nothing: Super+T (Terminal): macOS refused it."
            .. " The settings window's Keyboard shortcuts list them.")
end)

t.test("with Karabiner, every binding gets its own chord", function()
    local list, skipped = keys.bindings(keys.KARABINER)
    t.eq(#skipped, 0)
    t.eq(#list, #keys.map + #keys.plain + #keys.overview + #keys.karabiner_only)
end)

t.test("Ctrl+Up and Ctrl+Down open the overview, in place of Mission Control and App Exposé", function()
    for _, super in ipairs({ keys.KARABINER, keys.OPTION }) do
        local list, skipped = keys.bindings(super)
        local by = {}
        for _, b in ipairs(list) do
            if b.action == "overview" then
                by[b.keys] = { b.mods, b.key, b.arg, b.does }
            end
        end
        t.eq(by["Ctrl+Up"], { { "ctrl" }, "up", "all", "Overview of every workspace" })
        t.eq(by["Ctrl+Down"], { { "ctrl" }, "down", "current", "Overview of this workspace" })
        for _, s in ipairs(skipped) do
            t.eq(s.keys:match("^Ctrl%+") == nil, true, s.keys)
        end
    end
    t.eq(type(require("tide.wm").actions.overview), "function")
end)

t.test("Super+W opens a terminal on the workstation; the VM's has no key", function()
    local by = {}
    for _, b in ipairs(keys.map) do
        if b.action == "app" and not b.shift then
            by[b.key] = b.arg.run
        end
    end
    t.eq(by.w, "terminal_on_workstation")
    for _, b in ipairs(keys.map) do
        t.eq(type(b.arg) == "table" and b.arg.run == "terminal_on_vm", false, "a key runs terminal_on_vm")
    end
end)

t.test("a screenshot action asks the adapter for that kind", function()
    local a = require("fake").new()
    local wm = require("tide.wm").new(a, {})
    wm:act("screenshot", "window")
    wm:act("screenshot", "screen")
    t.eq(table.concat(a.shots, " "), "window screen")
end)

t.test('Super+Home goes to "in", Super+1…9 and Super+Shift+1…9 count along the bar, and 0 is the last', function()
    local home
    local nth, send = {}, {}
    for _, b in ipairs(keys.map) do
        if b.key == "home" then
            home = b.action
        end
        if b.key:match("^%d$") then
            local into = b.shift and send or nth
            into[tonumber(b.key)] = b
        end
    end
    t.eq(home, "home")
    for i = 0, 9 do
        t.eq(nth[i] and nth[i].action, "nth", "Super+" .. i)
        t.eq(nth[i] and nth[i].arg, i, "Super+" .. i)
        t.eq(send[i] and send[i].action, "send_nth", "Super+Shift+" .. i)
        t.eq(send[i] and send[i].arg, i, "Super+Shift+" .. i)
    end
end)

t.test("the switcher's keys open it on their own tabs, and Super+Tab, End and Return have their new jobs", function()
    local by = {}
    for _, b in ipairs(keys.map) do
        if not b.shift then
            by[b.key] = { b.action, b.arg }
        end
    end
    t.eq(by.space, { "launcher", "launch" })
    t.eq(by.f20, { "launcher", "launch" }, "Karabiner's lone Super tap opens the launcher, as on tide and tileco")
    t.eq(by.a, { "launcher", "attention" })
    t.eq(by.tab, { "flip" })
    t.eq(by["end"], { "last" })
    t.eq(by["return"], { "go_to" })
    t.eq(by.delete, { "close" })
    t.eq(by.z, { "minimize" })
    t.eq(by.home, { "home" })
end)

t.test("Super+Shift+Return moves the window to a workspace, Super+Return's old job", function()
    local shifted = {}
    for _, b in ipairs(keys.map) do
        if b.shift then
            shifted[b.key] = b.action
        end
    end
    t.eq(shifted["return"], "move_to")
end)

t.test("Super+V opens the picker on Clipboard; Super+C is Chat and Super+Shift+C Calendar", function()
    local by, shifted = {}, {}
    for _, b in ipairs(keys.map) do
        (b.shift and shifted or by)[b.key] = b
    end
    t.eq({ by.v.action, by.v.arg }, { "picker", "clipboard" })
    t.eq(by.h.arg.run, "home")
    t.eq(by.c.arg.run, "google-chat")
    t.eq(shifted.c.arg.run, "google-calendar")
    t.eq({ shifted.v.action, shifted.v.arg }, { "picker", "fill" }, "Super+Shift+V is the picker's Fill tab")
    t.eq({ by[";"].action, by[";"].arg, by[";"].does }, { "picker", "characters", "Emoji and characters" },
        "Super+; is its Characters tab")
end)

t.test("the picker key asks the window manager to open the picker", function()
    local wm = require("tide.wm")
    local asked
    wm.actions.picker({ open_picker = function(tab) asked = tab end }, "clipboard")
    t.eq(asked, "clipboard")
    wm.actions.picker({}, "clipboard") -- before the picker exists: nothing, no error
end)

t.test("Alt+Tab swaps with the master only with Karabiner, which makes it from physical Alt+Tab", function()
    local function find(list)
        for _, b in ipairs(list) do
            if b.key == "tab" and b.action == "swap_master" then
                return b
            end
        end
    end
    local b = find((keys.bindings(keys.KARABINER)))
    t.eq(b.mods, { "ctrl", "alt", "shift" })
    t.eq(find((keys.bindings(keys.OPTION))), nil, "not Ctrl+Tab, every app's next tab")
end)

-- An installed tide rule, as karabiner.json holds it: the Win key's
-- manipulator, with what its lone tap sends, Alt+Tab's if `alt_tab`, the
-- letters a and z, unless `no_z`, and Backspace sent as F19, unless
-- `old_backspace` keeps it Backspace.
local function rule(tap, alt_tab, no_z, old_backspace)
    local m = {
        { from = { key_code = "left_command", modifiers = { optional = { "any" } } }, to = { { key_code = "left_command" } },
            to_if_alone = { { key_code = tap, modifiers = { "left_option", "left_command", "left_control" } } } },
        { from = { key_code = "a", modifiers = { mandatory = { "left_command" }, optional = { "shift" } } },
            to = { { key_code = "a", modifiers = { "left_option", "left_command", "left_control" } } } },
    }
    if not no_z then
        m[#m + 1] = { from = { key_code = "z", modifiers = { mandatory = { "left_command" }, optional = { "shift" } } },
            to = { { key_code = "z", modifiers = { "left_option", "left_command", "left_control" } } } }
    end
    if alt_tab then
        m[#m + 1] = { from = { key_code = "tab", modifiers = { mandatory = { "left_option" } } },
            to = { { key_code = "tab", modifiers = { "shift", "left_command", "left_option" } } } }
    end
    m[#m + 1] = { from = { key_code = "delete_or_backspace", modifiers = { mandatory = { "left_command" }, optional = { "shift" } } },
        to = { { key_code = old_backspace and "delete_or_backspace" or "f19", modifiers = { "left_option", "left_command", "left_control" } } } }
    return { description = "tide: Win+key", manipulators = m }
end

t.test("an up-to-date tide rule has nothing missing", function()
    local read = env({ [CONFIG] = profiles(profile(true, rule("f20", true))) }, {})
    t.eq(keys.rule_gaps(read, HOME, decode), {})
end)

t.test("a rule enabled before conf's update is missing Alt+Tab and the Super tap, and says how to fix it", function()
    local read = env({ [CONFIG] = profiles(profile(true, rule("spacebar", false))) }, {})
    local gaps = keys.rule_gaps(read, HOME, decode)
    t.eq(gaps, { "Alt+Tab (swap with the master)", "the lone Super tap (the launcher)" })
    local notice = keys.gaps_notice(gaps)
    t.eq(notice:find("Alt+Tab (swap with the master) and the lone Super tap (the launcher) don't work", 1, true) ~= nil, true, notice)
    t.eq(notice:find("git pull in your conf checkout and run confinst", 1, true) ~= nil, true, notice)
    t.eq(notice:find('brings Karabiner\'s copy of the "tide:" rule up to date', 1, true) ~= nil, true, notice)
    read = env({ [CONFIG] = profiles(profile(true, rule("f20", false))) }, {})
    gaps = keys.rule_gaps(read, HOME, decode)
    t.eq(gaps, { "Alt+Tab (swap with the master)" })
    t.eq(keys.gaps_notice(gaps):find("doesn't work", 1, true) ~= nil, true)
end)

t.test("no rule, or no config, has no gaps to report: the fallback notice covers it", function()
    t.eq(keys.rule_gaps(env({}, {}), HOME, decode), {})
    t.eq(keys.rule_gaps(env({ [CONFIG] = profiles(profile(true)) }, {}), HOME, decode), {})
    -- Only the selected profile's rule counts.
    local read = env({ [CONFIG] = profiles(profile(false, rule("f20", true)), profile(true, rule("spacebar", false))) }, {})
    t.eq(#keys.rule_gaps(read, HOME, decode), 2)
end)

t.test("Alt+Tab's manipulator must send what tide binds", function()
    local r = rule("f20", true)
    r.manipulators[4].to[1].modifiers = { "left_control" } -- the old Cmd+Tab
    local read = env({ [CONFIG] = profiles(profile(true, r)) }, {})
    t.eq(keys.rule_gaps(read, HOME, decode), { "Alt+Tab (swap with the master)" })
end)

t.test("a rule without Win+Z is missing Super+Z, so minimize has no key", function()
    local read = env({ [CONFIG] = profiles(profile(true, rule("f20", true, true))) }, {})
    local gaps = keys.rule_gaps(read, HOME, decode)
    t.eq(gaps, { "Super+Z (minimize)" })
    t.eq(keys.gaps_notice(gaps):find("Super+Z (minimize) doesn't work", 1, true) ~= nil, true)
end)

t.test("a rule that still sends Win+Backspace as Backspace is missing Super+Backspace", function()
    local read = env({ [CONFIG] = profiles(profile(true, rule("f20", true, false, true))) }, {})
    local gaps = keys.rule_gaps(read, HOME, decode)
    t.eq(gaps, { "Super+Backspace (close the window)" })
end)

-- Some Macs take Ctrl+Option+Command+Backspace before Hammerspoon sees it,
-- so with Karabiner close is bound on the F19 the rule sends instead, and
-- still listed as Super+Backspace. With Option as Super it stays on
-- Backspace, which nothing takes there.
t.test("Super+Backspace closes the window, bound on F19 with Karabiner", function()
    local function close(list)
        local out = {}
        for _, b in ipairs(list) do
            if b.action == "close" then
                out[#out + 1] = { b.mods, b.key, b.keys }
            end
        end
        return out
    end
    t.eq(close((keys.bindings(keys.KARABINER))), { { { "ctrl", "alt", "cmd" }, "f19", "Super+Backspace" } })
    t.eq(close((keys.bindings(keys.OPTION))), { { { "alt" }, "delete", "Super+Backspace" } })
end)

t.done("keys")
