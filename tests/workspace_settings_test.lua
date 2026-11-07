-- Each workspace's own settings (SPEC.md §6.2, §15): tide's
-- workspaceSettings, whose askForName says which workspaces' new windows
-- and launches ask for a name, and whose pinnedApps tide's close actions
-- and an app's own close and quit keys leave open.

local t = require("t")
local json = require("json")
local fake = require("fake")
local standing = require("tide.standing")
local wm_mod = require("tide.wm")
local keys = require("tide.keys")
local pinned_hs = require("tide.pinned_hs")
local mute = require("tide.mute")

local DIR = "/home/user/.config/tide"

local function load(files)
    return standing.load(DIR, function(path)
        return files[path:match("[^/]*$")]
    end, json.decode)
end

-- tide started with `config`, one window open on home, ready to ask, with
-- every question recorded.
local function setup(config)
    local a = fake.new()
    a.add(1, {})
    local wm = wm_mod.new(a, config or {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    local asked, launches = {}, {}
    wm.ask_name = function(id)
        asked[#asked + 1] = id
    end
    wm.ask_launch = function(default, done)
        launches[#launches + 1] = { default = default, done = done }
    end
    wm.ready = true
    a.calls = {}
    return a, wm, asked, launches
end

local function open(a, wm, id, f)
    a.add(id, f or {})
    wm:schedule()
    a.tick()
end

local function app_key(key, shift)
    for _, b in ipairs(keys.map) do
        if b.key == key and (b.shift or false) == (shift or false) and b.action == "app" then
            return b.arg
        end
    end
end

-- Go to workspace `name`, made with window 1 sent there.
local function go(a, wm, name)
    a.focus_ = 1
    wm:act("send", name)
    wm:act("show", name)
end

-- Loading ------------------------------------------------------------------

t.test("with no workspaceSettings in either file, it's unset, for start()'s or tide's default", function()
    local s = load({ ["workspaces.json"] = '{"standing": ["in", "re"]}' })
    t.eq(s.workspaceSettings, nil)
    t.eq(standing.settings_of(nil, "in"), { ["in"] = { askForName = true } })
    t.eq(standing.setting(nil, "in", "IN"), { askForName = true, pinnedApps = {} })
    t.eq(standing.setting(nil, "in", "re"), { askForName = false, pinnedApps = {} })
end)

t.test("a .local file's workspaceSettings replaces the shared one whole", function()
    local s = load({
        ["workspaces.json"] = '{"workspaceSettings": {"in": {"askForName": true, "pinnedApps": ["Gmail"]}}}',
        ["workspaces.local.json"] = '{"workspaceSettings": {"re": {"askForName": true}}}',
    })
    t.eq(s.from.workspaceSettings, "workspaces.local.json")
    t.eq(standing.setting(s.workspaceSettings, "in", "in"), { askForName = false, pinnedApps = {} },
        "home isn't listed, so it doesn't ask")
    t.eq(standing.setting(s.workspaceSettings, "in", "RE"), { askForName = true, pinnedApps = {} },
        "names match ignoring case; a missing field is off")
end)

t.test("a workspaceSettings tide wouldn't take is an error at load, naming the setting", function()
    local function err(ws)
        local s, errors = load({ ["workspaces.local.json"] = '{"workspaceSettings": ' .. ws .. "}" })
        t.eq(s, nil, ws)
        return table.concat(errors, "; ")
    end
    local P = "workspaces.local.json: workspaceSettings"
    t.eq(err('["in"]'), P .. " must be an object, each key a workspace's name")
    t.eq(err('{"in": true}'), P .. ': "in" must be an object, with askForName or pinnedApps')
    t.eq(err('{"in": {"ask": true}}'), P .. ': "in": ask isn\'t a setting (askForName or pinnedApps)')
    t.eq(err('{"in": {"askForName": "yes"}}'), P .. ': "in": askForName must be true or false, not "yes"')
    t.eq(err('{"in": {"pinnedApps": "Gmail"}}'), P .. ': "in": pinnedApps must be a list')
    t.eq(err('{"in": {"pinnedApps": ["Gmail", 3]}}'), P .. ': "in": pinnedApps must list text, not 3 at 2')
    t.eq(err('{"in": {}, "IN": {}}'), P .. ' names "IN" twice')
    t.eq(err('{" in": {}}'), P .. ': " in" has space around it')
    t.eq(err('{"a@b": {}}'), P .. ': "a@b": a workspace\'s name can\'t have quotes, backslashes, @ or control characters')
    t.eq(err('{"": {}}'), P .. ': "": a workspace needs a name')
end)

t.test("start()'s workspace_settings is checked as the files are, naming it", function()
    local ok, why = pcall(wm_mod.new, fake.new(), { workspace_settings = { ["in"] = { askForName = 1 } } })
    t.eq(ok, false)
    t.eq(tostring(why):find('workspace_settings: "in": askForName must be true or false, not 1', 1, true) ~= nil, true,
        tostring(why))
    t.eq(pcall(wm_mod.new, fake.new(), { workspace_settings = {} }), true, "an empty one: nothing asks")
end)

t.test("the settings page gets workspaceSettings as JSON, empty lists and objects kept", function()
    t.eq(standing.encode_settings({}, mute.quote), "{}")
    local text = standing.encode_settings({ ["in"] = { askForName = true, pinnedApps = {} }, re = {} }, mute.quote)
    t.eq(text, '{"in": {"askForName": true, "pinnedApps": []}, "re": {}}')
    t.eq(json.decode(text)["in"].askForName, true)
end)

-- askForName ---------------------------------------------------------------

t.test("a new window on a workspace whose askForName is on asks, home or not", function()
    local a, wm, asked = setup({ workspace_settings = { work = { askForName = true } } })
    go(a, wm, "work")
    open(a, wm, 2)
    t.eq(asked, { 2 })
    t.eq(wm.windows[2].ws, "work", "it stays put until you answer")
    -- Enter on the workspace it's on keeps it there, and it asks no more.
    wm:answer(2, "WORK")
    t.eq(wm.windows[2].ws, "work")
    t.eq(wm.names, { "in", "work" })
    t.eq(a.focus_, 2)
    t.eq(wm.holding_keyboard, false)
    -- Home's askForName isn't on, so a window there doesn't ask.
    wm:act("show", "in")
    open(a, wm, 3)
    t.eq(asked, { 2 })
    t.eq(wm.windows[3].ws, "in")
end)

t.test("with home's askForName off, nothing asks, home included", function()
    for _, ws in ipairs({ {}, { ["in"] = { askForName = false, pinnedApps = { "Gmail" } } } }) do
        local a, wm, asked, launches = setup({ workspace_settings = ws })
        open(a, wm, 2)
        t.eq(asked, {})
        t.eq(wm.windows[2].ws, "in")
        wm:act("app", app_key("g"))
        t.eq(#launches, 0, "a launch from home starts straight away")
        t.eq(#a.launched, 1)
        t.eq(a.envs[1], { TIDE_WORKSPACE = "in" })
    end
end)

t.test("a launch from a workspace that asks asks first; named for it, its window doesn't ask again", function()
    local a, wm, asked, launches = setup({ workspace_settings = { work = { askForName = true } } })
    go(a, wm, "work")
    wm:act("app", app_key("g"))
    t.eq(#launches, 1)
    t.eq(#a.launched, 0, "nothing starts until you answer")
    launches[1].done("work")
    t.eq(#a.launched, 1)
    t.eq(a.envs[1], { TIDE_WORKSPACE = "work" })
    open(a, wm, 2, { app = "com.google.Chrome" })
    t.eq(wm.windows[2].ws, "work")
    t.eq(asked, {})
    -- One of home's apps launches straight away, and its window goes home
    -- without asking.
    wm:act("app", app_key("c"))
    t.eq(#launches, 1)
    t.eq(#a.launched, 2)
    open(a, wm, 3, { name = "Google Chat" })
    t.eq(wm.windows[3].ws, "in")
    t.eq(asked, {})
end)

t.test("a workspace's settings from tide's files apply as they change", function()
    local a, wm, asked = setup()
    wm:set_workspace_settings({ re = { askForName = true } })
    open(a, wm, 2)
    t.eq(asked, {}, "home no longer asks")
    t.eq(pcall(wm.set_workspace_settings, wm, { re = { askForName = "on" } }), false, "checked as start()'s are")
    wm:set_workspace_settings(nil)
    open(a, wm, 3)
    t.eq(asked, { 3 }, "back to tide's default: home asks")
end)

-- pinnedApps ---------------------------------------------------------------

local PINNED = { ["in"] = { askForName = true, pinnedApps = { "gmail", "Google Chat" } } }

t.test("the close key leaves a window pinned where it is open, and says so; any other closes", function()
    local a, wm = setup({ workspace_settings = PINNED })
    open(a, wm, 2, { name = "Gmail" })
    open(a, wm, 3, { name = "TextEdit" })
    a.focus_ = 2
    a.calls = {}
    wm:act("close")
    t.eq(a.calls, {}, "not closed")
    t.eq(a.notes, { "Pinned window: it's pinned on in, so it stays open." })
    a.focus_ = 3
    wm:act("close")
    t.eq(a.calls, { "close 3" })
    t.eq(#a.notes, 1)
end)

t.test("a pinned app's window on another workspace closes as any other does", function()
    local a, wm = setup({ workspace_settings = PINNED })
    open(a, wm, 2, { name = "Gmail" })
    a.focus_ = 2
    wm:act("send", "mail")
    a.focus_ = 2
    a.calls = {}
    wm:act("close")
    t.eq(a.calls, { "close 2" })
    t.eq(a.notes, {})
end)

t.test("the name prompt's Esc leaves a pinned window open there, and closes any other", function()
    local a, wm, asked = setup({ workspace_settings = { ["in"] = { askForName = true, pinnedApps = { "Notes" } } } })
    open(a, wm, 2, { name = "Notes" })
    t.eq(asked, { 2 }, "pinned isn't one of home's apps, so it asks")
    a.calls = {}
    wm:answer(2, nil)
    for _, c in ipairs(a.calls) do
        t.eq(c ~= "close 2", true, "not closed")
    end
    t.eq(a.notes, { "Pinned window: it's pinned on in, so it stays open." })
    t.eq(wm.windows[2].ws, "in")
    t.eq(a.focus_, 2)
    t.eq(wm.holding_keyboard, false)
    open(a, wm, 3, { name = "TextEdit" })
    a.calls = {}
    wm:answer(3, nil)
    t.eq(a.calls, { "close 3" })
end)

-- A stand-in for Hammerspoon's hotkeys: each made one, enabled or not, and
-- the keys posted.
local function fake_hs()
    local s = { made = {}, strokes = {} }
    s.hotkey = {
        new = function(mods, key, fn)
            local k = { mods = table.concat(mods, "+"), key = key, fn = fn, on = false }
            function k:enable()
                k.on = true
                return k
            end
            function k:disable()
                k.on = false
                return k
            end
            s.made[#s.made + 1] = k
            return k
        end,
    }
    s.eventtap = {
        keyStroke = function(mods, key)
            s.strokes[#s.strokes + 1] = table.concat(mods, "+") .. "+" .. key
        end,
    }
    -- What's held: each enabled hotkey's chord.
    function s.held()
        local out = {}
        for _, k in ipairs(s.made) do
            if k.on then
                out[#out + 1] = k.mods .. "+" .. k.key
            end
        end
        return out
    end
    -- A press of `chord`: the hotkey's, if one holds it, else the app's.
    function s.press(chord)
        for _, k in ipairs(s.made) do
            if k.on and k.mods .. "+" .. k.key == chord then
                k.fn()
                return "tide"
            end
        end
        return "app"
    end
    return s
end

t.test("Cmd+W, Cmd+Shift+W and Cmd+Q are kept from a pinned window, and only from it", function()
    local a, wm = setup({ workspace_settings = PINNED })
    local hs = fake_hs()
    pinned_hs.new(hs, wm, function() end)
    open(a, wm, 2, { name = "Gmail" })
    open(a, wm, 3, { name = "TextEdit" })
    t.eq(hs.held(), {}, "nothing's held until a pinned window is focused")
    a.focus_ = 2
    wm:focused(2)
    t.eq(hs.held(), { "cmd+w", "cmd+shift+w", "cmd+q" })
    for _, chord in ipairs({ "cmd+w", "cmd+shift+w", "cmd+q" }) do
        t.eq(hs.press(chord), "tide", chord)
    end
    t.eq(hs.strokes, {}, "the app never sees them")
    t.eq(#a.notes, 3)
    t.eq(a.notes[1], "Pinned window: it's pinned on in, so it stays open.")
    t.eq(hs.press("cmd+n"), "app", "its other keys are its own")
    -- Another window gets them as ever.
    a.focus_ = 3
    wm:focused(3)
    t.eq(hs.held(), {})
    t.eq(hs.press("cmd+w"), "app")
    -- Moved off the workspace that pins it, it's an ordinary window.
    a.focus_ = 2
    wm:focused(2)
    wm:act("send", "mail")
    t.eq(hs.held(), {})
end)

t.test("a held key that finds focus moved on before tide heard goes on to the app", function()
    local a, wm = setup({ workspace_settings = PINNED })
    local hs = fake_hs()
    pinned_hs.new(hs, wm, function() end)
    open(a, wm, 2, { name = "Gmail" })
    open(a, wm, 3, { name = "TextEdit" })
    a.focus_ = 2
    wm:focused(2)
    -- Focus moves to window 3, unheard, and Cmd+W comes first.
    a.focus_ = 3
    t.eq(hs.press("cmd+w"), "tide")
    t.eq(hs.strokes, { "cmd+w" }, "posted on to the app, with the hotkeys off")
    t.eq(a.notes, {})
    t.eq(hs.held(), {})
end)

t.test("with nothing pinned, focus changes never ask macOS which window is focused", function()
    local a, wm = setup()
    local asks = 0
    local focused = a.focused
    function a.focused()
        asks = asks + 1
        return focused()
    end
    open(a, wm, 2)
    a.focus_ = 2
    local before = asks
    wm:check_pinned_focus()
    t.eq(asks, before)
end)

t.done("workspace_settings")
