local t = require("t")
local fake = require("fake")
local wm_mod = require("tide.wm")
local keys = require("tide.keys")

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
    t.eq(wm:part("in", "A").order, { 1, 2 })
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
    t.eq(wm:part("in", "A").order, { 1, 2 })
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
    t.eq(wm:part("in", "A").order, { 1, 2 })
    -- Window 1's tile is x 0..1056, y 25..1080.
    t.eq(frame(a, 3), { x = 328, y = 453, w = 400, h = 200 })
end)

-- Not under the pointer: a slow app's window, such as System Settings'
-- About This Mac, arrives after the pointer has moved on, and would land
-- where it was.
t.test("a float with no parent centers on its display, wherever the pointer is", function()
    local a, wm = setup(2)
    a.px, a.py = 1500, 300
    a.add(3, { app = "com.apple.systempreferences", pid = 300, frame = { x = 0, y = 0, w = 600, h = 500 } })
    wm:sync()
    t.eq(wm.windows[3].floating, true)
    t.eq(frame(a, 3), { x = 660, y = 303, w = 600, h = 500 })
end)

t.test("a dialog centers on its parent, wherever the pointer is", function()
    local a, wm = setup(2)
    a.focus_ = 1
    a.px, a.py = 1500, 300
    a.add(3, { subrole = "AXDialog", frame = { x = 0, y = 0, w = 400, h = 200 } })
    wm:sync()
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
    t.eq(wm:part("in", "A").order, { 2, 1, 3 })
    t.eq(frame(a, 2).x, 0)
end)

t.test("Alt+Tab swaps with the master", function()
    local a, wm = setup(3)
    a.focus_ = 3
    wm:act("swap_master")
    t.eq(wm:part("in", "A").order, { 3, 2, 1 })
end)

t.test("Super+\\ grows the master by 0.025", function()
    local a, wm = setup(2)
    a.focus_ = 1
    wm:act("mfact", 1)
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.575)
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
    t.eq(wm.mru["in"][1], 2)
    t.eq(wm:part("in", "A").order, { 1, 2 })
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
    t.eq(wm:part("in", "A").order, { 1 })
    t.eq(frame(a, 1).w, 1920)
    wm:act("toggle_float")
    t.eq(wm:part("in", "A").order, { 1, 2 })
end)

-- Bitwarden's extension opens its sign-in, autofill and passkey prompts in
-- a Chrome popup window, which may open before its page has named it.
t.test("a new window named after it opens is decided again, and floats if its name says so", function()
    local a, wm = setup(1)
    a.add(2, { app = "com.google.Chrome", pid = 200, title = "", frame = { x = 1500, y = 60, w = 380, h = 630 } })
    wm:sync()
    wm:retile()
    t.eq(wm:part("in", "A").order, { 1, 2 }, "tiled at first")
    a.clock = a.clock + 1
    a.wins[2].title = "Bitwarden"
    wm:retitled(2)
    t.eq(wm.windows[2].floating, true, "floats")
    t.eq(wm:part("in", "A").order, { 1 })
    t.eq(frame(a, 1).w, 1920, "the tile left takes the room")
    t.eq(frame(a, 2).w, 380, "at its own size")
end)

t.test("a window renamed after it settled, or one you placed, isn't decided again", function()
    local a, wm = setup(1)
    a.add(2, { app = "com.google.Chrome", pid = 200, title = "New Tab" })
    wm:sync()
    a.clock = a.clock + wm_mod.SETTLE + 1
    a.wins[2].title = "Bitwarden" -- a tab of that name, much later
    wm:retitled(2)
    t.eq(wm.windows[2].floating or false, false, "settled")

    a, wm = setup(1)
    a.add(2, { app = "com.google.Chrome", pid = 200, title = "" })
    wm:sync()
    a.focus_ = 2
    wm:act("toggle_float")
    wm:act("toggle_float") -- you tiled it
    a.wins[2].title = "Bitwarden"
    wm:retitled(2)
    t.eq(wm.windows[2].floating, false, "yours")
end)

t.test("one workspace spans every display, and windows tile on their own display's part", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, {})
    a.add(2, { frame = { x = 2000, y = 100, w = 800, h = 600 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    t.eq(wm.windows[2].ws, "in")
    t.eq(wm.windows[2].screen, "B")
    t.eq(frame(a, 1), { x = 0, y = 25, w = 1920, h = 1055 })
    t.eq(frame(a, 2), { x = 1920, y = 25, w = 1920, h = 1055 })
end)

t.test("each display keeps its own layout, mfact and masters within the workspace", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, {})
    a.add(2, {})
    a.add(3, { frame = { x = 2000, y = 100, w = 800, h = 600 } })
    a.add(4, { frame = { x = 2000, y = 100, w = 800, h = 600 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    a.focus_ = 3
    wm:act("monocle")
    wm:act("mfact", 1)
    t.eq(wm:part("in", "B").mode, "monocle")
    t.eq(wm:part("in", "A").mode, "tile", "A's layout is its own")
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.55)
    t.eq(frame(a, 3), { x = 1920, y = 25, w = 1920, h = 1055 })
    t.eq(frame(a, 1).w < 1920, true, "A still tiles")
    a.focus_ = 1
    wm:act("nmaster", 1)
    t.eq(wm:part("in", "A").opts.tile.nmaster, 2)
    t.eq(wm:part("in", "B").opts.tile.nmaster, 1)
    -- Another workspace has its own parts, and this one's come back as left.
    wm:show("re")
    wm:show("in")
    t.eq(wm:part("in", "B").mode, "monocle")
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
    t.eq(wm:part("in", "A").mode, "monocle")
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

t.test("after a close, a window not focused since tide started still gets focus", function()
    local a, wm = setup(2)
    a.focus_ = 2
    a.drop(2)
    a.focus_ = nil
    wm:schedule()
    a.tick()
    t.eq(a.focus_, 1)
end)

t.test("after a close, a launcher or Tide Settings with the focus keeps it", function()
    local a, wm = setup(2)
    wm:focused(1)
    a.drop(2)
    a.focus_ = nil
    a.own = true
    a.calls = {}
    wm:schedule()
    a.tick()
    t.eq(a.focus_, nil)
    for _, c in ipairs(a.calls) do
        t.eq(c:match("^focus") == nil, true, c)
    end
end)

t.test("a new window that took focus first still goes after the one you were in", function()
    local cfg = {}
    for k, v in pairs(require("tide.layout").defaults) do
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
    local order = wm:part_of(wm.windows[4]).order
    t.eq(order[1], 1)
    t.eq(order[2], 4)
end)

t.test("after a close, a tile missing from the focus history still gets focus", function()
    local a, wm = setup(3)
    a.focus_ = 3
    wm.mru["in"] = { 3 } -- 1 and 2 arrived without a focus event
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
    wm:raise_floats("in", nil)
    t.eq(a.calls[#a.calls], "raise 2")
end)

t.test("tide's own moves aren't read as drags", function()
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
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.6)
    t.eq(frame(a, 2), { x = 1152, y = 25, w = 768, h = 1055 })
end)

t.test("a resize drag sets the split as it goes, the other tiles following, and leaves the dragged one alone", function()
    local a, wm = setup(2)
    a.buttons = true
    a.wins[1].frame = { x = 0, y = 25, w = 1152, h = 1055 }
    a.calls = {}
    wm:moved(1)
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.6, "while the button is held")
    t.eq(frame(a, 2), { x = 1152, y = 25, w = 768, h = 1055 }, "the neighbor follows at once")
    for _, c in ipairs(a.calls) do
        t.eq(c ~= "frame 1", true, "the dragged window isn't moved under the pointer")
    end
    -- Further along the same drag.
    a.wins[1].frame = { x = 0, y = 25, w = 960, h = 1055 }
    a.tick()
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.5)
    t.eq(frame(a, 2).x, 960)
    a.buttons = false
    a.tick()
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.5, "the drop keeps it")
    t.eq(frame(a, 1), { x = 0, y = 25, w = 960, h = 1055 })
end)

t.test("a lone window narrows on both sides as its edge is dragged, staying centered", function()
    local a, wm = setup(1)
    a.buttons = true
    -- The right edge dragged in to x = 1536, the left still at 0.
    a.wins[1].frame = { x = 0, y = 25, w = 1536, h = 1055 }
    wm:moved(1)
    t.eq(a.wins[1].frame, { x = 384, y = 25, w = 1152, h = 1055 }, "the left edge follows, mid-drag")
    -- Further: the right edge, still under the pointer, at 1344.
    a.wins[1].frame = { x = 384, y = 25, w = 960, h = 1055 }
    a.tick()
    t.eq(a.wins[1].frame, { x = 576, y = 25, w = 768, h = 1055 })
    a.buttons = false
    a.tick()
    t.eq(a.wins[1].frame, { x = 576, y = 25, w = 768, h = 1055 }, "the drop keeps it")
end)

t.test("a lone window's left edge keeps hold of its width as tide mirrors the right", function()
    local a, wm = setup(1)
    a.buttons = true
    a.wins[1].frame = { x = 384, y = 25, w = 1536, h = 1055 } -- the left edge in to 384
    wm:moved(1)
    t.eq(a.wins[1].frame, { x = 384, y = 25, w = 1152, h = 1055 })
    a.wins[1].frame = { x = 576, y = 25, w = 960, h = 1055 } -- further, to 576
    a.tick()
    t.eq(a.wins[1].frame, { x = 576, y = 25, w = 768, h = 1055 }, "the left edge still leads")
    a.buttons = false
    a.tick()
    t.eq(a.wins[1].frame, { x = 576, y = 25, w = 768, h = 1055 }, "and the drop keeps it")
end)

t.test("a corner drag that starts with the height still finds the side you hold", function()
    local a, wm = setup(1)
    a.buttons = true
    a.wins[1].frame = { x = 0, y = 25, w = 1920, h = 1054 } -- the height first
    wm:moved(1)
    a.wins[1].frame = { x = 384, y = 25, w = 1536, h = 1055 } -- then the left edge
    a.tick()
    t.eq(a.wins[1].frame, { x = 384, y = 25, w = 1152, h = 1055 })
    a.wins[1].frame = { x = 576, y = 25, w = 960, h = 1055 }
    a.tick()
    t.eq(a.wins[1].frame, { x = 576, y = 25, w = 768, h = 1055 }, "the left edge leads")
    a.buttons = false
    a.tick()
    t.eq(a.wins[1].frame.x, 576)
end)

t.test("a move drag still waits for the button to come up", function()
    local a, wm = setup(3)
    a.buttons = true
    a.wins[1].frame = { x = 1000, y = 500, w = 1056, h = 1055 }
    wm:moved(1)
    t.eq(wm:part("in", "A").order, { 1, 2, 3 }, "nothing swaps mid-drag")
    a.buttons = false
    a.tick()
    t.eq(wm:part("in", "A").order, { 3, 2, 1 })
end)

t.test("dropping a tile on another swaps them", function()
    local a, wm = setup(3)
    -- Window 1 moved, same size, its center now in window 3's tile.
    a.wins[1].frame = { x = 1000, y = 500, w = 1056, h = 1055 }
    wm:moved(1)
    t.eq(wm:part("in", "A").order, { 3, 2, 1 })
    t.eq(frame(a, 3).x, 0)
end)

t.test("dropping a tile on another display moves it there, in the same workspace", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, {})
    a.add(2, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    a.wins[2].frame = { x = 2400, y = 200, w = 864, h = 1055 }
    wm:moved(2)
    t.eq(wm.windows[2].ws, "in")
    t.eq(wm.windows[2].screen, "B")
    t.eq(wm:part("in", "B").order, { 2 })
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
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.6)
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
    t.eq(wm.windows[2].screen, "B")
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.55)
    t.eq(a.wins[2].frame, { x = 1920, y = 25, w = 1280, h = 775 })
end)

t.test("a tile dragged onto another display and resized there mid-drag leaves its display's split alone", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1280, h = 775 }, full = { x = 1920, y = 0, w = 1280, h = 800 } }
    a.add(1, {})
    a.add(2, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    a.buttons = true
    a.wins[2].frame = { x = 2000, y = 25, w = 864, h = 775 }
    wm:moved(2)
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.55, "mid-drag")
    a.buttons = false
    a.tick()
    t.eq(wm.windows[2].screen, "B")
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.55, "after the drop")
end)

t.test("a corner drag leaves the dragged tile where the pointer has it, the neighbors following", function()
    local a, wm = setup(2)
    a.buttons = true
    -- The master's bottom-right corner dragged: wider, and shorter.
    a.wins[1].frame = { x = 0, y = 25, w = 1152, h = 800 }
    a.calls = {}
    wm:moved(1)
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.6)
    t.eq(a.wins[1].frame, { x = 0, y = 25, w = 1152, h = 800 }, "its bottom stays under the pointer")
    t.eq(frame(a, 2).x, 1152)
end)

t.test("a corner drag taken back to where it started puts the split back", function()
    local a, wm = setup(2)
    local start = frame(a, 1)
    a.buttons = true
    a.wins[1].frame = { x = 0, y = 25, w = 1152, h = 800 }
    wm:moved(1)
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.6)
    a.wins[1].frame = start
    a.tick()
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.55, "mid-drag, back to the start")
    t.eq(frame(a, 2).x, start.x + start.w, "the neighbor back beside it")
    a.buttons = false
    a.tick()
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.55, "after the drop")
    t.eq(frame(a, 2).x, start.x + start.w)
end)

t.test("an edge taken back and out again in one drag sets the split again", function()
    local a, wm = setup(2)
    local start = frame(a, 1)
    a.buttons = true
    a.wins[1].frame = { x = 0, y = 25, w = 1152, h = 1055 }
    wm:moved(1)
    a.wins[1].frame = start
    a.tick()
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.55)
    a.wins[1].frame = { x = 0, y = 25, w = 1152, h = 1055 }
    a.tick()
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.6, "out again")
    a.buttons = false
    a.tick()
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.6)
    t.eq(frame(a, 2).x, 1152, "no overlap")
end)

t.test("a corner drag whose width goes back puts the split back, whatever its height", function()
    local a, wm = setup(2)
    a.buttons = true
    a.wins[1].frame = { x = 0, y = 25, w = 1152, h = 800 }
    wm:moved(1)
    a.wins[1].frame = { x = 0, y = 25, w = 1056, h = 800 }
    a.tick()
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.55, "mid-drag")
    a.buttons = false
    a.tick()
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.55, "after the drop")
    t.eq(frame(a, 1).w, 1056)
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

t.test("a float Super+dragged to the other display is on that display, in the same workspace", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, {})
    a.add(2, { frame = { x = 2000, y = 100, w = 800, h = 600 } })
    a.add(3, { subrole = "AXDialog", frame = { x = 100, y = 100, w = 300, h = 200 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    t.eq(wm.windows[3].screen, "A")
    local f = a.wins[3].frame
    local x, y = f.x + 10, f.y + 10
    local d = wm:grab("move", x, y)
    t.eq(d.id, 3)
    wm:drop(d, x + 1920, y)
    t.eq(wm.windows[3].screen, "B")
    t.eq(wm.windows[3].ws, "in")
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
    wm:act("send", "4")
    wm:show("4", nil, true)
    a.tick()
    a.focus_ = 1
    wm:focused(1)
    wm:act("show", "in")
    a.tick()
    a.focus_ = 2
    wm:focused(2)
    wm:act("app", { bundle = "net.kovidgoyal.kitty" })
    t.eq(wm.history[1], 2)
    wm:focused(1)
    wm:act("show", "in")
    a.tick()
    wm:act("app", { bundle = "net.kovidgoyal.kitty" })
    t.eq(wm:current_ws(), "4")
end)

t.test("Cmd+Return asks for a new window, even when the app is running", function()
    local a, wm = setup(1)
    a.wins[1].app = "net.kovidgoyal.kitty"
    wm.windows[1].app = "net.kovidgoyal.kitty"
    wm:act("app", { bundle = "net.kovidgoyal.kitty" })
    t.eq(#a.launched, 0)
    wm.actions.app(wm, { bundle = "net.kovidgoyal.kitty" }, true)
    t.eq(a.fresh[1], true)
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
    t.eq(wm:current_ws(), "in")
end)

t.test("Super+L locks the screen and Super+Shift+E logs out, as on tide", function()
    local a, wm = setup(1)
    local function act(key, shift)
        for _, b in ipairs(keys.map) do
            if b.key == key and (b.shift or false) == shift then
                wm:act(b.action, b.arg)
                return
            end
        end
        error("no binding for Super+" .. (shift and "Shift+" or "") .. key)
    end
    act("l", false)
    t.eq(a.system, { "lock" })
    act("e", true)
    t.eq(a.system, { "lock", "logout" })
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
    t.eq(wm:part("in", "A").mode, "twocol")
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

t.test("the settings action opens the window on the section it names", function()
    local wm = wm_mod.new(fake.new(), {})
    local opened = {}
    wm.open_settings = function(section)
        opened[#opened + 1] = section or "none"
    end
    wm:act("settings", "startup")
    wm:act("settings")
    t.eq(opened, { "startup", "none" })
end)

t.test("new layout settings retile every display at once, and the same ones change nothing", function()
    local layout = require("tide.layout")
    local a, wm = setup(3)
    wm:act("mfact", 1)
    local c = layout.copy(layout.defaults)
    c.modes.tile.mfact = 0.5
    wm:set_layout(c)
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.5, "what the keys set gives way")
    t.eq(frame(a, 1).w, 960)
    wm:act("mfact", 1)
    wm:set_layout(layout.copy(c))
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.525, "a reload with the same settings keeps the keys'")
end)

-- Parking (SPEC.md §6): the default way a hidden workspace hides. -----------

local park = require("tide.park")

-- Whether the adapter was asked to minimize anything.
local function minimizes(a)
    for _, c in ipairs(a.calls) do
        if c:match("^minimize ") then
            return true
        end
    end
    return false
end

-- Where display A parks a window of `w` by `h`, alone: its top-left 1 pt
-- inside A's bottom-right corner.
local function spot_on_a(w, h)
    return { x = 1919, y = 1079, w = w, h = h }
end

t.test("in park mode, a switch parks the hidden workspace's windows and never minimizes", function()
    local a, wm = setup(2)
    t.eq(wm.hide, "park", "the default")
    local f1, f2 = frame(a, 1), frame(a, 2)
    a.calls = {}
    wm:show("2", nil, true)
    t.eq(minimizes(a), false, "nothing minimized")
    t.eq(a.wins[1].minimized, nil)
    t.eq(frame(a, 1), spot_on_a(f1.w, f1.h))
    t.eq(frame(a, 2), spot_on_a(f2.w, f2.h))
    t.eq(wm.parked[1], true)
    t.eq(wm.parked[2], true)
    t.eq(wm:tiled("in", "A"), {}, "a parked window isn't on screen")
end)

t.test("switching back puts parked windows back in their tiles", function()
    local a, wm = setup(3)
    local before = { frame(a, 1), frame(a, 2), frame(a, 3) }
    wm:show("2", nil, true)
    wm:show("in")
    for i = 1, 3 do
        t.eq(frame(a, i), before[i], "tile " .. i)
        t.eq(wm.parked[i], nil, "unparked " .. i)
    end
    t.eq(wm:tiled("in", "A"), { 1, 2, 3 })
end)

t.test("the workspace coming in is laid out before the one leaving is parked", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("send", "2")
    a.add(2, {})
    wm:sync()
    wm:retile()
    a.calls = {}
    wm:show("2", nil, true)
    t.eq(a.calls[1], "frame 1", "1 comes in first")
    t.eq(a.calls[2], "frame 2", "then 2 leaves")
end)

t.test("a float gets its own frame back when its workspace shows again", function()
    local a, wm = setup(1)
    a.focus_ = 1
    a.add(2, { subrole = "AXDialog", frame = { x = 0, y = 0, w = 400, h = 200 } })
    wm:sync()
    wm:retile()
    local f = frame(a, 2)
    -- You moved it.
    a.wins[2].frame = { x = 1300, y = 700, w = 400, h = 200 }
    wm:show("2", nil, true)
    t.eq(frame(a, 2), spot_on_a(400, 200))
    t.eq(wm.windows[2].ws, "in", "its park doesn't move it to another workspace")
    wm:show("in")
    t.eq(frame(a, 2), { x = 1300, y = 700, w = 400, h = 200 })
    t.eq(f ~= nil, true)
end)

t.test("macOS reporting a park's move isn't read as you moving the window", function()
    local a, wm = setup(2)
    a.add(3, { app = "com.apple.systempreferences", pid = 300, frame = { x = 0, y = 0, w = 600, h = 500 } })
    wm:sync()
    wm:show("2", nil, true)
    for _, id in ipairs({ 1, 2, 3 }) do
        wm:moved(id)
    end
    t.eq(wm.windows[1].ws, "in")
    t.eq(wm.windows[3].ws, "in", "the float stays on its workspace")
    t.eq(wm:part("in", "A").order, { 1, 2 })
    t.eq(wm.windows[1].screen, "A")
end)

t.test("focusing a parked window, as Cmd+Tab does, brings its workspace along", function()
    local a, wm = setup(2)
    wm:focused(1)
    wm:show("2", nil, true)
    t.eq(wm.parked[1], true)
    -- Cmd+Tab: Command down, then macOS focuses the app's window.
    wm:modifiers(true)
    a.focus_ = 1
    wm:focused(1)
    wm:modifiers(false)
    t.eq(wm.current, "in", "its workspace shows")
    t.eq(wm.parked[1], nil)
    t.eq(wm.parked[2], nil)
    t.eq(park.hidden(frame(a, 1), wm:fulls()), false, "back on screen")
    t.eq(a.focus_, 1)
end)

t.test("a late report of a focus from before a switch doesn't pull you back", function()
    local a, wm = setup(2)
    a.focus_ = 1
    wm:focused(1)
    wm:show("2", nil, true)
    -- The switch focused window 2's workspace's window; macOS reports the
    -- old focus late.
    a.focus_ = 3
    wm:focused(1)
    t.eq(wm.current, "2", "the workspace you switched to stays")
    t.eq(wm.parked[1], true)
end)

t.test("switching to an empty workspace takes the focus off the parked window", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:focused(1)
    wm:show("2", nil, true)
    t.eq(wm.parked[1], true)
    t.eq(a.focus_, nil, "typing reaches no window you can't see")
    t.eq(a.own, true, "Hammerspoon has the focus")
end)

t.test("a parked window's sliver isn't a window to pick under the pointer", function()
    local a, wm = setup(1)
    wm:show("2", nil, true)
    t.eq(wm:window_at(1919, 1079), nil)
end)

t.test("restore_all brings every parked window back onto its display", function()
    local a, wm = setup(2)
    a.focus_ = 1
    a.add(3, { subrole = "AXDialog", frame = { x = 0, y = 0, w = 400, h = 200 } })
    wm:sync()
    wm:retile()
    local tile, float = frame(a, 1), frame(a, 3)
    wm:show("2", nil, true)
    wm:restore_all()
    t.eq(next(wm.parked), nil, "nothing parked")
    t.eq(frame(a, 1), tile, "a tile where it was")
    t.eq(frame(a, 3), float, "a float where it was")
    t.eq(park.hidden(frame(a, 2), wm:fulls()), false, "the other tile too")
end)

t.test("Super+Z in park mode still minimizes, to the tray, and the window stays down", function()
    local a, wm = setup(2)
    wm:focus_window(2)
    wm:focused(2)
    a.calls = {}
    wm:act("minimize")
    t.eq(a.wins[2].minimized, true, "really minimized")
    t.eq(a.calls[1], "minimize 2")
    t.eq(wm.windows[2].mine, true)
    t.eq(wm:minimized_windows("in", "A"), { 2 }, "in the tray")
    wm:minimized(2) -- macOS's report of tide's own minimize
    wm:show("2", nil, true)
    t.eq(wm.parked[2], nil, "a window you minimized isn't parked")
    t.eq(wm.parked[1], true)
    wm:show("in")
    t.eq(a.wins[2].minimized, true, "still down")
    t.eq(wm:tiled("in", "A"), { 1 })
end)

t.test("minimize mode hides by minimizing, as before, and moves nothing off screen", function()
    local a = fake.new()
    a.add(1, {})
    a.add(2, {})
    local wm = wm_mod.new(a, { hide = "minimize" })
    wm:sync()
    wm:reconcile()
    wm:retile()
    local f1 = frame(a, 1)
    a.calls = {}
    wm:show("2", nil, true)
    t.eq(a.calls, { "minimize 1", "minimize 2" })
    t.eq(a.wins[1].minimized, true)
    t.eq(frame(a, 1), f1, "not moved")
    t.eq(next(wm.parked), nil)
    a.calls = {}
    wm:show("in")
    t.eq(a.calls[1], "unminimize 1")
    t.eq(a.calls[2], "unminimize 2")
    t.eq(a.wins[1].minimized, false)
end)

t.test("a window tide minimized under the old scheme comes back in park mode", function()
    local a = fake.new()
    a.add(1, { minimized = true, title = "Shown" })
    a.add(2, { minimized = true, title = "Hidden" })
    local wm = wm_mod.new(a, { saved = {
        windows = {
            ["1"] = { ws = "in", mine = false, app = "com.example.app", pos = 1 },
            ["2"] = { ws = "2", mine = false, app = "com.example.app" },
        },
        current = "in",
        names = { "in", "2" },
    } })
    wm:sync()
    wm:reconcile()
    wm:retile()
    t.eq(a.wins[1].minimized, false, "its workspace shows: restored")
    t.eq(frame(a, 1), { x = 0, y = 25, w = 1920, h = 1055 }, "and tiled")
    t.eq(a.wins[2].minimized, false, "hidden: restored, then parked")
    t.eq(wm.parked[2], true)
    t.eq(frame(a, 2), spot_on_a(800, 600))
    wm:unminimized(1)
    wm:unminimized(2)
    t.eq(wm.windows[2].mine, false, "macOS's reports are tide's, not yours")
end)

t.test("a native full-screen window hides by minimizing, since it can't be parked", function()
    local a, wm = setup(2)
    a.wins[2].fullscreen = true
    local f = frame(a, 2)
    a.calls = {}
    wm:show("2", nil, true)
    t.eq(a.wins[2].minimized, true, "minimized")
    t.eq(frame(a, 2), f, "not moved")
    t.eq(wm.parked[2], nil)
    t.eq(wm.parked[1], true, "the other window parks")
    wm:minimized(2)
    t.eq(wm.windows[2].mine, false, "tide's own minimize")
    -- macOS takes it out of full screen as it minimizes.
    a.wins[2].fullscreen = false
    wm:reconcile()
    t.eq(a.wins[2].minimized, true, "it stays down, not unminimized to be parked")
    wm:show("in")
    t.eq(a.wins[2].minimized, false, "back with its workspace")
end)

t.test("parked windows survive a restart that didn't bring them back first", function()
    local a, wm = setup(2)
    a.focus_ = 1
    a.add(3, { subrole = "AXDialog", frame = { x = 0, y = 0, w = 400, h = 200 } })
    wm:sync()
    wm:retile()
    a.wins[3].frame = { x = 1300, y = 700, w = 400, h = 200 }
    wm:show("2", nil, true)
    local spot = frame(a, 1)
    -- A restart with the windows still parked: a crash, say.
    a.calls = {}
    local wm2 = wm_mod.new(a, { saved = a.saved })
    wm2:sync()
    wm2:reconcile()
    wm2:retile()
    t.eq(wm2.current, "2")
    t.eq(wm2.parked[1], true, "parked again")
    t.eq(wm2.parked[3], true)
    t.eq(frame(a, 1), spot, "left where it was")
    t.eq(a.calls, {}, "nothing moved")
    wm2:show("in")
    t.eq(frame(a, 3), { x = 1300, y = 700, w = 400, h = 200 }, "the float's saved frame")
    t.eq(park.hidden(frame(a, 1), wm2:fulls()), false, "the tiles placed")
    t.eq(wm2:tiled("in", "A"), { 1, 2 })
end)

t.test("a window left at a park spot, whose workspace now shows, is placed as usual", function()
    local a = fake.new()
    a.add(1, { frame = spot_on_a(800, 600) })
    a.add(2, { app = "com.apple.systempreferences", pid = 300, frame = spot_on_a(600, 500) })
    local wm = wm_mod.new(a, { saved = {
        windows = {
            ["1"] = { ws = "in", mine = false, app = "com.example.app", pos = 1 },
            ["2"] = { ws = "in", mine = false, app = "com.apple.systempreferences" },
        },
        current = "in",
    } })
    wm:sync()
    wm:reconcile()
    wm:retile()
    t.eq(frame(a, 1), { x = 0, y = 25, w = 1920, h = 1055 }, "tiled")
    t.eq(park.hidden(frame(a, 2), wm:fulls()), false, "the float is back on screen")
    t.eq(next(wm.parked), nil)
end)

t.test("with a display to the right, a window parks clear of it", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, { frame = { x = 100, y = 100, w = 800, h = 600 } })
    a.add(2, { frame = { x = 2000, y = 100, w = 800, h = 600 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    t.eq(wm.windows[2].screen, "B")
    wm:show("2", nil, true)
    local f1, f2 = frame(a, 1), frame(a, 2)
    t.eq({ x = f1.x, y = f1.y }, { x = 1 - f1.w, y = 1079 }, "A's bottom-left, away from B")
    t.eq({ x = f2.x, y = f2.y }, { x = 3839, y = 1079 }, "B's bottom-right")
    wm:show("in")
    t.eq(wm.windows[1].screen, "A")
    t.eq(wm.windows[2].screen, "B", "each back on its own display")
    t.eq(wm:tiled("in", "B"), { 2 })
end)

t.test("a float still parked after a restart keeps its display", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, { app = "com.apple.systempreferences", pid = 300, frame = { x = 2000, y = 100, w = 600, h = 500 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    t.eq(wm:screen_of(1), "B")
    wm:show("2", nil, true)
    local wm2 = wm_mod.new(a, { saved = a.saved })
    wm2:sync()
    wm2:reconcile()
    t.eq(wm2.parked[1], true)
    t.eq(wm2.windows[1].screen, "B", "not the first display, which an off-screen frame would say")
    wm2:show("in")
    t.eq(wm2:screen_of(1), "B")
end)

t.test("a parked float still to be placed keeps its display as it comes back", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, { app = "com.apple.systempreferences", pid = 300, frame = { x = 2000, y = 100, w = 600, h = 500 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    wm:show("2", nil, true)
    t.eq(wm.parked[1], true)
    -- New float rules leave its placement to come, as set_float_rules does.
    wm.windows[1].place_pending = { w = 600, h = 500 }
    wm:show("in")
    t.eq(wm.parked[1], nil)
    t.eq(wm.windows[1].screen, "B")
    t.eq(frame(a, 1).x >= 1920, true, "placed on B, not the first display, which its off-screen frame would say")
end)

t.test("a parked float re-parked after a display appears keeps where you left it", function()
    local a = fake.new()
    a.add(1, { app = "com.apple.systempreferences", pid = 300, frame = { x = 300, y = 200, w = 600, h = 500 } })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    local before = frame(a, 1)
    before = { x = before.x, y = before.y, w = before.w, h = before.h }
    wm:show("2", nil, true)
    t.eq(wm.parked[1], true)
    -- A taller display to A's right shows A's bottom-right spot.
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1415 }, full = { x = 1920, y = 0, w = 1920, h = 1440 } }
    wm:reconcile()
    t.eq(park.hidden(frame(a, 1), wm:fulls()), true, "parked clear of B")
    wm:show("in")
    t.eq(frame(a, 1), before, "back where you left it, not at its old spot")
end)

t.test("a parked tile floated while hidden comes back at the float's size, not its tile's", function()
    local a, wm = setup(2)
    wm:show("2", nil, true)
    t.eq(wm.parked[1], true)
    -- As retitled() does for a popup whose title arrives late.
    wm:float_tile(1, { frame = { x = 0, y = 0, w = 400, h = 300 }, pid = a.wins[1].pid })
    wm:show("in")
    local f = frame(a, 1)
    t.eq({ w = f.w, h = f.h }, { w = 400, h = 300 }, "the float's own size")
    t.eq(park.hidden(f, wm:fulls()), false, "on screen")
end)

t.test("a bad hide setting fails at load, naming the setting", function()
    for _, v in ipairs({ "hidden", true, 1 }) do
        local ok, e = pcall(wm_mod.new, fake.new(), { hide = v })
        t.eq(ok, false, tostring(v))
        t.eq(tostring(e):find('hide must be "park" or "minimize"', 1, true) ~= nil, true, tostring(e))
    end
    t.eq(wm_mod.new(fake.new(), { hide = "minimize" }).hide, "minimize")
    t.eq(wm_mod.new(fake.new(), { hide = "park" }).hide, "park")
end)

t.done("wm")
