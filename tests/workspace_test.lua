local t = require("t")
local fake = require("fake")
local wm_mod = require("timo.wm")

local function setup(n, saved)
    local a = fake.new()
    for i = 1, n or 0 do
        a.add(i, {})
    end
    local wm = wm_mod.new(a, { saved = saved })
    wm:sync()
    wm:reconcile()
    wm:retile()
    a.calls = {}
    return a, wm
end

local function two_displays(a)
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
end

t.test("Super+N shows workspace N, hiding the one before", function()
    local a, wm = setup(2)
    a.focus_ = 1
    wm:act("show", 3)
    t.eq(wm.screen_ws.A, 3)
    t.eq(a.wins[1].minimized, true)
    t.eq(a.wins[2].minimized, true)
    wm:act("show", 1)
    t.eq(a.wins[1].minimized, false)
    t.eq(a.wins[2].minimized, false)
end)

t.test("restores come before minimizes, so the screen never goes empty", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("send", 2)
    a.calls = {}
    wm:act("show", 2)
    t.eq(a.calls[1], "unminimize 1")
    wm:act("send", 1)
    a.add(5, {})
    wm:sync()
    a.calls = {}
    a.focus_ = 5
    wm:act("show", 1)
    t.eq(a.calls[1], "unminimize 1")
    t.eq(a.calls[2], "minimize 5")
end)

t.test("Super+Shift+N sends the window away, and focus stays on this workspace", function()
    local a, wm = setup(2)
    wm:focused(1)
    wm:focused(2)
    a.focus_ = 2
    wm:act("send", 4)
    t.eq(wm.windows[2].ws, 4)
    t.eq(a.wins[2].minimized, true)
    t.eq(wm.workspaces[1].order, { 1 })
    t.eq(a.focus_, 1)
    t.eq(a.wins[1].frame.w, 1920)
end)

t.test("showing a workspace focuses its last used window", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:focused(2)
    wm:act("send", 3)
    wm:act("show", 3)
    t.eq(a.focus_, 2)
end)

t.test("Super+Left and Right step through workspaces, stopping at 1 and 9", function()
    local _, wm = setup(1)
    wm:act("step", -1)
    t.eq(wm.screen_ws.A, 1)
    wm:act("step", 1)
    t.eq(wm.screen_ws.A, 2)
    wm:act("show", 9)
    wm:act("step", 1)
    t.eq(wm.screen_ws.A, 9)
end)

t.test("Super+Shift+Right carries the window to the next workspace and follows it", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("carry", 1)
    t.eq(wm.screen_ws.A, 2)
    t.eq(wm.windows[2].ws, 2)
    t.eq(a.wins[2].minimized, false)
    t.eq(a.wins[1].minimized, true)
    t.eq(a.focus_, 2)
end)

t.test("showing a workspace that's on the other display swaps the two", function()
    local a = fake.new()
    two_displays(a)
    a.add(1, {})
    a.add(2, { frame = { x = 2000, y = 100, w = 800, h = 600 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    t.eq(wm.screen_ws, { A = 1, B = 2 })
    a.focus_ = 1
    wm:act("show", 2)
    t.eq(wm.screen_ws, { A = 2, B = 1 })
    t.eq(a.wins[1].minimized or false, false)
    t.eq(a.wins[2].minimized or false, false)
    t.eq(a.wins[2].frame.x, 0, "workspace 2 tiles on the display now showing it")
    t.eq(a.wins[1].frame.x, 1920)
end)

t.test("after swapping in an empty workspace, keys still act on this display", function()
    local a = fake.new()
    two_displays(a)
    a.add(1, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    t.eq(wm.screen_ws, { A = 1, B = 2 })
    a.focus_ = 1
    wm:act("show", 2) -- empty: window 1 goes to B and keeps focus
    t.eq(wm.screen_ws, { A = 2, B = 1 })
    t.eq(a.wins[1].frame.x >= 1920, true)
    wm:act("show", 3)
    t.eq(wm.screen_ws, { A = 3, B = 1 }, "3 goes on A, not over window 1 on B")
    -- Clicking the window the swap carried to B means B, though its focus
    -- didn't change.
    wm:clicked()
    t.eq(wm:current_screen(), "B")
    wm:keep_keys_on("A")
    -- Once focus moves, the usual rule is back: here, the pointer's display.
    a.pointer_uuid = "B"
    a.focus_ = nil
    t.eq(wm:current_screen(), "B")
end)

t.test("after swapping in an empty workspace, layout keys act on it", function()
    local a = fake.new()
    two_displays(a)
    a.add(1, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    a.focus_ = 1
    wm:act("show", 2)
    t.eq(wm:current_ws(), 2, "not window 1's workspace, now on B")
end)

t.test("a Send that empties this display keeps the keys here", function()
    local a = fake.new()
    two_displays(a)
    a.add(1, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    t.eq(wm.screen_ws, { A = 1, B = 2 })
    a.focus_ = 1
    wm:act("send", 2) -- window 1 goes to B, still focused
    t.eq(wm:current_screen(), "A")
    wm:act("show", 3)
    t.eq(wm.screen_ws, { A = 3, B = 2 })
end)

t.test("a window you minimize stays minimized when its workspace comes back", function()
    local a, wm = setup(2)
    a.wins[2].minimized = true
    wm:minimized(2)
    t.eq(wm.windows[2].mine, true)
    wm:act("show", 2)
    wm:act("show", 1)
    t.eq(a.wins[2].minimized, true)
    t.eq(a.wins[1].minimized, false)
end)

t.test("timo's own minimizes aren't read as yours", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("show", 2)
    wm:minimized(1)
    t.eq(wm.windows[1].mine or false, false)
end)

t.test("restoring a hidden window from the Dock brings its workspace along", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("send", 5)
    a.tick() -- timo's expectation lapses
    a.wins[1].minimized = false
    wm:unminimized(1)
    t.eq(wm.screen_ws.A, 5)
    t.eq(a.focus_, 1)
end)

t.test("a new window joins the workspace showing", function()
    local a, wm = setup(0)
    wm:act("show", 4)
    a.add(1, {})
    wm:schedule()
    a.tick()
    t.eq(wm.windows[1].ws, 4)
end)

t.test("a display going away hides its workspace, and Super+N brings it back", function()
    local a = fake.new()
    two_displays(a)
    a.add(1, {})
    a.add(2, { frame = { x = 2000, y = 100, w = 800, h = 600 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    a.screens_[2] = nil
    wm:schedule()
    a.tick()
    t.eq(a.wins[2].minimized, true)
    a.focus_ = 1
    wm:act("show", 2)
    t.eq(a.wins[2].minimized, false)
    t.eq(a.wins[2].frame.x, 0)
end)

t.test("a restart puts windows back on their workspaces", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", 3)
    local snap = a.saved
    -- timo restarts: window 2 is still minimized, on workspace 3.
    local wm2 = wm_mod.new(a, { saved = snap })
    wm2:sync()
    wm2:reconcile()
    t.eq(wm2.windows[2].ws, 3)
    t.eq(wm2.windows[2].mine, false)
    t.eq(a.wins[2].minimized, true)
    wm2:act("show", 3)
    t.eq(a.wins[2].minimized, false)
end)

t.test("saved window ids that come back as strings still match", function()
    local a = fake.new()
    a.add(7, { minimized = true })
    local wm = wm_mod.new(a, { saved = { windows = { ["7"] = { ws = 2, mine = false } }, screens = { A = 1 } } })
    wm:sync()
    t.eq(wm.windows[7].ws, 2)
end)

t.test("quitting restores every hidden window except yours", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", 3)
    a.wins[1].minimized = true
    wm:minimized(1)
    wm:restore_all()
    t.eq(a.wins[2].minimized, false)
    t.eq(a.wins[1].minimized, true)
end)

t.test("a window minimized before timo started counts as yours", function()
    local a = fake.new()
    a.add(1, { minimized = true })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    t.eq(wm.windows[1].mine, true)
    t.eq(a.wins[1].minimized, true)
end)

t.test("carrying a window to the workspace on the other display shows it here", function()
    local a = fake.new()
    two_displays(a)
    a.add(1, {})
    a.add(2, { frame = { x = 2000, y = 100, w = 800, h = 600 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    a.focus_ = 1
    wm:act("carry", 1)
    t.eq(wm.screen_ws, { A = 2, B = 1 })
    t.eq(wm.windows[1].ws, 2)
    t.eq(a.wins[1].frame.x < 1920, true, "it stays on display A")
end)

t.test("a float goes with its workspace to the other display", function()
    local a = fake.new()
    two_displays(a)
    a.add(1, {})
    a.add(3, { subrole = "AXDialog", frame = { x = 100, y = 100, w = 300, h = 200 } })
    a.add(2, { frame = { x = 2000, y = 100, w = 800, h = 600 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    local before = a.wins[3].frame
    a.focus_ = 2
    wm:act("show", 1) -- display B now shows workspace 1
    t.eq(wm.screen_ws.B, 1)
    t.eq(a.wins[3].frame.x, before.x + 1920)
    t.eq(a.wins[3].frame.y, before.y)
end)

t.test("a restore that finishes late still gets a tile", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", 2)
    -- macOS takes its time: the window still reads as minimized when
    -- show() lays out, and comes back after.
    local unmin = a.unminimize
    a.unminimize = function(id)
        a.calls[#a.calls + 1] = "unminimize " .. id
    end
    wm:act("show", 2)
    a.unminimize = unmin
    a.wins[2].minimized = false
    wm:unminimized(2)
    a.tick()
    t.eq(a.wins[2].frame, { x = 0, y = 25, w = 1920, h = 1055 })
end)

t.test("a float you drag to the other display stays there", function()
    local a = fake.new()
    two_displays(a)
    a.add(1, {})
    a.add(3, { subrole = "AXDialog", frame = { x = 100, y = 100, w = 300, h = 200 } })
    a.add(2, { frame = { x = 2000, y = 100, w = 800, h = 600 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    a.wins[3].frame = { x = 2100, y = 200, w = 300, h = 200 }
    wm:moved(3)
    t.eq(wm.windows[3].ws, 2)
    wm:retile()
    t.eq(a.wins[3].frame.x, 2100)
end)

t.test("a tile you drag to the other display stays there after a restart, and gets focus back", function()
    local a = fake.new()
    two_displays(a)
    a.add(1, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    a.focus_ = 1
    wm:focused(1)
    wm:request(1, { x = 2000, y = 100, w = 800, h = 600 })
    t.eq(wm.windows[1].ws, 2)
    local wm2 = wm_mod.new(a, { saved = a.saved })
    wm2:sync()
    t.eq(wm2.windows[1].ws, 2)
    -- Away and back on that display: the dragged window gets focus.
    wm:show(3, "B")
    a.tick()
    a.calls = {}
    wm:show(2, "B")
    a.tick()
    local focused = false
    for _, c in ipairs(a.calls) do
        focused = focused or c == "focus 1"
    end
    t.eq(focused, true)
end)

t.test("a minimize that finishes after its workspace came back is undone", function()
    local a, wm = setup(1)
    a.focus_ = 1
    local min = a.minimize
    a.minimize = function(id)
        a.calls[#a.calls + 1] = "minimize " .. id
    end
    wm:act("show", 2) -- asks for the minimize, which hasn't landed
    wm:act("show", 1) -- back before it does
    a.minimize = min
    a.wins[1].minimized = true
    wm:minimized(1)
    a.tick()
    t.eq(a.wins[1].minimized, false)
end)

t.test("a minimize report that lands after the switch back is still timo's", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("show", 2) -- minimize asked; the window reads minimized, no report yet
    t.eq(a.wins[1].minimized, true)
    wm:act("show", 1) -- restore asked before that report
    wm:minimized(1) -- the late minimize report
    t.eq(wm.windows[1].mine or false, false)
    wm:unminimized(1)
    wm:act("show", 2)
    wm:act("show", 1)
    t.eq(a.wins[1].minimized, false, "still comes back with its workspace")
end)

t.test("two minimizes still waiting on their reports are both timo's", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("show", 2) -- minimize #1; the window reads minimized, no report yet
    wm:act("show", 1) -- restore #1, no report yet
    wm:act("show", 2) -- minimize #2, no report yet
    wm:minimized(1)
    wm:unminimized(1)
    wm:minimized(1)
    t.eq(wm.windows[1].mine or false, false)
    wm:act("show", 1)
    t.eq(a.wins[1].minimized, false, "still comes back with its workspace")
end)

t.test("a minimize whose report never comes doesn't hold back a later one", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("show", 2) -- minimize #1; its report is lost
    local lapse = a.timers -- minimize #1's timeout, not yet run out
    a.timers = {}
    wm:act("show", 1) -- restore, reported
    wm:unminimized(1)
    a.tick()
    wm:act("show", 2) -- held back: minimize #1 still looks in flight
    a.tick()
    t.eq(a.wins[1].minimized, false)
    for _, timer in ipairs(lapse) do
        timer.fn() -- minimize #1's wait runs out
    end
    a.tick()
    t.eq(a.wins[1].minimized, true, "hidden with its workspace")
end)

t.test("an older minimize's timeout doesn't clear a newer one's expectation", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("show", 2) -- minimize #1 asked, and lands
    wm:minimized(1)
    local first = a.timers -- minimize #1's timeout, not yet run out
    a.timers = {}
    wm:act("show", 1) -- restore asked, and lands
    wm:unminimized(1)
    local min = a.minimize
    a.minimize = function(id) -- minimize #2 asked; it lands later
        a.calls[#a.calls + 1] = "minimize " .. id
    end
    wm:act("show", 2)
    a.minimize = min
    for _, timer in ipairs(first) do
        if not timer.stopped then
            timer.fn() -- #1's timeout runs out
        end
    end
    a.wins[1].minimized = true
    wm:minimized(1) -- minimize #2 lands
    t.eq(wm.windows[1].mine or false, false)
end)

t.test("a workspace's last window gets focus once its slow restore lands", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:focused(2)
    wm:act("send", 3)
    local unmin = a.unminimize
    a.unminimize = function(id)
        a.calls[#a.calls + 1] = "unminimize " .. id
    end
    a.calls = {}
    wm:act("show", 3)
    local function focused_2()
        for _, c in ipairs(a.calls) do
            if c == "focus 2" then
                return true
            end
        end
        return false
    end
    t.eq(focused_2(), false, "not while still minimized")
    a.unminimize = unmin
    a.wins[2].minimized = false
    wm:unminimized(2)
    t.eq(focused_2(), true, "once restored")
end)

local function slow_show(a, wm)
    a.focus_ = 2
    wm:focused(2)
    wm:act("send", 3)
    a.unminimize = function(id)
        a.calls[#a.calls + 1] = "unminimize " .. id
    end
    a.calls = {}
    wm:act("show", 3)
    t.eq(wm.focus_after, 2)
    a.calls = {}
end

t.test("a click while a restore is on its way cancels its focus", function()
    local a, wm = setup(2)
    slow_show(a, wm)
    wm:clicked()
    a.wins[2].minimized = false
    wm:unminimized(2)
    t.eq(a.calls, {})
end)

t.test("focusing another window while a restore is on its way cancels its focus", function()
    local a, wm = setup(3)
    slow_show(a, wm)
    wm:focus_window(3)
    a.wins[2].minimized = false
    a.calls = {}
    wm:unminimized(2)
    t.eq(a.calls, {})
end)

t.test("a later switch cancels the wait for a slow restore", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:focused(2)
    wm:act("send", 3)
    local unmin = a.unminimize
    a.unminimize = function() end
    wm:act("show", 3)
    a.unminimize = unmin
    a.focus_ = 1
    wm:act("show", 1)
    a.calls = {}
    a.wins[2].minimized = false
    wm:unminimized(2)
    for _, c in ipairs(a.calls) do
        t.eq(c ~= "focus 2", true, c)
    end
end)

t.test("after a restart, showing a workspace focuses one of its windows", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", 3)
    local snap = a.saved
    local wm2 = wm_mod.new(a, { saved = snap })
    wm2:sync()
    wm2:reconcile()
    a.calls = {}
    wm2:act("show", 3)
    local focused = false
    for _, c in ipairs(a.calls) do
        if c == "focus 2" then
            focused = true
        end
    end
    t.eq(focused, true)
end)

t.test("showing a workspace passes over a window whose app you hid", function()
    local a, wm = setup(3)
    a.focus_ = 1
    wm:act("send", 3)
    a.focus_ = 2
    wm:act("send", 3)
    wm:act("show", 3)
    a.tick()
    wm:focused(1)
    wm:focused(2)
    a.wins[2].hidden = true -- Cmd+H on 2's app
    wm:act("show", 1)
    a.tick()
    a.calls = {}
    wm:act("show", 3)
    a.tick()
    local focused
    for _, c in ipairs(a.calls) do
        focused = c:match("^focus (%d+)") or focused
    end
    t.eq(focused, "1")
end)

t.test("a window you send joins the end of the stack, even when new windows go to master", function()
    local cfg = {}
    for k, v in pairs(require("timo.layout").defaults) do
        cfg[k] = v
    end
    cfg.new_window = "master"
    local a = fake.new()
    for i = 1, 3 do
        a.add(i, {})
    end
    local wm = wm_mod.new(a, { layout = cfg })
    wm:sync()
    wm:reconcile()
    wm:retile()
    a.focus_ = 1
    wm:act("send", 4)
    a.focus_ = 2
    wm:act("send", 4)
    local order = wm.workspaces[4].order
    t.eq(order[#order], 2)
end)

t.test("an app key brings its workspace along", function()
    local a, wm = setup(2)
    a.wins[2].app = "net.kovidgoyal.kitty"
    wm.windows[2].app = "net.kovidgoyal.kitty"
    a.focus_ = 2
    wm:act("send", 4)
    wm:act("app", { bundle = "net.kovidgoyal.kitty" })
    t.eq(wm.screen_ws.A, 4)
    t.eq(a.focus_, 2)
end)

t.test("Cmd+Return launches on the first empty workspace", function()
    local a, wm = setup(2)
    wm.actions.app(wm, { run = "browser2" }, true)
    t.eq(wm.screen_ws.A, 2)
    t.eq(a.launched[1].run, "browser2")
end)

t.done("workspaces")
