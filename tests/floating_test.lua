-- The float rules you make (floating.lua) and the window manager's side
-- of them: a new rule floats what's open, Floating now, and the question
-- after Super+Shift+F.

local t = require("t")
local fake = require("fake")
local json = require("json")
local floating = require("tide.floating")
local wm_mod = require("tide.wm")
local keys = require("tide.keys")

local DIR = "/home/user/.config/tide"
local SHARED = DIR .. "/" .. floating.FILE
local LOCAL = DIR .. "/" .. floating.LOCAL_FILE

local function store(init)
    local files = init or {}
    local read = function(p)
        return files[p]
    end
    local write = function(p, text)
        files[p] = text
        return true
    end
    return files, read, write
end

t.test("the rules are in their own files in tide's folder, the local list replacing the shared", function()
    local _, read = store({
        [SHARED] = '{"rules": [{"app": "com.example.a"}]}',
        [LOCAL] = '{"rules": [{"app": "com.apple.Preview", "title": "^Info$"}]}',
    })
    local list, from = floating.load(DIR, read, json.decode)
    t.eq(from, floating.LOCAL_FILE)
    t.eq(list, { { app = "com.apple.Preview", title = "^Info$", action = "float" } })
    _, read = store({ [SHARED] = '{"rules": [{"app": "com.example.a", "title": ""}]}' })
    list, from = floating.load(DIR, read, json.decode)
    t.eq(from, floating.FILE)
    t.eq(list, { { app = "com.example.a", action = "float" } }, "a title of \"\" is none")
    _, read = store({})
    t.eq({ floating.load(DIR, read, json.decode) }, { {} }, "no files: no rules")
end)

t.test("a wrong entry is an error naming the file and the entry, and gives no rules", function()
    local cases = {
        { '{"rules": [{"title": "x"}]}', "rules[1] names no app" },
        { '{"rules": [{"app": "a b"}]}', "rules[1] has a space in its app" },
        { '{"rules": [{"app": "a", "class": "x"}]}', 'rules[1] has "class", which isn\'t app or title' },
        { '{"rules": [{"app": "a", "title": "[x"}]}', "rules[1] the title isn't a Lua pattern" },
        { '{"rules": [{"app": "a", "title": "^Save["}]}', "rules[1] the title isn't a Lua pattern: it has a [ with no ]" },
        { '{"rules": [{"app": "a"}, {"app": "a", "title": ""}]}', "rules[2] is listed already" },
        { '{"rules": {"app": "a"}}', "rules must be a list" },
        { '[{"app": "a"}]', "not a JSON object" },
        { "{", "not a JSON object" },
    }
    for _, c in ipairs(cases) do
        local _, read = store({ [LOCAL] = c[1] })
        local list, err = floating.load(DIR, read, json.decode)
        t.eq(list, nil, c[1])
        t.eq(err:find(floating.LOCAL_FILE .. ": " .. c[2], 1, true) ~= nil, true, err)
    end
    local many = {}
    for i = 1, floating.MAX + 1 do
        many[i] = '{"app": "a' .. i .. '"}'
    end
    local _, read = store({ [LOCAL] = '{"rules": [' .. table.concat(many, ",") .. "]}" })
    local list, err = floating.load(DIR, read, json.decode)
    t.eq(list, nil)
    t.eq(err:find("more than 64", 1, true) ~= nil, true, err)
end)

t.test("a title's exact pattern escapes Lua's magic characters", function()
    t.eq(floating.exact("Save As..."), "^Save As%.%.%.$")
    t.eq(floating.exact("50% (a+b) [x]^$*?-"), "^50%% %(a%+b%) %[x%]%^%$%*%?%-$")
    for _, title in ipairs({ "Save As...", "50% (a+b) [x]^$*?-", "Ünïcode — dash" }) do
        t.eq(title:find(floating.exact(title)) ~= nil, true, title)
        t.eq(("x" .. title):find(floating.exact(title)), nil, "only the exact title: " .. title)
    end
end)

t.test("adding a rule copies the list in effect to the local file, keeping its other keys", function()
    local files, read, write = store({
        [SHARED] = '{"rules": [{"app": "com.example.a"}]}',
        [LOCAL] = '{"other": 1}',
    })
    t.eq(floating.edit(DIR, read, json.decode, json.encode, write, function(list)
        return floating.with(list, " com.apple.Preview ", "^Info$")
    end), true)
    local v = json.decode(files[LOCAL])
    t.eq(v.other, 1)
    t.eq(v.rules, { { app = "com.example.a" }, { app = "com.apple.Preview", title = "^Info$" } })
    t.eq(files[SHARED], '{"rules": [{"app": "com.example.a"}]}', "the shared file is left alone")
    -- Removing the last leaves an empty list, which still replaces the shared one.
    floating.edit(DIR, read, json.decode, json.encode, write, function(list)
        return floating.without(list, 1, "com.example.a", "")
    end)
    floating.edit(DIR, read, json.decode, json.encode, write, function(list)
        return floating.without(list, 1, "com.apple.Preview", "^Info$")
    end)
    t.eq(json.decode(files[LOCAL]).rules, {})
    t.eq(files[LOCAL]:find('"rules": []', 1, true) ~= nil, true, "written as a list")
    t.eq(floating.load(DIR, read, json.decode), {})
end)

t.test("an add, move or removal that can't be made writes nothing, and says why", function()
    local files, read, write = store({ [LOCAL] = '{"rules": [{"app": "a"}, {"app": "b", "title": "^x$"}]}' })
    local before = files[LOCAL]
    local function edit(fn)
        return floating.edit(DIR, read, json.decode, json.encode, write, fn)
    end
    local cases = {
        { function(l) return floating.with(l, "", "") end, "type an app's bundle ID" },
        { function(l) return floating.with(l, "a", "") end, "a is listed already" },
        { function(l) return floating.with(l, "c", "%") end, "the title isn't a Lua pattern: it ends with %" },
        { function(l) return floating.with(l, "c", "^Save[") end, "it has a [ with no ] to end it" },
        { function(l) return floating.with(l, "c", "%b(") end, "it has a %b without two characters" },
        { function(l) return floating.with(l, "c d", "") end, "has a space" },
        { function(l) return floating.moved(l, 1, "b", "^x$", 1) end, "the rules changed" },
        { function(l) return floating.without(l, 3, "a", "") end, "the rules changed" },
    }
    for i, c in ipairs(cases) do
        local ok, why = edit(c[1])
        t.eq(ok, nil, "case " .. i)
        t.eq(why:find(c[2], 1, true) ~= nil, true, why)
    end
    t.eq(files[LOCAL], before)
    files[LOCAL] = "{"
    local ok, why = edit(function(l) return floating.with(l, "c", "") end)
    t.eq(ok, nil)
    t.eq(why:find("Fix the file", 1, true) ~= nil, true, why)
end)

t.test("a move swaps a rule with its neighbor, and stops at the ends", function()
    local list = { { app = "a" }, { app = "b" }, { app = "c" } }
    t.eq(floating.moved(list, 2, "b", "", -1), { { app = "b" }, { app = "a" }, { app = "c" } })
    t.eq(floating.moved(list, 3, "c", "", 1), list)
    t.eq(list, { { app = "a" }, { app = "b" }, { app = "c" } }, "the list given is left alone")
end)

local function std(extra)
    local f = { role = "AXWindow", subrole = "AXStandardWindow", app = "com.example.app", title = "Doc" }
    for k, v in pairs(extra or {}) do
        f[k] = v
    end
    return f
end

t.test("what floats a window already is named, rule or dialog", function()
    local file = { { app = "com.example.app", title = "^Doc$", action = "float" } }
    t.eq(floating.covered_by(std(), {}, file), "rule 1")
    t.eq(floating.covered_by(std(), { { app = "com.example.app", action = "tile" } }, file), nil,
        "start()'s rules come first")
    t.eq(floating.covered_by(std({ app = "com.apple.systempreferences" }), {}, {}), "built-in rule")
    t.eq(floating.covered_by(std({ subrole = "AXDialog" }), {}, {}), "macOS reports it as a dialog or panel")
    t.eq(floating.covered_by(std({ size_settable = false }), {}, {}), "its size can't be changed")
    t.eq(floating.covered_by(std(), {}, {}), nil)
end)

t.test("More about this window lists only what macOS says", function()
    t.eq(floating.about({ role = "AXWindow", subrole = "AXDialog", modal = false, size_settable = true,
        name = "Preview", path = "/System/Applications/Preview.app" }), {
        { label = "Role", value = "AXWindow" },
        { label = "Subrole", value = "AXDialog" },
        { label = "Modal", value = "no" },
        { label = "Resizable", value = "yes" },
        { label = "App", value = "Preview" },
        { label = "App's path", value = "/System/Applications/Preview.app" },
    })
    t.eq(floating.about(nil), {})
end)

t.test("the question is asked once per app a login, and again at the next", function()
    local yes, s = floating.ask(nil, "Mon 1", "com.a")
    t.eq(yes, true)
    yes, s = floating.ask(s, "Mon 1", "com.a")
    t.eq(yes, false, "not twice")
    yes, s = floating.ask(s, "Mon 1", "com.b")
    t.eq(yes, true, "another app")
    yes = floating.ask(s, "Tue 2", "com.a")
    t.eq(yes, true, "a new login")
end)

-- The window manager, with three tiles.
local function setup(apps)
    local a = fake.new()
    for i, app in ipairs(apps) do
        a.add(i, { app = app, title = "Window " .. i })
    end
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    return a, wm
end

local function rule(app, title)
    return { app = app, title = title, action = "float" }
end

t.test("a new rule floats the tiled windows open now that it covers", function()
    local a, wm = setup({ "com.a", "com.b", "com.a" })
    t.eq(wm:part("in", "A").order, { 1, 2, 3 })
    local ids = wm:set_float_rules({ rule("com.a") })
    t.eq(ids, { 1, 3 })
    t.eq(wm.windows[1].floating, true)
    t.eq(wm.windows[3].floating, true)
    t.eq(wm:part("in", "A").order, { 2 })
    -- Placed as a new float is: centered, as it asked.
    t.eq(a.wins[1].frame.w, 800)
    t.eq(wm:set_float_rules({ rule("com.a") }), {}, "the same rules again float nothing")
end)

t.test("a window you tiled by hand under a rule stays tiled when a broader rule comes", function()
    local _, wm = setup({ "com.a", "com.a" })
    wm:set_float_rules({ rule("com.a", "^Window 1$") })
    t.eq(wm.windows[1].floating, true)
    wm:focused(1)
    wm.a.focus_ = 1
    wm:act("toggle_float") -- tiled by hand
    t.eq(wm.windows[1].floating, false)
    t.eq(wm:set_float_rules({ rule("com.a", "^Window 1$"), rule("com.a") }), { 2 })
    t.eq(wm.windows[1].floating, false, "still tiled")
end)

t.test("a window tiled by hand under one of tide's own rules isn't floated by a new rule", function()
    local a = fake.new()
    a.add(1, { app = "com.apple.systempreferences", title = "Settings" })
    local wm = wm_mod.new(a, {})
    wm:sync()
    a.focus_ = 1
    wm:act("toggle_float")
    t.eq(wm.windows[1].floating, false)
    t.eq(wm:set_float_rules({ rule("com.apple.systempreferences") }), {})
end)

t.test("full screen and maximized windows are left as they are, and nothing is tiled", function()
    local a, wm = setup({ "com.a", "com.a", "com.b" })
    a.wins[1].fullscreen = true
    a.focus_ = 2
    wm:focused(2)
    wm:act("maximize")
    t.eq(wm:set_float_rules({ rule("com.a"), rule("com.b") }), { 3 })
    t.eq(not wm.windows[1].floating, true)
    t.eq(not wm.windows[2].floating, true)
    -- Taking the rules out tiles nothing back.
    t.eq(wm:set_float_rules({}), {})
    t.eq(wm.windows[3].floating, true)
end)

t.test("a window on a workspace that isn't showing floats there, unmoved until it shows", function()
    local a, wm = setup({ "com.a", "com.b" })
    a.focus_ = 2
    wm:focused(2)
    wm.ask_move = function(done) done("re") end
    wm:act("move_to")
    t.eq(wm.windows[2].ws, "re")
    wm:act("home")
    t.eq(wm:shown("re"), false)
    a.calls = {}
    t.eq(wm:set_float_rules({ rule("com.b") }), { 2 })
    t.eq(wm.windows[2].floating, true)
    for _, c in ipairs(a.calls) do
        t.eq(c == "frame 2", false, "not placed while hidden")
    end
    -- Shown, it's placed as a new float is: at the size it opened at,
    -- centered, not left at its tile's frame.
    wm:act("show", "re")
    t.eq(a.wins[2].frame, { x = 560, y = 253, w = 800, h = 600 })
    a.calls = {}
    wm:retile()
    t.eq(a.calls, {}, "placed once")
end)

t.test("a window you minimized floats where it is, and is placed once restored", function()
    local a, wm = setup({ "com.a", "com.b" })
    a.focus_ = 2
    wm:focused(2)
    wm:act("minimize")
    t.eq(a.wins[2].minimized, true)
    a.calls = {}
    t.eq(wm:set_float_rules({ rule("com.b") }), { 2 })
    for _, c in ipairs(a.calls) do
        t.eq(c == "frame 2", false, "not placed while minimized")
    end
    a.wins[2].minimized = false
    wm:unminimized(2)
    a.tick()
    t.eq(a.wins[2].frame, { x = 560, y = 253, w = 800, h = 600 })
end)

t.test("start()'s rules come before the files', and keep working", function()
    local a = fake.new()
    a.add(1, { app = "com.a", title = "x" })
    a.add(2, { app = "com.b", title = "y" })
    local wm = wm_mod.new(a, { rules = { { app = "com.a", action = "tile" }, { app = "com.b", action = "float" } } })
    wm:sync()
    t.eq(wm.windows[2].floating, true)
    t.eq(wm:set_float_rules({ rule("com.a") }), {}, "start()'s tile rule wins")
    t.eq(not wm.windows[1].floating, true)
end)

t.test("Floating now lists the floating windows no rule covers, one per app", function()
    local a, wm = setup({ "com.a", "com.a", "com.b", "com.c" })
    a.add(5, { app = "com.d", subrole = "AXDialog", title = "Dialog" })
    a.app_names = {}
    a.wins[1].name, a.wins[2].name, a.wins[3].name = "Alpha", "Alpha", "Beta"
    wm:sync()
    for _, id in ipairs({ 1, 2, 3 }) do
        a.focus_ = id
        wm:act("toggle_float")
    end
    wm:set_float_rules({ rule("com.b") })
    local now = wm:floating_now()
    t.eq(#now, 1, "one for Alpha; Beta has a rule, the dialog floats anyway")
    t.eq(now[1].app, "com.a")
    t.eq(now[1].name, "Alpha")
    t.eq(now[1].title, "^Window 1$")
end)

t.test("floating a window by the key asks only when no rule covers it", function()
    local a, wm = setup({ "com.a", "com.b" })
    local asked = {}
    wm.floated_by_hand = function(id)
        asked[#asked + 1] = id
    end
    wm:set_float_rules({ rule("com.b", "^Nothing$") })
    a.focus_ = 1
    wm:act("toggle_float")
    t.eq(asked, { 1 })
    wm:act("toggle_float") -- tiled again: no question
    t.eq(asked, { 1 })
    -- A rule covers window 2, which you tiled by hand: floating it again
    -- doesn't ask.
    a.wins[2].title = "Nothing"
    wm.windows[2].floating = true
    a.focus_ = 2
    wm:act("toggle_float")
    wm:act("toggle_float")
    t.eq(asked, { 1 })
end)

t.test("Super+Shift+I opens the Floating page for the focused window", function()
    local found
    for _, b in ipairs(keys.map) do
        if b.key == "i" and b.shift then
            found = b.action
        end
    end
    t.eq(found, "float_rule")
    local a, wm = setup({ "com.a" })
    local opened = {}
    wm.open_float_rule = function(id)
        opened[#opened + 1] = id or "none"
    end
    a.focus_ = 1
    wm:act("float_rule")
    a.focus_ = nil
    wm:act("float_rule")
    t.eq(opened, { 1, "none" })
end)


t.test("a bad pattern that gets past the checks doesn't stop windows being decided", function()
    local a, wm = setup({ "com.a" })
    -- As if a hand edit got one past floating.parse: the rule is skipped.
    t.eq(wm:set_float_rules({ rule("com.a", "^Window["), rule("com.b") }), {})
    a.add(2, { app = "com.a", title = "Window 2" })
    a.add(3, { app = "com.b", title = "Other" })
    wm:sync()
    t.eq(wm.windows[2].kind, "tile")
    t.eq(wm.windows[3].floating, true, "the rules after it still apply")
end)

t.done("floating")
