local t = require("t")
local fake = require("fake")
local wm_mod = require("tilemo.wm")

-- `config` is start()'s; `saved` the last run's state.
local function setup(n, saved, config)
    local a = fake.new()
    for i = 1, n or 0 do
        a.add(i, {})
    end
    config = config or {}
    config.saved = saved
    local wm = wm_mod.new(a, config)
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
    wm:show("3", nil, true)
    t.eq(wm.screen_ws.A, "3")
    t.eq(a.wins[1].minimized, true)
    t.eq(a.wins[2].minimized, true)
    wm:act("show", "in")
    t.eq(a.wins[1].minimized, false)
    t.eq(a.wins[2].minimized, false)
end)

t.test("restores come before minimizes, so the screen never goes empty", function()
    local a, wm = setup(1)
    -- One of "in"'s apps, so it may go back there.
    wm.windows[1].name = "Mail"
    a.focus_ = 1
    wm:act("send", "2")
    a.calls = {}
    wm:show("2", nil, true)
    t.eq(a.calls[1], "unminimize 1")
    wm:act("send", "in")
    a.add(5, {})
    wm:sync()
    a.calls = {}
    a.focus_ = 5
    wm:act("show", "in")
    t.eq(a.calls[1], "unminimize 1")
    t.eq(a.calls[2], "minimize 5")
end)

t.test("Super+Shift+N sends the window away, and focus stays on this workspace", function()
    local a, wm = setup(2)
    wm:focused(1)
    wm:focused(2)
    a.focus_ = 2
    wm:act("send", "4")
    t.eq(wm.windows[2].ws, "4")
    t.eq(a.wins[2].minimized, true)
    t.eq(wm.workspaces["in"].order, { 1 })
    t.eq(a.focus_, 1)
    t.eq(a.wins[1].frame.w, 1920)
end)

t.test("showing a workspace focuses its last used window", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:focused(2)
    wm:act("send", "3")
    wm:show("3", nil, true)
    t.eq(a.focus_, 2)
end)

t.test("Super+Left and Right step through workspaces in bar order, stopping at the first and last", function()
    local a, wm = setup(2, nil, { workspaces = { "in" } })
    a.focus_ = 2
    wm:act("send", "web")
    a.focus_ = 1
    wm:act("send", "docs")
    t.eq(wm.names, { "in", "web", "docs" })
    wm:act("step", -1)
    t.eq(wm.screen_ws.A, "in")
    wm:act("step", 1)
    t.eq(wm.screen_ws.A, "web")
    wm:act("step", 1)
    t.eq(wm.screen_ws.A, "docs")
    wm:act("step", 1)
    t.eq(wm.screen_ws.A, "docs")
end)

t.test("Super+1…9 show the Nth workspace in bar order, Super+1 home, and past the last nothing", function()
    local a, wm = setup(2, nil, { workspaces = { "in", "re" } })
    a.focus_ = 2
    wm:act("send", "web")
    t.eq(wm:listed(), { "in", "re", "web" })
    wm:act("nth", 3)
    t.eq(wm.screen_ws.A, "web")
    wm:act("nth", 2)
    t.eq(wm.screen_ws.A, "re", "a standing workspace, made by going there")
    wm:act("nth", 1)
    t.eq(wm.screen_ws.A, "in", "Super+1 is home")
    wm:act("nth", 4)
    t.eq(wm.screen_ws.A, "in", "nothing past the last")
end)

t.test("Super+Shift+1…9 send the window to the Nth workspace, and focus stays here", function()
    local a, wm = setup(2, nil, { workspaces = { "in", "re" } })
    wm:focused(1)
    wm:focused(2)
    a.focus_ = 2
    wm:act("send_nth", 2)
    t.eq(wm.windows[2].ws, "re")
    t.eq(wm.screen_ws.A, "in")
    t.eq(a.focus_, 1)
    a.focus_ = 1
    wm:act("send_nth", 3)
    t.eq(wm.windows[1].ws, "in", "nothing past the last")
end)

t.test("Super+Shift+Right carries the window to the next workspace and follows it", function()
    local a, wm = setup(2, nil, { workspaces = { "in" } })
    a.focus_ = 2
    wm:act("carry", 1)
    t.eq(wm.screen_ws.A, "in", "no workspace after the last")
    wm:ensure_ws("2")
    wm:act("carry", 1)
    t.eq(wm.screen_ws.A, "2")
    t.eq(wm.windows[2].ws, "2")
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
    t.eq(wm.screen_ws, { A = "in", B = "2" })
    a.focus_ = 1
    wm:show("2", nil, true)
    t.eq(wm.screen_ws, { A = "2", B = "in" })
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
    t.eq(wm.screen_ws, { A = "in", B = "2" })
    a.focus_ = 1
    wm:show("2", nil, true) -- empty: window 1 goes to B and keeps focus
    t.eq(wm.screen_ws, { A = "2", B = "in" })
    t.eq(a.wins[1].frame.x >= 1920, true)
    wm:show("3", nil, true)
    t.eq(wm.screen_ws, { A = "3", B = "in" }, "3 goes on A, not over window 1 on B")
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
    wm:show("2", nil, true)
    t.eq(wm:current_ws(), 2, "not window 1's workspace, now on B")
end)

t.test("a Send that empties this display keeps the keys here", function()
    local a = fake.new()
    two_displays(a)
    a.add(1, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    t.eq(wm.screen_ws, { A = "in", B = "2" })
    a.focus_ = 1
    wm:act("send", "2") -- window 1 goes to B, still focused
    t.eq(wm:current_screen(), "A")
    wm:show("3", nil, true)
    t.eq(wm.screen_ws, { A = "3", B = "2" })
end)

t.test("a switch says which display it showed the workspace on", function()
    local a = fake.new()
    two_displays(a)
    a.add(1, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    local shown
    wm.on_show = function(n, uuid)
        shown = { n, uuid }
    end
    a.focus_ = 1
    wm:show("2", nil, true) -- window 1, still focused, goes to B
    t.eq(shown, { 2, "A" })
end)

t.test("a window you minimize stays minimized when its workspace comes back", function()
    local a, wm = setup(2)
    a.wins[2].minimized = true
    wm:minimized(2)
    t.eq(wm.windows[2].mine, true)
    wm:show("2", nil, true)
    wm:act("show", "in")
    t.eq(a.wins[2].minimized, true)
    t.eq(a.wins[1].minimized, false)
end)

t.test("tilemo's own minimizes aren't read as yours", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:show("2", nil, true)
    wm:minimized(1)
    t.eq(wm.windows[1].mine or false, false)
end)

t.test("restoring a hidden window from the Dock brings its workspace along", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("send", "5")
    a.tick() -- tilemo's expectation lapses
    a.wins[1].minimized = false
    wm:unminimized(1)
    t.eq(wm.screen_ws.A, "5")
    t.eq(a.focus_, 1)
end)

t.test("a new window joins the workspace showing", function()
    local a, wm = setup(0)
    wm:show("4", nil, true)
    a.add(1, {})
    wm:schedule()
    a.tick()
    t.eq(wm.windows[1].ws, "4")
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
    wm:show("2", nil, true)
    t.eq(a.wins[2].minimized, false)
    t.eq(a.wins[2].frame.x, 0)
end)

t.test("a restart puts windows back on their workspaces", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", "3")
    local snap = a.saved
    -- tilemo restarts: window 2 is still minimized, on workspace 3.
    local wm2 = wm_mod.new(a, { saved = snap })
    wm2:sync()
    wm2:reconcile()
    t.eq(wm2.windows[2].ws, "3")
    t.eq(wm2.windows[2].mine, false)
    t.eq(a.wins[2].minimized, true)
    wm2:act("show", "3")
    t.eq(a.wins[2].minimized, false)
end)

t.test("saved window ids that come back as strings still match", function()
    local a = fake.new()
    a.add(7, { minimized = true })
    local wm = wm_mod.new(a, { saved = { windows = { ["7"] = { ws = "2", mine = false } }, screens = { A = "in" } } })
    wm:sync()
    t.eq(wm.windows[7].ws, "2")
end)

t.test("quitting restores every hidden window except yours", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", "3")
    a.wins[1].minimized = true
    wm:minimized(1)
    wm:restore_all()
    t.eq(a.wins[2].minimized, false)
    t.eq(a.wins[1].minimized, true)
end)

t.test("a window minimized before tilemo started counts as yours", function()
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
    local wm = wm_mod.new(a, { workspaces = { "in" } })
    wm:sync()
    wm:reconcile()
    a.focus_ = 1
    wm:act("carry", 1)
    t.eq(wm.screen_ws, { A = "2", B = "in" })
    t.eq(wm.windows[1].ws, "2")
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
    wm:act("show", "in") -- display B now shows workspace 1
    t.eq(wm.screen_ws.B, "in")
    t.eq(a.wins[3].frame.x, before.x + 1920)
    t.eq(a.wins[3].frame.y, before.y)
end)

t.test("a restore that finishes late still gets a tile", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", "2")
    -- macOS takes its time: the window still reads as minimized when
    -- show() lays out, and comes back after.
    local unmin = a.unminimize
    a.unminimize = function(id)
        a.calls[#a.calls + 1] = "unminimize " .. id
    end
    wm:show("2", nil, true)
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
    t.eq(wm.windows[3].ws, "2")
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
    t.eq(wm.windows[1].ws, "2")
    local wm2 = wm_mod.new(a, { saved = a.saved })
    wm2:sync()
    t.eq(wm2.windows[1].ws, "2")
    -- Away and back on that display: the dragged window gets focus.
    wm:show("3", "B", true)
    a.tick()
    a.calls = {}
    wm:show("2", "B")
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
    wm:show("2", nil, true) -- asks for the minimize, which hasn't landed
    wm:act("show", "in") -- back before it does
    a.minimize = min
    a.wins[1].minimized = true
    wm:minimized(1)
    a.tick()
    t.eq(a.wins[1].minimized, false)
end)

t.test("a minimize report that lands after the switch back is still tilemo's", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:show("2", nil, true) -- minimize asked; the window reads minimized, no report yet
    t.eq(a.wins[1].minimized, true)
    wm:act("show", "in") -- restore asked before that report
    wm:minimized(1) -- the late minimize report
    t.eq(wm.windows[1].mine or false, false)
    wm:unminimized(1)
    wm:show("2", nil, true)
    wm:act("show", "in")
    t.eq(a.wins[1].minimized, false, "still comes back with its workspace")
end)

t.test("two minimizes still waiting on their reports are both tilemo's", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:show("2", nil, true) -- minimize #1; the window reads minimized, no report yet
    wm:act("show", "in") -- restore #1, no report yet
    wm:show("2", nil, true) -- minimize #2, no report yet
    wm:minimized(1)
    wm:unminimized(1)
    wm:minimized(1)
    t.eq(wm.windows[1].mine or false, false)
    wm:act("show", "in")
    t.eq(a.wins[1].minimized, false, "still comes back with its workspace")
end)

t.test("a minimize whose report never comes doesn't hold back a later one", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:show("2", nil, true) -- minimize #1; its report is lost
    local lapse = a.timers -- minimize #1's timeout, not yet run out
    a.timers = {}
    wm:act("show", "in") -- restore, reported
    wm:unminimized(1)
    a.tick()
    wm:show("2", nil, true) -- held back: minimize #1 still looks in flight
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
    wm:show("2", nil, true) -- minimize #1 asked, and lands
    wm:minimized(1)
    local first = a.timers -- minimize #1's timeout, not yet run out
    a.timers = {}
    wm:act("show", "in") -- restore asked, and lands
    wm:unminimized(1)
    local min = a.minimize
    a.minimize = function(id) -- minimize #2 asked; it lands later
        a.calls[#a.calls + 1] = "minimize " .. id
    end
    wm:show("2", nil, true)
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
    wm:act("send", "3")
    local unmin = a.unminimize
    a.unminimize = function(id)
        a.calls[#a.calls + 1] = "unminimize " .. id
    end
    a.calls = {}
    wm:show("3", nil, true)
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
    wm:act("send", "3")
    a.unminimize = function(id)
        a.calls[#a.calls + 1] = "unminimize " .. id
    end
    a.calls = {}
    wm:show("3", nil, true)
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
    wm:act("send", "3")
    local unmin = a.unminimize
    a.unminimize = function() end
    wm:show("3", nil, true)
    a.unminimize = unmin
    a.focus_ = 1
    wm:act("show", "in")
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
    wm:act("send", "3")
    local snap = a.saved
    local wm2 = wm_mod.new(a, { saved = snap })
    wm2:sync()
    wm2:reconcile()
    a.calls = {}
    wm2:act("show", "3")
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
    wm:act("send", "3")
    a.focus_ = 2
    wm:act("send", "3")
    wm:show("3", nil, true)
    a.tick()
    wm:focused(1)
    wm:focused(2)
    a.wins[2].hidden = true -- Cmd+H on 2's app
    wm:act("show", "in")
    a.tick()
    a.calls = {}
    wm:show("3", nil, true)
    a.tick()
    local focused
    for _, c in ipairs(a.calls) do
        focused = c:match("^focus (%d+)") or focused
    end
    t.eq(focused, "1")
end)

t.test("a window you send joins the end of the stack, even when new windows go to master", function()
    local cfg = {}
    for k, v in pairs(require("tilemo.layout").defaults) do
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
    wm:act("send", "4")
    a.focus_ = 2
    wm:act("send", "4")
    local order = wm.workspaces["4"].order
    t.eq(order[#order], 2)
end)

t.test("an app key brings its workspace along", function()
    local a, wm = setup(2)
    a.wins[2].app = "net.kovidgoyal.kitty"
    wm.windows[2].app = "net.kovidgoyal.kitty"
    a.focus_ = 2
    wm:act("send", "4")
    wm:act("app", { bundle = "net.kovidgoyal.kitty" })
    t.eq(wm.screen_ws.A, "4")
    t.eq(a.focus_, 2)
end)

t.test("Cmd+Return launches a new window here, with no empty workspace to use", function()
    local a, wm = setup(2)
    wm.actions.app(wm, { run = "browser2" }, true)
    t.eq(wm.screen_ws.A, "in")
    t.eq(a.launched[1].run, "browser2")
    t.eq(a.fresh[1], true)
end)

t.test("choosing a window from the Attention tab goes there, with its workspace", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", "3")
    wm.attention:title(2, "com.example.app", "Chat (1)")
    a.focus_ = 1
    wm:activate(wm:attention_windows()[1])
    t.eq(wm.screen_ws.A, "3")
    t.eq(a.focus_, 2)
end)

t.test("a badged app that quit isn't listed as wanting attention", function()
    local _, wm = setup(2)
    wm.attention:badge("com.example.gone", "3")
    t.eq(wm:attention_windows(), {})
end)

t.test("the windows wanting attention, as the launcher lists them, come newest first and once each", function()
    local a, wm = setup(3)
    a.wins[2].app = "com.example.chat"
    wm.windows[2].app = "com.example.chat"
    wm.attention:title(3, "x", "Mail (1)")
    wm.attention:title(2, "com.example.chat", "Chat (1)")
    wm.attention:badge("com.example.chat", "1")
    wm.attention:badge("com.example.gone", "2")
    t.eq(wm:attention_windows(), { 2, 3 })
end)

t.test("a count rising in the window you're in doesn't want attention", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:focused(2)
    a.wins[2].title = "Chat (1)"
    wm:poll_attention()
    t.eq(#wm.attention:list(), 0)
    a.wins[1].title = "Mail (2)"
    wm:poll_attention()
    t.eq(#wm.attention:list(), 1)
end)

t.test("a badged app's mark goes to its last used window, whichever workspace it's on", function()
    local a, wm = setup(3)
    for _, id in ipairs({ 1, 2 }) do
        a.wins[id].app = "com.example.chat"
        wm.windows[id].app = "com.example.chat"
    end
    a.focus_ = 2
    wm:act("send", "4")
    wm:show("4", nil, true)
    a.tick()
    a.focus_ = 2
    wm:focused(2)
    wm:act("show", "in")
    a.tick()
    a.focus_ = 3
    wm:focused(3)
    wm.attention:badge("com.example.chat", "1")
    wm:activate(wm:attention_windows()[1])
    t.eq(a.focus_, 2)
    t.eq(wm.screen_ws.A, "4")
end)

t.test("the menu bar state marks here, occupied and wanting attention", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", "3")
    wm.attention:title(2, "x", "c (1)")
    local st = wm:bar_state()
    t.eq(#st, 5, '"in", the standing ones, then 3')
    t.eq(st[1].name, "in")
    t.eq(st[1].here, true)
    t.eq(st[2].name, "re")
    t.eq(st[2].occupied or false, false, "a standing one not made yet")
    t.eq(st[5].name, "3")
    t.eq(st[5].occupied, true)
    t.eq(st[5].urgent, true)
    a.focus_ = 1
    wm:act("send", "4")
    st = wm:bar_state()
    t.eq(st[1].occupied or false, false, '"in" stays, empty')
end)

-- Named workspaces (SPEC.md §6.1, §6.2, §6.5) -------------------------------

t.test('"in" is made at start, first, and stays when it\'s empty and left', function()
    local a, wm = setup(1)
    t.eq(wm.names, { "in" })
    t.eq(wm.screen_ws.A, "in")
    a.focus_ = 1
    wm:act("send", "web")
    wm:act("show", "web")
    t.eq(wm.names, { "in", "web" })
    t.eq(wm.workspaces["in"] ~= nil, true)
end)

t.test("an empty workspace goes once you leave it, unless you minimized what's on it", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", "web")
    a.focus_ = 1
    wm:act("send", "docs")
    t.eq(wm.names, { "in", "web", "docs" }, "in the order they were made")
    wm:act("show", "web")
    a.focus_ = 2
    wm:act("send", "in")
    t.eq(wm.names, { "in", "web", "docs" }, "refused: 2 isn't one of \"in\"'s apps")
    wm.windows[2].name = "Mail"
    wm:act("send", "in")
    t.eq(wm.names, { "in", "web", "docs" }, "still showing, so not left yet")
    wm:act("show", "docs")
    t.eq(wm.names, { "in", "docs" }, "web went once left empty")
    -- A workspace whose only window you minimized isn't empty.
    a.wins[1].minimized = true
    wm:minimized(1)
    wm:act("home")
    t.eq(wm.names, { "in", "docs" })
end)

t.test("a workspace closed down to nothing while hidden goes too", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", "web")
    a.drop(2)
    wm:schedule()
    a.tick()
    t.eq(wm.names, { "in" })
end)

t.test('Super+Home shows "in"', function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("send", "web")
    wm:act("show", "web")
    t.eq(wm.screen_ws.A, "web")
    wm:act("home")
    t.eq(wm.screen_ws.A, "in")
end)

t.test("names are compared ignoring case, and keep the case they were made with", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", "Web")
    a.focus_ = 1
    wm:act("send", "  WEB ")
    t.eq(wm.windows[1].ws, "Web")
    t.eq(wm.names, { "in", "Web" })
    t.eq(wm:find("web"), "Web")
    t.eq(wm:act("send", "   "), nil, "a blank name moves nothing")
    t.eq(wm.windows[1].ws, "Web")
end)

t.test('sending another app\'s window to "in" is refused, with a notice', function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("send", "web")
    wm:act("show", "web")
    wm:act("send", "IN")
    t.eq(wm.windows[1].ws, "web")
    t.eq(#a.notes, 1)
end)

t.test('"in"\'s apps always open on "in", by app name, wherever you are', function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("send", "web")
    wm:act("show", "web")
    a.add(2, { name = "Gmail", app = "com.google.Chrome.app.gmail" })
    a.add(3, { name = "Notes" })
    wm:sync()
    t.eq(wm.windows[2].ws, "in")
    t.eq(wm.windows[3].ws, "web")
    t.eq(a.wins[2].minimized, nil, "not reconciled yet")
    wm:reconcile()
    t.eq(a.wins[2].minimized, true, "hidden, since \"in\" isn't showing")
end)

-- Bitwarden's pop-out from a Chrome window you moved off "in", with Chrome
-- one of "in"'s apps: untitled, it opens on "in" like any Chrome window.
t.test("a popup that floats once named joins its parent's workspace, as one named at once does", function()
    local a = fake.new()
    a.add(1, { name = "Google Chrome", app = "com.google.Chrome", pid = 200, title = "Amazon" })
    local wm = wm_mod.new(a, { home_apps = { "Google Chrome" } })
    wm:sync()
    wm:reconcile()
    wm:retile()
    a.focus_ = 1
    wm:act("send", "web")
    wm:act("show", "web")
    a.add(2, { name = "Google Chrome", app = "com.google.Chrome", pid = 200, title = "" })
    wm:sync()
    wm:reconcile()
    t.eq(wm.windows[2].ws, "in", "a tile, at first")
    a.clock = a.clock + 1
    a.wins[2].title = "Bitwarden"
    wm:retitled(2)
    t.eq(wm.windows[2].ws, "web")
    t.eq(a.wins[2].minimized, false, "showing, over its parent")
end)

t.test('"in"\'s apps are a setting, checked at start', function()
    local a = fake.new()
    a.add(1, { name = "Slack" })
    local wm = wm_mod.new(a, { home_apps = { "Slack" } })
    wm:sync()
    t.eq(wm.windows[1].ws, "in")
    local function err(list)
        local ok, e = pcall(wm_mod.new, fake.new(), { home_apps = list })
        return not ok and tostring(e) or nil
    end
    t.eq(err("Mail"):find("home_apps must be a list", 1, true) ~= nil, true)
    t.eq(err({ "Mail", 3 }):find("home_apps[2]", 1, true) ~= nil, true)
    t.eq(err({ "Mail", "" }):find("home_apps[2]", 1, true) ~= nil, true)
    t.eq(err({ app = "Mail" }):find("home_apps must be a list", 1, true) ~= nil, true)
    t.eq(err({}), nil, "an empty list is fine")
end)

t.test("a second display shows a workspace of its own, named by its number", function()
    local a = fake.new()
    two_displays(a)
    local wm = wm_mod.new(a, {})
    wm:sync()
    t.eq(wm.screen_ws, { A = "in", B = "2" })
    t.eq(wm.names, { "in", "2" })
end)

t.test("names, their order and each display's are saved by name", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", "web")
    a.focus_ = 1
    wm:act("send", "docs")
    wm:act("show", "docs")
    t.eq(a.saved.names, { "in", "web", "docs" })
    t.eq(a.saved.screens, { A = "docs" })
    t.eq(a.saved.windows[2].ws, "web")
    local wm2 = wm_mod.new(a, { saved = a.saved })
    wm2:sync()
    wm2:reconcile()
    t.eq(wm2.names, { "in", "web", "docs" })
    t.eq(wm2.screen_ws.A, "docs")
    t.eq(wm2.windows[2].ws, "web")
end)

t.test("a numbered state from before names is read once into \"1\" to \"9\" after \"in\"", function()
    local a = fake.new()
    a.add(1, { name = "Notes" })
    a.add(2, { name = "Mail" })
    a.add(3, { name = "Notes" })
    a.add(4, { name = "Mail" })
    local saved = {
        windows = {
            ["1"] = { ws = 3, mine = false, app = "com.example.app", pos = 1 },
            ["2"] = { ws = 3, mine = false, app = "com.example.app", pos = 2 },
            ["3"] = { ws = 1.0, mine = false, app = "com.example.app", pos = 1 },
            -- 5's only window is one of "in"'s apps, so 5 goes.
            ["4"] = { ws = 5, mine = false, app = "com.example.app", pos = 1 },
        },
        screens = { A = 5, B = 7 },
    }
    local wm = wm_mod.new(a, { saved = saved })
    t.eq(wm.names, { "in", "1", "3", "5" }, "7 had no windows")
    wm:sync()
    wm:reconcile()
    t.eq(wm.names, { "in", "1", "3" })
    t.eq(wm.windows[1].ws, "3")
    t.eq(wm.windows[2].ws, "in", "one of \"in\"'s apps")
    t.eq(wm.windows[3].ws, "1")
    t.eq(wm.windows[4].ws, "in")
    t.eq(wm.screen_ws.A, "in", "5 was dropped")
    t.eq(a.saved.names, { "in", "1", "3" })
    t.eq(a.saved.windows[1].ws, "3", "saved by name from now on")
    -- Read once: a later start reads names, and moves nothing to "in".
    local wm2 = wm_mod.new(a, { saved = a.saved })
    t.eq(wm2.migrated, false)
end)

t.test("a display showing a number keeps showing that workspace", function()
    local a = fake.new()
    a.add(1, {})
    local wm = wm_mod.new(a, { saved = { windows = { ["1"] = { ws = 4, mine = false, app = "com.example.app" } }, screens = { A = 4 } } })
    wm:sync()
    wm:reconcile()
    t.eq(wm.screen_ws.A, "4")
    t.eq(wm.names, { "in", "4" })
end)

-- Standing workspaces (SPEC.md §6.1) ----------------------------------------

t.test("standing workspaces are listed from the start, made on demand, and never removed", function()
    local a, wm = setup(2)
    t.eq(wm.names, { "in" }, "none made at start")
    t.eq((wm:listed()), { "in", "re", "oc", "me" })
    a.focus_ = 2
    wm:act("send", "web")
    t.eq((wm:listed()), { "in", "re", "oc", "me", "web" }, "the rest follow")
    wm:act("show", "oc")
    t.eq(wm.names, { "in", "oc", "web" }, "showing one makes it, in its place")
    a.focus_ = 1
    wm:act("send", "ME")
    t.eq(wm.names, { "in", "oc", "me", "web" }, "so does sending to one, by any case")
    t.eq(wm.windows[1].ws, "me")
    wm:act("home")
    t.eq(wm.names, { "in", "oc", "me", "web" }, "oc stays though left empty")
    a.focus_ = 2
    wm:act("show", "web")
    a.focus_ = 2
    wm:act("send", "me")
    wm:act("home")
    t.eq(wm.names, { "in", "oc", "me" }, "web goes")
end)

t.test("Next and Previous step through the standing workspaces, made or not", function()
    local _, wm = setup(1)
    wm:act("step", 1)
    t.eq(wm.screen_ws.A, "re")
    t.eq(wm.names, { "in", "re" })
    wm:act("step", 1)
    wm:act("step", 1)
    wm:act("step", 1)
    t.eq(wm.screen_ws.A, "me", "the last")
end)

t.test("the standing workspaces are a setting, checked at start, the first being home", function()
    local a, wm = setup(1, nil, { workspaces = { "work", "home" } })
    t.eq((wm:listed()), { "work", "home" })
    t.eq(wm.home, "work")
    t.eq(wm.names, { "work" }, "home made at start")
    t.eq(wm.screen_ws.A, "work")
    t.eq(wm.windows[1].ws, "work")
    wm:act("show", "home")
    wm:act("home")
    t.eq(wm.screen_ws.A, "work", "Super+Home goes to the first, whatever its name")
    -- "in" is just a name now.
    a.focus_ = 1
    wm:act("send", "in")
    t.eq(wm.windows[1].ws, "in")
    wm:act("home")
    t.eq((wm:listed()), { "work", "home", "in" })
    -- Home's apps open on home, and only they go there.
    a.add(2, { name = "Mail" })
    wm:sync()
    t.eq(wm.windows[2].ws, "work")
    a.focus_ = 1
    wm:act("show", "in")
    a.focus_ = 1
    wm:act("send", "WORK")
    t.eq(wm.windows[1].ws, "in", "refused")
    local function err(list)
        local ok, e = pcall(wm_mod.new, fake.new(), { workspaces = list })
        return not ok and tostring(e) or nil
    end
    t.eq(err({}):find("workspaces must name at least one workspace", 1, true) ~= nil, true)
    t.eq(err({ "work", "Work" }):find("workspaces[2]", 1, true) ~= nil, true)
    t.eq(err({ "work", "  " }):find("workspaces[2] must be a name", 1, true) ~= nil, true)
    t.eq(err("work"):find("workspaces must be a list", 1, true) ~= nil, true)
    t.eq(err({ "work", "in" }), nil, '"in" anywhere is fine')
    -- What a name can't hold is an error at load, naming the setting.
    for _, bad in ipairs({ 'team "x"', "it's", "a`b", "a\\b", "a\27[31mb", "a\127b", "a\0b" }) do
        local e = err({ "work", bad })
        t.eq(e and e:find("workspaces[2]", 1, true) ~= nil, true, bad)
        t.eq(e and e:find("can't have quotes, backslashes or control characters", 1, true) ~= nil, true, bad)
    end
    t.eq(err({ "work", "PR-12 login", "café" }), nil, "anything else is fine")
end)

t.test("a numbered state becomes workspaces after the standing ones", function()
    local a = fake.new()
    a.add(1, {})
    local wm = wm_mod.new(a, { saved = { windows = { ["1"] = { ws = 2, mine = false, app = "com.example.app" } }, screens = { A = 1 } } })
    wm:sync()
    wm:act("show", "oc")
    t.eq((wm:listed()), { "in", "re", "oc", "me", "2" })
    t.eq(wm.names, { "in", "oc", "2" })
end)

t.test("names are compared with Unicode case folding, not byte by byte", function()
    t.eq(wm_mod.fold("Équipe"), "équipe")
    t.eq(wm_mod.fold("ŁÓDŹ"), "łódź")
    t.eq(wm_mod.fold("ΑΘΗΝΑ"), "αθηνα")
    t.eq(wm_mod.fold("МОСКВА Ёж"), "москва ёж")
    t.eq(wm_mod.fold("ÿŸ"), "ÿÿ")
    t.eq(wm_mod.fold("日本"), "日本")
    t.eq(wm_mod.fold("\255bad"), "\255bad", "not UTF-8: byte by byte")
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("send", "Équipe")
    a.focus_ = 1
    wm:act("send", "équipe")
    t.eq(wm.windows[1].ws, "Équipe")
    t.eq(wm:find("ÉQUIPE"), "Équipe")
end)

t.test('a dialog of one of "in"\'s apps stays with its parent on another workspace', function()
    local a, wm = setup(0)
    a.add(1, { name = "Mail", pid = 300 })
    wm:sync()
    a.focus_ = 1
    wm:focused(1)
    wm:act("send", "web")
    wm:act("show", "web")
    a.focus_ = 1
    a.add(2, { name = "Mail", pid = 300, subrole = "AXDialog" })
    a.add(3, { name = "Mail", pid = 300 })
    wm:sync()
    t.eq(wm.windows[2].ws, "web", "the dialog, with its parent")
    t.eq(wm.windows[3].ws, "in", "a new main window still goes to \"in\"")
end)

-- Super+Tab, Super+End and Super+Return (SPEC.md §7.2) ---------------------

-- Three workspaces with a window each besides home: web, docs and mail.
local function three(a, wm)
    for id, n in pairs({ [2] = "web", [3] = "docs" }) do
        a.focus_ = id
        wm:act("send", n)
    end
end

t.test("Super+Tab goes home from anywhere, and from home back to the last workspace", function()
    local a, wm = setup(3)
    three(a, wm)
    wm:act("flip")
    t.eq(wm.screen_ws.A, "in", "nowhere to go back to yet")
    wm:act("show", "web")
    wm:act("show", "docs")
    wm:act("flip")
    t.eq(wm.screen_ws.A, "in")
    wm:act("flip")
    t.eq(wm.screen_ws.A, "docs", "back")
    wm:act("flip")
    t.eq(wm.screen_ws.A, "in", "and again: it toggles")
    wm:act("flip")
    t.eq(wm.screen_ws.A, "docs")
end)

t.test("Super+End goes to the last workspace other than home and this one", function()
    local a, wm = setup(3)
    three(a, wm)
    wm:act("show", "web")
    wm:act("show", "docs")
    wm:act("last")
    t.eq(wm.screen_ws.A, "web", "the task workspace before")
    wm:act("last")
    t.eq(wm.screen_ws.A, "docs", "and back")
    wm:act("home")
    wm:act("last")
    t.eq(wm.screen_ws.A, "docs", "from home, where Super+Tab goes")
    wm:act("home")
    wm:act("flip")
    t.eq(wm.screen_ws.A, "docs")
end)

t.test("Super+End and Super+Tab pass over a workspace that's gone", function()
    local a, wm = setup(3)
    three(a, wm)
    wm:act("show", "web")
    wm:act("show", "docs")
    -- docs' window closes while it's hidden: docs goes.
    wm:act("home")
    a.drop(3)
    wm:schedule()
    a.tick()
    t.eq(wm:find("docs"), nil)
    wm:act("flip")
    t.eq(wm.screen_ws.A, "web")
end)

t.test("Super+Shift+Return asks for a workspace and moves the window there, following it", function()
    local a, wm = setup(2)
    local asked
    wm.ask_move = function(done)
        asked = done
    end
    wm:focused(1)
    wm:focused(2)
    a.focus_ = 2
    wm:act("move_to")
    t.eq(wm.holding_keyboard, true)
    a.calls = {}
    asked("Web")
    t.eq(wm.windows[2].ws, "Web")
    t.eq(wm.screen_ws.A, "Web", "you follow it, as on tide")
    for _, c in ipairs(a.calls) do
        t.eq(c ~= "minimize 2" and c ~= "unminimize 2", true, "the moving window never hides on the way: " .. c)
    end
    t.eq(a.focus_, 2, "still on the window you moved")
    t.eq(a.wins[2].minimized == true, false, "showing")
    t.eq(a.wins[1].minimized, true, "the workspace left is hidden")
    t.eq(wm.holding_keyboard, false)
    -- Esc leaves it, and you stay.
    wm:act("move_to")
    asked(nil)
    t.eq(wm.windows[2].ws, "Web")
    t.eq(wm.screen_ws.A, "Web")
    -- Home takes only its own apps: refused, nothing moves or shows.
    wm:act("move_to")
    asked("IN")
    t.eq(wm.windows[2].ws, "Web")
    t.eq(wm.screen_ws.A, "Web")
    t.eq(#a.notes, 1)
end)

t.test("Super+Shift+Return refuses a name with what a name can't hold, and asks again", function()
    local a, wm = setup(2)
    local asks = {}
    wm.ask_move = function(done)
        asks[#asks + 1] = done
    end
    a.focus_ = 2
    wm:act("move_to")
    asks[1]('it\'s "web"')
    t.eq(wm.windows[2].ws, "in", "left where it was")
    t.eq(a.notes, { "A workspace's name can't have quotes, backslashes or control characters" })
    t.eq(#asks, 2, "asked again")
    t.eq(wm.holding_keyboard, true)
    asks[2]("web")
    t.eq(wm.windows[2].ws, "web")
    t.eq(wm.holding_keyboard, false)
end)

t.test("Super+Shift+Return with no window focused asks nothing, and logs why", function()
    local a, wm = setup(0)
    local asked, logged = 0, {}
    wm.ask_move = function()
        asked = asked + 1
    end
    function a.log(msg)
        logged[#logged + 1] = msg
    end
    a.focus_ = nil
    wm:act("move_to")
    t.eq(asked, 0)
    t.eq(#logged, 1)
    t.eq(logged[1]:find("no window", 1, true) ~= nil, true, logged[1])
end)

t.test("Super+Return goes to a workspace by name, moving no window", function()
    local a, wm = setup(2, nil, { workspaces = { "in" } })
    local asked
    wm.ask_go = function(done)
        asked = done
    end
    a.focus_ = 2
    wm:act("send", "web")
    a.focus_ = 1
    wm:act("go_to")
    t.eq(wm.holding_keyboard, true)
    asked("WEB")
    t.eq(wm.screen_ws.A, "web", "an existing name, ignoring case")
    t.eq(wm.windows[1].ws, "in", "nothing moved")
    t.eq(wm.windows[2].ws, "web")
    t.eq(a.focus_, 2, "its last used window")
    t.eq(wm.holding_keyboard, false)
    -- Home is offered: nothing moves there.
    wm:act("go_to")
    asked("in")
    t.eq(wm.screen_ws.A, "in")
    -- Esc stays where you are.
    wm:act("go_to")
    asked(nil)
    t.eq(wm.screen_ws.A, "in")
    t.eq(wm.holding_keyboard, false)
    t.eq(#a.notes, 0)
end)

t.test("Super+Return works on an empty workspace, and a new name makes an empty one that goes once left", function()
    local a, wm = setup(0, nil, { workspaces = { "in" } })
    local asked
    wm.ask_go = function(done)
        asked = done
    end
    a.focus_ = nil
    wm:act("go_to")
    t.eq(asked ~= nil, true, "asked with no window focused")
    asked("notes")
    t.eq(wm.screen_ws.A, "notes")
    t.eq(wm:find("notes"), "notes", "made")
    wm:act("go_to")
    asked("in")
    t.eq(wm.screen_ws.A, "in")
    t.eq(wm:find("notes"), nil, "empty, and left: gone")
end)

t.test("Super+Return pressed again while its prompt is open asks nothing more", function()
    local a, wm = setup(1)
    local asks = {}
    wm.ask_go = function(done)
        asks[#asks + 1] = done
    end
    wm:act("go_to")
    wm:act("go_to")
    t.eq(#asks, 1)
    asks[1](nil)
    t.eq(#asks, 1, "nothing waiting behind it")
    t.eq(wm.holding_keyboard, false)
    wm:act("go_to")
    t.eq(#asks, 2, "asks again once answered")
end)

t.test("Super+Return refuses a name with what a name can't hold, and asks again", function()
    local a, wm = setup(1)
    local asks = {}
    wm.ask_go = function(done)
        asks[#asks + 1] = done
    end
    wm:act("go_to")
    asks[1]('it\'s "web"')
    t.eq(wm.screen_ws.A, "in")
    t.eq(a.notes, { "A workspace's name can't have quotes, backslashes or control characters" })
    t.eq(#asks, 2, "asked again")
    asks[2]("web")
    t.eq(wm.screen_ws.A, "web")
    t.eq(wm.holding_keyboard, false)
end)

t.done("workspaces")
