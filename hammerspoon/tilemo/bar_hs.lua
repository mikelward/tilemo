-- The bar on Hammerspoon: bar.lua's state in a borderless hs.webview along
-- the top of each display (SPEC.md §8), kept open and updated rather than
-- rebuilt. The page is built like the dashboard's, from the same copies of
-- tileco's modules. Not runnable outside Hammerspoon.

local bar = require("tilemo.bar")
local bluetooth = require("tilemo.bluetooth")
local tray_hs = require("tilemo.tray_hs")
local dashboard = require("tilemo.dashboard")

local M = {}

-- How often to read the status items that have no watcher, in seconds.
M.POLL = 5
-- How often blueutil is asked whether Bluetooth is on, besides at start and
-- on wake: a process each time, so less often than the rest.
M.BLUETOOTH_POLL = 30

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/dashboard/"

local function read(name)
    local f, err = io.open(DIR .. name)
    if not f then
        error("tilemo: can't read the bar's " .. name .. ": " .. tostring(err))
    end
    local text = f:read("a")
    f:close()
    return text
end

-- Built once at start, so a missing file is an error then.
local function build()
    local sources = {}
    for _, name in ipairs(dashboard.BAR_MODULES) do
        sources[name] = read(name)
    end
    return dashboard.page(read("bar.html"), read("launcher.css"), sources, dashboard.BAR_MODULES)
end

local function same(a, b)
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- Mute or unmute the default microphone, with a sign. Super+Shift+M calls
-- this too, with the bar on or off. Returns whether it changed.
function M.toggle_mic(log)
    local dev = hs.audiodevice.defaultInputDevice()
    if not dev then
        hs.alert.show("No microphone")
        return false
    end
    local muted = dev:inputMuted()
    -- Some devices have no mute control of their own.
    if muted == nil then
        hs.alert.show("This microphone can't be muted")
        log("bar: " .. tostring(dev:name()) .. " has no input mute")
        return false
    end
    if not dev:setInputMuted(not muted) then
        hs.alert.show("Couldn't " .. (muted and "unmute" or "mute") .. " the microphone")
        log("bar: setInputMuted failed on " .. tostring(dev:name()))
        return false
    end
    hs.alert.show(muted and "Microphone on" or "Microphone muted")
    return true
end

-- `tilemo` is the started tilemo module: its wm, adapter and dashboard.
function M.new(tilemo)
    -- `errors` keeps what the pages reported going wrong, for the log and
    -- the smoke test.
    local self = { views = {}, icons = {}, errors = {} }
    local page = build()
    local log = tilemo.adapter.log
    -- The last error from each source, so a lasting one is logged once.
    local failed = {}

    local function try(what, fn)
        local ok, v = pcall(fn)
        if ok then
            failed[what] = nil
            return v
        end
        if failed[what] ~= tostring(v) then
            failed[what] = tostring(v)
            log("bar: couldn't read " .. what .. ": " .. tostring(v))
        end
    end

    local function read_icons()
        local raw = {}
        raw.bluetooth = self.bluetooth and self.bluetooth.state
        raw.battery = try("the battery", function()
            local p = hs.battery.percentage()
            return p and {
                percent = p,
                charging = hs.battery.isCharging(),
                charged = hs.battery.isCharged(),
                remaining = hs.battery.timeRemaining(),
                to_full = hs.battery.timeToFullCharge(),
            }
        end)
        raw.audio = try("the volume", function()
            local dev = hs.audiodevice.defaultOutputDevice()
            return dev and { volume = dev:outputVolume(), muted = dev:outputMuted() }
        end)
        -- Bluetooth audio devices, outputs then inputs, by name; bar.lua
        -- lists each once.
        raw.bluetooth_audio = try("the Bluetooth audio devices", function()
            local out = {}
            for _, list in ipairs({ hs.audiodevice.allOutputDevices(), hs.audiodevice.allInputDevices() }) do
                for _, dev in ipairs(list or {}) do
                    if dev:transportType() == "Bluetooth" then
                        out[#out + 1] = dev:name()
                    end
                end
            end
            return out
        end)
        -- No "in use": Hammerspoon's inUse() asks whether the device is
        -- running at all, so a headset playing sound would light it.
        raw.mic = try("the microphone", function()
            local dev = hs.audiodevice.defaultInputDevice()
            return dev and { muted = dev:inputMuted() }
        end)
        raw.camera = try("the cameras", function()
            local cams = hs.camera.allCameras()
            if #cams == 0 then
                return nil
            end
            for _, c in ipairs(cams) do
                if c:isInUse() then
                    return { in_use = true }
                end
            end
            return { in_use = false }
        end)
        raw.source = try("the input source", function()
            local list = {}
            for _, name in ipairs(hs.keycodes.layouts()) do
                list[#list + 1] = { name = name, method = false }
            end
            for _, name in ipairs(hs.keycodes.methods()) do
                list[#list + 1] = { name = name, method = true }
            end
            return { current = hs.keycodes.currentMethod() or hs.keycodes.currentLayout(), list = list }
        end)
        raw.awake = try("keep awake", function()
            return hs.caffeinate.get("displayIdle")
        end)
        raw.presenting = tilemo.presenter and tilemo.presenter.presenting() or false
        -- The network name needs Location Services on recent macOS; without
        -- it ssid is nil and the icon shows without a name.
        raw.wifi = try("Wi-Fi", function()
            local d = hs.wifi.interfaceDetails()
            return d and { power = d.power, rssi = d.rssi, ssid = d.ssid, interface = d.interface }
        end)
        raw.network = try("the network", function()
            -- false with no route, as Hammerspoon reports it.
            local v4, v6 = hs.network.primaryInterfaces()
            return { primary = v4 or v6 or nil }
        end)
        self.sources = raw.source and raw.source.list or {}
        self.current_source = raw.source and raw.source.current
        self.icons = bar.icons(raw, function(name, err)
            if failed["item " .. name] ~= tostring(err) then
                failed["item " .. name] = tostring(err)
                log("bar: couldn't draw " .. name .. ": " .. tostring(err))
            end
        end)
    end

    local open_url = tilemo.adapter.open_url

    function self.refresh()
        read_icons()
        self.update()
    end

    -- A watcher can fire many times in a burst (a volume slider, a device
    -- appearing), so they share one refresh shortly after.
    local pending
    local function refresh_soon()
        if pending then
            return
        end
        pending = tilemo.adapter.after(0.1, function()
            pending = nil
            self.refresh()
        end)
    end

    local function toggle(what)
        if what == "mic" then
            M.toggle_mic(log)
        elseif what == "volume" then
            local dev = hs.audiodevice.defaultOutputDevice()
            if dev and not dev:setOutputMuted(not dev:outputMuted()) then
                log("bar: setOutputMuted failed on " .. tostring(dev:name()))
            end
        elseif what == "awake" then
            tilemo.presenter.toggle_keep_awake()
        elseif what == "presenter" then
            tilemo.presenter.toggle_presenter()
        elseif what == "source" then
            local nxt = bar.next_source(self.sources or {}, self.current_source)
            if nxt then
                local ok
                if nxt.method then
                    ok = hs.keycodes.setMethod(nxt.name)
                else
                    ok = hs.keycodes.setLayout(nxt.name)
                end
                if not ok then
                    log("bar: couldn't switch to " .. nxt.name)
                end
            end
        end
        self.refresh()
    end

    local function step_volume(d)
        local dev = hs.audiodevice.defaultOutputDevice()
        if not dev then
            return
        end
        local v, unmute = bar.volume_step(dev:outputVolume(), dev:outputMuted(), d)
        if not dev:setOutputVolume(v) then
            log("bar: setOutputVolume failed on " .. tostring(dev:name()))
        end
        if unmute and not dev:setOutputMuted(false) then
            log("bar: setOutputMuted failed on " .. tostring(dev:name()))
        end
        self.refresh()
    end

    -- A bar item's tip, or the full title's, below a bar (SPEC.md §8),
    -- drawn as the tray's tips are: the page can't draw past its own strip.
    local TIP_MAX = 600
    -- The tip on screen, if any: its canvas, and the display and bar frame
    -- it was drawn for, so it goes with that bar (drop_orphaned_tip).
    local tip
    local function hide_tip()
        if tip then
            tip.canvas:delete()
            tip = nil
        end
    end
    local function show_tip(uuid, t)
        hide_tip()
        local v = uuid and self.views[uuid]
        local text = type(t.text) == "string" and t.text or ""
        if text == "" or not v or v.hidden then
            return
        end
        local size = hs.drawing.getTextDrawingSize(text, { size = tray_hs.TIP_SIZE })
        local w, h = bar.tip_size(size.w, size.h, TIP_MAX)
        local c = tray_hs.colors()
        local canvas = tray_hs.floating(hs.canvas.new(bar.tip_frame(v.frame, tonumber(t.x) or v.frame.w / 2, w, h)))
        tip = { canvas = canvas, uuid = uuid, frame = { x = v.frame.x, y = v.frame.y, w = v.frame.w, h = v.frame.h } }
        canvas:appendElements({
            type = "rectangle",
            action = "fill",
            fillColor = c.tip,
            roundedRectRadii = { xRadius = 7, yRadius = 7 },
        }, {
            type = "text",
            text = text,
            textSize = tray_hs.TIP_SIZE,
            textColor = c.fg,
            textLineBreak = "wordWrap",
            frame = { x = 9, y = 5, w = w - 18, h = h - 10 },
        })
        canvas:show()
    end

    local function on_message(msg, from)
        local body = msg.body or {}
        if body.error then
            local e = "display " .. tostring(from) .. ": " .. tostring(body.error)
            self.errors[#self.errors + 1] = e
            log("bar: page error on " .. e)
            return
        end
        -- Out of the page's own callback before changing what's on screen.
        tilemo.adapter.after(0, function()
            bar.handle(tilemo.wm, body, {
                open = open_url,
                dashboard = function(uuid)
                    tilemo.dashboard.show(uuid)
                end,
                toggle = toggle,
                volume = step_volume,
                clock_errors = tilemo.report_clock_errors,
                good_clocks = tilemo.keep_good_clocks,
                tip = show_tip,
            })
        end)
    end

    -- Each app's icon as a small PNG data URL, made once per bundle id:
    -- 32 px is the chip's 16 at 2x, a few kilobytes a time. An app with no
    -- icon is cached as false, so it isn't asked again every update.
    self.app_icons = {}
    local function icon_of(bundle)
        local url = self.app_icons[bundle]
        if url == nil then
            url = try("the icon of " .. bundle, function()
                local img = hs.image.imageFromAppBundle(bundle)
                return img and img:setSize({ w = 32, h = 32 }):encodeAsURLString(false, "PNG")
            end) or false
            self.app_icons[bundle] = url
        end
        return url or nil
    end
    self.icon_of = icon_of

    local function run(v, js)
        v.view:evaluateJavaScript(js, function(_, err)
            if bar.js_failed(err) then
                log("bar: " .. hs.inspect(err))
            end
        end)
    end

    local function push(v, title)
        if not v.ready then
            return
        end
        local state = bar.state(tilemo.wm, v.uuid, title, self.icons, icon_of)
        state.clockFiles = tilemo.clock_files
        state.goodClocks = tilemo.good_clocks
        local json = hs.json.encode(state)
        if json == v.sent then
            return
        end
        v.sent = json
        run(v, "tilemo.update(" .. json .. ")")
    end

    -- Hover. The bar's window never becomes key, and WebKit follows the
    -- pointer only in the key window, so :hover never fires there; tilemo
    -- tells the page where the pointer is instead, on every move over a
    -- bar, and that it left.
    local hovered
    function self.pointer(x, y)
        local frames = {}
        for uuid, v in pairs(self.views) do
            frames[uuid] = { x = v.frame.x, y = v.frame.y, w = v.frame.w, h = v.frame.h, hidden = v.hidden }
        end
        local uuid, px, py = bar.pointer_at(frames, x, y)
        local old = hovered and self.views[hovered]
        if old and hovered ~= uuid and old.ready then
            run(old, "tilemo.pointer(null)")
        end
        hovered = uuid
        local v = uuid and self.views[uuid]
        if v and v.ready then
            run(v, string.format("tilemo.pointer(%d, %d)", math.floor(px), math.floor(py)))
        end
    end

    local function create(uuid, frame)
        local v = { uuid = uuid, frame = frame }
        -- Each view keeps its own handler, and both stay referenced here.
        v.content = hs.webview.usercontent.new("tilemo")
        v.content:setCallback(function(msg)
            on_message(msg, uuid)
        end)
        v.view = hs.webview.new(frame, { developerExtrasEnabled = false }, v.content)
        v.view:windowStyle({ "borderless" })
        -- A title for the rules to see: tilemo leaves its own windows alone.
        v.view:windowTitle("tilemo bar")
        -- Above every app's windows, below the menu bar, so the menu bar
        -- still shows over it when the pointer reaches the top.
        v.view:level(hs.drawing.windowLevels.floating)
        v.view:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces + hs.drawing.windowBehaviors.stationary)
        -- `nav` is how far the page got, for a smoke test that finds it
        -- not ready.
        v.nav = "loading"
        v.view:navigationCallback(function(action, _, _, err)
            v.nav = action
            if action == "didFinishNavigation" then
                v.ready = true
                v.sent = nil
                self.update()
            elseif action == "didFailNavigation" or action == "didFailProvisionalNavigation" then
                local e = "display " .. uuid .. ": " .. action .. ": " .. hs.inspect(err)
                self.errors[#self.errors + 1] = e
                log("bar: " .. e)
            end
        end)
        v.view:html(page)
        v.view:show()
        return v
    end

    -- One strip per display, following displays as they come and go.
    -- A tip whose bar was hidden (a full-screen window, entered from the
    -- keyboard with the pointer still), removed with its display, or moved
    -- goes too. That bar's page, if it's still there, is told the pointer
    -- left, so it asks again once the pointer is back over an item with a tip.
    local function drop_orphaned_tip()
        if not tip or not bar.tip_orphaned(tip.uuid, tip.frame, self.views) then
            return
        end
        local v = self.views[tip.uuid]
        hide_tip()
        if v and v.ready then
            run(v, "tilemo.pointer(null)")
        end
    end

    local function sync_views()
        local present = {}
        for _, s in ipairs(tilemo.adapter.screens()) do
            present[s.uuid] = true
            local frame = bar.strip(s.area, bar.HEIGHT)
            local v = self.views[s.uuid]
            if not v then
                self.views[s.uuid] = create(s.uuid, frame)
            elseif not same(v.frame, frame) then
                v.frame = frame
                v.view:frame(frame)
            end
        end
        for uuid, v in pairs(self.views) do
            if not present[uuid] then
                v.view:delete()
                self.views[uuid] = nil
            end
        end
        drop_orphaned_tip()
    end

    function self.update()
        sync_views()
        local f = tilemo.adapter.focused()
        local title = f and tilemo.wm.windows[f] and tilemo.adapter.title(f) or ""
        for _, v in pairs(self.views) do
            -- Out of a full-screen window's way, and back after.
            local hide = bar.hidden(tilemo.wm, v.uuid)
            if hide ~= (v.hidden or false) then
                v.hidden = hide
                if hide then
                    v.view:hide()
                else
                    v.view:show()
                end
            end
            push(v, title)
        end
        drop_orphaned_tip()
    end

    -- The bar's frames, for the smoke test.
    function self.frames()
        local out = {}
        for uuid, v in pairs(self.views) do
            local f = v.view:frame()
            out[uuid] = { x = f.x, y = f.y, w = f.w, h = f.h, hidden = v.hidden or false }
        end
        return out
    end

    -- Watchers, so a change shows at once rather than on the next poll.
    -- Each is kept here: Hammerspoon stops one that's collected.
    local function watch_devices()
        for _, k in ipairs({ "out_dev", "in_dev" }) do
            local d = self[k]
            if d then
                try("an audio device watcher", function()
                    d:watcherStop()
                end)
            end
        end
        self.out_dev = try("the output device", hs.audiodevice.defaultOutputDevice)
        self.in_dev = try("the input device", hs.audiodevice.defaultInputDevice)
        for _, k in ipairs({ "out_dev", "in_dev" }) do
            local d = self[k]
            if d then
                try("an audio device watcher", function()
                    d:watcherCallback(function()
                        refresh_soon()
                    end):watcherStart()
                end)
            end
        end
    end

    local function watch_cameras()
        for _, c in ipairs(self.cameras or {}) do
            try("a camera watcher", function()
                c:stopPropertyWatcher()
            end)
        end
        self.cameras = try("the cameras", hs.camera.allCameras) or {}
        for _, c in ipairs(self.cameras) do
            try("a camera watcher", function()
                c:setPropertyWatcherCallback(function()
                    refresh_soon()
                end):startPropertyWatcher()
            end)
        end
    end

    try("the audio device watcher", function()
        hs.audiodevice.watcher.setCallback(function()
            watch_devices()
            refresh_soon()
        end)
        hs.audiodevice.watcher.start()
    end)
    watch_devices()
    try("the camera watcher", function()
        hs.camera.setWatcherCallback(function()
            watch_cameras()
            refresh_soon()
        end)
        hs.camera.startWatcher()
    end)
    watch_cameras()
    try("the input source watcher", function()
        hs.keycodes.inputSourceChanged(function()
            refresh_soon()
        end)
    end)

    -- Bluetooth on or off, from blueutil, run without waiting so it never
    -- holds the bar up (bluetooth.lua). Each answer that changes it redraws.
    self.bluetooth = bluetooth.poller({
        find = function()
            return bluetooth.find(function(p)
                return hs.fs.attributes(p) ~= nil
            end)
        end,
        run = function(path, args, done)
            local ok, task = pcall(hs.task.new, path, function(code, out, err)
                done(code, out, err)
            end, args)
            if not ok then
                return false, tostring(task)
            end
            if not task or not task:start() then
                return false, "hs.task couldn't run " .. path
            end
            return true
        end,
        log = log,
        changed = function()
            refresh_soon()
        end,
    })
    self.bluetooth:poll()
    self.bluetooth_timer = hs.timer.doEvery(M.BLUETOOTH_POLL, function()
        self.bluetooth:poll()
    end)
    -- Waking, the radio may have changed while asleep.
    try("the wake watcher", function()
        self.wake_watcher = hs.caffeinate.watcher.new(function(event)
            if event == hs.caffeinate.watcher.systemDidWake then
                self.bluetooth:poll()
            end
        end):start()
    end)

    read_icons()
    -- The battery, Wi-Fi, the network and keep awake have no watcher here.
    self.timer = hs.timer.doEvery(M.POLL, function()
        self.refresh()
    end)
    sync_views()
    return self
end

return M
