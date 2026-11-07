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

local links = require("tide.links")

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

-- `ws` lists the workspaces in bar order, each { name, here, occupied,
-- urgent }.
function M.title(ws)
    local parts = {}
    for _, w in ipairs(ws) do
        local s = M.short(w.name)
        if w.here then
            s = "[" .. s .. "]"
        end
        if w.urgent then
            s = s .. "!"
        end
        parts[#parts + 1] = s
    end
    return table.concat(parts, " ")
end

-- The window level for display `s`'s bar: floating, above every app's
-- windows but below the menu bar, so the menu bar still shows over it when
-- the pointer reaches the top. Over a notch, macOS moves any window below
-- the main menu's level out of the notch's strip (canvases and web views
-- alike, on the owner's MacBook), so that bar is at the main menu's level,
-- the lowest that stays there.
function M.level(s)
    -- Over a menu bar macOS keeps showing (Automatically hide: Never), the
    -- bar covers it, at the status level, just above the menu bar's.
    if s.menu_bar then
        return "status"
    end
    if s.notch then
        return "mainMenu"
    end
    return "floating"
end

-- What the room macOS keeps at the top of a display is, from its `area`
-- (hs.screen's frame) and `full` frame: whether it has a notch, and whether
-- it is a menu bar that shows (`hidden`: the menu bar hides itself). With
-- the menu bar hidden, the only room kept is a notch's. With it shown, the
-- room is the menu bar, and a notched display's is taller: 37 px or more,
-- where a plain one's is 24 or 25 *(heights seen on Sonoma and later;
-- unverified per model)*, so the title and chips still keep clear of it.
-- A menu bar set to show is one to cover even where macOS keeps no room
-- for it: on the owner's Mac, set to Never, hs.screen's frame starts at
-- the top, menu bar and all, and a bar below its level sat under it.
M.NOTCH_MENU_BAR = 30

function M.top_room(area, full, hidden)
    local room = area.y - full.y
    if hidden then
        return room > 0, false
    end
    return room > M.NOTCH_MENU_BAR, true
end

-- The strip along the top of a display's area, and the tiling area left
-- below it.
function M.strip(area, h)
    return { x = area.x, y = area.y, w = area.w, h = h }
end

function M.below(area, h)
    return { x = area.x, y = area.y + h, w = area.w, h = math.max(0, area.h - h) }
end

-- Display `s`'s bar strip and the tiling area below it, for a bar `h` tall.
-- On a MacBook's display with a notch, macOS keeps a strip as tall as the
-- notch at the top of the screen even with the menu bar hidden, so its
-- `area` (hs.screen's frame) starts below the notch. There (`s.notch`, from
-- the adapter) the bar goes up to the top of the screen, as tall as that
-- strip or `h`, whichever is taller, and windows tile below it.
--
-- With the menu bar showing (`s.menu_bar`, from the adapter), the bar covers
-- it the same way: from the top of the screen, as tall as the menu bar or
-- `h`, so the menu bar never slides in over the bar (SPEC.md §8).
--
-- `floor`, when given, is where the bar's window really ends: macOS may
-- refuse the strip and move the window down (bar_hs.lua reads it back), and
-- windows then tile below it rather than under it.
function M.place(s, h, floor)
    local area = s.area
    local strip, below
    if (s.notch or s.menu_bar) and s.full and s.full.y < area.y then
        strip = { x = area.x, y = s.full.y, w = area.w, h = math.max(h, area.y - s.full.y) }
        local top = strip.y + strip.h
        below = { x = area.x, y = top, w = area.w, h = math.max(0, area.y + area.h - top) }
    else
        strip, below = M.strip(area, h), M.below(area, h)
    end
    if floor and floor > below.y then
        local bottom = below.y + below.h
        below = { x = below.x, y = floor, w = below.w, h = math.max(0, bottom - floor) }
    end
    return strip, below
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

-- The events Show Menu Bar's tap watches, as hs.eventtap.event.types
-- names. Releases count too: pressing a menu's title, dragging onto an item
-- and letting go chooses it with only the press on the menu bar.
M.REVEAL_EVENTS = { "leftMouseDown", "leftMouseUp", "rightMouseDown", "rightMouseUp", "keyDown" }

-- Whether an event ends Show Menu Bar: Esc or Return, which closes a menu or
-- chooses its item (`kind` "key", `key` as hs.keycodes.map names it), or a
-- press or release (`kind` "mouse") below every bar's strip at x, y. So a
-- click on the menu bar or a menu's title keeps it, and choosing a menu's
-- item, by a click or a drag, or a click anywhere else, brings the bars
-- back. `frames` as for pointer_at.
function M.reveal_done(frames, kind, key, x, y)
    if kind == "key" then
        return key == "escape" or key == "return"
    end
    if kind ~= "mouse" then
        return false
    end
    for _, f in pairs(frames) do
        if x >= f.x and x < f.x + f.w and y >= f.y and y < f.y + f.h then
            return false
        end
    end
    return true
end

-- Where to put a pointer at x, y back to, or nil to leave it: macOS shows
-- the hidden menu bar when the pointer reaches the top row of a display, so
-- over a shown bar's top row it goes one point down (SPEC.md §8). The Apple
-- logo opens the Apple menu without it. `frames` are the bars', as for
-- pointer_at; a hidden bar (a full-screen window) leaves the menu bar to
-- show as usual.
function M.off_top(frames, x, y)
    for _, f in pairs(frames) do
        if not f.hidden and x >= f.x and x < f.x + f.w and y < f.y + 1 and y > f.y - 1 then
            return f.y + 1
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

-- A chip shows the app icon of each window there wanting attention, up to
-- this many, then "+n" (SPEC.md §8).
M.CHIP_APPS = 5

-- Workspace `n`'s windows: its tiles in layout order, display by display,
-- then its other windows (floats) by id, so the icons don't shuffle.
local function windows_of(wm, n)
    local ids, seen = {}, {}
    for _, s in ipairs(wm:screens()) do
        local ws = wm.workspaces[n] and wm:part(n, s.uuid)
        for _, id in ipairs(ws and ws.order or {}) do
            if wm.windows[id] and wm.windows[id].ws == n and not seen[id] then
                ids[#ids + 1] = id
                seen[id] = true
            end
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
    for i, s in ipairs(wm:bar_state()) do
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
            occupied = s.occupied or false,
            urgent = s.urgent or false,
            apps = apps,
            wins = wins,
            more = math.max(0, #all - M.CHIP_APPS),
        }
    end
    -- The keys can act on another display than the focused window's, after
    -- a switch leaves nothing to focus there (wm:keep_keys_on), so the
    -- title goes by the window itself, and by the keys only with no managed
    -- window.
    local f = wm.a.focused()
    local on = wm:screen_of(f) or wm:current_screen()
    -- The notch sits where the title goes, so a display with one has none.
    local notch = false
    for _, s in ipairs(wm.a.screens()) do
        if s.uuid == uuid and s.notch then
            notch = true
        end
    end
    return {
        uuid = uuid,
        workspaces = ws,
        title = on == uuid and not notch and title or "",
        notch = notch,
        icons = icons or {},
        app_icons = app_icons,
    }
end

local function holds(box, frame)
    local x, y = frame.x + frame.w / 2, frame.y + frame.h / 2
    return x >= box.x and x < box.x + box.w and y >= box.y and y < box.y + box.h
end

-- Whether display `uuid`'s bar hides, as tide's does under a full-screen
-- window (tide §7.1): its part of the workspace showing has a window in
-- tide's full screen, or
-- the focused window is in macOS's own full screen there. macOS's is only
-- known for the focused window: one left in its own Space may be swiped
-- away from without tide hearing *(unverified)*.
function M.hidden(wm, uuid)
    local n = wm.current
    for id, w in pairs(wm.windows) do
        if n and w.ws == n and w.screen == uuid and w.big == "full" then
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
--   audio = { volume = 0…100, muted, name } or nil with no output device,
--     volume nil on one with no volume control, muted nil on one that
--     can't mute,
--   mic = { muted } or nil with no input device,
--   camera = { in_use } or nil with no camera,
--   source = { current, list = { { name, method }, … } },
--   awake = whether the display is kept from sleeping,
--   presenting = whether presenter mode is on,
--   wifi = { power, rssi, ssid, interface } or nil with no Wi-Fi interface,
--   network = { primary = the interface carrying traffic, or nil,
--     services = the interfaces macOS's network services are up on }.
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

-- The speaker, in four levels with mute and its level as a %, as tide's
-- (tide §7.4). An output with no volume control of its own (a display's
-- speakers over HDMI or DisplayPort, many USB interfaces) still shows,
-- marked `fixed`, with no %: macOS reads no volume there, and a click
-- mutes it only if it can mute (`can_mute`), else opens Sound settings.
function ITEMS.volume(raw)
    local a = raw.audio
    if not a then
        return nil
    end
    local muted = a.muted == true
    if a.volume == nil then
        local tip = "Sound: " .. ((a.name and a.name ~= "") and a.name or "this output") .. " has no volume control"
        return {
            level = muted and "mute" or "fixed",
            muted = muted,
            fixed = true,
            can_mute = a.muted ~= nil,
            tip = muted and "Sound muted" or tip,
        }
    end
    local v = math.max(0, math.min(100, math.floor(a.volume + 0.5)))
    local level = "high"
    if muted or v <= 0 then
        level = "mute"
    elseif v < 34 then
        level = "low"
    elseif v < 67 then
        level = "mid"
    end
    return { level = level, muted = muted, text = v .. "%", tip = muted and "Sound muted" or ("Sound " .. v .. "%") }
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

-- Bluetooth on or off (bluetooth.lua), absent without a reading: no
-- blueutil, no adapter, or an error.
function ITEMS.bluetooth(raw)
    if raw.bluetooth then
        return { on = raw.bluetooth.on == true }
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

-- The interfaces a VPN runs over on macOS: utun for IKEv2, WireGuard and
-- most apps' Network Extension tunnels, ipsec for Cisco IPSec, ppp for
-- L2TP, and tun or tap for OpenVPN's older drivers *(unverified for every
-- client)*.
M.VPN_INTERFACES = { "utun", "ipsec", "ppp", "tun", "tap" }

-- Whether interface `name` is a VPN's.
function M.is_vpn(name)
    if type(name) ~= "string" then
        return false
    end
    for _, prefix in ipairs(M.VPN_INTERFACES) do
        if name:match("^" .. prefix .. "%d+$") then
            return true
        end
    end
    return false
end

-- Whether a network service that's up, as bar_hs.lua reads it ({ interface,
-- type, subtype }, the type from the service's Setup:/.../Interface), is a
-- VPN's: a tunnel whose service macOS itself calls a VPN. That's a VPN app's
-- Network Extension (type VPN), Cisco IPSec, or L2TP or PPTP over PPP, but
-- not PPPoE, a modem's PPP, or a tunnel macOS has no VPN service for, such
-- as its own and other apps' utun interfaces.
M.VPN_SERVICE_TYPES = { VPN = true, IPSec = true }
M.VPN_PPP_SUBTYPES = { L2TP = true, PPTP = true }

function M.is_vpn_service(svc)
    if type(svc) ~= "table" or not M.is_vpn(svc.interface) then
        return false
    end
    if M.VPN_SERVICE_TYPES[svc.type] then
        return true
    end
    return svc.type == "PPP" and M.VPN_PPP_SUBTYPES[svc.subtype] == true
end

-- Which network carries traffic: Wi-Fi, a wire, or none, and whether a VPN
-- is up, as tide's lock on the network icon (tide §7.4). Without the
-- primary interface, Wi-Fi being on stands in for it.
-- A VPN is up when traffic goes through a tunnel, or when a VPN's network
-- service is up (`raw.network.services`, M.is_vpn_service), which also
-- catches a VPN that carries only some traffic. A tunnel that's up with no
-- VPN service, as macOS's own utun interfaces are, isn't one. Under a VPN
-- that carries it all, the link below is Wi-Fi while that's joined to a
-- network, else a wire.
function ITEMS.network(raw)
    local w = raw.wifi
    local net = raw.network
    local primary
    if net then
        primary = net.primary
    elseif w and w.power then
        primary = w.interface or "wifi"
    end
    local vpn = M.is_vpn(primary)
    for _, svc in ipairs(net and net.services or {}) do
        vpn = vpn or M.is_vpn_service(svc)
    end
    local kind = "none"
    if M.is_vpn(primary) then
        local joined = w and w.power and ((w.rssi or 0) < 0 or (w.ssid or "") ~= "")
        kind = joined and "wifi" or "wired"
    elseif primary and w and (primary == w.interface or primary == "wifi") then
        kind = "wifi"
    elseif primary then
        kind = "wired"
    end
    if vpn then
        return { kind = kind, vpn = true }
    end
    return { kind = kind }
end

-- The system monitor (SPEC.md §8), as tide's (tide §7.4): the CPU's % in
-- the bar, in the warning color when the Mac is hot or memory is 90% full,
-- and the urgent color while macOS says it's throttling.
M.MEMORY_HIGH = 0.9

-- The share of time the CPU was busy between two hs.host.cpuUsageTicks()
-- readings' overall ticks ({ active, idle }), or nil without both.
function M.cpu_share(before, after)
    if type(before) ~= "table" or type(after) ~= "table" then
        return nil
    end
    local busy = (after.active or 0) - (before.active or 0)
    local idle = (after.idle or 0) - (before.idle or 0)
    if busy < 0 or idle < 0 or busy + idle <= 0 then
        return nil
    end
    return busy / (busy + idle)
end

-- Memory in use from hs.host.vmStat(): wired, active and compressed pages,
-- near Activity Monitor's "Memory Used" *(an approximation)*, as { used,
-- total } in bytes, or nil when a count is missing.
function M.memory(vm)
    if type(vm) ~= "table" then
        return nil
    end
    local page, total = vm.pageSize, vm.memSize
    local wired, active, compressed = vm.pagesWiredDown, vm.pagesActive, vm.pagesUsedByVMCompressor
    -- Counted, not ipairs'd: a missing one would end the list early.
    local counts = { page, total, wired, active, compressed }
    for i = 1, 5 do
        if type(counts[i]) ~= "number" then
            return nil
        end
    end
    if total <= 0 then
        return nil
    end
    return { used = (wired + active + compressed) * page, total = total }
end

-- raw.sysmon is { cpu = 0…1 or nil, memory = { used, total } or nil,
-- thermal = hs.host.thermalState()'s "nominal", "fair", "serious" or
-- "critical" }. macOS gives no temperature or throttle count: its thermal
-- state stands in. "serious" (high) is hot, and "critical" (performance
-- significantly cut until it cools) is throttling.
function ITEMS.sysmon(raw)
    local s = raw.sysmon
    if not s then
        return nil
    end
    local text = s.cpu and (math.floor(s.cpu * 100 + 0.5) .. "%") or "–"
    local full = s.memory and s.memory.total > 0 and s.memory.used / s.memory.total >= M.MEMORY_HIGH
    local throttling = s.thermal == "critical"
    local hot = s.thermal == "serious"
    local tone = "normal"
    if throttling then
        tone = "danger"
    elseif hot or full then
        tone = "warn"
    end
    local tip = { s.cpu and ("CPU " .. text) or "CPU" }
    if throttling then
        tip[#tip + 1] = "throttling"
    elseif hot then
        tip[#tip + 1] = "hot"
    end
    if full then
        tip[#tip + 1] = "memory nearly full"
    end
    return { text = text, tone = tone, tip = table.concat(tip, ", ") }
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

-- The volume keys, as hs.eventtap's systemKey() names them, and the step
-- each takes: up, down, or 0 for mute.
M.VOLUME_KEYS = { SOUND_UP = 1, SOUND_DOWN = -1, MUTE = 0 }

-- The step a volume key takes, or nil to leave the key to macOS. tide takes
-- them only for an output it reads over DDC (ddc.lua), a monitor's speakers
-- that macOS has no volume for and answers with its "no volume" sign.
function M.volume_key(key, over_ddc)
    if not over_ddc then
        return nil
    end
    return M.VOLUME_KEYS[key]
end

-- What the on-screen sign says after a volume key: the level, or muted.
function M.volume_sign(volume, muted)
    if muted then
        return "Sound muted"
    end
    return "Sound " .. math.max(0, math.min(100, math.floor((volume or 0) + 0.5))) .. "%"
end

-- The session menu (SPEC.md §8), as tide's (tide §7.4): lock, log out,
-- sleep (tide's suspend), restart and shut down, in the Apple menu's
-- groups. Each id is a function in `run` (bar_hs.lua's, hs.caffeinate's).
M.SESSION = {
    { id = "lock", label = "Lock" },
    { id = "logout", label = "Log Out" },
    "-",
    { id = "sleep", label = "Sleep" },
    { id = "restart", label = "Restart" },
    { id = "shutdown", label = "Shut Down" },
}
M.SESSION_TIP = "Lock, log out or power off"

-- The session menu as hs.menubar's menu table: each entry runs its action
-- from `run`, by id.
function M.session_menu(run)
    local menu = {}
    for _, e in ipairs(M.SESSION) do
        if e == "-" then
            menu[#menu + 1] = { title = "-" }
        else
            menu[#menu + 1] = {
                title = e.label,
                fn = function()
                    run(e.id)
                end,
            }
        end
    end
    return menu
end

-- The Apple logo's menu (SPEC.md §8): tide's own copy of the Apple menu,
-- since the real one can't be opened while the menu bar stays hidden. A
-- pointer moved to the top edge by software doesn't reveal it, an
-- Accessibility press on it reports success and shows nothing, and on one
-- Mac "Move focus to the menu bar" doesn't either (all seen on a Mac). An
-- entry with `open` opens that, the rest run the session action of their
-- id. Not here: Recent Items, Force Quit, whose key is the system's own,
-- and anything a profile adds to the real one.
M.APPLE = {
    -- tide's bar covering the menu bar, hidden until a click below it or
    -- Esc, so the real one, with the app's menus and status items, shows.
    { id = "menubar", label = "Show Menu Bar" },
    "-",
    { id = "about", label = "About This Mac", open = "x-apple.systempreferences:com.apple.SystemProfiler.AboutExtension" },
    "-",
    { id = "settings", label = "System Settings…", open = "/System/Applications/System Settings.app" },
    { id = "appstore", label = "App Store…", open = "/System/Applications/App Store.app" },
    "-",
    { id = "sleep", label = "Sleep" },
    { id = "restart", label = "Restart…" },
    { id = "shutdown", label = "Shut Down…" },
    "-",
    { id = "lock", label = "Lock Screen" },
    { id = "logout", label = "Log Out…" },
}

-- The Apple logo's menu as hs.menubar's menu table: `open(target)` for an
-- entry that opens something, else `run(id)`, the session's.
function M.apple_menu(open, run)
    local menu = {}
    for _, e in ipairs(M.APPLE) do
        if e == "-" then
            menu[#menu + 1] = { title = "-" }
        else
            menu[#menu + 1] = {
                title = e.label,
                fn = function()
                    if e.open then
                        open(e.open)
                    else
                        run(e.id)
                    end
                end,
            }
        end
    end
    return menu
end

-- The System Settings pane each icon opens *(unverified on macOS 26)*: the
-- settings window's, so the two agree.
M.PANES = {
    battery = links.PANES.battery,
    volume = links.PANES.sound,
    wifi = links.PANES.wifi,
    network = links.PANES.network,
    bluetooth = links.PANES.bluetooth,
    -- Not a pane: the system monitor's click opens Activity Monitor, where
    -- tide's opens a popover with the busiest processes.
    sysmon = "/System/Applications/Utilities/Activity Monitor.app",
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
-- dashboard(uuid), switcher(uuid) for the logo, toggle(what), volume(step),
-- session(uuid, { x }) for the session menu under the icon at x,
-- settings(page) for a right-click's settings page, "" for the first,
-- sound(uuid, { right }) for the volume popover under the speaker,
-- and tip(uuid, tip).
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
        if w and uuid and wm:shown(w.ws) and w.screen == uuid then
            wm:act("maximize")
        end
    elseif body.dashboard then
        act.dashboard(uuid)
    elseif body.switcher and act.switcher then
        act.switcher(uuid)
    elseif body.toggle then
        act.toggle(body.toggle)
    elseif body.volume then
        act.volume(tonumber(body.volume))
    elseif body.menubar and act.menubar then
        act.menubar(uuid)
    elseif type(body.settings) == "string" and act.settings then
        act.settings(body.settings)
    elseif body.workspaces and act.workspaces then
        act.workspaces(uuid)
    elseif type(body.session) == "table" and act.session then
        act.session(uuid, body.session)
    elseif type(body.sound) == "table" and act.sound then
        act.sound(uuid, body.sound)
    elseif type(body.tip) == "table" and act.tip then
        act.tip(uuid, body.tip)
    elseif body.clockErrors and act.clock_errors then
        act.clock_errors(body.clockErrors)
    elseif body.goodClocks and act.good_clocks then
        act.good_clocks(body.goodClocks)
    end
end

-- Scrolling over the workspaces steps from the one showing, in bar order,
-- stopping at the first and last, where Super+PgUp and PgDn wrap round.
function M.step(wm, uuid, d)
    return wm:step_from(wm:current_ws(), d)
end

return M
