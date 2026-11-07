-- Do Not Disturb on tide's schedule through Hammerspoon (dndsched_hs.lua),
-- against stand-in presenter shortcuts and a clock: on as a window opens,
-- off as it closes, unless you changed it yourself meanwhile.

local t = require("t")
local json = require("json")

local run = require("jsrun")("tide's DND module")
if not run then
    print("SKIP Do Not Disturb's schedule on the Mac: no node")
    return
end

-- A schedule open all day, every day, and one that's off.
local ALWAYS = '{"dndScheduled": true, "dndFrom": "00:00", "dndTo": "23:59"}'
local OFF = '{"dndScheduled": false}'

local function stub(shared)
    local s = { set = {}, timers = {}, logged = {} }
    _G.hs = {
        json = { decode = json.decode },
        caffeinate = { watcher = { systemDidWake = 1, new = function() return { start = function() end } end } },
    }
    local tide = {
        notification_files = { shared = shared },
        presenter = {
            set_dnd = function(on)
                s.set[#s.set + 1] = on
            end,
        },
        adapter = {
            read = function(path)
                local f = io.open(path)
                local text = f and f:read("a")
                if f then
                    f:close()
                end
                return text
            end,
            javascript = run,
            after = function(seconds, fn)
                local timer = { seconds = seconds, fn = fn, stop = function() end }
                s.timers[#s.timers + 1] = timer
                return timer
            end,
            log = function(line)
                s.logged[#s.logged + 1] = line
            end,
        },
    }
    package.loaded["tide.dndsched_hs"] = nil
    s.dnd = require("tide.dndsched_hs").new(tide)
    s.tide = tide
    return s
end

t.test("on as a window opens, and off as it closes", function()
    local s = stub(ALWAYS)
    t.eq(s.set, { true })
    t.eq(s.timers[#s.timers].seconds, 60, "looked at every minute")
    s.tide.notification_files = { shared = OFF }
    s.dnd.look()
    t.eq(s.set, { true, false })
end)

t.test("changed by hand meanwhile, it's left as you set it", function()
    local s = stub(ALWAYS)
    s.dnd.own_changed()
    s.tide.notification_files = { shared = OFF }
    s.dnd.look()
    t.eq(s.set, { true })
end)

t.test("a file gone wrong in a window keeps the last good schedule", function()
    local s = stub(ALWAYS)
    s.tide.notification_files = { shared = '{"dndScheduled": true, "dndFrom": "25:00"}' }
    s.dnd.look()
    t.eq(s.set, { true }, "still on")
    t.eq(#s.logged, 1, "and the file's said")
    t.eq(s.logged[1]:match("notifications%.json") ~= nil, true, s.logged[1])
    s.tide.notification_files = { shared = OFF }
    s.dnd.look()
    t.eq(s.set, { true, false }, "put right, it's followed again")
end)

t.test("off by default: nothing", function()
    local s = stub(nil)
    t.eq(s.set, {})
    t.eq(s.logged, {})
end)

t.done("dndsched_hs")
