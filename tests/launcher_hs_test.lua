-- The chooser switcher (launcher_hs.lua) against a stand-in hs.chooser
-- that, as Hammerspoon's, can't be touched once deleted: the settings
-- window deletes it to switch launchers while a browser may still be
-- listing its tabs.

local t = require("t")

local function stub()
    local s = { tabs = {}, builds = 0 }
    local methods = {}
    local visible = false
    local on_choice
    function methods:isVisible()
        return visible
    end
    -- As HSChooser.m's: showing hands the query to the query callback.
    function methods:show()
        visible = true
        if s.typed then
            s.typed("")
        end
    end
    function methods:queryChangedCallback(fn)
        s.typed = fn
    end
    function methods:choices()
        s.builds = s.builds + 1
    end
    function methods:cancel()
        visible = false
        on_choice(nil)
    end
    function methods:query()
        return ""
    end
    function methods:delete()
        -- As libchooser.m's: the userdata loses its metatable.
        setmetatable(self, nil)
    end
    s.hs = {
        settings = {
            get = function() end,
            set = function() end,
        },
        timer = {
            secondsSinceEpoch = function()
                return 0
            end,
        },
        chooser = {
            new = function(fn)
                on_choice = fn
                local c = setmetatable({}, {
                    __index = function(_, name)
                        return methods[name] or function() end
                    end,
                })
                s.chooser = c
                return c
            end,
        },
        hotkey = {
            bind = function()
                return { delete = function() end }
            end,
        },
        host = {
            interfaceStyle = function() end,
        },
    }
    s.tide = {
        adapter = {
            focused = function() end,
            log = function() end,
        },
        wm = {
            hold = function() end,
            focus_window = function() end,
            focus_unburied = function(_, id)
                s.refocused = id
            end,
            note_tabs = function()
                s.noted = true
            end,
        },
    }
    return s
end

local function launcher_with(s)
    _G.hs = s.hs
    package.loaded["tide.launcher_hs"] = nil
    local launcher_hs = require("tide.launcher_hs")
    launcher_hs.collector = function()
        return function()
            return {}
        end
    end
    launcher_hs.fetch_tabs = function(_, done)
        s.tabs[#s.tabs + 1] = done
    end
    return launcher_hs.new(s.tide)
end

t.test("a browser's tabs that answer after the switcher is deleted are dropped", function()
    local s = stub()
    local launcher = launcher_with(s)
    launcher.show("launch")
    t.eq(launcher.is_open(), true)
    launcher.delete()
    local ok, err = pcall(s.tabs[1], { { title = "Docs", url = "https://example.com/" } })
    t.eq(ok, true, tostring(err))
    t.eq(s.noted, nil, "the tabs aren't noted for a deleted switcher")
end)

t.test("an open builds the rows once, though showing asks for them again", function()
    local s = stub()
    local launcher = launcher_with(s)
    launcher.show("launch")
    t.eq(s.builds, 1)
end)

t.test("typing, another tab and a browser's tabs each build them again", function()
    local s = stub()
    local launcher = launcher_with(s)
    launcher.show("launch")
    s.typed("sa")
    t.eq(s.builds, 2)
    launcher.show("windows")
    t.eq(s.builds, 3)
    s.tabs[1]({ { title = "Docs", url = "https://example.com/" } })
    t.eq(s.builds, 4)
    launcher.cancel()
    launcher.show("launch")
    t.eq(s.builds, 5, "a new open, built afresh")
end)

t.test("a browser's tabs that answer while the switcher's open join it", function()
    local s = stub()
    local launcher = launcher_with(s)
    launcher.show("launch")
    s.tabs[1]({ { title = "Docs", url = "https://example.com/" } })
    t.eq(s.noted, true)
    launcher.cancel()
end)

-- hs.application.get as Hammerspoon's application.lua has it: by bundle
-- ID first, and failing that, a walk of every running app by name, which
-- takes tens of milliseconds a time.
local function apps_stub(running)
    local s = { walks = 0, tasks = {} }
    _G.hs = {
        application = {
            applicationsForBundleID = function(bundle)
                return running[bundle] and { running[bundle] } or {}
            end,
            get = function(hint)
                if running[hint] then
                    return running[hint]
                end
                s.walks = s.walks + 1
            end,
        },
        task = {
            new = function(path, done, args)
                local task = { path = path, args = args }
                function task:start()
                    s.tasks[#s.tasks + 1] = task
                    return task
                end
                return task
            end,
        },
        timer = {
            doAfter = function()
                return { stop = function() end }
            end,
        },
    }
    package.loaded["tide.launcher_hs"] = nil
    return s, require("tide.launcher_hs")
end

t.test("asking for tabs doesn't walk every running app for a browser that isn't running", function()
    local s, launcher_hs = apps_stub({})
    launcher_hs.fetch_tabs({ adapter = { log = function() end } }, function() end)
    t.eq(s.walks, 0)
    t.eq(#s.tasks, 0, "no browser is asked")
end)

t.test("only a running browser is asked for its tabs", function()
    local s, launcher_hs = apps_stub({ ["com.apple.Safari"] = { name = "Safari" } })
    launcher_hs.fetch_tabs({ adapter = { log = function() end } }, function() end)
    t.eq(#s.tasks, 1)
    t.eq(s.tasks[1].path, "/usr/bin/osascript")
    t.eq(s.tasks[1].args[2]:find("Safari", 1, true) ~= nil, true, s.tasks[1].args[2])
end)

t.done("launcher_hs")
