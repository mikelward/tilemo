local t = require("t")
local fake = require("fake")
local wm_mod = require("tide.wm")
local ffm_mod = require("tide.ffm")
local dashboard = require("tide.dashboard")
local bar = require("tide.bar")

t.test("the menu bar names each workspace, the one showing marked", function()
    t.eq(bar.title({
        { name = "in", here = true },
        { name = "docs", occupied = true },
        { name = "web" },
        { name = "chat", occupied = true, urgent = true },
    }), "[in] docs web chat!")
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

t.test("on a display with a notch, the bar goes up to the top of the screen", function()
    -- A 14-inch MacBook Pro's display, the menu bar hidden: macOS still
    -- keeps the notch's 32 px at the top.
    local notched = { area = { x = 0, y = 32, w = 1512, h = 950 }, full = { x = 0, y = 0, w = 1512, h = 982 }, notch = true }
    local strip, below = bar.place(notched, 36)
    t.eq(strip, { x = 0, y = 0, w = 1512, h = 36 }, "over the notch, its own height")
    t.eq(below, { x = 0, y = 36, w = 1512, h = 946 }, "windows start under the bar")
    local tall = { area = { x = 0, y = 38, w = 1728, h = 1079 }, full = { x = 0, y = 0, w = 1728, h = 1117 }, notch = true }
    strip, below = bar.place(tall, 36)
    t.eq(strip, { x = 0, y = 0, w = 1728, h = 38 }, "a notch taller than the bar: the notch's height")
    t.eq(below, { x = 0, y = 38, w = 1728, h = 1079 })
end)

t.test("without a notch, the bar sits at the top of the area as before", function()
    local plain = { area = { x = 0, y = 25, w = 1920, h = 1055 }, full = { x = 0, y = 0, w = 1920, h = 1080 } }
    local strip, below = bar.place(plain, 36)
    t.eq(strip, bar.strip(plain.area, 36), "a visible menu bar's room stays the menu bar's")
    t.eq(below, bar.below(plain.area, 36))
    plain.notch = true
    plain.area.y, plain.area.h = 0, 1080
    strip = bar.place(plain, 36)
    t.eq(strip.y, 0, "a notch flag with no room kept is just the top")
end)

t.test("a bar over a menu bar macOS keeps showing covers it, from the top of the screen", function()
    t.eq(bar.level({ menu_bar = true }), "status", "just above the menu bar's level")
    local shown = { area = { x = 0, y = 24, w = 1920, h = 1056 }, full = { x = 0, y = 0, w = 1920, h = 1080 }, menu_bar = true }
    local strip, below = bar.place(shown, 36)
    t.eq(strip, { x = 0, y = 0, w = 1920, h = 36 }, "over the 24 px menu bar, and on past it")
    t.eq(below, { x = 0, y = 36, w = 1920, h = 1044 })
    local notch = { area = { x = 0, y = 38, w = 1512, h = 944 }, full = { x = 0, y = 0, w = 1512, h = 982 }, menu_bar = true }
    strip, below = bar.place(notch, 36)
    t.eq(strip, { x = 0, y = 0, w = 1512, h = 38 }, "as tall as a notched Mac's menu bar")
    t.eq(below.y, 38)
end)

t.test("the room at the top is a notch, a menu bar that shows, or both", function()
    local full = { x = 0, y = 0, w = 1512, h = 982 }
    local function room(y, hidden)
        local notch, menu_bar = bar.top_room({ x = 0, y = y, w = 1512, h = 982 - y }, full, hidden)
        return { notch = notch, menu_bar = menu_bar }
    end
    t.eq(room(38, true), { notch = true, menu_bar = false }, "hidden: only a notch keeps room")
    t.eq(room(0, true), { notch = false, menu_bar = false })
    t.eq(room(38, false), { notch = true, menu_bar = true }, "a notched display's menu bar, shown, still keeps the title clear")
    t.eq(room(25, false), { notch = false, menu_bar = true }, "a plain display's")
    t.eq(room(0, false), { notch = false, menu_bar = true },
        "a menu bar that shows is covered even where macOS keeps no room for it")
end)

t.test("with no room kept for a menu bar that shows, the bar covers it from the top, above its level", function()
    local s = { area = { x = 0, y = 0, w = 1920, h = 1080 }, full = { x = 0, y = 0, w = 1920, h = 1080 } }
    s.notch, s.menu_bar = bar.top_room(s.area, s.full, false)
    t.eq(bar.level(s), "status", "not floating, which the menu bar draws over")
    local strip, below = bar.place(s, 36)
    t.eq(strip, { x = 0, y = 0, w = 1920, h = 36 })
    t.eq(below.y, 36)
end)

t.test("Show Menu Bar ends on Esc or a click below the bars, not on the menu bar", function()
    local frames = { A = { x = 0, y = 0, w = 1920, h = 36 }, B = { x = 1920, y = 0, w = 1280, h = 36 } }
    t.eq(bar.reveal_done(frames, "key", "escape", 0, 0), true)
    t.eq(bar.reveal_done(frames, "key", "a", 0, 0), false, "typing in a menu keeps it")
    t.eq(bar.reveal_done(frames, "mouse", nil, 100, 10), false, "a menu's title")
    t.eq(bar.reveal_done(frames, "mouse", nil, 2000, 10), false, "on the other display's")
    t.eq(bar.reveal_done(frames, "mouse", nil, 100, 200), true, "a menu item, or anywhere else")
    t.eq(bar.reveal_done(frames, "key", "return", 0, 0), true, "choosing an item by key")
end)

t.test("Show Menu Bar ends when a menu's item is chosen by dragging from its title", function()
    local frames = { A = { x = 0, y = 0, w = 1920, h = 36 } }
    local watched = {}
    for _, name in ipairs(bar.REVEAL_EVENTS) do
        watched[name] = true
    end
    t.eq(watched.leftMouseUp and watched.rightMouseUp, true, "the release is watched")
    t.eq(bar.reveal_done(frames, "mouse", nil, 100, 10), false, "the press on the title")
    t.eq(bar.reveal_done(frames, "mouse", nil, 120, 140), true, "the release on the item")
end)

t.test("a bar over a notch sits at the main menu's level, the lowest macOS leaves there", function()
    t.eq(bar.level({ notch = true }), "mainMenu")
    t.eq(bar.level({}), "floating", "elsewhere, below the menu bar, which shows over it")
end)

t.test("windows tile below where the bar really is, when macOS moved it down", function()
    local notched = { area = { x = 0, y = 32, w = 1512, h = 950 }, full = { x = 0, y = 0, w = 1512, h = 982 }, notch = true }
    local strip, below = bar.place(notched, 36, 68)
    t.eq(strip, { x = 0, y = 0, w = 1512, h = 36 }, "still asked for at the top")
    t.eq(below, { x = 0, y = 68, w = 1512, h = 914 }, "but windows start under the bar's real bottom")
    _, below = bar.place(notched, 36, 30)
    t.eq(below.y, 36, "a floor above the strip's bottom changes nothing")
    local a = fake.new()
    a.screens_[1] = notched
    notched.uuid = "A"
    a.add(1, { title = "Notes" })
    local wm = wm_mod.new(a, { top = bar.HEIGHT, workspaces = { "in" } })
    wm:sync()
    wm:reconcile()
    wm.bar_floor.A = 68
    wm:retile()
    t.eq(a.wins[1].frame.y, 68)
    t.eq(a.wins[1].frame.h, 914)
end)

t.test("a display with a notch tiles under the raised bar, and shows no title", function()
    local a = fake.new()
    a.screens_[1] = { uuid = "A", area = { x = 0, y = 32, w = 1512, h = 950 }, full = { x = 0, y = 0, w = 1512, h = 982 }, notch = true }
    a.add(1, { title = "Notes" })
    local wm = wm_mod.new(a, { top = bar.HEIGHT, workspaces = { "in" } })
    wm:sync()
    wm:reconcile()
    wm:retile()
    t.eq(a.wins[1].frame.y, 36)
    t.eq(a.wins[1].frame.h, 946)
    a.focus_ = 1
    t.eq(bar.state(wm, "A", "Notes", {}).title, "", "the notch is where the title would be")
    t.eq(bar.state(wm, "A", "Notes", {}).notch, true, "the page keeps the middle clear")
    local opened
    bar.handle(wm, { uuid = "A", workspaces = true }, { workspaces = function(uuid) opened = uuid end })
    t.eq(opened, "A", "the +n chip opens the switcher's Workspaces")
end)

t.test("a right-click opens its item's settings page, or the first", function()
    local _, wm = two_displays()
    local shown = {}
    local act = { settings = function(page) shown[#shown + 1] = page end }
    bar.handle(wm, { uuid = "A", settings = "clocks" }, act)
    bar.handle(wm, { uuid = "A", settings = "" }, act)
    bar.handle(wm, { uuid = "A", settings = 3 }, act)
    -- "" goes on as it is, so an open window turns to its first page too.
    t.eq(shown, { "clocks", "" }, "a page that isn't a name opens nothing")
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

t.test("every display's bar marks the one workspace showing, and the title shows on the focused one", function()
    local a, wm = two_displays()
    a.focus_ = 1
    wm:ensure_ws("2")
    local sa = bar.state(wm, "A", "Notes", {})
    local sb = bar.state(wm, "B", "Notes", {})
    t.eq(sa.workspaces[1], {
        n = "in",
        current = true,
        occupied = true,
        urgent = false,
        apps = {},
        wins = {},
        more = 0,
    })
    t.eq(sb.workspaces[1].current, true, "B shows it too")
    t.eq(sa.workspaces[2].n, "2")
    t.eq(sa.workspaces[2].current, false)
    t.eq(sb.workspaces[2].current, false)
    t.eq(sa.title, "Notes")
    t.eq(sb.title, "")
    t.eq(sb.uuid, "B")
end)

t.test("the title follows the focused window, not where the keys act", function()
    local a, wm = two_displays()
    a.focus_ = 1
    -- Super+Right onto B, which has nothing of this workspace: the keys
    -- go there, focus stays on window 1 on A.
    wm:act("select", 1)
    t.eq(wm:current_screen(), "B")
    t.eq(bar.state(wm, "A", "Notes", {}).title, "Notes")
    t.eq(bar.state(wm, "B", "Notes", {}).title, "")
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
    t.eq(wm.current, "4")
    t.eq(wm:current_screen(), "B", "nothing to focus there, so the keys stay on B")
    bar.handle(wm, { uuid = "B", show = "nothing" }, act)
    t.eq(wm.current, "4", "a name with no workspace does nothing")
    bar.handle(wm, { uuid = "B", step = -1 }, act)
    t.eq(wm.current, "in")
    bar.handle(wm, { uuid = "B", open = "wifi" }, act)
    bar.handle(wm, { uuid = "B", open = "nothing" }, act)
    t.eq(opened, { bar.PANES.wifi })
end)

t.test("a bar's toggles, volume steps and volume popover go to Hammerspoon", function()
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
    act.sound = function(uuid, at)
        got[#got + 1] = "sound " .. uuid .. " " .. tostring(at.right)
    end
    bar.handle(wm, { uuid = "B", toggle = "mic" }, act)
    bar.handle(wm, { uuid = "B", volume = -1 }, act)
    bar.handle(wm, { uuid = "B", sound = { right = 1730 } }, act)
    bar.handle(wm, { uuid = "B", sound = "junk" }, act)
    t.eq(got, { "toggle mic", "volume -1", "sound B 1730" })
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
    for _, id in ipairs(wm:part("in", "A").order) do
        if id ~= 3 and #wins < bar.CHIP_APPS then
            wins[#wins + 1] = id
            apps[#apps + 1] = wm.windows[id].app
        end
    end
    t.eq(s.workspaces[1].wins, wins)
    t.eq(s.workspaces[1].apps, apps)
    t.eq(s.workspaces[1].more, 3, "two more tiles and the float")
    t.eq(s.workspaces[2], nil, "B has no workspace of its own")
    -- Icons only for the apps shown, each asked for once.
    t.eq(#seen, 5)
    for _, app in ipairs(apps) do
        t.eq(s.app_icons[app], app ~= "app4" and ("data:" .. app) or false)
    end
    t.eq(s.app_icons.float, nil)
end)

t.test("a notifying app's icon shows on the chip of its last used window", function()
    local a, wm = two_displays()
    a.add(2, { app = "chat" })
    wm:sync()
    wm.attention:notified("chat")
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

t.test("clicking an attention icon focuses its window, bringing its hidden workspace to every display", function()
    local a, wm = two_displays()
    a.focus_ = 1
    wm:send(1, "web")
    wm:sync()
    wm:reconcile()
    t.eq(wm:shown("web"), false)
    wm.attention:activated(1, "com.example.app")
    -- From JSON, the id may come back as a float.
    bar.handle(wm, { uuid = "B", focus = 1.0 }, {})
    t.eq(wm.current, "web")
    t.eq(wm.windows[1].screen, "A", "it stays on its own display")
    t.eq(a.focus_, 1)
end)

t.test("clicking an attention icon on the workspace showing only focuses it", function()
    local a, wm = two_displays()
    a.add(2, { app = "chat" })
    wm:sync()
    wm:reconcile()
    a.focus_ = 1
    bar.handle(wm, { uuid = "B", focus = 2 }, {})
    t.eq(wm.current, "in")
    t.eq(a.focus_, 2)
    -- A window that's gone does nothing.
    bar.handle(wm, { uuid = "B", focus = 99 }, {})
    t.eq(a.focus_, 2)
end)

t.test("the bar hides on a display while a window there is in tide's full screen", function()
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

t.test("scrolling on any display's bar steps from the workspace showing, stopping at the first and last", function()
    local _, wm = two_displays()
    wm:ensure_ws("3")
    t.eq(bar.step(wm, "B", 1), "3")
    t.eq(bar.step(wm, "A", 1), "3")
    t.eq(bar.step(wm, "B", -1), "in")
    wm:show("3")
    t.eq(bar.step(wm, "B", 1), "3")
    t.eq(bar.step(wm, "A", -1), "in")
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
    local keys = require("tide.keys")
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

t.test("a VPN's interfaces are its tunnels, not a link", function()
    for _, name in ipairs({ "utun0", "utun12", "ipsec0", "ppp0", "tun3", "tap1" }) do
        t.eq(bar.is_vpn(name), true, name)
    end
    for _, name in ipairs({ "en0", "en7", "bridge0", "awdl0", "utun", "lo0", "", false }) do
        t.eq(bar.is_vpn(name), false, tostring(name))
    end
end)

t.test("a VPN carrying all traffic shows the link under it, with the lock", function()
    local joined = { power = true, rssi = -55, ssid = "home", interface = "en0" }
    t.eq(bar.icons({ wifi = joined, network = { primary = "utun4" } }).network, { kind = "wifi", vpn = true })
    t.eq(bar.icons({ wifi = { power = true, rssi = 0, interface = "en0" }, network = { primary = "utun4" } }).network,
        { kind = "wired", vpn = true }, "Wi-Fi on but not joined: the VPN runs over a wire")
    t.eq(bar.icons({ network = { primary = "ppp0" } }).network, { kind = "wired", vpn = true })
end)

t.test("a VPN carrying only some traffic still shows the lock", function()
    local wifi = { power = true, rssi = -55, interface = "en0" }
    local en0 = { interface = "en0", type = "IEEE80211" }
    local function network(svc)
        return bar.icons({ wifi = wifi, network = { primary = "en0", services = { en0, svc } } }).network
    end
    t.eq(network({ interface = "utun3", type = "VPN", subtype = "com.wireguard.macos" }), { kind = "wifi", vpn = true })
    t.eq(network({ interface = "ipsec0", type = "IPSec" }), { kind = "wifi", vpn = true })
    t.eq(network({ interface = "ppp0", type = "PPP", subtype = "L2TP" }), { kind = "wifi", vpn = true })
    t.eq(network({ interface = "en7", type = "Ethernet" }), { kind = "wifi" }, "no tunnel, no lock")
end)

t.test("a tunnel with no VPN service behind it isn't a VPN", function()
    local wifi = { power = true, rssi = -55, interface = "en0" }
    local function network(svc)
        return bar.icons({ wifi = wifi, network = { primary = "en0", services = { svc } } }).network
    end
    t.eq(network({ interface = "utun2" }), { kind = "wifi" }, "macOS's own utun, with no Setup: interface")
    t.eq(network({ interface = "utun5", type = "Ethernet" }), { kind = "wifi" }, "not a VPN's type")
    t.eq(network({ interface = "ppp0", type = "PPP", subtype = "PPPoE" }), { kind = "wifi" }, "PPPoE is a link")
    t.eq(network("utun3"), { kind = "wifi" }, "a bare name is no service")
end)

t.test("the CPU's share is busy ticks over all ticks between readings", function()
    t.eq(bar.cpu_share({ active = 100, idle = 300 }, { active = 130, idle = 370 }), 0.3)
    t.eq(bar.cpu_share(nil, { active = 130, idle = 370 }), nil, "the first reading has nothing to compare")
    t.eq(bar.cpu_share({ active = 100, idle = 300 }, { active = 100, idle = 300 }), nil, "no time passed")
    t.eq(bar.cpu_share({ active = 500, idle = 900 }, { active = 10, idle = 20 }), nil, "the counters went back")
end)

t.test("memory in use is wired, active and compressed pages", function()
    local vm = { pageSize = 16384, memSize = 16384 * 1000, pagesWiredDown = 200, pagesActive = 300, pagesUsedByVMCompressor = 100 }
    t.eq(bar.memory(vm), { used = 600 * 16384, total = 16384 * 1000 })
    vm.pagesUsedByVMCompressor = nil
    t.eq(bar.memory(vm), nil, "a missing count: no reading")
    t.eq(bar.memory(nil), nil)
end)

t.test("the system monitor shows CPU %, colored as tide's when hot, throttling or short of memory", function()
    local mem = { used = 5, total = 10 }
    t.eq(bar.icons({ sysmon = { cpu = 0.234, memory = mem, thermal = "nominal" } }).sysmon,
        { text = "23%", tone = "normal", tip = "CPU 23%" })
    t.eq(bar.icons({ sysmon = { cpu = 0.2, thermal = "fair" } }).sysmon.tone, "normal", "fair is only warm")
    t.eq(bar.icons({ sysmon = { cpu = 0.2, thermal = "serious" } }).sysmon,
        { text = "20%", tone = "warn", tip = "CPU 20%, hot" })
    t.eq(bar.icons({ sysmon = { cpu = 0.2, thermal = "critical" } }).sysmon,
        { text = "20%", tone = "danger", tip = "CPU 20%, throttling" })
    t.eq(bar.icons({ sysmon = { cpu = 0.2, memory = { used = 9, total = 10 } } }).sysmon,
        { text = "20%", tone = "warn", tip = "CPU 20%, memory nearly full" })
    t.eq(bar.icons({ sysmon = { cpu = 0.2, memory = { used = 9.5, total = 10 }, thermal = "critical" } }).sysmon,
        { text = "20%", tone = "danger", tip = "CPU 20%, throttling, memory nearly full" })
    t.eq(bar.icons({ sysmon = {} }).sysmon, { text = "–", tone = "normal", tip = "CPU" }, "before a second reading")
    t.eq(bar.icons({}).sysmon, nil)
end)

t.test("the session menu locks, logs out, sleeps, restarts and shuts down, in the Apple menu's groups", function()
    local ran = {}
    local menu = bar.session_menu(function(id)
        ran[#ran + 1] = id
    end)
    local titles = {}
    for _, item in ipairs(menu) do
        titles[#titles + 1] = item.title
        if item.fn then
            item.fn()
        end
    end
    t.eq(titles, { "Lock", "Log Out", "-", "Sleep", "Restart", "Shut Down" })
    t.eq(ran, { "lock", "logout", "sleep", "restart", "shutdown" })
end)

t.test("the pointer is kept off a bar's top row, so the hidden menu bar stays hidden", function()
    local frames = { A = { x = 0, y = 0, w = 1512, h = 36 }, B = { x = 1512, y = 0, w = 1920, h = 36, hidden = true } }
    t.eq(bar.off_top(frames, 100, 0), 1, "one point down")
    t.eq(bar.off_top(frames, 100, 0.4), 1)
    t.eq(bar.off_top(frames, 100, 1), nil, "already off it")
    t.eq(bar.off_top(frames, 100, 20), nil)
    t.eq(bar.off_top(frames, 1600, 0), nil, "a hidden bar, under a full-screen window, leaves the menu bar to show")
    t.eq(bar.off_top({ C = { x = 0, y = -1080, w = 1920, h = 36 } }, 100, -1080), -1079, "a display above another")
    t.eq(bar.off_top(frames, 2000, 500), nil)
end)

t.test("the Apple logo's menu is the Apple menu's entries, each opening or doing the real thing", function()
    local opened, ran, titles = {}, {}, {}
    for _, item in ipairs(bar.apple_menu(function(target)
        opened[#opened + 1] = target
    end, function(id)
        ran[#ran + 1] = id
    end)) do
        titles[#titles + 1] = item.title
        if item.fn then
            item.fn()
        end
    end
    t.eq(titles, { "Show Menu Bar", "-", "About This Mac", "-", "System Settings…", "App Store…", "-", "Sleep", "Restart…", "Shut Down…", "-", "Lock Screen", "Log Out…" })
    t.eq(opened, {
        "x-apple.systempreferences:com.apple.SystemProfiler.AboutExtension",
        "/System/Applications/System Settings.app",
        "/System/Applications/App Store.app",
    })
    t.eq(ran, { "menubar", "sleep", "restart", "shutdown", "lock", "logout" }, "Show Menu Bar, then the session menu's own actions")
end)

t.test("the Apple logo opens the Apple menu, from its own bar", function()
    local got
    bar.handle(nil, { uuid = "B", menubar = true }, {
        menubar = function(uuid)
            got = uuid
        end,
    })
    t.eq(got, "B")
end)

t.test("the session icon opens the menu under itself, on its own bar", function()
    local got
    bar.handle(nil, { uuid = "B", session = { x = 1880 } }, {
        session = function(uuid, at)
            got = { uuid, at.x }
        end,
    })
    t.eq(got, { "B", 1880 })
end)

t.test("the system monitor's click opens Activity Monitor", function()
    local opened = {}
    bar.handle(nil, { uuid = "B", open = "sysmon" }, { open = function(u) opened[#opened + 1] = u end })
    t.eq(opened, { "/System/Applications/Utilities/Activity Monitor.app" })
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

t.test("the volume keys are tide's only for a monitor it reads over DDC", function()
    t.eq(bar.volume_key("SOUND_UP", true), 1)
    t.eq(bar.volume_key("SOUND_DOWN", true), -1)
    t.eq(bar.volume_key("MUTE", true), 0)
    t.eq(bar.volume_key("BRIGHTNESS_UP", true), nil, "other media keys stay macOS's")
    t.eq(bar.volume_key("SOUND_UP", false), nil, "an output macOS has a volume for stays macOS's")
end)

t.test("the volume keys' sign says the level or muted", function()
    t.eq(bar.volume_sign(45, false), "Sound 45%")
    t.eq(bar.volume_sign(44.6, nil), "Sound 45%")
    t.eq(bar.volume_sign(45, true), "Sound muted")
    t.eq(bar.volume_sign(nil, false), "Sound 0%")
end)

t.test("Super+Shift+M mutes the microphone", function()
    local keys = require("tide.keys")
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
    t.eq(bar.icons({ audio = { volume = 90, muted = true } }).volume, { level = "mute", muted = true, text = "90%", tip = "Sound muted" })
    t.eq(bar.icons({ audio = { volume = 0 } }).volume.level, "mute")
end)

t.test("the volume says its level as a %, as tide's", function()
    t.eq(bar.icons({ audio = { volume = 39.6, muted = false } }).volume, { level = "mid", muted = false, text = "40%", tip = "Sound 40%" })
end)

t.test("an output with no volume control, as a monitor's speakers, still shows", function()
    t.eq(bar.icons({ audio = { name = "LG HDR 4K", muted = false } }).volume,
        { level = "fixed", muted = false, fixed = true, can_mute = true, tip = "Sound: LG HDR 4K has no volume control" })
    t.eq(bar.icons({ audio = { name = "LG HDR 4K", muted = true } }).volume,
        { level = "mute", muted = true, fixed = true, can_mute = true, tip = "Sound muted" })
    t.eq(bar.icons({ audio = { name = "LG HDR 4K" } }).volume,
        { level = "fixed", muted = false, fixed = true, can_mute = false, tip = "Sound: LG HDR 4K has no volume control" },
        "nor any mute: a click opens Sound settings")
    t.eq(bar.icons({ audio = {} }).volume.tip, "Sound: this output has no volume control")
    t.eq(bar.icons({}).volume, nil, "no output device: no icon")
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

local DIR = "hammerspoon/tide/dashboard/"

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
    t.eq(dashboard.js_failed({ code = 0 }), false)
    t.eq(dashboard.js_failed(nil), false)
    t.eq(dashboard.js_failed({ code = 4, localizedDescription = "A JavaScript exception occurred" }), true)
end)

t.test("the bar's page carries tileco's stylesheet and its own script", function()
    local sources = {}
    for _, name in ipairs(dashboard.BAR_MODULES) do
        sources[name] = read(name)
    end
    local html = dashboard.page(read("bar.html"), read("launcher.css"), sources, dashboard.BAR_MODULES)
    t.eq(html:find("TIDE_", 1, true), nil)
    t.eq(html:find('modules["./bar.js"]', 1, true) ~= nil, true)
    t.eq(html:find('modules["./dashboard.js"]', 1, true), nil)
    -- The page reports its own errors, from a script that runs first.
    local onerror = html:find("window.onerror", 1, true)
    t.eq(onerror ~= nil and onerror < html:find('modules["./bar.js"]', 1, true), true)
end)

t.test("the bar's page draws the chips, title, clocks and icons", function()
    local node = io.popen("command -v node"):read("l")
    if not node then
        if os.getenv("TIDE_NEED_NODE") then
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
