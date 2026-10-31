local t = require("t")
local keys = require("tilemo.keys")

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

t.test("with Karabiner running and tilemo's rule loaded, Super is Ctrl+Option+Command", function()
    local read, running = env({ [CONFIG] = profiles(profile(true, { description = "tilemo: Win to Super" })) },
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

t.test("a rule whose description only mentions tilemo later doesn't count", function()
    local read, running = env({ [CONFIG] = profiles(profile(true, { description = "not tilemo: x" })) },
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
    local read, running = env({ [CONFIG] = profiles(profile(true, { description = "tilemo: x" })) }, {})
    t.eq(select(2, keys.super(read, running, HOME, decode)), false)
end)

t.test("the rule only counts in the selected profile", function()
    local read, running = env({
        [CONFIG] = profiles(profile(false, { description = "tilemo: x" }), profile(true, { description = "other" })),
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
    local wm = require("tilemo.wm")
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
        -- Without Ctrl, macOS saves the shot to a file; tilemo copies it
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
    t.eq(table.concat(skipped, " "), "alt+f13")
end)

t.test("with Karabiner, every binding gets its own chord", function()
    local list, skipped = keys.bindings(keys.KARABINER)
    t.eq(#skipped, 0)
    t.eq(#list, #keys.map + #keys.plain + #keys.karabiner_only)
end)

t.test("Super+W and Super+V open terminals on the workstation and the VM", function()
    local by = {}
    for _, b in ipairs(keys.map) do
        if b.action == "app" and not b.shift then
            by[b.key] = b.arg.run
        end
    end
    t.eq(by.w, "terminal_on_workstation")
    t.eq(by.v, "terminal_on_vm")
end)

t.test("a screenshot action asks the adapter for that kind", function()
    local a = require("fake").new()
    local wm = require("tilemo.wm").new(a, {})
    wm:act("screenshot", "window")
    wm:act("screenshot", "screen")
    t.eq(table.concat(a.shots, " "), "window screen")
end)

t.test('Super+Home goes to "in", and Super+1…9 and Super+Shift+1…9 count along the bar', function()
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
    for i = 1, 9 do
        t.eq(nth[i] and nth[i].action, "nth", "Super+" .. i)
        t.eq(nth[i] and nth[i].arg, i, "Super+" .. i)
        t.eq(send[i] and send[i].action, "send_nth", "Super+Shift+" .. i)
        t.eq(send[i] and send[i].arg, i, "Super+Shift+" .. i)
    end
    t.eq(nth[0], nil, "no Super+0")
end)

t.test("the switcher's keys open it on their own tabs, and Super+Tab, End and Return have their new jobs", function()
    local by = {}
    for _, b in ipairs(keys.map) do
        if not b.shift then
            by[b.key] = { b.action, b.arg }
        end
    end
    t.eq(by.space, { "launcher", "launch" })
    t.eq(by.f20, { "launcher", "workspaces" }, "Karabiner's lone Super tap")
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

t.test("Super+C opens the picker on Clipboard; Calendar has no key; Super+H and Super+Shift+C stay", function()
    local by, shifted = {}, {}
    for _, b in ipairs(keys.map) do
        (b.shift and shifted or by)[b.key] = b
    end
    t.eq({ by.c.action, by.c.arg }, { "picker", "clipboard" })
    t.eq(by.h.arg.run, "home")
    t.eq(shifted.c.arg.run, "google-chat")
    for _, b in ipairs(keys.map) do
        t.eq(type(b.arg) == "table" and b.arg.run == "google-calendar", false, "a key runs google-calendar")
    end
end)

t.test("the picker key asks the window manager to open the picker", function()
    local wm = require("tilemo.wm")
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

-- An installed tilemo rule, as karabiner.json holds it: the Win key's
-- manipulator, with what its lone tap sends, Alt+Tab's if `alt_tab`, and
-- the letters a and z, unless `no_z`.
local function rule(tap, alt_tab, no_z)
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
    return { description = "tilemo: Win+key", manipulators = m }
end

t.test("an up-to-date tilemo rule has nothing missing", function()
    local read = env({ [CONFIG] = profiles(profile(true, rule("f20", true))) }, {})
    t.eq(keys.rule_gaps(read, HOME, decode), {})
end)

t.test("a rule enabled before conf's update is missing Alt+Tab and the Super tap, and says how to fix it", function()
    local read = env({ [CONFIG] = profiles(profile(true, rule("spacebar", false))) }, {})
    local gaps = keys.rule_gaps(read, HOME, decode)
    t.eq(gaps, { "Alt+Tab (swap with the master)", "the lone Super tap (the workspace list)" })
    local notice = keys.gaps_notice(gaps)
    t.eq(notice:find("Alt+Tab (swap with the master) and the lone Super tap (the workspace list) don't work", 1, true) ~= nil, true, notice)
    t.eq(notice:find('remove the "tilemo:" rule under Complex Modifications and add it again', 1, true) ~= nil, true, notice)
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

t.test("Alt+Tab's manipulator must send what tilemo binds", function()
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

t.done("keys")
