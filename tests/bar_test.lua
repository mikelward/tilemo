local t = require("t")
local fake = require("fake")
local wm_mod = require("timo.wm")
local ffm_mod = require("timo.ffm")
local dashboard = require("timo.dashboard")
local bar = require("timo.bar")

local function ws(spec)
    local out = {}
    for n = 1, 9 do
        out[n] = spec[n] or {}
    end
    return out
end

t.test("the menu bar shows this display's workspace, others showing, and occupied ones", function()
    t.eq(bar.title(ws({ { here = true }, { occupied = true }, { elsewhere = true }, nil, { occupied = true, urgent = true } })),
        "[1] 2 (3) 5!")
end)

t.test("empty workspaces that aren't showing are left out", function()
    t.eq(bar.title(ws({ nil, { here = true } })), "[2]")
end)

local function two_displays(top)
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, { title = "Notes" })
    local wm = wm_mod.new(a, { top = top or bar.HEIGHT })
    wm:sync()
    wm:reconcile()
    wm:retile()
    return a, wm
end

t.test("the strip sits along the top of the area, and tiling starts below it", function()
    local area = { x = 0, y = 25, w = 1920, h = 1055 }
    t.eq(bar.strip(area, 36), { x = 0, y = 25, w = 1920, h = 36 })
    t.eq(bar.below(area, 36), { x = 0, y = 61, w = 1920, h = 1019 })
end)

t.test("with the bar on, windows tile below it and maximize stops at it", function()
    local a, wm = two_displays()
    a.add(2, {})
    wm:sync()
    wm:retile()
    t.eq(a.wins[1].frame.y, 61)
    t.eq(a.wins[2].frame.y, 61)
    t.eq(a.wins[1].frame.h, 1019)
    a.focus_ = 1
    wm:act("maximize")
    t.eq(a.wins[1].frame, { x = 0, y = 61, w = 1920, h = 1019 })
end)

t.test("with the bar off, tiling has the whole area", function()
    local a = two_displays(0)
    t.eq(a.wins[1].frame.y, 25)
end)

t.test("focus follows mouse pauses over the bar, as over the menu bar", function()
    local _, wm = two_displays()
    local ffm = ffm_mod.new(wm, wm.a, {})
    t.eq(ffm:paused(100, 40, false), true)
    t.eq(ffm:paused(100, 80, false), false)
end)

t.test("each display's bar marks its own workspace, and the title shows on the focused one", function()
    local a, wm = two_displays()
    a.focus_ = 1
    local sa = bar.state(wm, "A", "Notes", {})
    local sb = bar.state(wm, "B", "Notes", {})
    t.eq(sa.workspaces[1], { n = 1, current = true, elsewhere = false, occupied = true, urgent = false })
    t.eq(sa.workspaces[2].elsewhere, true)
    t.eq(sb.workspaces[2].current, true)
    t.eq(sb.workspaces[1].elsewhere, true)
    t.eq(sa.title, "Notes")
    t.eq(sb.title, "")
    t.eq(sb.uuid, "B")
end)

t.test("the title follows the focused window, not where the keys act", function()
    local a, wm = two_displays()
    a.focus_ = 1
    -- Swapping an empty workspace in carries window 1 to B, with focus,
    -- while the keys stay on A.
    wm:act("show", 2)
    t.eq(wm.screen_ws, { A = 2, B = 1 })
    t.eq(wm:current_screen(), "A")
    t.eq(bar.state(wm, "A", "Notes", {}).title, "")
    t.eq(bar.state(wm, "B", "Notes", {}).title, "Notes")
end)

t.test("a bar's messages act on its own display, not where the keys are", function()
    local a, wm = two_displays()
    a.focus_ = 1
    t.eq(wm:current_screen(), "A")
    local opened, dash = {}, {}
    local act = {
        open = function(url)
            opened[#opened + 1] = url
        end,
        dashboard = function(uuid)
            dash[#dash + 1] = uuid
        end,
    }
    bar.handle(wm, { uuid = "B", dashboard = true }, act)
    t.eq(dash, { "B" })
    bar.handle(wm, { uuid = "B", show = 4 }, act)
    t.eq(wm.screen_ws, { A = 1, B = 4 })
    bar.handle(wm, { uuid = "B", step = 1 }, act)
    t.eq(wm.screen_ws, { A = 1, B = 5 })
    bar.handle(wm, { uuid = "B", open = "wifi" }, act)
    bar.handle(wm, { uuid = "B", open = "nothing" }, act)
    t.eq(opened, { bar.PANES.wifi })
end)

t.test("scrolling steps from that display's workspace, stopping at 1 and 9", function()
    local _, wm = two_displays()
    t.eq(bar.step(wm, "B", 1), 3)
    t.eq(bar.step(wm, "A", -1), 1)
    wm.screen_ws.B = 9
    t.eq(bar.step(wm, "B", 1), 9)
end)

t.test("the battery shows its rounded percentage and whether it's charging", function()
    t.eq(bar.icons({ battery = { percent = 83.6, charging = true } }).battery, { percent = 84, charging = true, text = "84%" })
    t.eq(bar.icons({}).battery, nil)
end)

t.test("the volume shows its level, or mute", function()
    t.eq(bar.icons({ audio = { volume = 20 } }).volume.level, "low")
    t.eq(bar.icons({ audio = { volume = 50 } }).volume.level, "mid")
    t.eq(bar.icons({ audio = { volume = 90 } }).volume.level, "high")
    t.eq(bar.icons({ audio = { volume = 90, muted = true } }).volume, { level = "mute", muted = true })
    t.eq(bar.icons({ audio = { volume = 0 } }).volume.level, "mute")
end)

t.test("Wi-Fi shows signal bars, and the name only when macOS gives it", function()
    t.eq(bar.icons({ wifi = { power = true, rssi = -55, ssid = "home" } }).wifi, { on = true, bars = 3, name = "home" })
    t.eq(bar.icons({ wifi = { power = true, rssi = -75 } }).wifi, { on = true, bars = 1 })
    t.eq(bar.icons({ wifi = { power = false, rssi = -55, ssid = "home" } }).wifi, { on = false, bars = 0 })
    t.eq(bar.icons({}).wifi, nil)
end)

t.test("every icon opens a settings pane", function()
    for _, k in ipairs({ "battery", "volume", "wifi" }) do
        t.eq(bar.PANES[k]:find("^x%-apple%.systempreferences:") ~= nil, true)
    end
end)

local DIR = "hammerspoon/timo/dashboard/"

local function read(name)
    local f = assert(io.open(DIR .. name))
    local s = f:read("a")
    f:close()
    return s
end

t.test("the bar's page carries tico's stylesheet and its own script", function()
    local sources = {}
    for _, name in ipairs(dashboard.BAR_MODULES) do
        sources[name] = read(name)
    end
    local html = dashboard.page(read("bar.html"), read("launcher.css"), sources, dashboard.BAR_MODULES)
    t.eq(html:find("TIMO_", 1, true), nil)
    t.eq(html:find('modules["./bar.js"]', 1, true) ~= nil, true)
    t.eq(html:find('modules["./dashboard.js"]', 1, true), nil)
end)

t.test("the bar's page draws the chips, title, clocks and icons", function()
    local node = io.popen("command -v node"):read("l")
    if not node then
        if os.getenv("TIMO_NEED_NODE") then
            error("node is needed to check the bar's page")
        end
        print("SKIP the bar's page draws the chips, title, clocks and icons: no node")
        return
    end
    local sources = {}
    for _, name in ipairs(dashboard.BAR_MODULES) do
        sources[name] = read(name)
    end
    local path = os.tmpname()
    local f = assert(io.open(path, "w"))
    f:write(dashboard.bundle(sources, dashboard.BAR_MODULES))
    f:close()
    local p = io.popen("TZ=Europe/Dublin node tests/bar_page.cjs " .. path .. " 2>&1")
    local out = p:read("a")
    local ok = p:close()
    os.remove(path)
    if not ok then
        error(out)
    end
end)

t.done("bar")
