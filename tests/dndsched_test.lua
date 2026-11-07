-- Do Not Disturb on tide's schedule (dndsched.lua): the window tide's
-- module finds, run in node as JavaScriptCore would run it, and what each
-- start and end does.

local t = require("t")
local json = require("json")
local dndsched = require("tide.dndsched")
local dashboard = require("tide.dashboard")

t.test("a window starting turns it on; ending turns off only what it turned on", function()
    local state, set = dndsched.step(nil, false)
    t.eq(set, nil, "outside one at the first look: left as it is")
    state, set = dndsched.step(state, 1000)
    t.eq(set, true)
    state, set = dndsched.step(state, 1000)
    t.eq(set, nil, "the same window: nothing")
    state, set = dndsched.step(state, false)
    t.eq(set, false)
    state = dndsched.step(state, 2000)
    state = dndsched.own_changed(state)
    local _, after = dndsched.step(state, false)
    t.eq(after, nil, "turned on or off by hand: left as you set it")
    local _, first = dndsched.step(nil, 3000)
    t.eq(first, true, "started inside one: on")
end)

local run = require("jsrun")("tide's DND module")
if not run then
    print("SKIP Do Not Disturb's schedule: no node")
    t.done("dndsched")
    return
end

local function read(name)
    local f = assert(io.open("hammerspoon/tide/dashboard/" .. name))
    local s = f:read("a")
    f:close()
    return s
end
local sources = {}
for _, name in ipairs(dndsched.MODULES) do
    sources[name] = read(name)
end
local BUNDLE = dashboard.bundle(sources, dndsched.MODULES)

-- Wednesday 2026-11-04 at `h`:00, UTC, in ms.
local function at(h)
    return (os.time({ year = 2026, month = 11, day = 4, hour = 0 }) - os.time({ year = 1970, month = 1, day = 1, hour = 0 })
        + h * 3600) * 1000
end

local function window(shared, own, now)
    local ok, out = run(dndsched.script(BUNDLE, shared, own, now))
    local r, why = dndsched.read(ok, out, json.decode)
    assert(r, why)
    return r
end

t.test("tide's module finds the window, overnight into the next day", function()
    local on = '{"dndScheduled": true, "dndFrom": "22:00", "dndTo": "07:00"}'
    t.eq(window(on, nil, at(23)).window, at(22))
    t.eq(window(on, nil, at(30)).window, at(22), "06:00 the next day")
    t.eq(window(on, nil, at(12)).window, false)
    t.eq(window(nil, nil, at(23)).window, false, "off by default")
    t.eq(window(on, '{"dndDays": ["mon"]}', at(23)).window, false, "a Wednesday isn't listed")
end)

t.test("a file that's wrong is said", function()
    t.eq(window('{"dndFrom": "25:00"}', nil, at(12)).errors[1]:match("^notifications.json: ") ~= nil, true)
end)

t.done("dndsched")
