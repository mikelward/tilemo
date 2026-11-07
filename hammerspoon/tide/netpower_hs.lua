-- The Network and Power pages' readings (netpower.lua), through
-- hs.wifi, hs.network and hs.battery, as the bar reads them; and Wi-Fi's
-- On or Off, through hs.wifi.setPower.

local netpower = require("tide.netpower")
local bar_hs = require("tide.bar_hs")

local M = {}

-- Seconds Wi-Fi is given to come on or go off before the page reads it.
M.SETTLE = 2
-- Seconds between reads while the window's open, so the pages follow the
-- battery and the network without the bar.
M.EVERY = 5

-- `tide` is the started tide module: its adapter (log, after).
-- `changed()` is called once a change has had time to show.
function M.new(tide, changed)
    local self = {}
    local a = tide.adapter
    local timer

    function self.state()
        local d = hs.wifi.interfaceDetails()
        local v4, v6 = hs.network.primaryInterfaces()
        local p = hs.battery.percentage()
        return netpower.state({
            wifi = d and { power = d.power, rssi = d.rssi, ssid = d.ssid, interface = d.interface },
            -- false with no route, as Hammerspoon reports it. The services
            -- tell a VPN that carries only some traffic, as the bar's do.
            network = { primary = v4 or v6 or nil, services = bar_hs.services(self) },
            battery = p and {
                percent = p,
                charging = hs.battery.isCharging(),
                charged = hs.battery.isCharged(),
                remaining = hs.battery.timeRemaining(),
                to_full = hs.battery.timeToFullCharge(),
            },
        }, function(name, err)
            a.log("settings: couldn't read " .. name .. ": " .. tostring(err))
        end)
    end

    self.act = {
        set_wifi = function(on)
            if not hs.wifi.setPower(on) then
                a.log("settings: macOS didn't turn Wi-Fi " .. (on and "on" or "off"))
            end
            a.after(M.SETTLE, changed)
        end,
    }

    -- Read every few seconds while `open`, from now; stop when it isn't.
    function self.watch(open)
        if timer then
            timer.stop()
            timer = nil
        end
        if open then
            local function tick()
                changed()
                timer = a.after(M.EVERY, tick)
            end
            timer = a.after(M.EVERY, tick)
        end
    end

    function self.handle(body)
        return netpower.handle(body, self.act)
    end

    return self
end

return M
