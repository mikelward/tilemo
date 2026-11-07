-- The picker's Return (SPEC.md §9.1): it copies the row, brings back the
-- app that was in front when the picker opened, and sends it Cmd+V.
-- picker_hs.lua runs here against a stand-in Hammerspoon: one chooser
-- whose rows are chosen by hand, a pasteboard that can refuse a write,
-- and keystrokes recorded with the app they went to.

local t = require("t")

local function stub()
    local s = { strokes = {}, logs = {}, alerts = {}, refuse_copy = false }
    local on_choice
    s.front = { name = function() return "Notes" end, activate = function() return not s.refuse_activate end }
    s.hs = {
        chooser = {
            new = function(fn)
                on_choice = fn
                local c = { visible = false }
                function c:query(q)
                    if q == nil then
                        return ""
                    end
                end
                function c:choices() end
                function c:placeholderText() end
                function c:queryChangedCallback() end
                function c:isVisible()
                    return c.visible
                end
                function c:show()
                    c.visible = true
                end
                function c:cancel()
                    c.visible = false
                    on_choice(nil)
                end
                function c:selectedRowContents() end
                s.chooser = c
                return c
            end,
        },
        pasteboard = {
            setContents = function(text)
                if s.refuse_copy then
                    return false
                end
                s.copied = text
                return true
            end,
            watcher = { new = function() return {} end },
        },
        application = {
            frontmostApplication = function()
                return s.front
            end,
        },
        eventtap = {
            keyStroke = function(mods, key, _, app)
                s.strokes[#s.strokes + 1] = { keys = table.concat(mods, "+") .. "+" .. key, app = app }
            end,
        },
        hotkey = {
            bind = function()
                return { delete = function() end }
            end,
        },
        alert = {
            show = function(m)
                s.alerts[#s.alerts + 1] = m
            end,
        },
    }
    -- Return on a row holding `text`, as the chooser calls back.
    function s.choose(text)
        s.chooser.visible = false
        on_choice({ text = text, copy = text })
    end
    return s
end

local function setup()
    local s = stub()
    _G.hs = s.hs
    package.loaded["tide.picker_hs"] = nil
    local picker_hs = require("tide.picker_hs")
    local tide = {
        wm = { hold = function() end },
        adapter = { log = function(m) s.logs[#s.logs + 1] = m end },
    }
    return s, picker_hs.new(tide)
end

t.test("Return copies the row and pastes it with Cmd+V into the app that was in front", function()
    local s, p = setup()
    p.show("clipboard")
    s.choose("hello")
    t.eq(s.copied, "hello")
    t.eq(#s.strokes, 1)
    t.eq(s.strokes[1].keys, "cmd+v")
    t.eq(s.strokes[1].app == s.front, true, "the paste goes to the app that was in front")
end)

t.test("Esc pastes nothing", function()
    local s, p = setup()
    p.show("clipboard")
    s.chooser:cancel()
    t.eq(#s.strokes, 0)
    t.eq(s.copied, nil)
end)

t.test("a copy that fails pastes nothing, and says so", function()
    local s, p = setup()
    s.refuse_copy = true
    p.show("clipboard")
    s.choose("hello")
    t.eq(#s.strokes, 0)
    t.eq(s.alerts, { "Couldn't copy that" })
end)

t.test("an app that can't be brought back gets no paste, and the log says so", function()
    local s, p = setup()
    s.refuse_activate = true
    p.show("clipboard")
    s.choose("hello")
    t.eq(s.copied, "hello")
    t.eq(#s.strokes, 0)
    t.eq(#s.logs, 1)
    t.eq(s.logs[1]:find("couldn't bring Notes back", 1, true) ~= nil, true, s.logs[1])
end)

t.test("a second opening pastes into the app in front then, not the first one's", function()
    local s, p = setup()
    p.show("clipboard")
    s.chooser:cancel()
    local other = { name = function() return "Mail" end, activate = function() return true end }
    s.front = other
    p.show("clipboard")
    s.choose("x")
    t.eq(s.strokes[1].app == other, true)
end)

t.done("picker_hs")
