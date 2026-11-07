-- The settings window's Network and Power pages (SPEC.md §15): Wi-Fi On or
-- Off and the network it's joined to, how the Mac's online, and the
-- battery, read as the bar reads them (bar.lua's icons), so the two agree.
-- Pure Lua: bar_hs's readings in, what the pages show out.

local bar = require("tide.bar")

local M = {}

local ONLINE = { wifi = "Online over Wi-Fi", wired = "Online over a wire", none = "Offline" }

-- What the pages show, from `raw` (bar.icons' readings: wifi, network,
-- battery): `network.wifi` { on, line } or nil with no Wi-Fi, and
-- `network.online`; `power.battery`, its line, or nil with none.
function M.state(raw, on_error)
    local icons = bar.icons(raw or {}, on_error or function() end)
    local net = icons.network or { kind = "none" }
    local wifi
    local w = icons.wifi
    if w then
        local line
        if not w.on then
            line = "Off"
        elseif w.name and w.name ~= "" then
            line = "Joined to " .. w.name
        elseif net.kind == "wifi" or ((raw and raw.wifi and raw.wifi.rssi) or 0) < 0 then
            -- Joined, by the route or by the signal, as the bar tells it, even
            -- while a wire carries the traffic. macOS gives the name only
            -- with Location Services on for Hammerspoon.
            line = "Joined to a network; its name needs Location Services for Hammerspoon"
        else
            line = "Not joined to a network"
        end
        wifi = { on = w.on, line = line }
    end
    return {
        network = { wifi = wifi, online = ONLINE[net.kind] .. (net.vpn and ", through a VPN" or "") },
        power = { battery = icons.battery and icons.battery.tip or nil },
    }
end

-- Does what a message from the page asks, through `act`: set_wifi(on).
-- Returns whether it was one of these pages'.
function M.handle(body, act)
    if type(body) ~= "table" or body.wifiPower == nil then
        return false
    end
    act.set_wifi(body.wifiPower == true)
    return true
end

return M
