-- The bar on Hammerspoon: bar.lua's state in a borderless hs.webview along
-- the top of each display (SPEC.md §8), kept open and updated rather than
-- rebuilt. The page is built like the dashboard's, from the same copies of
-- tico's modules. Not runnable outside Hammerspoon.

local bar = require("timo.bar")
local dashboard = require("timo.dashboard")

local M = {}

-- How often to read the status items that have no watcher, in seconds.
M.POLL = 5

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/dashboard/"

local function read(name)
    local f, err = io.open(DIR .. name)
    if not f then
        error("timo: can't read the bar's " .. name .. ": " .. tostring(err))
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

-- `timo` is the started timo module: its wm, adapter and dashboard.
function M.new(timo)
    -- `errors` keeps what the pages reported going wrong, for the log and
    -- the smoke test.
    local self = { views = {}, icons = {}, errors = {} }
    local page = build()
    local log = timo.adapter.log
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

    -- hs.urlevent.openURL refuses a URL without "://", which a System
    -- Settings pane's lacks, so open(1) opens it. Each task is held until
    -- it exits: Hammerspoon may stop one that's collected.
    local opening = {}
    local function open_url(url)
        local task
        task = hs.task.new("/usr/bin/open", function(code, _, err)
            opening[task] = nil
            if code ~= 0 then
                log("bar: couldn't open " .. url .. ": " .. tostring(err))
            end
        end, { url })
        if task and task:start() then
            opening[task] = true
        else
            log("bar: couldn't run open for " .. url)
        end
    end

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
        pending = timo.adapter.after(0.1, function()
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
            local on = not hs.caffeinate.get("displayIdle")
            hs.caffeinate.set("displayIdle", on, true)
            hs.alert.show(on and "Keeping awake" or "Not keeping awake")
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

    local function on_message(msg, from)
        local body = msg.body or {}
        if body.error then
            local e = "display " .. tostring(from) .. ": " .. tostring(body.error)
            self.errors[#self.errors + 1] = e
            log("bar: page error on " .. e)
            return
        end
        -- Out of the page's own callback before changing what's on screen.
        timo.adapter.after(0, function()
            bar.handle(timo.wm, body, {
                open = open_url,
                dashboard = function(uuid)
                    timo.dashboard.show(uuid)
                end,
                toggle = toggle,
                volume = step_volume,
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

    local function push(v, title)
        if not v.ready then
            return
        end
        local json = hs.json.encode(bar.state(timo.wm, v.uuid, title, self.icons, icon_of))
        if json == v.sent then
            return
        end
        v.sent = json
        v.view:evaluateJavaScript("timo.update(" .. json .. ")", function(_, err)
            if err and next(err) then
                log("bar: " .. hs.inspect(err))
            end
        end)
    end

    local function create(uuid, frame)
        local v = { uuid = uuid, frame = frame }
        -- Each view keeps its own handler, and both stay referenced here.
        v.content = hs.webview.usercontent.new("timo")
        v.content:setCallback(function(msg)
            on_message(msg, uuid)
        end)
        v.view = hs.webview.new(frame, { developerExtrasEnabled = false }, v.content)
        v.view:windowStyle({ "borderless" })
        -- A title for the rules to see: timo leaves its own windows alone.
        v.view:windowTitle("timo bar")
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
    local function sync_views()
        local present = {}
        for _, s in ipairs(timo.adapter.screens()) do
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
    end

    function self.update()
        sync_views()
        local f = timo.adapter.focused()
        local title = f and timo.wm.windows[f] and timo.adapter.title(f) or ""
        for _, v in pairs(self.views) do
            -- Out of a full-screen window's way, and back after.
            local hide = bar.hidden(timo.wm, v.uuid)
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

    read_icons()
    -- The battery, Wi-Fi, the network and keep awake have no watcher here.
    self.timer = hs.timer.doEvery(M.POLL, function()
        self.refresh()
    end)
    sync_views()
    return self
end

return M
