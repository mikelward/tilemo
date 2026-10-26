local t = require("t")
local fake = require("fake")
local wm_mod = require("tilemo.wm")
local ffm_mod = require("tilemo.ffm")

-- Two tiles: 1 on the left (x 0..1056), 2 on the right.
local function setup(opts)
    local a = fake.new()
    a.add(1, {})
    a.add(2, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    local ffm = ffm_mod.new(wm, a, opts)
    wm.ffm = ffm
    -- The pointer is where it last moved, as on a Mac, so a resync after a
    -- raise reads the same spot the moves did.
    local move = ffm.move
    function ffm.move(self, x, y, ...)
        a.px, a.py = x, y
        return move(self, x, y, ...)
    end
    a.focus_ = 1
    ffm:move(500, 500)
    a.calls = {}
    return a, wm, ffm
end

local function focuses(a)
    local out = {}
    for _, c in ipairs(a.calls) do
        if c:find("^focus") then
            out[#out + 1] = c
        end
    end
    return out
end

t.test("crossing into a window focuses it at once", function()
    local a, _, ffm = setup()
    ffm:move(1500, 500)
    t.eq(focuses(a), { "focus 2" })
end)

t.test("moving inside the window it was over does nothing, even after a key moved focus", function()
    local a, wm, ffm = setup()
    wm:act("focus", 1) -- Super+J to window 2, pointer still over 1
    a.calls = {}
    ffm:move(510, 505)
    t.eq(focuses(a), {})
end)

t.test("a menu or popover over the window stops the lookup", function()
    local a, _, ffm = setup()
    a.covers = { { x = 900, y = 400, w = 400, h = 300 } }
    ffm:move(1200, 500) -- on the menu, over window 2
    t.eq(focuses(a), {})
    ffm:move(1000, 500) -- still on the menu, back over window 1
    t.eq(focuses(a), {})
end)

t.test("nothing changes while a button is held or Super is held", function()
    local a, _, ffm = setup()
    a.buttons = true
    ffm:move(1500, 500)
    a.buttons = false
    ffm:move(1500, 510, true)
    t.eq(focuses(a), {})
end)

t.test("the menu bar and the Dock pause it", function()
    local a, _, ffm = setup()
    ffm:move(1500, 10) -- in the menu bar strip, above window 2
    t.eq(focuses(a), {})
end)

t.test("the screenshot picker keeps focus", function()
    local a, _, ffm = setup()
    a.front_app = "com.apple.screencaptureui"
    ffm:move(1500, 500)
    t.eq(focuses(a), {})
end)

t.test("tilemo's launcher keeps the keyboard", function()
    local a, wm, ffm = setup()
    wm.holding_keyboard = true
    ffm:move(1500, 500)
    t.eq(focuses(a), {})
end)

t.test("entering a window whose app has a dialog open focuses the dialog", function()
    local a, wm, ffm = setup()
    a.add(3, { subrole = "AXDialog", pid = 100, frame = { x = 0, y = 0, w = 300, h = 200 } })
    a.focus_ = 1
    wm:sync()
    -- Window 2 is the same app (pid 100); its dialog is centered on window 1.
    a.calls = {}
    ffm:move(1800, 900)
    t.eq(focuses(a), { "focus 3" })
end)

t.test("a window you floated still defers to its app's dialog, and keeps it on top", function()
    local a, wm, ffm = setup()
    a.focus_ = 2
    wm:act("toggle_float") -- window 2 (pid 100) floats where it was
    a.add(3, { subrole = "AXDialog", pid = 100, frame = { x = 1500, y = 100, w = 200, h = 100 } })
    wm:sync()
    t.eq(ffm:prefer_dialog(2), 3)
    t.eq(ffm:prefer_dialog(3), 3, "the dialog itself takes focus")
    a.calls = {}
    wm:focus_window(2)
    t.eq(a.calls[#a.calls], "raise 3")
end)

t.test("moving from a tile onto a float over it is a crossing", function()
    local a, wm, ffm = setup()
    a.add(3, { subrole = "AXDialog", pid = 300, frame = { x = 0, y = 0, w = 300, h = 200 } })
    wm:sync()
    a.focus_ = 1
    ffm:remember(1)
    a.calls = {}
    local f = a.wins[3].frame
    ffm:move(f.x + 10, f.y + 10)
    t.eq(focuses(a), { "focus 3" })
end)

t.test("a float from the other display's workspace over a tile is a crossing", function()
    local a, wm, ffm = setup()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(3, { subrole = "AXDialog", pid = 300, frame = { x = 2000, y = 100, w = 300, h = 200 } })
    wm:map_screens()
    wm:sync()
    t.eq(wm.windows[3].ws ~= wm.windows[2].ws, true)
    -- Dragged back over the edge, it now covers part of window 2.
    a.wins[3].frame = { x = 1800, y = 100, w = 300, h = 200 }
    a.focus_ = 2
    ffm:remember(2)
    a.calls = {}
    ffm:move(1850, 150)
    t.eq(focuses(a), { "focus 3" })
end)

t.test("a window moving under a still pointer isn't focused, even after a nudge", function()
    local a, wm, ffm = setup()
    a.px, a.py = 500, 500
    -- Swap the tiles: window 2 is now under the pointer.
    wm:act("swap_master")
    a.calls = {}
    ffm:move(501, 500)
    t.eq(focuses(a), {})
end)

t.test("one focus is in flight at a time; the last target follows", function()
    local a, wm, ffm = setup()
    a.add(3, { frame = { x = 0, y = 0, w = 10, h = 10 } })
    wm:sync()
    wm:retile()
    a.calls = {}
    a.focus_ = nil
    ffm:move(1500, 300)
    local first = focuses(a)[1]
    ffm:move(500, 500)
    t.eq(#focuses(a), 1, "the second waits")
    wm:focused(a.focus_)
    t.eq(#focuses(a), 2, "and goes once the first is confirmed")
    t.eq(first ~= focuses(a)[2], true)
end)

t.test("closing a window focuses the one under the pointer", function()
    local a, wm = setup()
    a.add(3, {})
    wm:sync()
    wm:retile()
    a.px, a.py = 1500, 900 -- window 3, bottom right
    wm:focused(1)
    a.focus_ = 2
    a.drop(2)
    wm:schedule()
    a.tick()
    t.eq(a.focus_, 3)
end)

t.test("turned off, it does nothing", function()
    local a, _, ffm = setup({ enabled = false })
    ffm:move(1500, 500)
    t.eq(focuses(a), {})
    t.eq(ffm:toggle(), true)
    ffm:move(1500, 510)
    t.eq(focuses(a), { "focus 2" })
end)

t.test("crossing back to the window being focused drops what was queued", function()
    local a, wm, ffm = setup()
    ffm:move(1500, 500) -- B, in flight
    ffm:move(500, 500) -- A, queued
    ffm:move(1500, 510) -- back to B
    a.focus_ = 2
    wm:focused(2)
    t.eq(focuses(a), { "focus 2" })
end)

t.test("a queued focus waits out the same pauses as the pointer", function()
    local a, wm, ffm = setup()
    ffm:move(1500, 500)
    ffm:move(500, 500)
    a.front_app = "com.apple.SecurityAgent"
    wm:focused(2)
    t.eq(focuses(a), { "focus 2" })
end)

t.test("a queued focus waits for an open menu or a held button", function()
    for _, field in ipairs({ "menu", "buttons" }) do
        local a, wm, ffm = setup()
        ffm:move(1500, 500)
        ffm:move(500, 500)
        a[field] = true
        wm:focused(2)
        t.eq(focuses(a), { "focus 2" }, field)
    end
end)

t.test("a queued focus waits while Super is held", function()
    local held = false
    local a, wm, ffm = setup({ super_held = function()
        return held
    end })
    ffm:move(1500, 500)
    ffm:move(500, 500)
    held = true
    wm:focused(2)
    t.eq(focuses(a), { "focus 2" })
end)

t.test("a queued focus waits while the pointer is over the menu bar", function()
    local a, wm, ffm = setup()
    ffm:move(1500, 500)
    ffm:move(500, 500) -- A, queued
    ffm:move(500, 10) -- up into the menu bar, outside every work area
    wm:focused(2)
    t.eq(focuses(a), { "focus 2" })
end)

t.test("a dialog over part of a float is a crossing from that float", function()
    local a, wm, ffm = setup()
    a.add(3, { subrole = "AXDialog", pid = 300, frame = { x = 0, y = 0, w = 600, h = 400 } })
    wm:sync()
    a.add(4, { subrole = "AXDialog", pid = 400, frame = { x = 0, y = 0, w = 200, h = 100 } })
    wm:sync()
    local f3, f4 = a.wins[3].frame, a.wins[4].frame
    a.focus_ = 3
    ffm:remember(3)
    a.calls = {}
    ffm:move(f4.x + 5, f4.y + 5)
    t.eq(focuses(a), { "focus 4" })
    t.eq(f3.w, 600)
end)

t.test("a float dragged away isn't still taken for being under the pointer", function()
    local a, wm, ffm = setup()
    a.add(3, { subrole = "AXDialog", pid = 300, frame = { x = 0, y = 0, w = 300, h = 200 } })
    wm:sync()
    local f = a.wins[3].frame
    a.focus_ = 3
    a.px, a.py = f.x + 10, f.y + 10
    ffm:remember(3)
    local d = wm:grab("move", f.x + 10, f.y + 10)
    a.px = f.x + 1010 -- the pointer drags the float along
    wm:drop(d, f.x + 1010, f.y + 10)
    t.eq(ffm.last, 3)
    a.calls = {}
    ffm:move(f.x + 12, f.y + 10) -- back where the float was: window 1
    t.eq(focuses(a), { "focus 1" })
end)

t.test("an open menu holds focus even after the pointer leaves it", function()
    local a, _, ffm = setup()
    a.menu = true
    ffm:move(1500, 500)
    t.eq(focuses(a), {})
    a.menu = false
    ffm:move(1500, 510)
    t.eq(focuses(a), { "focus 2" })
end)

t.test("focusing an older float brings it to the top of tilemo's float order", function()
    local a, wm, ffm = setup()
    a.add(3, { subrole = "AXDialog", pid = 300, frame = { x = 0, y = 0, w = 600, h = 400 } })
    a.add(4, { subrole = "AXDialog", pid = 400, frame = { x = 0, y = 0, w = 200, h = 100 } })
    wm:sync()
    t.eq(wm.floats, { 3, 4 })
    a.focus(3) -- an app switch brings it to the front
    wm:focused(3)
    t.eq(wm.floats, { 4, 3 })
    -- The pointer over the overlap is now on 3, which is on top.
    local f4 = a.wins[4].frame
    a.px, a.py = f4.x + 5, f4.y + 5
    ffm:resync()
    t.eq(ffm.last, 3)
end)

t.test("leaving for the desktop and coming back is a crossing", function()
    local a, wm, ffm = setup()
    a.wins[2].frame = { x = 1500, y = 25, w = 420, h = 1055 } -- a gap at 1056..1500
    ffm:move(1200, 500) -- the desktop
    wm:act("focus", 1) -- a key moves focus to 2
    a.calls = {}
    ffm:move(500, 500) -- back into 1
    t.eq(focuses(a), { "focus 1" })
end)

t.test("leaving for the desktop drops what was queued", function()
    local a, wm, ffm = setup()
    a.wins[2].frame = { x = 1500, y = 25, w = 420, h = 1055 } -- a gap at 1056..1500
    ffm:move(1600, 500) -- B, in flight
    ffm:move(500, 500) -- A, queued
    ffm:move(1200, 500) -- the desktop
    a.focus_ = 2
    wm:focused(2)
    t.eq(focuses(a), { "focus 2" })
end)

t.test("a window moving under the still pointer drops what was queued", function()
    local a, wm, ffm = setup()
    ffm:move(1500, 500) -- B, in flight
    a.px, a.py = 500, 500
    ffm:move(500, 500) -- A, queued
    wm:act("swap_master") -- B into the master tile, under the pointer
    a.focus_ = 2
    wm:focused(2)
    t.eq(focuses(a), { "focus 2" })
end)

t.test("an older focus's timeout doesn't settle a newer one for the same window", function()
    local a, wm, ffm = setup()
    ffm:move(1500, 500) -- B
    local first = a.timers[#a.timers]
    a.focus_ = 2
    wm:focused(2)
    ffm:move(500, 500) -- A
    a.focus_ = 1
    wm:focused(1)
    ffm:move(1500, 510) -- B again, in flight
    ffm:move(500, 510) -- A, queued behind it
    a.calls = {}
    first.fn()
    t.eq(focuses(a), {})
end)

t.test("raising a tile's floats re-reads which float is in front", function()
    local a, wm, ffm = setup()
    a.add(3, { subrole = "AXDialog", pid = 300 })
    a.add(4, { subrole = "AXDialog", pid = 400 })
    wm:sync()
    -- Two floats that overlap, 4 in front.
    a.wins[3].frame = { x = 100, y = 100, w = 400, h = 300 }
    a.wins[4].frame = { x = 300, y = 200, w = 400, h = 300 }
    wm:retile()
    ffm:move(650, 450) -- 4's own part
    a.focus_ = 4
    wm:focused(4)
    a.wins[1].pid = 300
    wm.windows[1].pid = 300
    wm:focus_window(1) -- a key focuses 3's app's tile, so 3 is raised last
    a.focus_ = 1
    wm:focused(1)
    a.calls = {}
    ffm:move(450, 350) -- into the overlap, where 3 is now in front
    t.eq(focuses(a), { "focus 3" })
end)

t.test("a late confirmation for an earlier window doesn't settle the one in flight", function()
    local a, wm, ffm = setup()
    a.add(3, {})
    wm:sync()
    wm:retile()
    ffm:move(1500, 300) -- B, in flight
    ffm:move(500, 500) -- A, queued
    a.tick() -- B's wait runs out: A goes
    ffm:move(1500, 900) -- C, queued behind A
    a.calls = {}
    wm:focused(2) -- B's confirmation, late
    t.eq(focuses(a), {})
end)

t.done("ffm")
