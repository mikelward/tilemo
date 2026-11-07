-- The Network and Power pages' readings through Hammerspoon
-- (netpower_hs.lua), against a stand-in macOS: read as the bar reads them,
-- and the Wi-Fi switch set, then read again once it's had time.

local t = require("t")

local function stub(set_ok)
    local s = { logged = {}, timers = {}, changes = 0, wifi = true }
    _G.hs = {
        wifi = {
            interfaceDetails = function()
                return { power = s.wifi, rssi = s.wifi and -50 or 0, ssid = s.wifi and "Home" or nil, interface = "en0" }
            end,
            setPower = function(on)
                s.asked = on
                if set_ok then
                    s.wifi = on
                end
                return set_ok
            end,
        },
        network = {
            primaryInterfaces = function()
                return s.wifi and "en0" or false, false
            end,
            -- The services macOS has up: with `s.vpn`, a split-tunnel VPN's.
            configuration = {
                open = function()
                    return {
                        contents = function(_, key)
                            if key:find("^State:") then
                                return s.vpn and { ["State:/Network/Service/V1/IPv4"] = { InterfaceName = "utun4" } } or {}
                            end
                            return { [key] = { Type = "IPSec" } }
                        end,
                    }
                end,
            },
        },
        battery = {
            percentage = function()
                return nil
            end,
        },
    }
    local tide = {
        adapter = {
            log = function(line)
                s.logged[#s.logged + 1] = line
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
    package.loaded["tide.netpower_hs"] = nil
    s.np = require("tide.netpower_hs").new(tide, function()
        s.changes = s.changes + 1
    end)
    return s
end

t.test("read as the bar reads them", function()
    local s = stub(true)
    t.eq(s.np.state().network, { wifi = { on = true, line = "Joined to Home" }, online = "Online over Wi-Fi" })
    t.eq(s.np.state().power.battery, nil, "a Mac with no battery")
    s.vpn = true
    t.eq(s.np.state().network.online, "Online over Wi-Fi, through a VPN", "one that carries only some traffic too")
end)

t.test("read every few seconds while the window's open, without the bar", function()
    local s = stub(true)
    s.np.watch(true)
    t.eq(s.timers[1].seconds, 5)
    s.timers[1].fn()
    t.eq(s.changes, 1)
    t.eq(#s.timers, 2, "and again")
    s.np.watch(false)
    t.eq(s.timers[2].stopped, true)
end)

t.test("the switch sets Wi-Fi, and the page reads it once it's had time", function()
    local s = stub(true)
    t.eq(s.np.handle({ wifiPower = false }), true)
    t.eq(s.asked, false)
    t.eq(s.timers[1].seconds, 2)
    s.timers[1].fn()
    t.eq(s.changes, 1)
    t.eq(s.np.state().network.wifi.line, "Off")
end)

t.test("a switch macOS refuses is logged", function()
    local s = stub(false)
    s.np.handle({ wifiPower = false })
    t.eq(s.logged, { "settings: macOS didn't turn Wi-Fi off" })
end)

t.done("netpower_hs")
