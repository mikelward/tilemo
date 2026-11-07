-- Light or dark on tide's schedule (theme_hs.lua), against a stand-in
-- macOS: System Events sets it when tide's files choose a mode, and
-- nothing does without one; a switch by hand, or the settings window's,
-- holds; and tide's own change isn't taken for one by hand.

local t = require("t")
local json = require("json")

local run = require("jsrun")("tide's appearance module")
if not run then
    print("SKIP light or dark on the Mac: no node")
    return
end

local function stub(files)
    local s = { dark = false, scripts = {}, logged = {}, timers = {} }
    _G.hs = {
        json = { encode = json.encode, decode = json.decode },
        inspect = tostring,
        host = {
            interfaceStyle = function()
                return s.dark and "Dark" or nil
            end,
        },
        osascript = {
            applescript = function(script)
                s.scripts[#s.scripts + 1] = script
                s.dark = script:match("to true$") ~= nil
                return true
            end,
        },
        distributednotifications = {
            new = function(fn)
                s.notify = fn
                return { start = function() end }
            end,
        },
        caffeinate = {
            watcher = {
                systemDidWake = 1,
                new = function(fn)
                    s.wake = fn
                    return { start = function() end }
                end,
            },
        },
    }
    local tide = {
        appearance_files = files,
        adapter = {
            read = function(path)
                local f = io.open(path)
                if not f then
                    return nil
                end
                local text = f:read("a")
                f:close()
                return text
            end,
            javascript = run,
            after = function(seconds, fn)
                local timer = { seconds = seconds, fn = fn }
                function timer.stop()
                    timer.stopped = true
                end
                s.timers[#s.timers + 1] = timer
                return timer
            end,
            log = function(line)
                s.logged[#s.logged + 1] = line
            end,
        },
    }
    -- macOS telling of a change, which tide looks at once it's free.
    function s.changed()
        s.notify()
        s.timers[#s.timers].fn()
    end
    package.loaded["tide.theme_hs"] = nil
    s.theme = require("tide.theme_hs").new(tide)
    s.tide = tide
    return s
end

t.test("with no mode in tide's files, tide leaves macOS's appearance alone", function()
    local s = stub({ shared = '{"darkWallpaper": "~/n.png"}' })
    t.eq(s.scripts, {})
    t.eq(s.theme.state().chosen, false)
    t.eq(s.timers[1].seconds, 3600, "and looks again within the hour")
end)

t.test("a mode set is followed, through System Events", function()
    local s = stub({ ["local"] = '{"mode": "dark"}' })
    t.eq(s.scripts, { 'tell application "System Events" to tell appearance preferences to set dark mode to true' })
    t.eq(s.theme.state(), { chosen = true, dark = true })
    s.changed()
    s.theme.apply()
    t.eq(#s.scripts, 1, "its own change isn't one by hand, and it's set already")
end)

t.test("a switch by hand holds until the settings change", function()
    local s = stub({ shared = '{"mode": "light"}' })
    t.eq(s.scripts, {})
    s.dark = true
    s.changed()
    s.theme.apply()
    t.eq(s.scripts, {}, "not switched back")
    s.tide.appearance_files = { shared = '{"mode": "light"}', ["local"] = '{"light": "08:00"}' }
    s.theme.apply()
    t.eq(s.scripts, { 'tell application "System Events" to tell appearance preferences to set dark mode to false' },
        "new settings drop it")
end)

t.test("the settings window's switch sets the other, and holds", function()
    local s = stub({ shared = '{"mode": "light"}' })
    s.theme.flip()
    t.eq(s.dark, true)
    s.changed()
    s.theme.apply()
    t.eq(#s.scripts, 1)
    t.eq(s.theme.state().dark, true)
end)

t.test("a wake looks again", function()
    local s = stub({ shared = '{"mode": "dark"}' })
    s.dark = false
    s.wake(1)
    t.eq(#s.scripts, 2)
end)

t.test("a file that's wrong is logged once", function()
    local s = stub({ shared = '{"mode": "dusk"}' })
    s.theme.apply()
    t.eq(s.logged, { 'appearance: appearance.json: mode must be one of "schedule", "sun", "light", "dark"' })
end)

t.done("theme_hs")
