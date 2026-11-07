local t = require("t")
local fake = require("fake")
local wm_mod = require("tide.wm")
local ffm_mod = require("tide.ffm")
local tray = require("tide.tray")
local launcher = require("tide.launcher")

-- Minimize mode (`hide = "minimize"`), for the tests about hiding a
-- workspace by minimizing: they read macOS's minimized flag as hidden, or
-- test the minimize expectations. Parking, the default, has its own tests
-- (wm_test.lua, park_test.lua).
local function minimizing(config)
    config = config or {}
    config.hide = "minimize"
    return config
end

-- Windows 1..n on "in", on display A, with a second display B. `config`
-- is start()'s, over the workspaces "in" and "web".
local function setup(n, _, config)
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    for i = 1, n do
        a.add(i, { title = "Window " .. i, app = "app" .. i })
    end
    config = config or {}
    config.workspaces = { "in", "web" }
    local wm = wm_mod.new(a, config)
    wm:sync()
    wm:reconcile()
    wm:retile()
    return a, wm
end

-- macOS reporting back what tide asked it to do.
local function settle(a, wm)
    for id, w in pairs(a.wins) do
        if w.minimized and not w.reported then
            w.reported = true
            wm:minimized(id)
        end
    end
    a.tick()
end

-- Focus a window, as macOS reporting it would.
local function focus(wm, id)
    wm:focus_window(id)
    wm:focused(id)
end

local function ids(st)
    local out = {}
    for i, item in ipairs(st and st.items or {}) do
        out[i] = item.id
    end
    return out
end

t.test("Super+Z minimizes the focused window, frees its tile, and focuses the last used one", function()
    local a, wm = setup(3)
    focus(wm, 2)
    focus(wm, 3)
    wm:act("minimize")
    t.eq(a.wins[3].minimized, true)
    t.eq(wm.windows[3].mine, true)
    t.eq(a.focus_, 2)
    t.eq(wm:tiled("in", "A"), { 1, 2 })
    settle(a, wm)
    t.eq(wm.windows[3].mine, true, "macOS's report of tide's own minimize leaves it yours")
end)

t.test("Super+Z on no managed window does nothing", function()
    local a, wm = setup(1)
    a.focus_ = nil
    wm:act("minimize")
    t.eq(a.wins[1].minimized, nil)
end)

t.test("a window you minimized stays down when its workspace comes back", function()
    local a, wm = setup(2, nil, minimizing())
    focus(wm, 2)
    wm:act("minimize")
    settle(a, wm)
    wm:show("web", "A")
    settle(a, wm)
    wm:show("in", "A")
    settle(a, wm)
    t.eq(a.wins[1].minimized, false)
    t.eq(a.wins[2].minimized, true)
end)

t.test("the tray lists the windows you minimized there, in order, and not the ones tide hid", function()
    local a, wm = setup(4, nil, minimizing())
    focus(wm, 3)
    wm:act("minimize")
    -- Cmd+M, which macOS reports without tide asking.
    a.wins[1].minimized = true
    a.wins[1].reported = true
    wm:minimized(1)
    a.tick()
    t.eq(ids(tray.state(wm, "A")), { 3, 1 }, "newest at the right")
    t.eq(tray.state(wm, "A").items[1], { id = 3, app = "app3", title = "Window 3" })
    -- Window 4 goes to "web", which isn't showing: tide hides it.
    wm:send(4, "web")
    settle(a, wm)
    t.eq(a.wins[4].minimized, true)
    t.eq(ids(tray.state(wm, "A")), { 3, 1 })
    t.eq(tray.state(wm, "B"), nil, "B's part has none")
end)

t.test("each display's tray shows the windows you minimized from its own part of the workspace", function()
    local a, wm = setup(2)
    focus(wm, 2)
    -- Window 2 is the stack, on the right: Super+Shift+Right takes it to B.
    wm:act("move_side", 1)
    t.eq(wm.windows[2].screen, "B")
    t.eq(wm.windows[2].ws, "in")
    wm:act("minimize")
    settle(a, wm)
    t.eq(tray.state(wm, "A"), nil)
    t.eq(ids(tray.state(wm, "B")), { 2 })
    local trays = tray.all(wm)
    t.eq(trays.A, nil)
    t.eq(ids(trays.B), { 2 })
    t.eq(tray.all(wm, function(uuid)
        return uuid == "B"
    end).B, nil, "hidden with the bar")
end)

t.test("the tray sits in the bottom-right corner and grows to the left", function()
    local area = { x = 0, y = 25, w = 1920, h = 1055 }
    t.eq(tray.frame(area, 1), { x = 1920 - 12 - 38, y = 25 + 1055 - 12 - 38, w = 38, h = 38 })
    t.eq(tray.frame(area, 2).w, 72)
    t.eq(tray.icon_box(2), { x = 39, y = 5, w = 28, h = 28 })
    t.eq(tray.fits(1920), 55)
    t.eq(tray.fits(100), 2)
    t.eq(tray.fits(10), 0)
end)

t.test("with more than fit, the tray shows the newest", function()
    local a, wm = setup(4)
    a.screens_[1].area.w = 120
    for _, id in ipairs({ 1, 2, 3 }) do
        focus(wm, id)
        wm:act("minimize")
    end
    t.eq(ids(tray.state(wm, "A")), { 2, 3 })
end)

t.test("clicking an icon restores the window and focuses it", function()
    local a, wm = setup(3)
    focus(wm, 2)
    wm:act("minimize")
    settle(a, wm)
    tray.click(wm, 2)
    t.eq(a.wins[2].minimized, false)
    t.eq(wm.windows[2].mine, false)
    t.eq(a.focus_, 2)
    t.eq(tray.state(wm, "A"), nil)
    -- A window that's gone since does nothing.
    tray.click(wm, 99)
end)

t.test("clicking an icon for a hidden workspace's window brings the workspace", function()
    local a, wm = setup(2)
    wm:send(2, "web")
    wm:show("web", "A")
    settle(a, wm)
    focus(wm, 2)
    wm:act("minimize")
    settle(a, wm)
    wm:show("in", "A")
    settle(a, wm)
    tray.click(wm, 2)
    t.eq(wm:shown("web"), true)
    t.eq(a.wins[2].minimized, false)
end)

t.test("a title's tip sits above its icon, kept on the display", function()
    local area = { x = 0, y = 25, w = 1920, h = 1055 }
    local f = tray.frame(area, 2)
    local tip = tray.tip_frame(f, 2, 100, 24, area)
    t.eq(tip.x + tip.w, f.x + 39 + 28, "right-aligned with icon 2")
    t.eq(tip.y, f.y - 6 - 24)
    t.eq(tray.tip_frame(f, 1, 3000, 24, area).x, 12)
end)

t.test("focus follows mouse pauses over the tray", function()
    local _, wm = setup(1)
    local ffm = ffm_mod.new(wm, wm.a, {})
    wm.overlays = tray.frames({ A = { frame = { x = 1800, y = 1000, w = 100, h = 40 } } })
    t.eq(ffm:paused(1850, 1020, false), true)
    t.eq(ffm:paused(1700, 1020, false), false)
end)

t.test("the Windows tab marks the windows you minimized", function()
    local items = launcher.items({}, {}, {}, {}, {}, {}, {
        { id = 1, title = "Notes", app_name = "Notes", ws = "in", minimized = true },
        { id = 2, title = "Mail", app_name = "Mail", ws = "in" },
    })
    local by = {}
    for _, item in ipairs(items) do
        by[item.window] = item
    end
    t.eq(launcher.subtitle(by[1]), "Notes · in · minimized")
    t.eq(launcher.subtitle(by[2]), "Mail · in")
end)

t.done("tray")
