-- The name prompt's text (SPEC.md §6.2): its default opens selected, so
-- typing replaces it, and Home and End keep it. prompt_hs.lua runs here
-- against the fake adapter and a stand-in hs.chooser that edits its text
-- as an AppKit text field does: show() makes the field first responder,
-- which selects all of it, and setting the text puts the cursor at its end.

local t = require("t")
local fake = require("fake")
local wm_mod = require("tilemo.wm")

-- A stand-in for Hammerspoon: one chooser, timers run by hand, hotkeys
-- pressed by hand, and keystrokes delivered to the chooser.
local function stub()
    local s = { hotkeys = {}, timers = {}, strokes = {} }
    local field -- the chooser
    s.hs = {
        chooser = {
            new = function(on_choice)
                field = { text = "", from = 0, to = 0, shows = 0 }
                local c = {}
                function c:query(text)
                    if text == nil then
                        return field.text
                    end
                    field.text = text
                    field.from, field.to = #text, #text
                    return c
                end
                function c:choices(rows)
                    field.rows = rows
                end
                function c:placeholderText(p)
                    field.placeholder = p
                end
                function c:queryChangedCallback(fn)
                    field.changed = fn
                end
                function c:show()
                    field.shows = field.shows + 1
                    field.visible = true
                    field.from, field.to = 0, #field.text
                    -- As HSChooser's show: controlTextDidChange runs the
                    -- query callback.
                    field.changed(field.text)
                end
                function c:cancel()
                    field.visible = false
                    on_choice(nil)
                end
                field.choose = function(name)
                    field.visible = false
                    on_choice(name and { name = name } or nil)
                end
                s.chooser = c
                return c
            end,
        },
        timer = {
            doEvery = function(_, fn)
                local tm = { fn = fn }
                function tm:stop()
                    tm.stopped = true
                end
                s.timers[#s.timers + 1] = tm
                return tm
            end,
        },
        hotkey = {
            bind = function(mods, key, fn)
                local k = { mods = mods, key = key, fn = fn }
                function k:delete()
                    k.deleted = true
                end
                s.hotkeys[#s.hotkeys + 1] = k
                return k
            end,
        },
        eventtap = {
            keyStroke = function(mods, key)
                s.strokes[#s.strokes + 1] = table.concat(mods, "+") .. "+" .. key
                if mods[1] == "cmd" and key == "left" then
                    field.from, field.to = 0, 0
                elseif mods[1] == "cmd" and key == "right" then
                    field.from, field.to = #field.text, #field.text
                end
            end,
        },
    }
    -- Typing replaces the selection, or inserts at the cursor.
    function s.type(chars)
        field.text = field.text:sub(1, field.from) .. chars .. field.text:sub(field.to + 1)
        field.from = field.from + #chars
        field.to = field.from
        field.changed(field.text)
    end
    function s.field()
        return field
    end
    function s.selected()
        return field.text:sub(field.from + 1, field.to)
    end
    -- The live hotkey for `key`, if any.
    function s.key(key)
        for i = #s.hotkeys, 1, -1 do
            local k = s.hotkeys[i]
            if k.key == key and not k.deleted then
                return k
            end
        end
    end
    function s.tick()
        for _, tm in ipairs(s.timers) do
            if not tm.stopped then
                tm.fn()
            end
        end
    end
    return s
end

-- prompt_hs.lua against the fake adapter, with window 1 on "in" titled
-- `title`.
local function setup(title)
    local s = stub()
    _G.hs = s.hs
    package.loaded["tilemo.prompt_hs"] = nil
    local prompt_hs = require("tilemo.prompt_hs")
    local a = fake.new()
    a.add(1, { title = title })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    local tilemo = {
        wm = wm,
        adapter = a,
        name_patterns = {},
    }
    local prompt = prompt_hs.new(tilemo)
    return s, prompt, a, wm
end

t.test("the default opens selected, so typing replaces it", function()
    local s, prompt = setup("Mail")
    prompt.window(1)
    t.eq(s.field().text, "Mail")
    t.eq(s.selected(), "Mail", "all of it selected")
    s.type("w")
    t.eq(s.field().text, "w", "typing replaced the default")
    t.eq(s.field().rows[1].name, "w", "the typed name is the top row")
end)

t.test("a launch's default opens selected too", function()
    local s, prompt = setup("Mail")
    local got
    prompt.launch("ABC-123", function(name)
        got = name
    end)
    t.eq(s.selected(), "ABC-123")
    s.type("web")
    s.field().choose(s.field().text)
    t.eq(got, "web")
end)

t.test("Home and End keep the default and move the cursor", function()
    local s, prompt = setup("Mail")
    prompt.window(1)
    s.key("home").fn()
    t.eq(s.strokes, { "cmd+left" }, "Home is the text field's Cmd+Left")
    t.eq(s.field().text, "Mail", "the default stays")
    s.type("my")
    t.eq(s.field().text, "myMail", "typing goes in at the start")
    s.key("end").fn()
    t.eq(s.strokes[2], "cmd+right", "End is the text field's Cmd+Right")
    s.type("!")
    t.eq(s.field().text, "myMail!", "and at the end")
end)

t.test("Home and End are given back once the prompt is answered", function()
    local s, prompt = setup("Mail")
    prompt.window(1)
    t.eq(s.key("home") ~= nil and s.key("end") ~= nil, true, "taken while open")
    s.field().choose("Mail")
    t.eq(s.key("home"), nil, "Home given back")
    t.eq(s.key("end"), nil, "End given back")
    prompt.launch("x", function() end)
    s.chooser:cancel()
    t.eq(s.key("home"), nil, "and after Esc")
end)

t.test("opening the prompt isn't typing: the default follows the title, selected", function()
    local s, prompt, a = setup("Loading")
    prompt.window(1)
    a.wins[1].title = "ABC-123"
    s.tick()
    t.eq(s.field().text, "ABC-123", "the default followed the title")
    t.eq(s.selected(), "ABC-123", "and is selected again")
    s.type("x")
    t.eq(s.field().text, "x", "so typing still replaces it")
    a.wins[1].title = "Other"
    s.tick()
    t.eq(s.field().text, "x", "once typed, the title is no longer followed")
end)

t.test("Home stops the default following the title", function()
    local s, prompt, a = setup("Loading")
    prompt.window(1)
    s.key("home").fn()
    a.wins[1].title = "ABC-123"
    s.tick()
    t.eq(s.field().text, "Loading", "the cursor isn't yanked away")
end)

t.done("prompt_hs")
