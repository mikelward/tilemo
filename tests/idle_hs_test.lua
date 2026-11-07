-- tide's idle timeline through Hammerspoon (idle_hs.lua), against a
-- stand-in macOS: idle time, power assertions, the battery, and a clock the
-- test fires. Each step acts once; input lifts the dim and starts again.

local t = require("t")
local json = require("json")

local function stub(files)
    local s = { idle = 0, did = {}, timers = {}, logged = {}, veils = 0, battery = true, assertions = {} }
    _G.hs = {
        json = { decode = json.decode },
        host = {
            idleTime = function()
                return s.idle
            end,
        },
        battery = {
            powerSource = function()
                return s.battery and "Battery Power" or "AC Power"
            end,
        },
        caffeinate = {
            currentAssertions = function()
                return s.assertions
            end,
            lockScreen = function()
                s.did[#s.did + 1] = "lock"
            end,
            systemSleep = function()
                s.did[#s.did + 1] = "suspend"
            end,
        },
        screen = {
            allScreens = function()
                return { { fullFrame = function() return { x = 0, y = 0, w = 100, h = 100 } end } }
            end,
        },
        canvas = {
            windowLevels = { screenSaver = 1000 },
            new = function()
                s.veils = s.veils + 1
                local v = {}
                for _, m in ipairs({ "appendElements", "level", "behavior", "show" }) do
                    v[m] = function() end
                end
                function v.delete()
                    s.veils = s.veils - 1
                end
                return v
            end,
        },
    }
    local tide = {
        idle_files = files,
        adapter = {
            log = function(line)
                s.logged[#s.logged + 1] = line
            end,
            run = function(path, args)
                s.did[#s.did + 1] = path .. " " .. table.concat(args, " ")
                return true
            end,
            after = function(seconds, fn)
                local timer = { seconds = seconds, fn = fn }
                function timer.stop()
                    timer.stopped = true
                end
                s.timers[#s.timers + 1] = timer
                return timer
            end,
        },
    }
    package.loaded["tide.idle_hs"] = nil
    s.idler = require("tide.idle_hs").new(tide)
    s.tide = tide
    -- The clock's next look, `seconds` with no input by then.
    function s.look(seconds)
        s.idle = seconds
        s.timers[#s.timers].fn()
    end
    return s
end

local SET = { shared = '{"dim": 30, "lock": 60, "displaysOff": 90, "suspend": 120}' }

t.test("with nothing set, nothing runs", function()
    local s = stub({})
    t.eq(#s.timers, 0)
    t.eq(s.idler.running(), false)
end)

t.test("the timeline, step by step, each once", function()
    local s = stub(SET)
    t.eq(s.timers[1].seconds, 5)
    s.look(30)
    t.eq(s.veils, 1, "dimmed")
    t.eq(s.timers[#s.timers].seconds, 1, "looked at every second while dimmed")
    s.look(31)
    t.eq(s.veils, 1, "once")
    s.look(95)
    t.eq(s.did, { "lock", "/usr/bin/pmset displaysleepnow" })
    s.look(120)
    t.eq(s.did[3], "suspend")
end)

t.test("input lifts the dim and starts the timeline again", function()
    local s = stub(SET)
    s.look(40)
    t.eq(s.veils, 1)
    s.look(2)
    t.eq(s.veils, 0, "lifted")
    s.look(35)
    t.eq(s.veils, 1, "and dims again")
end)

t.test("a video playing holds it all; on AC there's no sleep", function()
    local s = stub(SET)
    -- As IOPMCopyAssertionsByProcess gives them: by process ID, each a list.
    s.assertions = { [4242] = { { AssertType = "PreventUserIdleDisplaySleep", AssertName = "Video" } } }
    s.look(200)
    t.eq(s.did, {})
    t.eq(s.veils, 0)
    s.assertions = {}
    s.battery = false
    s.look(201)
    t.eq(s.did, { "lock", "/usr/bin/pmset displaysleepnow" })
end)

t.test("a download holds the sleep alone", function()
    local s = stub(SET)
    s.assertions = { [77] = { { AssertType = "PreventUserIdleSystemSleep", AssertName = "Download" } } }
    s.look(200)
    t.eq(s.did, { "lock", "/usr/bin/pmset displaysleepnow" })
end)

t.test("switched off and on again, the timeline starts afresh", function()
    local s = stub(SET)
    s.look(70)
    t.eq(s.did, { "lock" })
    s.tide.idle_files = {}
    s.idler.reload()
    s.tide.idle_files = SET
    s.idler.reload()
    s.look(75)
    t.eq(s.did, { "lock", "lock" }, "the lock again, not skipped")
end)

t.test("taking the settings out stops it, and lifts a dim", function()
    local s = stub(SET)
    s.look(40)
    s.tide.idle_files = {}
    s.idler.reload()
    t.eq(s.veils, 0)
    t.eq(s.timers[#s.timers].stopped, true)
    t.eq(s.idler.running(), false)
end)

t.done("idle_hs")
