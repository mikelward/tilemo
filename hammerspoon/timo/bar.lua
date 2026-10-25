-- The bar (SPEC.md §8): what it shows, as plain data. Pure Lua; bar_hs.lua
-- draws it, one strip per display along the top, with the menu bar set to
-- hide.
--
-- With the bar off, the menu bar item draws the same workspaces as text
-- (title()):
--
--   [3]  the workspace on the display you're on
--   (5)  showing on another display
--   2    has windows
--   4!   has a window wanting attention
--
-- Empty workspaces that aren't showing are left out.

local M = {}

-- tide's bar height (tide §7.1).
M.HEIGHT = 36

-- `ws` lists, for n = 1…9, { here, elsewhere, occupied, urgent }.
function M.title(ws)
    local parts = {}
    for n = 1, #ws do
        local w = ws[n]
        if w.here or w.elsewhere or w.occupied then
            local s = tostring(n)
            if w.here then
                s = "[" .. s .. "]"
            elseif w.elsewhere then
                s = "(" .. s .. ")"
            end
            if w.urgent then
                s = s .. "!"
            end
            parts[#parts + 1] = s
        end
    end
    return table.concat(parts, " ")
end

-- The strip along the top of a display's area, and the tiling area left
-- below it.
function M.strip(area, h)
    return { x = area.x, y = area.y, w = area.w, h = h }
end

function M.below(area, h)
    return { x = area.x, y = area.y + h, w = area.w, h = math.max(0, area.h - h) }
end

-- What display `uuid`'s bar shows: the workspaces as seen from there, the
-- focused window's title on the display that window is on, and the status
-- icons (icons()). `title` is the focused window's title.
function M.state(wm, uuid, title, icons)
    local ws = {}
    for n, s in ipairs(wm:bar_state(uuid)) do
        ws[n] = {
            n = n,
            current = s.here or false,
            elsewhere = s.elsewhere or false,
            occupied = s.occupied or false,
            urgent = s.urgent or false,
        }
    end
    -- The keys can act on another display than the focused window's, after
    -- an empty workspace is swapped in (wm:keep_keys_on), so the title goes
    -- by the window itself, and by the keys only with no managed window.
    local f = wm.a.focused()
    local w = f and wm.windows[f]
    local on = w and w.ws and wm:shown(w.ws) or wm:current_screen()
    return { uuid = uuid, workspaces = ws, title = on == uuid and title or "", icons = icons or {} }
end

-- Wi-Fi signal in bars, 0 to 3, from the RSSI in dBm.
local function bars(rssi)
    if not rssi then
        return 0
    elseif rssi >= -60 then
        return 3
    elseif rssi >= -70 then
        return 2
    elseif rssi >= -80 then
        return 1
    end
    return 0
end

-- The status icons, from what Hammerspoon reports (bar_hs.lua reads it):
--   battery = { percent, charging } or nil on a Mac without one,
--   audio = { volume = 0…100, muted } or nil with no output device,
--   wifi = { power, rssi, ssid } or nil with no Wi-Fi interface.
-- The network name needs Location Services on recent macOS, so it may be
-- missing while the rest is there; then the icon shows without it.
function M.icons(raw)
    raw = raw or {}
    local out = {}
    local b = raw.battery
    if b and b.percent then
        local p = math.floor(b.percent + 0.5)
        out.battery = { percent = p, charging = b.charging or false, text = p .. "%" }
    end
    local a = raw.audio
    if a and a.volume then
        local v = math.floor(a.volume + 0.5)
        local level = "high"
        if a.muted or v <= 0 then
            level = "mute"
        elseif v < 34 then
            level = "low"
        elseif v < 67 then
            level = "mid"
        end
        out.volume = { level = level, muted = a.muted or false }
    end
    local w = raw.wifi
    if w then
        local on = w.power or false
        out.wifi = { on = on, bars = on and bars(w.rssi) or 0, name = on and w.ssid or nil }
    end
    return out
end

-- The System Settings pane each icon opens *(unverified on macOS 26)*.
M.PANES = {
    battery = "x-apple.systempreferences:com.apple.Battery-Settings.extension",
    volume = "x-apple.systempreferences:com.apple.Sound-Settings.extension",
    wifi = "x-apple.systempreferences:com.apple.wifi-settings-extension",
}

-- What a message from a bar's page does. Every message names its bar's
-- display, and acts there, not wherever the keys happen to be: a chip or a
-- scroll on display B's bar shows a workspace on B, and its clocks open the
-- dashboard on B. `act` holds what needs Hammerspoon: open(url) and
-- dashboard(uuid).
function M.handle(wm, body, act)
    local uuid = body.uuid
    if body.show then
        wm:show(tonumber(body.show), uuid)
    elseif body.step and uuid then
        wm:show(M.step(wm, uuid, tonumber(body.step)), uuid)
    elseif body.open then
        local url = M.PANES[body.open]
        if url then
            act.open(url)
        end
    elseif body.dashboard then
        act.dashboard(uuid)
    end
end

-- Scrolling over the workspaces steps from display `uuid`'s, stopping at 1
-- and 9, as Super+Left and Right do.
function M.step(wm, uuid, d)
    local cur = wm.screen_ws[uuid] or 1
    return math.max(1, math.min(wm.WORKSPACES, cur + d))
end

return M
