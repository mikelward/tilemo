-- The Network and Power pages (netpower.lua): Wi-Fi's On or Off and the
-- network it's joined to, how the Mac's online, and the battery, read as
-- the bar reads them; and the Wi-Fi switch.

local t = require("t")
local netpower = require("tide.netpower")

t.test("Wi-Fi joined to a network, online over it", function()
    local s = netpower.state({
        wifi = { power = true, rssi = -50, ssid = "Home", interface = "en0" },
        network = { primary = "en0", services = {} },
    })
    t.eq(s.network, { wifi = { on = true, line = "Joined to Home" }, online = "Online over Wi-Fi" })
end)

t.test("joined with no name says what macOS needs for one", function()
    local s = netpower.state({ wifi = { power = true, rssi = -50, interface = "en0" }, network = { primary = "en0" } })
    t.eq(s.network.wifi.line, "Joined to a network; its name needs Location Services for Hammerspoon")
    -- Joined while a wire carries the traffic: the signal says so.
    local wired = netpower.state({ wifi = { power = true, rssi = -50, interface = "en0" }, network = { primary = "en5" } })
    t.eq(wired.network.wifi.line, "Joined to a network; its name needs Location Services for Hammerspoon")
    t.eq(wired.network.online, "Online over a wire")
end)

t.test("Wi-Fi off, on a wire, or offline; and no Wi-Fi at all", function()
    local off = netpower.state({ wifi = { power = false, interface = "en0" }, network = { primary = "en5" } })
    t.eq(off.network, { wifi = { on = false, line = "Off" }, online = "Online over a wire" })
    local alone = netpower.state({ wifi = { power = true, interface = "en0" }, network = {} })
    t.eq(alone.network, { wifi = { on = true, line = "Not joined to a network" }, online = "Offline" })
    t.eq(netpower.state({ network = { primary = "utun3", services = {} } }).network.wifi, nil)
end)

t.test("the battery as the bar's hover says it, or none", function()
    t.eq(netpower.state({ battery = { percent = 84.4, remaining = 135 } }).power.battery, "Battery 84%, 2:15 left")
    t.eq(netpower.state({ battery = { percent = 100, charged = true } }).power.battery, "Battery 100%, charged")
    t.eq(netpower.state({}).power.battery, nil)
end)

t.test("the Wi-Fi switch, and nothing else, is these pages'", function()
    local set = {}
    local act = { set_wifi = function(on) set[#set + 1] = on end }
    t.eq(netpower.handle({ wifiPower = false }, act), true)
    t.eq(netpower.handle({ bluetoothPower = true }, act), false)
    t.eq(netpower.handle(nil, act), false)
    t.eq(set, { false })
end)

t.done("netpower")
