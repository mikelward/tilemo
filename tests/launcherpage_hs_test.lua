-- The dashboard launcher's webview (launcherpage_hs.lua) against a stand-in
-- hs.webview: it's made hidden as the launcher starts, and a page that
-- fails to load is made again at the next key, whether or not one was
-- pressed while it loaded.

local t = require("t")

local function stub()
    local s = { views = {}, holds = {}, keys = {}, scripts = {} }
    -- The live hotkey for `key`, if any.
    function s.key(key)
        for i = #s.keys, 1, -1 do
            if s.keys[i].key == key and not s.keys[i].deleted then
                return s.keys[i]
            end
        end
    end
    s.hs = {
        settings = { get = function() end, set = function() end },
        inspect = function(v)
            return tostring(v)
        end,
        timer = {
            secondsSinceEpoch = function()
                return 0
            end,
        },
        drawing = { windowLevels = { modalPanel = 8 } },
        hotkey = {
            bind = function(mods, key, fn)
                local k = { mods = mods, key = key, fn = fn }
                function k:delete()
                    k.deleted = true
                end
                s.keys[#s.keys + 1] = k
                return k
            end,
        },
        screen = {
            mainScreen = function()
                return { fullFrame = function() return { x = 0, y = 0, w = 800, h = 600 } end }
            end,
        },
        webview = {
            usercontent = {
                new = function()
                    return {
                        setCallback = function(_, fn)
                            -- What the page sends, as WebKit hands it over.
                            s.send = function(body)
                                fn({ body = body })
                            end
                        end,
                    }
                end,
            },
            new = function(frame)
                local v = { frame_ = frame, shown = false, deleted = false }
                local methods = {}
                function methods:navigationCallback(fn)
                    v.navigate = fn
                end
                function methods:windowCallback(fn)
                    v.window = fn
                end
                function methods:show()
                    v.shown = true
                end
                function methods:hide()
                    v.shown = false
                end
                function methods:delete()
                    v.deleted = true
                end
                function methods:hswindow() end
                -- As Hammerspoon answers a script that ran.
                function methods:evaluateJavaScript(js, done)
                    s.ran = (s.ran or 0) + 1
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
    s.tide = {
        adapter = {
            focused = function() end,
            log = function(line)
                s.logged = line
            end,
            after = function(_, fn)
                fn()
            end,
        },
        wm = {
            current_screen = function()
                return "uuid-1"
            end,
            screen_by_uuid = function()
                return { full = { x = 0, y = 0, w = 800, h = 600 } }
            end,
            hold = function(_, what, on)
                s.holds[what] = on
            end,
            own_window = function(_, owner, frame)
                s.own = s.own or {}
                s.own[owner] = frame
            end,
            focus_window = function() end,
            focus_unburied = function(_, id)
                s.refocused = id
            end,
        },
    }
    return s
end

local function launcher_with(s)
    _G.hs = s.hs
    package.loaded["tide.launcherpage_hs"] = nil
    package.loaded["tide.launcher_hs"] = nil
    local launcher_hs = require("tide.launcher_hs")
    launcher_hs.collector = function()
        return function()
            return {}
        end
    end
    launcher_hs.fetch_tabs = function() end
    return require("tide.launcherpage_hs").new(s.tide)
end

t.test("the page is made hidden as the launcher starts, and a key shows it", function()
    local s = stub()
    local page = launcher_with(s)
    t.eq(#s.views, 1)
    t.eq(s.views[1].shown, false)
    page.show("launch")
    t.eq(#s.views, 1, "no second webview")
    t.eq(s.views[1].shown, true)
    t.eq(s.holds.launcher, true)
    page.cancel()
    t.eq(s.views[1].shown, false)
    t.eq(s.views[1].deleted, false, "kept for the next key")
    t.eq(s.holds.launcher, false)
end)

-- Back to the window you were in, unless that would bury another app's
-- float (wm.focus_unburied, SPEC.md §5.1).
t.test("closing the launcher goes back to the window you were in, keeping floats on top", function()
    local s = stub()
    s.tide.adapter.focused = function()
        return 7
    end
    local page = launcher_with(s)
    page.show("launch")
    page.cancel()
    t.eq(s.refocused, 7)
end)

t.test("a page that fails to load while open closes, and the next key makes it again", function()
    local s = stub()
    local page = launcher_with(s)
    page.show("launch")
    s.views[1].navigate("didFailProvisionalNavigation", s.views[1], nil, { code = -1009 })
    t.eq(s.views[1].deleted, true)
    t.eq(page.is_open(), false)
    t.eq(s.holds.launcher, false, "focus follows mouse comes back")
    page.show("launch")
    t.eq(#s.views, 2, "a new webview, loading the page again")
    t.eq(s.views[2].shown, true)
    t.eq(page.is_open(), true)
end)

t.test("a call the page ran isn't logged as a failure", function()
    local s = stub()
    _G.hs = s.hs
    s.hs.json = { encode = function() return "{}" end }
    s.hs.caffeinate = { get = function() return false end }
    s.tide.wm.listed = function() return {}, {} end
    s.tide.wm.bar_state = function() return {} end
    s.tide.wm.windows = {}
    s.tide.wm.screens = function() return {} end
    local page = launcher_with(s)
    s.views[1].navigate("didFinishNavigation", s.views[1])
    page.show("launch")
    t.eq(s.ran, 1, "the page was filled")
    t.eq(s.logged, nil)
    page.cancel()
end)

-- The rest of a loaded page's world: enough for an open to fill it.
local function loaded(s)
    s.hs.json = { encode = function() return "{}" end }
    s.hs.caffeinate = { get = function() return false end }
    s.tide.wm.listed = function() return {}, {} end
    s.tide.wm.bar_state = function() return {} end
    s.tide.wm.windows = {}
    s.tide.wm.screens = function() return {} end
    local page = launcher_with(s)
    s.views[1].navigate("didFinishNavigation", s.views[1])
    return page
end

t.test("Esc closes the launcher at once, without waiting on the page", function()
    local s = stub()
    local page = loaded(s)
    page.show("launch")
    local ran = #s.scripts
    t.eq(s.key("escape") ~= nil, true, "tide takes Esc while it's open")
    s.key("escape").fn()
    t.eq(page.is_open(), false)
    t.eq(s.views[1].shown, false)
    t.eq(#s.scripts, ran, "nothing asked of the page")
    t.eq(s.key("escape"), nil, "Esc is given back")
end)

t.test("with something typed, Esc clears the search and leaves it open", function()
    local s = stub()
    local page = loaded(s)
    page.show("launch")
    s.send({ typed = true })
    s.key("escape").fn()
    t.eq(page.is_open(), true)
    t.eq(s.scripts[#s.scripts], "tide.escape()")
    -- Cleared, the next Esc closes it.
    s.send({ typed = false })
    s.key("escape").fn()
    t.eq(page.is_open(), false)
end)

t.test("each open starts with nothing typed", function()
    local s = stub()
    local page = loaded(s)
    page.show("launch")
    s.send({ typed = true })
    page.cancel()
    page.show("launch")
    s.key("escape").fn()
    t.eq(page.is_open(), false)
end)

t.test("while it's open the launcher is one of tide's own windows, and closing says it's gone", function()
    local s = stub()
    local page = loaded(s)
    page.show("launch")
    t.eq(s.own.launcher, { x = 36, y = 26, w = 728, h = 520 }, "the panel, not the whole display")
    s.key("escape").fn()
    t.eq(s.own.launcher, nil)
end)

t.done("launcherpage_hs")
