-- The overview's webview (overview_hs.lua) against a stand-in hs.webview,
-- over the real window manager on the fake adapter: what the keys open and
-- close, what the page's choices do, and that focus follows mouse pauses
-- while it's open.

local t = require("t")
local fake = require("fake")
local wm_mod = require("tide.wm")

local function stub()
    local s = { views = {}, scripts = {}, icons = {} }
    s.hs = {
        inspect = tostring,
        json = {
            encode = function(v)
                s.encoded = v
                return "{}"
            end,
        },
        drawing = { windowLevels = { modalPanel = 8 } },
        image = {
            imageFromAppBundle = function(bundle)
                s.icons[#s.icons + 1] = bundle
                if bundle == "com.example.none" then
                    return nil
                end
                local img = {}
                function img:setSize()
                    return img
                end
                function img:encodeAsURLString()
                    return "data:" .. bundle
                end
                return img
            end,
        },
        webview = {
            usercontent = {
                new = function()
                    return {
                        setCallback = function(_, fn)
                            s.send = function(body)
                                fn({ body = body })
                            end
                        end,
                    }
                end,
            },
            new = function(frame)
                local v = { frame_ = frame, deleted = false }
                local methods = {}
                function methods:navigationCallback(fn)
                    v.navigate = fn
                end
                function methods:windowCallback(fn)
                    v.window = fn
                end
                function methods:delete()
                    v.deleted = true
                end
                function methods:hswindow() end
                function methods:evaluateJavaScript(js, done)
                    s.scripts[#s.scripts + 1] = js
                    if done then
                        done(nil, { code = 0 })
                    end
                end
                setmetatable(v, {
                    __index = function(_, name)
                        return methods[name] or function() end
                    end,
                })
                s.views[#s.views + 1] = v
                return v
            end,
        },
    }
    local a = fake.new()
    a.add(1, { title = "Notes", app = "com.apple.Notes" })
    a.add(2, { title = "Chat", app = "com.example.none" })
    a.add(3, { title = "Notes 2", app = "com.apple.Notes" })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    a.focus_ = 2
    wm:act("send", "re")
    a.focus_ = 1
    s.a, s.wm = a, wm
    s.tide = {
        wm = wm,
        adapter = {
            focused = a.focused,
            log = function(line)
                s.logged = line
            end,
            after = function(_, fn)
                fn()
            end,
        },
    }
    _G.hs = s.hs
    package.loaded["tide.overview_hs"] = nil
    s.overview = require("tide.overview_hs").new(s.tide)
    return s
end

local function open(s, scope)
    s.overview.show(scope)
    local v = s.views[#s.views]
    v.navigate("didFinishNavigation", v)
    return v
end

t.test("Ctrl+Up opens it over the display, pausing focus follows mouse, and again closes it", function()
    local s = stub()
    local v = open(s, "all")
    t.eq(v.frame_, { x = 0, y = 0, w = 1920, h = 1080 })
    t.eq(s.wm.holding_keyboard, true)
    t.eq(s.wm:own_at(500, 500), true, "focus follows mouse leaves it be")
    t.eq(#s.encoded.groups, 2)
    s.overview.show("all")
    t.eq(v.deleted, true)
    t.eq(s.wm.holding_keyboard, false)
end)

t.test("the page starts on the window focused before it took the focus", function()
    local s = stub()
    -- The page's window takes the focus, and then macOS reports none.
    s.hs.webview.new = (function(make)
        return function(...)
            local v = make(...)
            local mt = getmetatable(v)
            local index = mt.__index
            mt.__index = function(t2, name)
                if name == "hswindow" then
                    return function()
                        return { focus = function() s.a.focus_ = nil end }
                    end
                end
                return index(t2, name)
            end
            return v
        end
    end)(s.hs.webview.new)
    open(s, "all")
    t.eq(s.encoded.focused, 1)
    s.overview.show("current")
    t.eq(s.encoded.focused, 1, "and after switching scope")
end)

t.test("the other key while it's open shows that scope in the same page", function()
    local s = stub()
    local v = open(s, "all")
    s.overview.show("current")
    t.eq(#s.views, 1)
    t.eq(v.deleted, false)
    t.eq(s.encoded.scope, "current")
    t.eq(#s.encoded.groups, 1)
end)

t.test("each app's icon is read once, and an app with none sends none", function()
    local s = stub()
    open(s, "all")
    s.overview.show("current")
    s.overview.show("all")
    t.eq(s.encoded.icons["com.apple.Notes"], "data:com.apple.Notes")
    t.eq(s.encoded.icons["com.example.none"], nil)
    local notes = 0
    for _, b in ipairs(s.icons) do
        notes = notes + (b == "com.apple.Notes" and 1 or 0)
    end
    t.eq(notes, 1)
    t.eq(#s.icons, 2)
end)

t.test("choosing a card activates its window, bringing its workspace", function()
    local s = stub()
    local v = open(s, "all")
    s.send({ activate = 2 })
    t.eq(v.deleted, true)
    t.eq(s.wm:current_ws(), "re")
    t.eq(s.wm.holding_keyboard, false)
end)

t.test("choosing a window you minimized restores it", function()
    local s = stub()
    s.a.focus_ = 3
    s.wm:act("minimize")
    t.eq(s.wm.windows[3].mine, true)
    open(s, "all")
    s.send({ activate = 3 })
    t.eq(s.wm.windows[3].mine, false)
end)

t.test("a header shows its workspace, and Esc or a click on empty space closes", function()
    local s = stub()
    local v = open(s, "all")
    s.send({ show = "re" })
    t.eq(v.deleted, true)
    t.eq(s.wm:current_ws(), "re")
    v = open(s, "current")
    s.send({ close = true })
    t.eq(v.deleted, true)
    t.eq(s.wm:current_ws(), "re")
end)

t.test("a window gone since it opened is said, and closes it", function()
    local s = stub()
    local v = open(s, "all")
    s.send({ activate = 99 })
    t.eq(v.deleted, true)
    t.eq(s.logged, "overview: window 99 has gone")
end)

t.test("clicking another window closes it", function()
    local s = stub()
    local v = open(s, "all")
    v.window("focusChange", v, false)
    t.eq(v.deleted, true)
    t.eq(s.wm.holding_keyboard, false)
end)

t.done("overview_hs")
