local t = require("t")
local fake = require("fake")
local wm_mod = require("tilemo.wm")
local ffm_mod = require("tilemo.ffm")
local dashboard = require("tilemo.dashboard")
local bar = require("tilemo.bar")

t.test("the menu bar names each workspace: this display's, others showing, and the rest", function()
    t.eq(bar.title({
        { name = "in", here = true },
        { name = "docs", occupied = true },
        { name = "web", elsewhere = true },
        { name = "chat", occupied = true, urgent = true },
    }), "[in] docs (web) chat!")
end)

t.test("a long name is cut at 16 characters with an ellipsis", function()
    t.eq(bar.short("ABC-123 fix the login page"), "ABC-123 fix the …")
    t.eq(bar.short("sixteen chars ok"), "sixteen chars ok")
    t.eq(bar.short("ééééééééééééééééé"), "éééééééééééééééé…", "by character, not byte")
    t.eq(bar.title({ { name = "a much longer name than that", here = true } }), "[a much longer na…]")
end)

local function two_displays(top)
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, { title = "Notes" })
    -- No standing workspaces past "in", so B's comes second.
    local wm = wm_mod.new(a, { top = top or bar.HEIGHT, workspaces = { "in" } })
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
    t.eq(sa.workspaces[1], {
        n = "in",
        current = true,
        elsewhere = false,
        occupied = true,
        urgent = false,
        apps = {},
        wins = {},
        more = 0,
    })
    t.eq(sa.workspaces[2].n, "2")
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
    wm:show("2", nil, true)
    t.eq(wm.screen_ws, { A = "2", B = "in" })
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
    -- tide's logo: the switcher, opened or closed by Hammerspoon.
    local switched = {}
    act.switcher = function(uuid)
        switched[#switched + 1] = uuid
    end
    bar.handle(wm, { uuid = "B", switcher = true }, act)
    t.eq(switched, { "B" })
    t.eq(dash, { "B" }, "the logo isn't the clocks")
    wm:ensure_ws("4")
    bar.handle(wm, { uuid = "B", show = "4" }, act)
    t.eq(wm.screen_ws, { A = "in", B = "4" })
    bar.handle(wm, { uuid = "B", show = "nothing" }, act)
    t.eq(wm.screen_ws, { A = "in", B = "4" }, "a name with no workspace does nothing")
    t.eq(wm.names, { "in", "4" }, "B's empty 2 went once left")
    bar.handle(wm, { uuid = "B", step = -1 }, act)
    t.eq(wm.screen_ws, { A = "4", B = "in" }, "a step to the one on A swaps the two")
    bar.handle(wm, { uuid = "B", open = "wifi" }, act)
    bar.handle(wm, { uuid = "B", open = "nothing" }, act)
    t.eq(opened, { bar.PANES.wifi })
end)

t.test("a bar's toggles and volume steps go to Hammerspoon", function()
    local _, wm = two_displays()
    local got = {}
    local act = {
        toggle = function(what)
            got[#got + 1] = "toggle " .. what
        end,
        volume = function(d)
            got[#got + 1] = "volume " .. d
        end,
    }
    bar.handle(wm, { uuid = "B", toggle = "mic" }, act)
    bar.handle(wm, { uuid = "B", volume = -1 }, act)
    t.eq(got, { "toggle mic", "volume -1" })
end)

t.test("a bar's clocks, kept while a file is wrong, go to Hammerspoon", function()
    local _, wm = two_displays()
    local kept
    bar.handle(wm, { uuid = "B", goodClocks = { { zone = "Asia/Tokyo", label = "TYO" } } }, {
        good_clocks = function(c)
            kept = c
        end,
    })
    t.eq(kept, { { zone = "Asia/Tokyo", label = "TYO" } })
end)

t.test("hovering a bar's title or an item with a tip asks Hammerspoon for it, naming the display", function()
    local _, wm = two_displays()
    local got = {}
    local act = {
        tip = function(uuid, tip)
            got[#got + 1] = { uuid, tip.text, tip.x }
        end,
    }
    bar.handle(wm, { uuid = "B", tip = { text = "A long title", x = 500 } }, act)
    bar.handle(wm, { uuid = "B", tip = { text = "" } }, act)
    bar.handle(wm, { uuid = "B", tip = { text = "Microphone", x = 1800 } }, act)
    t.eq(got, { { "B", "A long title", 500 }, { "B", "" }, { "B", "Microphone", 1800 } })
end)

t.test("a tip sits below the bar, centered on its item, on its display", function()
    local frame = { x = 1920, y = 25, w = 1920, h = 30 }
    t.eq(bar.tip_frame(frame, 960, 400, 26), { x = 1920 + 760, y = 25 + 30 + 6, w = 400, h = 26 })
    t.eq(bar.tip_frame(frame, 50, 400, 26).x, 1920 + 6, "held off the left edge")
    t.eq(bar.tip_frame(frame, 1900, 400, 26).x, 1920 + 1920 - 6 - 400, "and the right")
end)

t.test("the title's tip goes with its bar: hidden, removed or moved", function()
    local frame = { x = 0, y = 25, w = 1920, h = 30 }
    local views = { A = { frame = { x = 0, y = 25, w = 1920, h = 30 } } }
    t.eq(bar.tip_orphaned("A", frame, views), false, "still there")
    views.A.hidden = true
    t.eq(bar.tip_orphaned("A", frame, views), true, "hidden for a full-screen window")
    views.A.hidden = false
    t.eq(bar.tip_orphaned("A", frame, views), false, "shown again")
    views.A.frame = { x = 0, y = 25, w = 1440, h = 30 }
    t.eq(bar.tip_orphaned("A", frame, views), true, "its display changed size")
    t.eq(bar.tip_orphaned("B", frame, views), true, "its display was removed")
end)

t.test("the title's tip is as wide as the title, wrapping a long one", function()
    t.eq({ bar.tip_size(200.4, 15, 600) }, { 219, 25 })
    t.eq({ bar.tip_size(1500, 15, 600) }, { 618, 15 * 4 + 10 }, "three lines' worth, and one to spare")
end)

t.test("a chip shows no app icons for windows that don't want attention", function()
    local a, wm = two_displays()
    for id = 2, 4 do
        a.add(id, { app = "app" .. id })
    end
    wm:sync()
    local asked = 0
    local s = bar.state(wm, "A", "", {}, function()
        asked = asked + 1
        return "data:x"
    end)
    t.eq(s.workspaces[1].occupied, true)
    t.eq(s.workspaces[1].apps, {})
    t.eq(s.workspaces[1].more, 0)
    t.eq(asked, 0, "no icon is made for a chip that shows none")
    t.eq(s.app_icons, {})
end)

t.test("a chip names its windows wanting attention, in layout order, up to five, then how many more", function()
    local a, wm = two_displays()
    for id = 2, 8 do
        a.add(id, { app = "app" .. id })
    end
    a.add(9, { app = "float", frame = { x = 300, y = 300, w = 200, h = 200 } })
    wm:sync()
    wm.windows[9].floating = true
    wm:retile()
    -- All but window 3 want attention, marked in no particular order.
    for _, id in ipairs({ 9, 5, 1, 2, 8, 4, 7, 6 }) do
        wm.attention:activated(id, wm.windows[id].app)
    end
    local seen = {}
    local s = bar.state(wm, "A", "", {}, function(app)
        seen[#seen + 1] = app
        return app ~= "app4" and ("data:" .. app) or nil
    end)
    local wins, apps = {}, {}
    for _, id in ipairs(wm.workspaces["in"].order) do
        if id ~= 3 and #wins < bar.CHIP_APPS then
            wins[#wins + 1] = id
            apps[#apps + 1] = wm.windows[id].app
        end
    end
    t.eq(s.workspaces[1].wins, wins)
    t.eq(s.workspaces[1].apps, apps)
    t.eq(s.workspaces[1].more, 3, "two more tiles and the float")
    t.eq(s.workspaces[2].apps, {})
    -- Icons only for the apps shown, each asked for once.
    t.eq(#seen, 5)
    for _, app in ipairs(apps) do
        t.eq(s.app_icons[app], app ~= "app4" and ("data:" .. app) or false)
    end
    t.eq(s.app_icons.float, nil)
end)

t.test("a badged app's icon shows on the chip of its last used window", function()
    local a, wm = two_displays()
    a.add(2, { app = "chat" })
    wm:sync()
    wm.attention:dock({ { app = "chat", label = "2" } })
    local s = bar.state(wm, "A", "", {})
    t.eq(s.workspaces[1].apps, { "chat" })
    t.eq(s.workspaces[1].wins, { 2 })
end)

t.test("floats follow a workspace's tiles in its chip", function()
    local a, wm = two_displays()
    a.add(2, { app = "float" })
    wm:sync()
    wm.windows[2].floating = true
    wm.attention:activated(2, "float")
    wm.attention:activated(1, "com.example.app")
    t.eq(bar.state(wm, "A", "", {}).workspaces[1].apps, { "com.example.app", "float" })
end)

t.test("clicking an attention icon focuses its window, bringing a hidden workspace to that bar's display", function()
    local a, wm = two_displays()
    a.focus_ = 1
    wm:send(1, "web")
    wm:sync()
    wm:reconcile()
    t.eq(wm:shown("web"), nil)
    wm.attention:activated(1, "com.example.app")
    -- From JSON, the id may come back as a float.
    bar.handle(wm, { uuid = "B", focus = 1.0 }, {})
    t.eq(wm:shown("web"), "B")
    t.eq(a.focus_, 1)
end)

t.test("clicking an attention icon leaves a workspace where it shows", function()
    local a, wm = two_displays()
    a.add(2, { app = "chat" })
    wm:sync()
    wm:reconcile()
    a.focus_ = 1
    bar.handle(wm, { uuid = "B", focus = 2 }, {})
    t.eq(wm:shown("in"), "A")
    t.eq(a.focus_, 2)
    -- A window that's gone does nothing.
    bar.handle(wm, { uuid = "B", focus = 99 }, {})
    t.eq(a.focus_, 2)
end)

t.test("the bar hides on a display while a window there is in tilemo's full screen", function()
    local a, wm = two_displays()
    a.focus_ = 1
    t.eq(bar.hidden(wm, "A"), false)
    wm:act("fullscreen")
    t.eq(bar.hidden(wm, "A"), true)
    t.eq(bar.hidden(wm, "B"), false)
    -- Maximized stops at the bar, so the bar stays.
    wm:act("maximize")
    t.eq(bar.hidden(wm, "A"), false)
    wm:act("fullscreen")
    a.wins[1].minimized = true
    t.eq(bar.hidden(wm, "A"), false, "a minimized window covers nothing")
    a.wins[1].minimized = false
    wm:act("restore")
    t.eq(bar.hidden(wm, "A"), false, "and it comes back after")
end)

t.test("the bar hides on a display while the focused window is in macOS's full screen there", function()
    local a, wm = two_displays()
    a.focus_ = 1
    a.wins[1].fullscreen = true
    a.wins[1].frame = { x = 0, y = 0, w = 1920, h = 1080 }
    t.eq(bar.hidden(wm, "A"), true)
    t.eq(bar.hidden(wm, "B"), false)
    a.wins[1].frame = { x = 1920, y = 0, w = 1920, h = 1080 }
    t.eq(bar.hidden(wm, "A"), false)
    t.eq(bar.hidden(wm, "B"), true)
    a.wins[1].fullscreen = false
    t.eq(bar.hidden(wm, "B"), false)
end)

t.test("double-clicking a bar's title maximizes the focused window on that display only", function()
    local a, wm = two_displays()
    a.focus_ = 1
    bar.handle(wm, { uuid = "B", maximize = true }, {})
    t.eq(wm.windows[1].big, nil, "the title isn't on B")
    bar.handle(wm, { uuid = "A", maximize = true }, {})
    t.eq(wm.windows[1].big, "max")
    t.eq(a.wins[1].frame, { x = 0, y = 61, w = 1920, h = 1019 })
    bar.handle(wm, { uuid = "A", maximize = true }, {})
    t.eq(wm.windows[1].big, nil, "again puts it back")
end)

t.test("scrolling steps from that display's workspace in bar order, stopping at the first and last", function()
    local _, wm = two_displays()
    wm:ensure_ws("3")
    t.eq(bar.step(wm, "B", 1), "3")
    t.eq(bar.step(wm, "B", -1), "in")
    t.eq(bar.step(wm, "A", -1), "in")
    wm.screen_ws.B = "3"
    t.eq(bar.step(wm, "B", 1), "3")
end)

t.test("the battery shows its rounded percentage and whether it's charging", function()
    t.eq(bar.icons({ battery = { percent = 83.6, charging = true } }).battery,
        { percent = 84, charging = true, text = "84%", tip = "Battery 84%, charging" })
    t.eq(bar.icons({}).battery, nil)
end)

t.test("the battery's tip says how long until full or empty, when macOS knows", function()
    local tip = function(b)
        b.percent = b.percent or 50
        return bar.icons({ battery = b }).battery.tip
    end
    t.eq(tip({ charging = true, to_full = 65 }), "Battery 50%, charging, full in 1:05")
    t.eq(tip({ charging = true, to_full = -1 }), "Battery 50%, charging")
    t.eq(tip({ remaining = 192 }), "Battery 50%, 3:12 left")
    t.eq(tip({ remaining = -1 }), "Battery 50%")
    t.eq(tip({ percent = 100, charged = true, remaining = -2 }), "Battery 100%, charged")
end)

t.test("a fractional time estimate still shows as hours and minutes", function()
    t.eq(bar.icons({ battery = { percent = 50, remaining = 192.6 } }).battery.tip, "Battery 50%, 3:12 left")
    t.eq(bar.icons({ battery = { percent = 50, charging = true, to_full = 64.9 } }).battery.tip,
        "Battery 50%, charging, full in 1:04")
end)

t.test("one reading that makes no sense drops that item, not the bar", function()
    local errs = {}
    local icons = bar.icons({ battery = { percent = "lots" }, mic = { muted = true }, awake = true }, function(name, err)
        errs[#errs + 1] = name .. ": " .. tostring(err)
    end)
    t.eq(icons.battery, nil)
    t.eq(icons.mic, { muted = true })
    t.eq(icons.awake, { on = true })
    t.eq(#errs, 1)
    t.eq(errs[1]:find("^battery: ") ~= nil, true)
end)

t.test("the microphone shows muted or not, and no in-use light", function()
    t.eq(bar.icons({ mic = { muted = true } }).mic, { muted = true })
    t.eq(bar.icons({ mic = {} }).mic, { muted = false })
    -- Hammerspoon's in-use reading is the whole device's, so even if a
    -- reader passed it along, the bar wouldn't show it.
    t.eq(bar.icons({ mic = { muted = false, in_use = true } }).mic, { muted = false })
    t.eq(bar.icons({}).mic, nil)
end)

t.test("the camera shows only while something has it on", function()
    t.eq(bar.icons({ camera = { in_use = true } }).camera, { in_use = true })
    t.eq(bar.icons({ camera = { in_use = false } }).camera, nil)
    t.eq(bar.icons({}).camera, nil)
end)

t.test("the input source shows only with more than one, as a short label", function()
    local one = { current = "U.S.", list = { { name = "U.S." } } }
    local two = { current = "Dvorak", list = { { name = "U.S." }, { name = "Dvorak" } } }
    t.eq(bar.icons({ source = one }).source, nil)
    t.eq(bar.icons({ source = two }).source, { label = "DVO", name = "Dvorak" })
    t.eq(bar.source_label("U.S."), "US")
    t.eq(bar.source_label("Pinyin - Simplified"), "PIN")
end)

t.test("a click on the input source goes to the next one, wrapping", function()
    local list = { { name = "U.S." }, { name = "Dvorak" }, { name = "Pinyin", method = true } }
    t.eq(bar.next_source(list, "U.S.").name, "Dvorak")
    t.eq(bar.next_source(list, "Pinyin").name, "U.S.")
    t.eq(bar.next_source(list, "gone").name, "U.S.")
end)

t.test("keep awake shows whether it's on", function()
    t.eq(bar.icons({ awake = true }).awake, { on = true })
    t.eq(bar.icons({ awake = false }).awake, { on = false })
    t.eq(bar.icons({}).awake, nil)
end)

t.test("keep awake says when presenter mode is on, whatever the assertion reads", function()
    t.eq(bar.icons({ awake = true, presenting = true }).awake, { on = true, presenting = true })
    t.eq(bar.icons({ awake = false, presenting = true }).awake, { on = true, presenting = true })
    t.eq(bar.icons({ presenting = true }).awake, { on = true, presenting = true })
    t.eq(bar.icons({ awake = true, presenting = false }).awake, { on = true })
end)

t.test("Super+S keeps awake and Super+P turns on presenter mode", function()
    local keys = require("tilemo.keys")
    local found = {}
    for _, b in ipairs(keys.map) do
        if not b.shift and (b.key == "s" or b.key == "p") then
            found[b.key] = b.action
        end
    end
    t.eq(found, { s = "keep_awake", p = "presenter" })
    local _, wm = two_displays()
    local calls = {}
    wm.toggle_keep_awake = function()
        calls[#calls + 1] = "awake"
    end
    wm.toggle_presenter = function()
        calls[#calls + 1] = "presenter"
    end
    wm:act("keep_awake")
    wm:act("presenter")
    t.eq(calls, { "awake", "presenter" })
end)

t.test("the network is Wi-Fi, a wire, or none, by the interface carrying traffic", function()
    local wifi = { power = true, rssi = -55, interface = "en0" }
    t.eq(bar.icons({ wifi = wifi, network = { primary = "en0" } }).network, { kind = "wifi" })
    t.eq(bar.icons({ wifi = wifi, network = { primary = "en7" } }).network, { kind = "wired" })
    t.eq(bar.icons({ wifi = wifi, network = {} }).network, { kind = "none" })
    t.eq(bar.icons({ network = { primary = "en5" } }).network, { kind = "wired" })
    -- Without the primary interface, Wi-Fi being on stands in.
    t.eq(bar.icons({ wifi = wifi }).network, { kind = "wifi" })
    t.eq(bar.icons({}).network, { kind = "none" })
end)

t.test("scrolling on the speaker steps the volume 5%, and up unmutes", function()
    t.eq({ bar.volume_step(50, false, 1) }, { 55, false })
    t.eq({ bar.volume_step(3, false, -1) }, { 0, false })
    t.eq({ bar.volume_step(98.4, false, 1) }, { 100, false })
    t.eq({ bar.volume_step(50, true, 1) }, { 55, true })
    t.eq({ bar.volume_step(50, true, -1) }, { 45, false })
end)

t.test("Super+Shift+M mutes the microphone", function()
    local keys = require("tilemo.keys")
    local found
    for _, b in ipairs(keys.map) do
        if b.key == "m" and b.shift then
            found = b.action
        end
    end
    t.eq(found, "mic_mute")
    local _, wm = two_displays()
    local toggled = 0
    wm.toggle_mic = function()
        toggled = toggled + 1
    end
    wm:act("mic_mute")
    t.eq(toggled, 1)
end)

t.test("each connected Bluetooth audio device gets an icon, named once, in order", function()
    t.eq(bar.icons({}).headphones, nil)
    t.eq(bar.icons({ bluetooth_audio = {} }).headphones, nil, "none connected: no icon")
    t.eq(bar.icons({ bluetooth_audio = { "Buds", "Car", "Buds", "" } }).headphones, { devices = { { name = "Buds" }, { name = "Car" } } },
        "a headset is an output and an input: one icon; a nameless one is left out")
end)

t.test("a headphones click opens Bluetooth settings", function()
    t.eq(bar.PANES.bluetooth, "x-apple.systempreferences:com.apple.BluetoothSettings")
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
    for _, k in ipairs({ "battery", "volume", "wifi", "network" }) do
        t.eq(bar.PANES[k]:find("^x%-apple%.systempreferences:") ~= nil, true)
    end
end)

local DIR = "hammerspoon/tilemo/dashboard/"

local function read(name)
    local f = assert(io.open(DIR .. name))
    local s = f:read("a")
    f:close()
    return s
end

t.test("the pointer over a bar is told to that bar, in its page's coordinates", function()
    local frames = {
        A = { x = 0, y = 25, w = 1920, h = 36 },
        B = { x = 1920, y = 0, w = 1920, h = 36 },
        C = { x = 3840, y = 0, w = 1920, h = 36, hidden = true },
    }
    local uuid, x, y = bar.pointer_at(frames, 100, 30)
    t.eq({ uuid, x, y }, { "A", 100, 5 })
    uuid, x, y = bar.pointer_at(frames, 1920, 35)
    t.eq({ uuid, x, y }, { "B", 0, 35 })
    t.eq(bar.pointer_at(frames, 100, 61), nil, "just below the bar")
    t.eq(bar.pointer_at(frames, 3900, 10), nil, "a hidden bar")
end)

t.test("a page's script failing is told from Hammerspoon's empty error", function()
    -- hs.webview passes { code = 0 } when the script ran.
    t.eq(bar.js_failed({ code = 0 }), false)
    t.eq(bar.js_failed(nil), false)
    t.eq(bar.js_failed({ code = 4, localizedDescription = "A JavaScript exception occurred" }), true)
end)

t.test("the bar's page carries tileco's stylesheet and its own script", function()
    local sources = {}
    for _, name in ipairs(dashboard.BAR_MODULES) do
        sources[name] = read(name)
    end
    local html = dashboard.page(read("bar.html"), read("launcher.css"), sources, dashboard.BAR_MODULES)
    t.eq(html:find("TILEMO_", 1, true), nil)
    t.eq(html:find('modules["./bar.js"]', 1, true) ~= nil, true)
    t.eq(html:find('modules["./dashboard.js"]', 1, true), nil)
    -- The page reports its own errors, from a script that runs first.
    local onerror = html:find("window.onerror", 1, true)
    t.eq(onerror ~= nil and onerror < html:find('modules["./bar.js"]', 1, true), true)
end)

t.test("the bar's page draws the chips, title, clocks and icons", function()
    local node = io.popen("command -v node"):read("l")
    if not node then
        if os.getenv("TILEMO_NEED_NODE") then
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
