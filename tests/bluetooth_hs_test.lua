-- The Bluetooth page's blueutil runs (bluetooth_hs.lua), against a
-- stand-in blueutil and clock: read as the window opens and every few
-- seconds while it's open, one read at a time; a change runs blueutil,
-- shows the device busy until it's done, and reads again.

local t = require("t")
local json = require("json")

local PATH = "/opt/homebrew/bin/blueutil"
local BUDS = "aa-bb-cc-dd-ee-ff"

-- tide's world: blueutil there or not, each run waiting for the test to
-- answer it, and timers the test fires.
local function stub(opts)
    local s = { runs = {}, logged = {}, timers = {}, changes = 0, polled = 0 }
    _G.hs = { json = { encode = json.encode, decode = json.decode } }
    local tide = {
        adapter = {
            exists = function(p)
                return opts.installed ~= false and p == PATH
            end,
            run = function(path, args, done)
                s.runs[#s.runs + 1] = { path = path, args = table.concat(args, " "), done = done }
                return opts.starts ~= false
            end,
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
        bar = {
            bluetooth = {
                poll = function()
                    s.polled = s.polled + 1
                end,
            },
        },
    }
    package.loaded["tide.bluetooth_hs"] = nil
    s.bt = require("tide.bluetooth_hs").new(tide, function()
        s.changes = s.changes + 1
    end)
    -- Answers the last run still waiting.
    function s.answer(code, out, err)
        for i = #s.runs, 1, -1 do
            local r = s.runs[i]
            if not r.answered then
                r.answered = true
                r.done(code, err or "", out or "")
                return r.args
            end
        end
        error("no run waiting")
    end
    return s
end

local PAIRED = json.encode({ { address = BUDS, name = "Buds", connected = false } })

t.test("opening reads the power, then the devices, and again every few seconds", function()
    local s = stub({})
    s.bt.watch(true)
    t.eq(s.runs[1].args, "-p")
    s.bt.refresh()
    t.eq(#s.runs, 1, "one read at a time")
    t.eq(s.answer(0, "1\n"), "-p")
    t.eq(s.runs[2].args, "--paired --format json")
    s.answer(0, PAIRED)
    t.eq(s.bt.state().devices[1].name, "Buds")
    t.eq(s.changes, 1)
    -- The refresh asked for meanwhile reads once more, then the clock.
    t.eq(#s.runs, 3)
    s.answer(0, "1\n")
    s.answer(0, PAIRED)
    t.eq(s.changes, 1, "the same again doesn't redraw")
    t.eq(#s.timers, 1)
    t.eq(s.timers[1].seconds, 5)
    s.timers[1].fn()
    t.eq(#s.runs, 5)
    s.answer(0, "0\n")
    t.eq(s.bt.state().on, false)
    t.eq(s.bt.state().devices, {}, "none listed while it's off")
    t.eq(#s.runs, 5, "and not read")
    t.eq(s.changes, 2)
    s.bt.watch(false)
    t.eq(s.timers[2].stopped, true, "closing stops the clock")
end)

t.test("connecting shows the device busy, then reads again and has the bar read", function()
    local s = stub({})
    s.bt.refresh()
    s.answer(0, "1\n")
    s.answer(0, PAIRED)
    t.eq(s.bt.handle({ bluetoothConnect = BUDS }), true)
    t.eq(s.runs[3].args, "--connect " .. BUDS)
    t.eq(s.bt.state().devices[1].status, "Connecting…")
    s.bt.handle({ bluetoothConnect = BUDS })
    t.eq(#s.runs, 3, "not asked twice while it's busy")
    s.answer(1, "", "Failed to connect \"" .. BUDS .. "\"\n")
    t.eq(s.logged[#s.logged], "settings: blueutil --connect " .. BUDS .. " exited 1: Failed to connect \"" .. BUDS .. "\"")
    t.eq(s.bt.state().devices[1].busy, false)
    s.answer(0, "1\n")
    s.answer(0, PAIRED)
    t.eq(s.bt.state().problem, "Couldn't connect Buds: Failed to connect \"" .. BUDS .. "\"",
        "the page says it failed, though the read after is fine")
    s.bt.handle({ bluetoothDisconnect = BUDS })
    t.eq(s.bt.state().problem, nil, "until the next change")
    t.eq(s.runs[4].args, "-p", "read again")
    t.eq(s.polled, 1)
end)

t.test("the power switch runs blueutil --power, and waits while it does", function()
    local s = stub({})
    s.bt.handle({ bluetoothPower = false })
    t.eq(s.runs[1].args, "--power 0")
    t.eq(s.bt.state().switching, true)
    s.bt.handle({ bluetoothPower = true })
    t.eq(#s.runs, 1)
    s.answer(0, "")
    t.eq(s.bt.state().switching, false)
    t.eq(s.runs[2].args, "-p")
end)

t.test("no blueutil says so once, and runs nothing", function()
    local s = stub({ installed = false })
    s.bt.watch(true)
    s.bt.refresh()
    t.eq(#s.runs, 0)
    t.eq(s.bt.state().problem, "blueutil isn't installed (brew install blueutil, or setup-macos --wm tide)")
    t.eq(#s.logged, 1)
    s.bt.handle({ bluetoothConnect = BUDS })
    t.eq(#s.runs, 0)
end)

t.test("a blueutil that won't start says why", function()
    local s = stub({ starts = false })
    s.bt.refresh()
    t.eq(s.bt.state().problem, "couldn't start blueutil -p")
end)

t.done("bluetooth_hs")
