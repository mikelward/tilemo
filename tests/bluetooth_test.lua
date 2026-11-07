local t = require("t")
local bluetooth = require("tide.bluetooth")
local bar = require("tide.bar")

t.test("blueutil -p's 1 is on and 0 is off", function()
    t.eq(bluetooth.parse(0, "1\n"), { on = true })
    t.eq(bluetooth.parse(0, "0\n"), { on = false })
    t.eq(bluetooth.parse(0, " 1 "), { on = true })
end)

t.test("a blueutil that fails or says something else is an error saying what", function()
    local s, why = bluetooth.parse(1, "", "Error: Bluetooth not available\n")
    t.eq(s, nil)
    t.eq(why, "blueutil -p exited 1: Error: Bluetooth not available")
    s, why = bluetooth.parse(0, "on\n", "")
    t.eq(s, nil)
    t.eq(why, 'blueutil -p printed "on", not 1 or 0')
    s, why = bluetooth.parse(2, "", "")
    t.eq(why, "blueutil -p exited 2")
end)

t.test("blueutil is found where Homebrew puts it, on Apple silicon first", function()
    local have = { ["/usr/local/bin/blueutil"] = true }
    local exists = function(p)
        return have[p] == true
    end
    t.eq(bluetooth.find(exists), "/usr/local/bin/blueutil")
    have["/opt/homebrew/bin/blueutil"] = true
    t.eq(bluetooth.find(exists), "/opt/homebrew/bin/blueutil")
    t.eq(bluetooth.find(function() return false end), nil)
end)

-- A poller with a fake blueutil: `runs` collects each run's callback.
local function poller(path)
    local runs, logs, changes = {}, {}, 0
    local p = bluetooth.poller({
        find = function()
            return path
        end,
        run = function(cmd, args, done)
            runs[#runs + 1] = { cmd = cmd, args = args, done = done }
            return true
        end,
        log = function(msg)
            logs[#logs + 1] = msg
        end,
        changed = function()
            changes = changes + 1
        end,
    })
    return p, runs, logs, function()
        return changes
    end
end

t.test("the poller reads blueutil -p, asynchronously, and says when the state changes", function()
    local p, runs, logs, changes = poller("/opt/homebrew/bin/blueutil")
    p:poll()
    t.eq(#runs, 1)
    t.eq(runs[1].cmd, "/opt/homebrew/bin/blueutil")
    t.eq(runs[1].args, { "-p" })
    t.eq(p.state, nil, "nothing until it answers")
    p:poll()
    t.eq(#runs, 1, "no second run while one is out")
    runs[1].done(0, "1\n", "")
    t.eq(p.state, { on = true })
    t.eq(changes(), 1)
    p:poll()
    runs[2].done(0, "1\n", "")
    t.eq(changes(), 1, "the same state isn't a change")
    p:poll()
    runs[3].done(0, "0\n", "")
    t.eq(p.state, { on = false })
    t.eq(changes(), 2)
    t.eq(logs, {})
end)

t.test("an error hides the icon, logged once until it changes or clears", function()
    local p, runs, logs = poller("/opt/homebrew/bin/blueutil")
    p:poll()
    runs[1].done(0, "1\n", "")
    p:poll()
    runs[2].done(1, "", "Error: Bluetooth not available\n")
    t.eq(p.state, nil)
    p:poll()
    runs[3].done(1, "", "Error: Bluetooth not available\n")
    t.eq(#logs, 1)
    t.eq(logs[1], "bar: Bluetooth on/off hidden: blueutil -p exited 1: Error: Bluetooth not available")
    p:poll()
    runs[4].done(0, "0\n", "")
    p:poll()
    runs[5].done(1, "", "Error: Bluetooth not available\n")
    t.eq(#logs, 2, "said again once it had cleared")
end)

t.test("with no blueutil, nothing runs, the icon hides and the log says so once", function()
    local p, runs, logs = poller(nil)
    p:poll()
    p:poll()
    t.eq(#runs, 0)
    t.eq(p.state, nil)
    t.eq(logs, { "bar: Bluetooth on/off hidden: blueutil isn't installed (brew install blueutil, or setup-macos --wm tide)" })
end)

t.test("a blueutil that can't start is an error, and the next poll tries again", function()
    local logs = {}
    local tries = 0
    local p = bluetooth.poller({
        find = function()
            return "/opt/homebrew/bin/blueutil"
        end,
        run = function()
            tries = tries + 1
            return false, "couldn't start it"
        end,
        log = function(msg)
            logs[#logs + 1] = msg
        end,
        changed = function() end,
    })
    p:poll()
    p:poll()
    t.eq(tries, 2, "not left waiting for an answer that won't come")
    t.eq(logs, { "bar: Bluetooth on/off hidden: couldn't start blueutil: couldn't start it" })
end)

t.test("the bar's Bluetooth item is on or off, and absent without a reading", function()
    t.eq(bar.icons({}).bluetooth, nil)
    t.eq(bar.icons({ bluetooth = { on = true } }).bluetooth, { on = true })
    t.eq(bar.icons({ bluetooth = { on = false } }).bluetooth, { on = false })
    t.eq(bar.icons({ bluetooth_audio = { "Buds" } }).headphones, { devices = { { name = "Buds" } } }, "headphones need no blueutil")
end)

local json = require("json")

t.test("the Bluetooth page's paired devices, from blueutil's JSON, named or by address", function()
    local out = json.encode({
        { address = "aa-bb-cc-dd-ee-ff", name = "Buds", connected = true, paired = true },
        { address = "11-22-33-44-55-66", connected = false, paired = true },
        { address = "--help", name = "Not one", connected = false },
        "not a device",
    })
    t.eq(bluetooth.parse_paired(0, out, "", json.decode), {
        { address = "aa-bb-cc-dd-ee-ff", name = "Buds", connected = true },
        { address = "11-22-33-44-55-66", name = "11-22-33-44-55-66", connected = false },
    })
    t.eq(bluetooth.parse_paired(0, "[]", "", json.decode), {})
end)

t.test("a blueutil --paired that fails or prints something else says what", function()
    local d, why = bluetooth.parse_paired(1, "", "Error: Bluetooth not available\n", json.decode)
    t.eq(d, nil)
    t.eq(why, "blueutil --paired exited 1: Error: Bluetooth not available")
    d, why = bluetooth.parse_paired(0, "Buds", "", json.decode)
    t.eq(d, nil)
    t.eq(why, "blueutil --paired printed something that isn't a JSON list")
end)

t.test("only an address reaches blueutil, never a name or an option", function()
    t.eq(bluetooth.address("aa-bb-cc-dd-ee-ff"), "aa-bb-cc-dd-ee-ff")
    t.eq(bluetooth.address("AA:BB:CC:DD:EE:FF"), "AA:BB:CC:DD:EE:FF")
    t.eq(bluetooth.address("--power"), nil)
    t.eq(bluetooth.address("Buds"), nil)
    t.eq(bluetooth.address("aa-bb-cc-dd-ee-ff -p 0"), nil)
    t.eq(bluetooth.address(12), nil)
end)

t.test("the page lists the devices while it's on, connected first, then by name", function()
    local devices = {
        { address = "33-33-33-33-33-33", name = "keyboard", connected = false },
        { address = "11-11-11-11-11-11", name = "Mouse", connected = false },
        { address = "22-22-22-22-22-22", name = "Buds", connected = true },
    }
    local s = bluetooth.page_state({ on = true, devices = devices, busy = { ["11-11-11-11-11-11"] = "connecting" } })
    t.eq(s.on, true)
    t.eq(s.switching, false)
    t.eq(s.devices, {
        { address = "22-22-22-22-22-22", name = "Buds", connected = true, busy = false, status = "Connected" },
        { address = "33-33-33-33-33-33", name = "keyboard", connected = false, busy = false, status = "" },
        { address = "11-11-11-11-11-11", name = "Mouse", connected = false, busy = true, status = "Connecting…" },
    })
    t.eq(bluetooth.page_state({ on = false, devices = devices }).devices, {}, "none while it's off")
    local unread = bluetooth.page_state({ problem = bluetooth.MISSING })
    t.eq(unread.on, nil)
    t.eq(unread.problem, bluetooth.MISSING)
end)

t.test("the page's messages switch it, and connect or disconnect an address alone", function()
    local did = {}
    local act = {
        set_power = function(on) did[#did + 1] = { "power", on } end,
        connect = function(a) did[#did + 1] = { "connect", a } end,
        disconnect = function(a) did[#did + 1] = { "disconnect", a } end,
    }
    t.eq(bluetooth.handle({ bluetoothPower = false }, act), true)
    t.eq(bluetooth.handle({ bluetoothConnect = "aa-bb-cc-dd-ee-ff" }, act), true)
    t.eq(bluetooth.handle({ bluetoothDisconnect = "aa-bb-cc-dd-ee-ff" }, act), true)
    t.eq(bluetooth.handle({ bluetoothConnect = "--power" }, act), true, "the page's, but nothing done")
    t.eq(bluetooth.handle({ soundMute = true }, act), false)
    t.eq(bluetooth.handle("x", act), false)
    t.eq(did, { { "power", false }, { "connect", "aa-bb-cc-dd-ee-ff" }, { "disconnect", "aa-bb-cc-dd-ee-ff" } })
end)

t.done("bluetooth")
