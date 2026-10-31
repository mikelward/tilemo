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
    t.eq(#list, #keys.map + #keys.plain)
end)

t.test("a screenshot action asks the adapter for that kind", function()
    local a = require("fake").new()
    local wm = require("tilemo.wm").new(a, {})
    wm:act("screenshot", "window")
    wm:act("screenshot", "screen")
    t.eq(table.concat(a.shots, " "), "window screen")
end)

t.test('Super+Home goes to "in", and Super+1…9 are left out while undecided', function()
    local home
    for _, b in ipairs(keys.map) do
        if b.key == "home" then
            home = b.action
        end
        t.eq(b.key:match("^%d$"), nil, "no digit keys: " .. b.key)
    end
    t.eq(home, "home")
end)

t.done("keys")
