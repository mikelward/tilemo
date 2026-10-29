local t = require("t")
local fake = require("fake")
local wm_mod = require("tilemo.wm")
local keys = require("tilemo.keys")

local function setup(n)
    local a = fake.new()
    for i = 1, n or 0 do
        a.add(i, {})
    end
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    return a, wm
end

local function frame(a, id)
    return a.wins[id].frame
end

t.test("windows tile in tide's tile layout on the display's area", function()
    local a = setup(3)
    t.eq(frame(a, 1), { x = 0, y = 25, w = 1056, h = 1055 })
    t.eq(frame(a, 2), { x = 1056, y = 25, w = 864, h = 528 })
    t.eq(frame(a, 3), { x = 1056, y = 553, w = 864, h = 527 })
end)

t.test("a window that's already in place isn't moved again", function()
    local a, wm = setup(2)
    a.calls = {}
    wm:retile()
    t.eq(a.calls, {})
end)

t.test("a new window is found on the next sync and joins the stack", function()
    local a, wm = setup(1)
    a.add(2, {})
    wm:schedule()
    a.tick()
    t.eq(wm.workspaces[1].order, { 1, 2 })
    t.eq(frame(a, 2).x, 1056)
end)

t.test("a burst of events makes one sync", function()
    local a, wm = setup(1)
    wm:schedule()
    wm:schedule()
    wm:schedule()
    local live = 0
    for _, timer in ipairs(a.timers) do
        if not timer.stopped then
            live = live + 1
        end
    end
    t.eq(live, 1)
end)

t.test("a closed window leaves the layout, and the last used window gets focus", function()
    local a, wm = setup(3)
    wm:focused(2)
    wm:focused(3)
    a.focus_ = 3
    a.drop(3)
    wm:schedule()
    a.tick()
    t.eq(wm.workspaces[1].order, { 1, 2 })
    t.eq(a.focus_, 2)
end)

t.test("minimized windows don't take a tile", function()
    local a, wm = setup(3)
    a.wins[2].minimized = true
    wm:retile()
    t.eq(frame(a, 1).w, 1056)
    t.eq(frame(a, 3), { x = 1056, y = 25, w = 864, h = 1055 })
end)

t.test("a dialog floats, centered on its app's focused window, and never tiles", function()
    local a, wm = setup(2)
    a.focus_ = 1
    a.add(3, { subrole = "AXDialog", frame = { x = 0, y = 0, w = 400, h = 200 } })
    wm:sync()
    wm:retile()
    t.eq(wm.windows[3].floating, true)
    t.eq(wm.workspaces[1].order, { 1, 2 })
    -- Window 1's tile is x 0..1056, y 25..1080.
    t.eq(frame(a, 3), { x = 328, y = 453, w = 400, h = 200 })
end)

t.test("a float bigger than its display is capped at 80%", function()
    local a, wm = setup(0)
    a.add(1, { subrole = "AXDialog", frame = { x = 0, y = 0, w = 3000, h = 2000 } })
    wm:sync()
    t.eq(frame(a, 1).w, 1536)
    t.eq(frame(a, 1).h, 844)
end)

t.test("focusing a tile raises the floats after it, its own app's last", function()
    local a, wm = setup(2)
    a.add(3, { subrole = "AXDialog", pid = 100 })
    a.add(4, { subrole = "AXDialog", pid = 200 })
    wm:sync()
    a.calls = {}
    wm:focus_window(1)
    t.eq(a.calls, { "focus 1", "raise 4", "raise 3" })
end)

t.test("Super+J and Super+K move focus along the stack, wrapping", function()
    local a, wm = setup(3)
    a.focus_ = 3
    wm:act("focus", 1)
    t.eq(a.focus_, 1)
    wm:act("focus", -1)
    t.eq(a.focus_, 3)
end)

t.test("Super+Shift+J moves the window and retiles", function()
    local a, wm = setup(3)
    a.focus_ = 1
    wm:act("move", 1)
    t.eq(wm.workspaces[1].order, { 2, 1, 3 })
    t.eq(frame(a, 2).x, 0)
end)

t.test("Super+Return swaps with the master", function()
    local a, wm = setup(3)
    a.focus_ = 3
    wm:act("swap_master")
    t.eq(wm.workspaces[1].order, { 3, 2, 1 })
end)

t.test("Super+\\ grows the master by 0.025", function()
    local a, wm = setup(2)
    a.focus_ = 1
    wm:act("mfact", 1)
    t.eq(wm.workspaces[1].opts.tile.mfact, 0.575)
    t.eq(frame(a, 1).w, 1104)
end)

t.test("monocle fills the area with every window", function()
    local a, wm = setup(2)
    a.focus_ = 1
    wm:act("monocle")
    t.eq(frame(a, 1), { x = 0, y = 25, w = 1920, h = 1055 })
    t.eq(frame(a, 2), { x = 0, y = 25, w = 1920, h = 1055 })
    a.calls = {}
    wm:act("focus", 1)
    t.eq(a.calls, { "focus 2" })
end)

t.test("in monocle, a float stays over the tile Super+J brings forward", function()
    local a, wm = setup(2)
    a.add(3, { subrole = "AXDialog" })
    wm:sync()
    a.focus_ = 1
    wm:act("monocle")
    a.calls = {}
    wm:act("focus", 1)
    t.eq(a.calls, { "focus 2", "raise 3" })
end)

t.test("a click or app switch onto a tile puts the floats back over it", function()
    local a, wm = setup(2)
    a.add(3, { subrole = "AXDialog", pid = 200 })
    wm:sync()
    a.calls = {}
    wm:focused(1)
    t.eq(a.calls, { "raise 3" })
end)

t.test("a new window focused before the next sync is added and remembered", function()
    local a, wm = setup(1)
    a.add(2, {})
    wm:focused(2)
    t.eq(wm.windows[2] ~= nil, true)
    t.eq(wm.mru[1][1], 2)
    t.eq(wm.workspaces[1].order, { 1, 2 })
end)

t.test("focusing a new window ends another's maximize", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("maximize")
    a.add(2, {})
    wm:focused(2)
    t.eq(wm.windows[1].big, nil)
end)

t.test("maximize covers the area until another window on the workspace is focused", function()
    local a, wm = setup(2)
    a.focus_ = 1
    wm:act("maximize")
    t.eq(frame(a, 1), { x = 0, y = 25, w = 1920, h = 1055 })
    wm:focused(2)
    t.eq(wm.windows[1].big, nil)
    t.eq(frame(a, 1).w, 1056)
end)

t.test("full screen covers the whole display, and Super+Down restores", function()
    local a, wm = setup(2)
    a.focus_ = 1
    wm:act("fullscreen")
    t.eq(frame(a, 1), { x = 0, y = 0, w = 1920, h = 1080 })
    wm:act("restore")
    t.eq(frame(a, 1).w, 1056)
    t.eq(frame(a, 1).y, 25)
end)

t.test("Super+Shift+F floats a tile and tiles it again", function()
    local a, wm = setup(2)
    a.focus_ = 2
    wm:act("toggle_float")
    t.eq(wm.windows[2].floating, true)
    t.eq(wm.workspaces[1].order, { 1 })
    t.eq(frame(a, 1).w, 1920)
    wm:act("toggle_float")
    t.eq(wm.workspaces[1].order, { 1, 2 })
end)

t.test("each display gets its own workspace, and windows tile on theirs", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, {})
    a.add(2, { frame = { x = 2000, y = 100, w = 800, h = 600 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    t.eq(wm.windows[2].ws, 2)
    t.eq(frame(a, 2), { x = 1920, y = 25, w = 1920, h = 1055 })
end)

t.test("ignored windows are never moved", function()
    local a, wm = setup(1)
    a.add(2, { title = "Picture in Picture", frame = { x = 5, y = 5, w = 300, h = 200 } })
    wm:sync()
    wm:retile()
    t.eq(frame(a, 2), { x = 5, y = 5, w = 300, h = 200 })
    t.eq(frame(a, 1).w, 1920)
end)

t.test("an unknown action is an error naming it", function()
    local _, wm = setup(0)
    local ok, err = pcall(wm.act, wm, "nope")
    t.eq(ok, false)
    t.eq(err:find("no action nope") ~= nil, true, err)
end)

t.test("layout keys work while an ignored window has focus", function()
    local a, wm = setup(2)
    a.add(3, { title = "Picture in Picture" })
    wm:sync()
    a.focus_ = 3
    wm:act("monocle")
    t.eq(wm.workspaces[1].mode, "monocle")
end)

t.test("maximizing a tile puts its floats back over it", function()
    local a, wm = setup(2)
    a.add(3, { subrole = "AXDialog" })
    wm:sync()
    a.focus_ = 1
    a.calls = {}
    wm:act("maximize")
    t.eq(a.calls[#a.calls], "raise 3")
end)

t.test("after a close, a minimized window is passed over for a visible one", function()
    local a, wm = setup(3)
    wm:focused(1)
    wm:focused(2)
    wm:focused(3)
    a.wins[2].minimized = true
    wm:minimized(2) -- you minimized it
    a.focus_ = 3
    a.drop(3)
    wm:schedule()
    a.tick()
    t.eq(a.focus_, 1)
end)

t.test("after a close, a window not focused since tilemo started still gets focus", function()
    local a, wm = setup(2)
    a.focus_ = 2
    a.drop(2)
    a.focus_ = nil
    wm:schedule()
    a.tick()
    t.eq(a.focus_, 1)
end)

t.test("a new window that took focus first still goes after the one you were in", function()
    local cfg = {}
    for k, v in pairs(require("tilemo.layout").defaults) do
        cfg[k] = v
    end
    cfg.new_window = "next"
    local a = fake.new()
    for i = 1, 3 do
        a.add(i, {})
    end
    local wm = wm_mod.new(a, { layout = cfg })
    wm:sync()
    wm:focused(1)
    a.add(4, {})
    a.focus_ = 4
    wm:focused(4)
    local order = wm.workspaces[wm.windows[4].ws].order
    t.eq(order[1], 1)
    t.eq(order[2], 4)
end)

t.test("after a close, a tile missing from the focus history still gets focus", function()
    local a, wm = setup(3)
    a.focus_ = 3
    wm.mru[1] = { 3 } -- 1 and 2 arrived without a focus event
    a.drop(3)
    a.focus_ = nil
    wm:schedule()
    a.tick()
    t.eq(a.focus_ ~= nil, true)
end)

t.test("a float you focus stays in front when a tile's floats are raised again", function()
    local a, wm = setup(1)
    a.add(2, { subrole = "AXDialog", pid = 100 })
    a.add(3, { subrole = "AXDialog", pid = 100 })
    wm:sync()
    wm:focused(2) -- the older float, brought forward
    a.calls = {}
    wm:raise_floats(1, nil)
    t.eq(a.calls[#a.calls], "raise 2")
end)

t.test("tilemo's own moves aren't read as drags", function()
    local a, wm = setup(2)
    a.calls = {}
    wm:moved(1)
    wm:moved(2)
    t.eq(a.calls, {})
end)

t.test("resizing the master by its edge sets the split", function()
    local a, wm = setup(2)
    a.wins[1].frame = { x = 0, y = 25, w = 1152, h = 1055 }
    wm:moved(1)
    t.eq(wm.workspaces[1].opts.tile.mfact, 0.6)
    t.eq(frame(a, 2), { x = 1152, y = 25, w = 768, h = 1055 })
end)

t.test("a drag waits for the button to come up", function()
    local a, wm = setup(2)
    a.buttons = true
    a.wins[1].frame = { x = 0, y = 25, w = 1152, h = 1055 }
    wm:moved(1)
    t.eq(wm.workspaces[1].opts.tile.mfact, 0.55)
    a.buttons = false
    a.tick()
    t.eq(wm.workspaces[1].opts.tile.mfact, 0.6)
end)

t.test("dropping a tile on another swaps them", function()
    local a, wm = setup(3)
    -- Window 1 moved, same size, its center now in window 3's tile.
    a.wins[1].frame = { x = 1000, y = 500, w = 1056, h = 1055 }
    wm:moved(1)
    t.eq(wm.workspaces[1].order, { 3, 2, 1 })
    t.eq(frame(a, 3).x, 0)
end)

t.test("dropping a tile on another display moves it to that display's workspace", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, {})
    a.add(2, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    a.wins[2].frame = { x = 2400, y = 200, w = 864, h = 1055 }
    wm:moved(2)
    t.eq(wm.windows[2].ws, 2)
    t.eq(frame(a, 2), { x = 1920, y = 25, w = 1920, h = 1055 })
    t.eq(frame(a, 1).w, 1920)
end)

t.test("Super+drag on a float moves it where it's dropped", function()
    local a, wm = setup(1)
    a.add(2, { subrole = "AXDialog", frame = { x = 0, y = 0, w = 400, h = 200 } })
    wm:sync()
    a.focus_ = 2
    local f = frame(a, 2)
    local d = wm:grab("move", f.x + 10, f.y + 10)
    t.eq(d.id, 2)
    wm:drop(d, f.x + 110, f.y + 60)
    t.eq(frame(a, 2), { x = f.x + 100, y = f.y + 50, w = 400, h = 200 })
end)

t.test("Super+right-drag on the master sets the split", function()
    local a, wm = setup(2)
    local d = wm:grab("resize", 1000, 500)
    t.eq(d.id, 1)
    wm:drop(d, 1096, 500)
    t.eq(wm.workspaces[1].opts.tile.mfact, 0.6)
end)

t.test("Super+middle-click maximizes the window under the pointer, and again restores it", function()
    local a, wm = setup(2)
    wm:maximize_at(1500, 500)
    t.eq(a.focus_, 2)
    t.eq(frame(a, 2), { x = 0, y = 25, w = 1920, h = 1055 })
    wm:maximize_at(1500, 500)
    t.eq(frame(a, 2).x, 1056)
end)

t.test("resize mode grows and shrinks the focused float, not a tile", function()
    local a, wm = setup(1)
    a.add(2, { subrole = "AXDialog", frame = { x = 0, y = 0, w = 400, h = 200 } })
    wm:sync()
    a.focus_ = 2
    wm:act("resize_by", { 40, -40 })
    t.eq(frame(a, 2).w, 440)
    t.eq(frame(a, 2).h, 160)
    a.focus_ = 1
    a.calls = {}
    wm:act("resize_by", { 40, 0 })
    t.eq(a.calls, {})
end)

t.test("Super+drag over picture-in-picture doesn't grab the tile under it", function()
    local a, wm = setup(2)
    a.add(3, { title = "Picture in Picture", frame = { x = 100, y = 100, w = 300, h = 200 } })
    wm:sync()
    t.eq(wm:grab("move", 150, 150), nil)
    wm:maximize_at(150, 150)
    t.eq(wm.windows[1].big, nil)
end)

t.test("a tile dropped on another display moves there even if macOS resized it", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1280, h = 775 }, full = { x = 1920, y = 0, w = 1280, h = 800 } }
    a.add(1, {})
    a.add(2, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    a.wins[2].frame = { x = 2000, y = 25, w = 864, h = 775 } -- shorter
    wm:moved(2)
    t.eq(wm.windows[2].ws, 2)
    t.eq(wm.workspaces[1].opts.tile.mfact, 0.55)
    t.eq(a.wins[2].frame, { x = 1920, y = 25, w = 1280, h = 775 })
end)

t.test("a lone window keeps the width you drag it to, until a second window opens", function()
    local a, wm = setup(1)
    wm:request(1, { x = 0, y = 25, w = 1536, h = 1055 }) -- right edge dragged in to x = 1536
    local f = a.wins[1].frame
    t.eq(f.w, 1152) -- 60% of 1920, centered
    t.eq(f.x, 384)
    a.add(2, {})
    wm:sync()
    wm:retile()
    t.eq(a.wins[1].frame.x, 0)
    a.drop(2)
    wm:sync()
    wm:retile()
    t.eq(a.wins[1].frame.w, 1152)
end)

t.test("a float Super+dragged to the other display joins its workspace", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, {})
    a.add(2, { frame = { x = 2000, y = 100, w = 800, h = 600 } })
    a.add(3, { subrole = "AXDialog", frame = { x = 100, y = 100, w = 300, h = 200 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    local before = wm.windows[3].ws
    local f = a.wins[3].frame
    local x, y = f.x + 10, f.y + 10
    local d = wm:grab("move", x, y)
    t.eq(d.id, 3)
    wm:drop(d, x + 1920, y)
    t.eq(wm.windows[3].ws ~= before, true)
    t.eq(wm.windows[3].ws, wm.windows[2].ws)
end)

t.test("an app key brings the app's last window forward instead of launching", function()
    local a, wm = setup(2)
    a.wins[2].app = "net.kovidgoyal.kitty"
    wm.windows[2].app = "net.kovidgoyal.kitty"
    a.focus_ = 1
    wm:act("app", { bundle = "net.kovidgoyal.kitty" })
    t.eq(a.focus_, 2)
    t.eq(#a.launched, 0)
end)

t.test("an app key goes to the app's last used window, whichever workspace it's on", function()
    local a, wm = setup(2)
    for _, id in ipairs({ 1, 2 }) do
        a.wins[id].app = "net.kovidgoyal.kitty"
        wm.windows[id].app = "net.kovidgoyal.kitty"
    end
    a.focus_ = 1
    wm:act("send", 4)
    wm:act("show", 4)
    a.tick()
    a.focus_ = 1
    wm:focused(1)
    wm:act("show", 1)
    a.tick()
    a.focus_ = 2
    wm:focused(2)
    wm:act("app", { bundle = "net.kovidgoyal.kitty" })
    t.eq(wm.history[1], 2)
    wm:focused(1)
    wm:act("show", 1)
    a.tick()
    wm:act("app", { bundle = "net.kovidgoyal.kitty" })
    t.eq(wm:current_ws(), 4)
end)

t.test("Cmd+Return asks for a new window on an empty workspace, even when the app is running", function()
    local a, wm = setup(1)
    a.wins[1].app = "net.kovidgoyal.kitty"
    wm.windows[1].app = "net.kovidgoyal.kitty"
    wm:act("app", { bundle = "net.kovidgoyal.kitty" })
    t.eq(#a.launched, 0)
    wm.actions.app(wm, { bundle = "net.kovidgoyal.kitty" }, true)
    t.eq(a.fresh[1], true)
    t.eq(wm:shown(2) ~= nil, true)
end)

t.test("Super+T opens a new terminal window every time, on this workspace, as tide's does", function()
    local a, wm = setup(1)
    a.wins[1].app = "net.kovidgoyal.kitty"
    wm.windows[1].app = "net.kovidgoyal.kitty"
    local spec
    for _, b in ipairs(keys.map) do
        if b.key == "t" and not b.shift then
            spec = b.arg
        end
    end
    wm:act("app", spec)
    wm:act("app", spec)
    t.eq(#a.launched, 2)
    t.eq(a.launched[1].bundle, "net.kovidgoyal.kitty")
    t.eq(a.fresh, { true, true })
    t.eq(wm:current_ws(), 1)
end)

t.test("an app key launches the app when it has no window", function()
    local a, wm = setup(1)
    wm:act("app", { bundle = "com.example.other" })
    t.eq(a.launched[1].bundle, "com.example.other")
    wm:act("app", { run = "browser2" })
    t.eq(a.launched[2].run, "browser2")
end)

t.test("Super+Space asks for the launcher", function()
    local _, wm = setup(0)
    local opened = false
    wm.open_launcher = function()
        opened = true
    end
    wm:act("launcher")
    t.eq(opened, true)
end)

t.test("a layout command switches the workspace's layout", function()
    local a, wm = setup(2)
    a.focus_ = 1
    wm:act("layout", "twocol")
    t.eq(wm.workspaces[1].mode, "twocol")
end)


t.test("one overlay letting go of the keyboard doesn't release another's hold", function()
    local a = fake.new()
    local wm = wm_mod.new(a, {})
    wm:hold("dashboard", true)
    wm:hold("launcher", true) -- the launcher opens over the dashboard
    wm:hold("dashboard", false) -- which closes as it loses focus
    t.eq(wm.holding_keyboard, true)
    wm:hold("launcher", false)
    t.eq(wm.holding_keyboard, false)
end)

t.done("wm")
