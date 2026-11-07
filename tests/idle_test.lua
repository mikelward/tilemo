-- tide's idle timeline on the Mac (idle.lua): read from tide's idle files
-- as tide reads them, and which steps are due after so long with no input.

local t = require("t")
local json = require("json")
local idle = require("tide.idle")

t.test("nothing set leaves macOS's own; anything set runs tide's, over its defaults", function()
    t.eq(idle.load(nil, nil, json.decode).chosen, false)
    t.eq(idle.load("{}", "{}", json.decode).chosen, false)
    local l = idle.load('{"lock": 600}', '{"suspendOnAC": true}', json.decode)
    t.eq(l.chosen, true)
    t.eq(l.idle, { dim = 150, lock = 600, displaysOff = 330, suspend = 1800, suspendOnAC = true })
    t.eq(l.errors, {})
end)

t.test("a file that's wrong is named, and the last good timings stand", function()
    local good = idle.load('{"lock": 600}', nil, json.decode)
    local l = idle.load('{"lock": 0}', '{"nap": 5}', json.decode, good)
    t.eq(l.errors, {
        "idle.json: lock must be a whole number of seconds above 0",
        'idle.local.json: unknown setting "nap"; expected dim, lock, displaysOff, suspend, suspendOnAC',
    })
    t.eq(l.idle.lock, 600)
    t.eq(l.chosen, true)
    t.eq(idle.load('{"suspendOnAC": 1}', nil, json.decode).errors, { "idle.json: suspendOnAC must be true or false" })
    t.eq(idle.load('[1]', nil, json.decode).errors[1]:match("^idle.json: expected an object") ~= nil, true)
end)

t.test("each step is due once its time has passed, in order, once", function()
    local d = idle.DEFAULTS
    t.eq(idle.due(d, 100, {}, true), {})
    t.eq(idle.due(d, 150, {}, true), { "dim" })
    t.eq(idle.due(d, 340, { dim = true }, true), { "lock", "displaysOff" })
    t.eq(idle.due(d, 4000, {}, true), { "dim", "lock", "displaysOff", "suspend" }, "back from a long sleep")
    t.eq(idle.due(d, 4000, { dim = true, lock = true, displaysOff = true, suspend = true }, true), {})
end)

t.test("on AC there's no suspend unless set; an app holding things awake holds them", function()
    local d = idle.DEFAULTS
    t.eq(idle.due(d, 4000, { dim = true, lock = true, displaysOff = true }, false), {})
    local ac = { dim = 150, lock = 300, displaysOff = 330, suspend = 1800, suspendOnAC = true }
    t.eq(idle.due(ac, 4000, { dim = true, lock = true, displaysOff = true }, false), { "suspend" })
    t.eq(idle.due(d, 4000, {}, true, { display = true }), {}, "a video playing")
    t.eq(idle.due(d, 4000, {}, true, { system = true }), { "dim", "lock", "displaysOff" }, "a download")
end)

t.done("idle")
