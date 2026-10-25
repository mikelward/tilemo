-- The bar on Hammerspoon: bar.lua's state in a borderless hs.webview along
-- the top of each display (SPEC.md §8), kept open and updated rather than
-- rebuilt. The page is built like the dashboard's, from the same copies of
-- tico's modules. Not runnable outside Hammerspoon.

local bar = require("timo.bar")
local dashboard = require("timo.dashboard")

local M = {}

-- How often to read the battery, the volume and Wi-Fi, in seconds.
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

-- `timo` is the started timo module: its wm, adapter and dashboard.
function M.new(timo)
    local self = { views = {}, icons = {} }
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
            return p and { percent = p, charging = hs.battery.isCharging() }
        end)
        raw.audio = try("the volume", function()
            local dev = hs.audiodevice.defaultOutputDevice()
            return dev and { volume = dev:outputVolume(), muted = dev:outputMuted() }
        end)
        -- The network name needs Location Services on recent macOS; without
        -- it ssid is nil and the icon shows without a name.
        raw.wifi = try("Wi-Fi", function()
            local d = hs.wifi.interfaceDetails()
            return d and { power = d.power, rssi = d.rssi, ssid = d.ssid }
        end)
        self.icons = bar.icons(raw)
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

    local function on_message(msg)
        local body = msg.body or {}
        -- Out of the page's own callback before changing what's on screen.
        timo.adapter.after(0, function()
            bar.handle(timo.wm, body, {
                open = open_url,
                dashboard = function(uuid)
                    timo.dashboard.show(uuid)
                end,
            })
        end)
    end

    local function push(v, title)
        if not v.ready then
            return
        end
        local json = hs.json.encode(bar.state(timo.wm, v.uuid, title, self.icons))
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
        v.content:setCallback(on_message)
        v.view = hs.webview.new(frame, { developerExtrasEnabled = false }, v.content)
        v.view:windowStyle({ "borderless" })
        -- A title for the rules to see: timo leaves its own windows alone.
        v.view:windowTitle("timo bar")
        -- Above every app's windows, below the menu bar, so the menu bar
        -- still shows over it when the pointer reaches the top.
        v.view:level(hs.drawing.windowLevels.floating)
        v.view:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces + hs.drawing.windowBehaviors.stationary)
        v.view:navigationCallback(function(action)
            if action == "didFinishNavigation" then
                v.ready = true
                v.sent = nil
                self.update()
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
            push(v, title)
        end
    end

    -- The bar's frames, for the smoke test.
    function self.frames()
        local out = {}
        for uuid, v in pairs(self.views) do
            local f = v.view:frame()
            out[uuid] = { x = f.x, y = f.y, w = f.w, h = f.h }
        end
        return out
    end

    read_icons()
    self.timer = hs.timer.doEvery(M.POLL, function()
        read_icons()
        self.update()
    end)
    sync_views()
    return self
end

return M
