local t = require("t")
local keys = require("timo.keys")

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

t.test("with Karabiner running and timo's rule loaded, Super is Ctrl+Option+Command", function()
    local read, running = env({ [CONFIG] = profiles(profile(true, { description = "timo: Win to Super" })) },
        { ["Karabiner-Core-Service"] = true })
    local super, ok = keys.super(read, running, HOME, decode)
    t.eq(ok, true)
    t.eq(super, { "ctrl", "alt", "cmd" })
end)

t.test("without Karabiner's rule, Super falls back to Option", function()
    local read, running = env({ [CONFIG] = profiles(profile(true)) }, { ["Karabiner-Core-Service"] = true })
    local super, ok = keys.super(read, running, HOME, decode)
    t.eq(ok, false)
    t.eq(super, { "alt" })
end)

t.test("with the rule but Karabiner not running, Super falls back to Option", function()
    local read, running = env({ [CONFIG] = profiles(profile(true, { description = "timo: x" })) }, {})
    t.eq(select(2, keys.super(read, running, HOME, decode)), false)
end)

t.test("the rule only counts in the selected profile", function()
    local read, running = env({
        [CONFIG] = profiles(profile(false, { description = "timo: x" }), profile(true, { description = "other" })),
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
    local wm = require("timo.wm")
    for _, b in ipairs(keys.map) do
        t.eq(type(wm.actions[b.action]), "function", b.action)
    end
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

t.done("keys")
