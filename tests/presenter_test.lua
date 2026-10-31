local t = require("t")
local presenter = require("tilemo.presenter")

local OFF = presenter.OFF

t.test("Super+P turns on Do Not Disturb and keep awake, remembering keep awake", function()
    local step = presenter.presenter(OFF, false)
    t.eq(step, { state = { presenting = true, awake_before = false }, awake = true, dnd = presenter.DND_ON })
end)

t.test("Super+P again puts keep awake back as it was, and turns Do Not Disturb off", function()
    for _, before in ipairs({ false, true }) do
        local on = presenter.presenter(OFF, before)
        local off = presenter.presenter(on.state, true)
        t.eq(off, { state = OFF, awake = before, dnd = presenter.DND_OFF }, tostring(before))
    end
end)

t.test("outside presenter mode, Super+S toggles keep awake and nothing else", function()
    t.eq(presenter.keep_awake(OFF, false), { state = OFF, awake = true })
    t.eq(presenter.keep_awake(OFF, true), { state = OFF, awake = false })
    t.eq(presenter.keep_awake(nil, false), { state = OFF, awake = true })
end)

t.test("Super+S while presenting turns keep awake off and ends presenter mode, leaving Do Not Disturb on", function()
    local on = presenter.presenter(OFF, true)
    t.eq(presenter.keep_awake(on.state, true), { state = OFF, awake = false })
end)

t.test("the launcher's Do Not Disturb toggles it, and while presenting turns it off and ends presenter mode", function()
    t.eq(presenter.dnd(OFF), { state = OFF, dnd = presenter.DND_TOGGLE })
    local on = presenter.presenter(OFF, false)
    t.eq(presenter.dnd(on.state), { state = OFF, dnd = presenter.DND_OFF })
end)

t.test("the signs say what the key did", function()
    t.eq(presenter.awake_sign(true), "Keeping awake")
    t.eq(presenter.awake_sign(false), "Not keeping awake")
    t.eq(presenter.presenter_sign(true), "Presenting")
    t.eq(presenter.presenter_sign(false), "Presenter mode off")
end)

t.test("a missing shortcut is found in `shortcuts list`'s lines, exactly", function()
    local list = "Do Not Disturb On\nDo Not Disturb Off  \nSomething else\n"
    t.eq(presenter.missing(list, { presenter.DND_ON, presenter.DND_OFF }), {})
    t.eq(presenter.missing("Do Not Disturb On\n", { presenter.DND_ON, presenter.DND_OFF }), { presenter.DND_OFF })
    t.eq(presenter.missing("Do Not Disturb Only\n", { presenter.DND_ON }), { presenter.DND_ON })
    t.eq(presenter.missing(nil, { presenter.DND_TOGGLE }), { presenter.DND_TOGGLE })
end)

t.test("the setup notice names each shortcut, what it does, and that keep awake still works", function()
    local text = presenter.setup_notice({ presenter.DND_ON, presenter.DND_OFF })
    t.eq(text:find("\"Do Not Disturb On\" (turn it on until turned off)", 1, true) ~= nil, true, text)
    t.eq(text:find("\"Do Not Disturb Off\" (turn it off)", 1, true) ~= nil, true, text)
    t.eq(text:find("Set Focus", 1, true) ~= nil, true, text)
    t.eq(text:find("Keep awake works without them.", 1, true) ~= nil, true, text)
end)

t.test("a failed shortcut says its exit and what it printed", function()
    t.eq(presenter.failed_notice("Do Not Disturb On", 1, "Error: not allowed\n"),
        "The \"Do Not Disturb On\" shortcut failed (exit 1): Error: not allowed, so Do Not Disturb didn't change.")
    t.eq(presenter.failed_notice("Do Not Disturb Off", 1, ""),
        "The \"Do Not Disturb Off\" shortcut failed (exit 1), so Do Not Disturb didn't change.")
end)

-- A fake runner: each call is kept, with its callback, for the test to
-- finish in whatever order it likes.
local function fake_run()
    local calls = {}
    return calls, function(path, args, done)
        calls[#calls + 1] = { path = path, args = args, done = done }
        return true
    end
end

local LIST = presenter.DND_ON .. "\n" .. presenter.DND_OFF .. "\n" .. presenter.DND_TOGGLE .. "\n"

local function ran(calls)
    local out = {}
    for _, c in ipairs(calls) do
        out[#out + 1] = table.concat(c.args, " ")
    end
    return out
end

t.test("a second request while the first runs waits, so the last one asked runs last", function()
    local calls, run = fake_run()
    local d = presenter.driver(run, function() end)
    d.request(presenter.DND_ON)
    d.request(presenter.DND_OFF)
    t.eq(ran(calls), { "list" }, "one at a time")
    calls[1].done(0, "", LIST)
    t.eq(ran(calls), { "list", "run Do Not Disturb On" })
    calls[2].done(0, "", "")
    t.eq(ran(calls), { "list", "run Do Not Disturb On", "list" }, "then Off's lookup")
    calls[3].done(0, "", LIST)
    t.eq(ran(calls), { "list", "run Do Not Disturb On", "list", "run Do Not Disturb Off" }, "then Off")
end)

t.test("of several waiting, only the latest runs, so Super+P three times ends on", function()
    local calls, run = fake_run()
    local d = presenter.driver(run, function() end)
    d.request(presenter.DND_ON)
    d.request(presenter.DND_OFF)
    d.request(presenter.DND_ON)
    calls[1].done(0, "", LIST)
    calls[2].done(0, "", "")
    -- On was found the first time, so it runs without a lookup.
    calls[3].done(0, "", "")
    t.eq(ran(calls), { "list", "run Do Not Disturb On", "run Do Not Disturb On" })
    t.eq(d.busy, false)
end)

t.test("waiting toggles compose: two cancel, and one flips a waiting on or off", function()
    t.eq(presenter.queued(nil, presenter.DND_TOGGLE), presenter.DND_TOGGLE)
    t.eq(presenter.queued(presenter.DND_TOGGLE, presenter.DND_TOGGLE), nil)
    t.eq(presenter.queued(presenter.DND_ON, presenter.DND_TOGGLE), presenter.DND_OFF)
    t.eq(presenter.queued(presenter.DND_OFF, presenter.DND_TOGGLE), presenter.DND_ON)
    t.eq(presenter.queued(presenter.DND_TOGGLE, presenter.DND_ON), presenter.DND_ON)
    t.eq(presenter.queued(presenter.DND_ON, presenter.DND_OFF), presenter.DND_OFF)
end)

t.test("a missing shortcut is said once, and the next request still runs", function()
    local calls, run = fake_run()
    local said = {}
    local d = presenter.driver(run, function(text)
        said[#said + 1] = text
    end)
    d.request(presenter.DND_ON)
    calls[1].done(0, "", "Something else\n")
    t.eq(#said, 1)
    t.eq(said[1]:find("\"Do Not Disturb On\"", 1, true) ~= nil, true, said[1])
    d.request(presenter.DND_ON)
    calls[2].done(0, "", "")
    t.eq(#said, 1, "not said again")
    d.request(presenter.DND_OFF)
    calls[3].done(0, "", LIST)
    t.eq(ran(calls), { "list", "list", "list", "run Do Not Disturb Off" })
end)

t.test("a shortcut that fails, or a runner that can't start, is reported and frees the queue", function()
    local calls, run = fake_run()
    local said = {}
    local d = presenter.driver(run, function(text)
        said[#said + 1] = text
    end)
    d.request(presenter.DND_ON)
    calls[1].done(0, "", LIST)
    calls[2].done(1, "Error: not allowed", "")
    t.eq(said, { presenter.failed_notice(presenter.DND_ON, 1, "Error: not allowed") })
    t.eq(d.busy, false)
    local none = presenter.driver(function()
        return false
    end, function(text)
        said[#said + 1] = text
    end)
    none.request(presenter.DND_OFF)
    t.eq(none.busy, false)
    t.eq(said[2]:find("couldn't start", 1, true) ~= nil, true, said[2])
end)

t.done("presenter")
