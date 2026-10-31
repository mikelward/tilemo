-- The bar (SPEC.md §8): what it shows, as plain data. Pure Lua; bar_hs.lua
-- draws it, one strip per display along the top, with the menu bar set to
-- hide.
--
-- With the bar off, the menu bar item draws the same workspaces as text,
-- by name (title()):
--
--   [in]   the workspace on the display you're on
--   (web)  showing on another display
--   docs   neither
--   mail!  has a window wanting attention
--
-- Every workspace is listed: only "in" is ever empty and not showing, since
-- the rest go once they're left empty (SPEC.md §6.1).

local M = {}

-- tide's bar height (tide §7.1).
M.HEIGHT = 36

-- A long name is cut to this many characters, with an ellipsis (SPEC.md
-- §8, a guess to confirm).
M.NAME_MAX = 16

-- `name` cut to M.NAME_MAX characters, counting UTF-8 characters, with an
-- ellipsis if it was cut.
function M.short(name)
    local ok, len = pcall(utf8.len, name)
    if not ok or not len or len <= M.NAME_MAX then
        return name
    end
    return name:sub(1, utf8.offset(name, M.NAME_MAX + 1) - 1) .. "…"
end

-- `ws` lists the workspaces in bar order, each { name, here, elsewhere,
-- occupied, urgent }.
function M.title(ws)
    local parts = {}
    for _, w in ipairs(ws) do
        local s = M.short(w.name)
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

-- Which bar the pointer at x, y is over, and where on it: the uuid and the
-- point in that bar's page, or nil off every bar. `frames` are the bars'
-- frames by display uuid; a hidden one doesn't count.
function M.pointer_at(frames, x, y)
    for uuid, f in pairs(frames) do
        if not f.hidden and x >= f.x and x < f.x + f.w and y >= f.y and y < f.y + f.h then
            return uuid, x - f.x, y - f.y
        end
    end
    return nil
end

-- A bar item's tip, or the full title's, below bar `frame` and centered at
-- `x` in it, `w` by `h`, kept on the bar's display with M.TIP_GAP to spare
-- (SPEC.md §8).
M.TIP_GAP = 6
function M.tip_frame(frame, x, w, h)
    local left = frame.x + x - w / 2
    left = math.max(frame.x + M.TIP_GAP, math.min(left, frame.x + frame.w - M.TIP_GAP - w))
    return { x = math.floor(left), y = frame.y + frame.h + M.TIP_GAP, w = w, h = h }
end

-- Whether a tip drawn under display `owner`'s bar, when its frame was
-- `frame`, has lost its bar: `views` (by display uuid, each with its frame
-- and whether it's hidden) has none there now, or that bar is hidden, as
-- for a full-screen window, or has moved.
function M.tip_orphaned(owner, frame, views)
    local v = views[owner]
    if not v or v.hidden then
        return true
    end
    local f = v.frame
    return f.x ~= frame.x or f.y ~= frame.y or f.w ~= frame.w or f.h ~= frame.h
end

-- The tip's size for text measured `text_w` by `line_h` on one line: as
-- wide as the text plus padding, up to `max` wide, with as many lines as
-- wrapping it there takes (one more, to spare a short last word).
function M.tip_size(text_w, line_h, max)
    if text_w <= max then
        return math.ceil(text_w) + 18, math.ceil(line_h) + 10
    end
    return max + 18, math.ceil(line_h) * (math.ceil(text_w / max) + 1) + 10
end

-- Whether hs.webview:evaluateJavaScript's error says it failed. It passes a
-- table even on success, made from no error at all: { code = 0 }.
function M.js_failed(err)
    return type(err) == "table" and ((err.code or 0) ~= 0 or err.localizedDescription ~= nil)
end

-- A chip shows the app icon of each window there wanting attention, up to
-- this many, then "+n" (SPEC.md §8).
M.CHIP_APPS = 5

-- Workspace `n`'s windows: its tiles in layout order, then its other
-- windows (floats) by id, so the icons don't shuffle.
local function windows_of(wm, n)
    local ids, seen = {}, {}
    local ws = wm.workspaces[n]
    for _, id in ipairs(ws and ws.order or {}) do
        if wm.windows[id] and wm.windows[id].ws == n then
            ids[#ids + 1] = id
            seen[id] = true
        end
    end
    local rest = {}
    for id, w in pairs(wm.windows) do
        if w.ws == n and not seen[id] then
            rest[#rest + 1] = id
        end
    end
    table.sort(rest, function(x, y)
        return tostring(x) < tostring(y)
    end)
    for _, id in ipairs(rest) do
        ids[#ids + 1] = id
    end
    return ids
end

-- What display `uuid`'s bar shows: the workspaces as seen from there, each
-- by name, with the apps of its windows wanting attention (SPEC.md §8) in
-- `apps` and those windows' ids in `wins`, the focused window's title on
-- the display that window is on, and the status icons (icons()). `title`
-- is the focused window's title. `icon_of(app)`, if given, gives an app's
-- icon as a data URL, sent once per app in `app_icons` rather than once per
-- window.
function M.state(wm, uuid, title, icons, icon_of)
    local ws = {}
    local app_icons = {}
    local wanting = {}
    for _, id in ipairs(wm:attention_windows()) do
        wanting[id] = true
    end
    for i, s in ipairs(wm:bar_state(uuid)) do
        local all = {}
        for _, id in ipairs(windows_of(wm, s.name)) do
            if wanting[id] then
                all[#all + 1] = id
            end
        end
        local apps, wins = {}, {}
        for i = 1, math.min(#all, M.CHIP_APPS) do
            local app = wm.windows[all[i]].app or ""
            apps[i] = app
            wins[i] = all[i]
            if icon_of and app ~= "" and app_icons[app] == nil then
                app_icons[app] = icon_of(app) or false
            end
        end
        ws[i] = {
            n = s.name,
            current = s.here or false,
            elsewhere = s.elsewhere or false,
            occupied = s.occupied or false,
            urgent = s.urgent or false,
            apps = apps,
            wins = wins,
            more = math.max(0, #all - M.CHIP_APPS),
        }
    end
    -- The keys can act on another display than the focused window's, after
    -- an empty workspace is swapped in (wm:keep_keys_on), so the title goes
    -- by the window itself, and by the keys only with no managed window.
    local f = wm.a.focused()
    local w = f and wm.windows[f]
    local on = w and w.ws and wm:shown(w.ws) or wm:current_screen()
    return {
        uuid = uuid,
        workspaces = ws,
        title = on == uuid and title or "",
        icons = icons or {},
        app_icons = app_icons,
    }
end

local function holds(box, frame)
    local x, y = frame.x + frame.w / 2, frame.y + frame.h / 2
    return x >= box.x and x < box.x + box.w and y >= box.y and y < box.y + box.h
end

-- Whether display `uuid`'s bar hides, as tide's does under a full-screen
-- window (tide §7.1): its workspace has a window in tilemo's full screen, or
-- the focused window is in macOS's own full screen there. macOS's is only
-- known for the focused window: one left in its own Space may be swiped
-- away from without tilemo hearing *(unverified)*.
function M.hidden(wm, uuid)
    local n = wm.screen_ws[uuid]
    for id, w in pairs(wm.windows) do
        if n and w.ws == n and w.big == "full" then
            local st = wm.a.state(id)
            if st and not st.minimized and not st.hidden then
                return true
            end
        end
    end
    local f = wm.a.focused()
    local st = f and wm.a.state(f)
    if st and st.fullscreen and st.frame then
        for _, s in ipairs(wm.a.screens()) do
            if s.uuid == uuid and holds(s.full or s.area, st.frame) then
                return true
            end
        end
    end
    return false
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
--   presenting = whether presenter mode is on,
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

-- Each Bluetooth audio device connected, by name (SPEC.md §8), as tide's
-- headphones icons: macOS lists one only while it's connected. A headset
-- is both an output and an input, so a name is listed once.
function ITEMS.headphones(raw)
    local devices, seen = {}, {}
    for _, name in ipairs(raw.bluetooth_audio or {}) do
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            devices[#devices + 1] = { name = name }
        end
    end
    if #devices > 0 then
        return { devices = devices }
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

-- While presenting (SPEC.md §10) it says so, in words, since presenter
-- mode is easy to forget on after a talk.
function ITEMS.awake(raw)
    if raw.presenting then
        return { on = true, presenting = true }
    end
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
    bluetooth = "x-apple.systempreferences:com.apple.BluetoothSettings",
}

-- The managed window a page names: ids come back through JSON, which may
-- not keep a number's Lua subtype.
local function window_named(wm, id)
    local n = tonumber(id)
    for wid in pairs(wm.windows) do
        if wid == id or (n and tonumber(wid) == n) then
            -- The window's own key, not the page's copy of it.
            return wid
        end
    end
end

-- What a message from a bar's page does. Every message names its bar's
-- display, and acts there, not wherever the keys happen to be: a chip or a
-- scroll on display B's bar shows a workspace on B, an attention icon on
-- B's bar brings a hidden workspace to B with its window, its clocks open the
-- dashboard on B, and a double-click on its title maximizes the focused
-- window only if that window is on B, where the title shows. `act` holds what needs Hammerspoon: open(url),
-- dashboard(uuid), toggle(what), volume(step) and tip(uuid, tip).
function M.handle(wm, body, act)
    local uuid = body.uuid
    if body.show then
        wm:show(tostring(body.show), uuid)
    elseif body.focus ~= nil then
        local id = window_named(wm, body.focus)
        if id then
            wm:activate(id, uuid)
        end
    elseif body.step and uuid then
        wm:show(M.step(wm, uuid, tonumber(body.step)), uuid)
    elseif body.open then
        local url = M.PANES[body.open]
        if url then
            act.open(url)
        end
    elseif body.maximize then
        local _, w = wm:focused_tile()
        if w and uuid and wm:shown(w.ws) == uuid then
            wm:act("maximize")
        end
    elseif body.dashboard then
        act.dashboard(uuid)
    elseif body.toggle then
        act.toggle(body.toggle)
    elseif body.volume then
        act.volume(tonumber(body.volume))
    elseif type(body.tip) == "table" and act.tip then
        act.tip(uuid, body.tip)
    elseif body.clockErrors and act.clock_errors then
        act.clock_errors(body.clockErrors)
    elseif body.goodClocks and act.good_clocks then
        act.good_clocks(body.goodClocks)
    end
end

-- Scrolling over the workspaces steps from display `uuid`'s, in bar order,
-- stopping at the first and last, as Super+Left and Right do.
function M.step(wm, uuid, d)
    return wm:step_from(wm.screen_ws[uuid] or wm.home, d)
end

return M
