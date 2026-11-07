-- Light or dark from tide's appearance files (theme.lua), worked out by
-- tide's own module, run in node as JavaScriptCore would run it: macOS's
-- own with no mode set, tide's schedule, a switch by hand holding until
-- the next change, and what's wrong with a file.

local t = require("t")
local json = require("json")
local theme = require("tide.theme")
local dashboard = require("tide.dashboard")

local run = require("jsrun")("tide's appearance module")
if not run then
    print("SKIP light or dark: no node")
    return
end

local function read(name)
    local f = assert(io.open("hammerspoon/tide/dashboard/" .. name))
    local s = f:read("a")
    f:close()
    return s
end
local sources = {}
for _, name in ipairs(theme.MODULES) do
    sources[name] = read(name)
end
local BUNDLE = dashboard.bundle(sources, theme.MODULES)

-- 2026-11-04 at `h`:`m`, UTC, in ms.
local function at(h, m)
    return (os.time({ year = 2026, month = 11, day = 4, hour = 0 }) - os.time({ year = 1970, month = 1, day = 1, hour = 0 })
        + h * 3600 + (m or 0) * 60) * 1000
end

local function plan(shared, own, now, held)
    local ok, out = run(theme.script(BUNDLE, shared, own, now, held, json.encode))
    local p, why = theme.read(ok, out, json.decode)
    assert(p, why)
    return p
end

local CLOCK = '{"mode": "schedule", "light": "07:00", "dark": "19:00"}'

t.test("with no mode in tide's files, macOS's own stays", function()
    t.eq(plan(nil, nil, at(12)).chosen, false)
    t.eq(plan('{"darkWallpaper": "~/n.png"}', "{}", at(12)).chosen, false)
end)

t.test("by the clock: light from 07:00, dark from 19:00, and when it changes", function()
    local noon = plan(CLOCK, nil, at(12))
    t.eq(noon.chosen, true)
    t.eq(noon.dark, false)
    t.eq(noon.next, at(19))
    local night = plan(nil, CLOCK, at(23))
    t.eq(night.dark, true)
    t.eq(night.next, at(31), "07:00 the next day")
    local always = plan('{"mode": "dark"}', nil, at(12))
    t.eq(always.dark, true)
    t.eq(always.next, nil)
end)

t.test("a switch by hand holds until the next change, then the schedule's back", function()
    local noon = plan(CLOCK, nil, at(12))
    t.eq(theme.hold(noon, false), nil, "what it says already needs no hold")
    local held = theme.hold(noon, true)
    local p = plan(CLOCK, nil, at(13), held)
    t.eq(p.dark, true)
    t.eq(p.held, true)
    t.eq(p.next, at(19))
    t.eq(plan(CLOCK, nil, at(20), held).held, false, "gone at the change")
    t.eq(plan(CLOCK, nil, at(13), held).dark, true)
    t.eq(plan('{"mode": "schedule", "light": "08:00", "dark": "19:00"}', nil, at(13), held).held, false,
        "and when the settings change")
    -- A fixed mode has no next change: a hold lasts until the settings do.
    local always = plan('{"mode": "light"}', nil, at(12))
    local flipped = theme.hold(always, true)
    t.eq(plan('{"mode": "light"}', nil, at(30), flipped).dark, true)
end)

t.test("a file that's wrong is said, and tide's last good settings stand", function()
    local p = plan('{"mode": "dusk"}', nil, at(12))
    t.eq(p.errors, { 'appearance.json: mode must be one of "schedule", "sun", "light", "dark"' })
    t.eq(p.chosen, false, "with nothing good yet, macOS's own stays")
    local good = plan('{"mode": "dark"}', nil, at(12))
    t.eq(good.dark, true)
    local ok, out = run(theme.script(BUNDLE, '{"mode": "dark"}', '{"dimStrength": 2}', at(12), nil, json.encode, good.good))
    local bad = theme.read(ok, out, json.decode)
    t.eq(#bad.errors, 1)
    t.eq(bad.chosen, true)
    t.eq(bad.dark, true, "still the last good mode, not tide's defaults")
end)

t.test("a look again at the next change, or within the hour", function()
    t.eq(theme.wait({ chosen = true, next = at(12, 30) }, at(12)), 1800)
    t.eq(theme.wait({ chosen = true, next = at(19) }, at(12)), theme.RECHECK)
    t.eq(theme.wait({}, at(12)), theme.RECHECK)
    t.eq(theme.wait(nil, at(12)), theme.RECHECK)
    t.eq(theme.wait({ chosen = false, next = at(12, 30) }, at(12)), theme.RECHECK,
        "no mode chosen: tide's default schedule isn't followed")
    t.eq(theme.wait({ chosen = true, next = at(12) }, at(12)), 1)
end)

t.test("System Events sets it", function()
    t.eq(theme.applescript(true), 'tell application "System Events" to tell appearance preferences to set dark mode to true')
    t.eq(theme.applescript(false):match("to false$") ~= nil, true)
    local p, why = theme.read(false, "boom", json.decode)
    t.eq(p, nil)
    t.eq(why, "couldn't work out light or dark: boom")
end)

t.done("theme")
