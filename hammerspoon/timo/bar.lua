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

-- "1:05" for 65 minutes.
local function hm(minutes)
    -- macOS's estimate can be a fraction of a minute.
    minutes = math.floor(minutes)
    return string.format("%d:%02d", minutes // 60, minutes % 60)
end

local function battery_tip(b, p)
    local tip = "Battery " .. p .. "%"
    if b.charged then
        return tip .. ", charged"
    elseif b.charging then
        tip = tip .. ", charging"
        if b.to_full and b.to_full > 0 then
            tip = tip .. ", full in " .. hm(b.to_full)
        end
        return tip
    elseif b.remaining and b.remaining > 0 then
        return tip .. ", " .. hm(b.remaining) .. " left"
    end
    return tip
end

-- A short label for an input source: its first word's letters, up to
-- three, in capitals ("U.S." is US, "Dvorak" is DVO).
function M.source_label(name)
    local word = (name or ""):match("^%s*(%S+)") or ""
    return word:gsub("[^%w]", ""):sub(1, 3):upper()
end

-- The status icons, from what Hammerspoon reports (bar_hs.lua reads it):
--   battery = { percent, charging, charged, remaining, to_full } or nil on
--     a Mac without one, the times in minutes and negative when unknown,
--   audio = { volume = 0…100, muted } or nil with no output device,
--   mic = { muted } or nil with no input device,
--   camera = { in_use } or nil with no camera,
--   source = { current, list = { { name, method }, … } },
--   awake = whether the display is kept from sleeping,
--   wifi = { power, rssi, ssid, interface } or nil with no Wi-Fi interface,
--   network = { primary = the interface carrying traffic, or nil }.
-- The Wi-Fi network's name needs Location Services on recent macOS, so it
-- may be missing while the rest is there; then the icon shows without it.
-- Each item's drawing state from the raw readings, by name.
local ITEMS = {}

function ITEMS.battery(raw)
    local b = raw.battery
    if b and b.percent then
        local p = math.floor(b.percent + 0.5)
        return { percent = p, charging = b.charging or false, text = p .. "%", tip = battery_tip(b, p) }
    end
end

function ITEMS.volume(raw)
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
        return { level = level, muted = a.muted or false }
    end
end

function ITEMS.mic(raw)
    if raw.mic then
        return { muted = raw.mic.muted or false }
    end
end

-- Only while something has it on, as macOS's green dot.
function ITEMS.camera(raw)
    if raw.camera and raw.camera.in_use then
        return { in_use = true }
    end
end

function ITEMS.source(raw)
    local src = raw.source
    if src and src.current and src.list and #src.list > 1 then
        return { label = M.source_label(src.current), name = src.current }
    end
end

function ITEMS.awake(raw)
    if raw.awake ~= nil then
        return { on = raw.awake }
    end
end

function ITEMS.wifi(raw)
    local w = raw.wifi
    if w then
        local on = w.power or false
        return { on = on, bars = on and bars(w.rssi) or 0, name = on and w.ssid or nil }
    end
end

-- Which network carries traffic: Wi-Fi, a wire, or none. Without the
-- primary interface, Wi-Fi being on stands in for it.
function ITEMS.network(raw)
    local w = raw.wifi
    local primary
    if raw.network then
        primary = raw.network.primary
    elseif w and w.power then
        primary = w.interface or "wifi"
    end
    if primary and w and (primary == w.interface or primary == "wifi") then
        return { kind = "wifi" }
    elseif primary then
        return { kind = "wired" }
    end
    return { kind = "none" }
end

-- Every item at once. One that can't make sense of its reading is left
-- out, and `on_error(name, err)` hears why, so one bad reading can't stop
-- the rest of the bar.
function M.icons(raw, on_error)
    raw = raw or {}
    local out = {}
    for name, item in pairs(ITEMS) do
        local ok, v = pcall(item, raw)
        if ok then
            out[name] = v
        elseif on_error then
            on_error(name, v)
        else
            error(v, 0)
        end
    end
    return out
end

-- The next input source after `current`, in `list` order, wrapping.
function M.next_source(list, current)
    for i, s in ipairs(list) do
        if s.name == current then
            return list[i % #list + 1]
        end
    end
    return list[1]
end

-- The volume after a scroll step of 5% up or down, and whether it unmutes,
-- as the volume keys do.
function M.volume_step(volume, muted, d)
    local v = math.max(0, math.min(100, math.floor((volume or 0) + 0.5) + 5 * d))
    return v, muted and d > 0
end

-- The System Settings pane each icon opens *(unverified on macOS 26)*.
M.PANES = {
    battery = "x-apple.systempreferences:com.apple.Battery-Settings.extension",
    volume = "x-apple.systempreferences:com.apple.Sound-Settings.extension",
    wifi = "x-apple.systempreferences:com.apple.wifi-settings-extension",
    network = "x-apple.systempreferences:com.apple.Network-Settings.extension",
}

-- What a message from a bar's page does. Every message names its bar's
-- display, and acts there, not wherever the keys happen to be: a chip or a
-- scroll on display B's bar shows a workspace on B, and its clocks open the
-- dashboard on B. `act` holds what needs Hammerspoon: open(url),
-- dashboard(uuid), toggle(what) and volume(step).
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
    elseif body.toggle then
        act.toggle(body.toggle)
    elseif body.volume then
        act.volume(tonumber(body.volume))
    end
end

-- Scrolling over the workspaces steps from display `uuid`'s, stopping at 1
-- and 9, as Super+Left and Right do.
function M.step(wm, uuid, d)
    local cur = wm.screen_ws[uuid] or 1
    return math.max(1, math.min(wm.WORKSPACES, cur + d))
end

return M
