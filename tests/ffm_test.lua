local t = require("t")
local fake = require("fake")
local wm_mod = require("tide.wm")
local ffm_mod = require("tide.ffm")

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

t.test("a parked window's sliver in the display's corner isn't focused", function()
    local a, wm, ffm = setup()
    wm:show("2", nil, true)
    a.calls = {}
    -- Both windows are parked with their top-left 1 pt inside the corner.
    ffm:move(1919, 1079)
    t.eq(focuses(a), {})
    t.eq(wm.current, "2", "its workspace doesn't come along")
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

t.test("tide's launcher keeps the keyboard", function()
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

t.test("a float from the other display over a tile is a crossing", function()
    local a, wm, ffm = setup()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(3, { subrole = "AXDialog", pid = 300, frame = { x = 2000, y = 100, w = 300, h = 200 } })
    wm:map_screens()
    wm:sync()
    t.eq(wm.windows[3].screen, "B")
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

t.test("focusing an older float brings it to the top of tide's float order", function()
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

local function has(list, want)
    for _, v in ipairs(list) do
        if v == want then
            return true
        end
    end
    return false
end

t.test("Notification Center's window isn't moved or focused, and the pointer over it stays put", function()
    local a, wm, ffm = setup()
    a.calls = {}
    -- Over the right half of window 2, and in front of it.
    a.add(3, {
        app = "com.apple.notificationcenterui", pid = 300, title = "Notification Center",
        size_settable = false, frame = { x = 1500, y = 25, w = 420, h = 1055 },
    })
    wm:sync()
    ffm:move(1700, 500)
    t.eq(has(a.calls, "frame 3"), false, "not moved")
    t.eq(focuses(a), {})
end)

t.test("a Chrome popup isn't moved, and entering its window focuses the window", function()
    local a, wm, ffm = setup()
    a.calls = {}
    -- Chrome's find bar: a window of its own, AXUnknown and a fixed size,
    -- at the top right of window 2, the same app's.
    a.add(3, { subrole = "AXUnknown", pid = 100, size_settable = false, frame = { x = 1600, y = 60, w = 300, h = 40 } })
    wm:sync()
    ffm:move(1500, 500)
    t.eq(has(a.calls, "frame 3"), false, "not moved")
    t.eq(focuses(a), { "focus 2" })
end)

-- Three tiles of three apps, 1 focused long enough ago that only what
-- tide asks for since counts for the focus guard (SPEC.md §14.1). Returns
-- a point inside each window too.
local function three_apps()
    local a = fake.new()
    a.add(1, { app = "a", pid = 1 })
    a.add(2, { app = "b", pid = 2 })
    a.add(3, { app = "c", pid = 3 })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    local ffm = ffm_mod.new(wm, a)
    wm.ffm = ffm
    local move = ffm.move
    function ffm.move(self, x, y, ...)
        a.px, a.py = x, y
        return move(self, x, y, ...)
    end
    local function inside(id)
        local f = a.wins[id].frame
        return f.x + f.w // 2, f.y + f.h // 2
    end
    ffm:move(inside(1))
    wm:focused(1)
    a.clock = 100
    a.calls = {}
    return a, wm, ffm, inside
end

local function marked(wm, id)
    for _, m in ipairs(wm.attention:list()) do
        if m.id == id then
            return true
        end
    end
    return false
end

t.test("crossing two other apps' windows quickly ends in the second, not back in the first", function()
    local a, wm, ffm, inside = three_apps()
    ffm:move(inside(2)) -- in flight
    ffm:move(inside(3)) -- queued
    wm:focused(2) -- macOS confirms 2, so 3 goes
    wm:focused(3)
    t.eq(focuses(a), { "focus 2", "focus 3" })
    t.eq(a.focused(), 3)
    t.eq(marked(wm, 2), false, "2 isn't taken for a thief")
end)

t.test("a focus macOS confirms after its wait ran out isn't taken for theft", function()
    local a, wm, ffm, inside = three_apps()
    ffm:move(inside(2)) -- in flight
    ffm:move(inside(3)) -- queued
    a.tick() -- 2's wait runs out, so 3 goes
    wm:focused(2) -- 2's report, late
    wm:focused(3)
    t.eq(focuses(a), { "focus 2", "focus 3" })
    t.eq(a.focused(), 3)
    t.eq(marked(wm, 2), false)
end)

-- macOS won't raise another app's window back over the app that was just
-- focused (SPEC.md §13), so focusing a tile under a float buries the float
-- for good. Focus follows mouse leaves such a tile alone; a click focuses it.
t.test("a tile under another app's float isn't focused by the pointer", function()
    local a, wm, ffm = setup()
    a.add(3, { subrole = "AXDialog", app = "com.example.other", pid = 300, frame = { x = 1400, y = 300, w = 300, h = 200 } })
    wm:sync()
    a.wins[3].frame = { x = 1400, y = 300, w = 300, h = 200 }
    a.focus_ = 1
    ffm:remember(1)
    a.calls = {}
    ffm:move(1200, 900) -- window 2, outside the float over it
    t.eq(focuses(a), {})
    t.eq(a.ordered()[1], 3, "the float stays in front")
end)

t.test("a tile no float covers is still focused", function()
    local a, wm, ffm = setup()
    a.add(3, { subrole = "AXDialog", app = "com.example.other", pid = 300, frame = { x = 100, y = 300, w = 300, h = 200 } })
    wm:sync()
    a.wins[3].frame = { x = 100, y = 300, w = 300, h = 200 }
    a.focus_ = 1
    ffm:remember(1)
    a.calls = {}
    ffm:move(1500, 900)
    t.eq(focuses(a), { "focus 2" })
end)

t.test("Hammerspoon's own floats don't hold focus back: they keep a floating level", function()
    local a, wm, ffm = setup()
    a.add(3, { app = "org.hammerspoon.Hammerspoon", title = "Hammerspoon Console", pid = 300, frame = { x = 1400, y = 300, w = 300, h = 200 } })
    wm:sync()
    a.wins[3].frame = { x = 1400, y = 300, w = 300, h = 200 }
    t.eq(wm.windows[3].floating, true)
    a.focus_ = 1
    ffm:remember(1)
    a.calls = {}
    ffm:move(1200, 900)
    t.eq(focuses(a), { "focus 2" })
end)

t.test("Hammerspoon's Preferences, with no floating level, holds focus back", function()
    local a, wm, ffm = setup()
    a.add(3, { app = "org.hammerspoon.Hammerspoon", title = "Hammerspoon Preferences", pid = 300, frame = { x = 1400, y = 300, w = 300, h = 200 } })
    wm:sync()
    a.wins[3].frame = { x = 1400, y = 300, w = 300, h = 200 }
    t.eq(wm.windows[3].floating, true)
    a.focus_ = 1
    ffm:remember(1)
    a.calls = {}
    ffm:move(1200, 900)
    t.eq(focuses(a), {})
end)

t.test("a queued focus skips a tile under another app's float", function()
    local a, wm, ffm = setup()
    a.add(3, { subrole = "AXDialog", app = "com.example.other", pid = 300, frame = { x = 1400, y = 300, w = 300, h = 200 } })
    wm:sync()
    a.wins[3].frame = { x = 1400, y = 300, w = 300, h = 200 }
    a.focus_ = 2
    ffm:remember(2)
    a.calls = {}
    ffm:move(500, 500) -- window 1, in flight
    ffm:move(1200, 900) -- back over window 2, under the float
    a.focus_ = 1
    wm:focused(1)
    t.eq(focuses(a), { "focus 1" })
end)

-- The report: an app floated by a rule sits in the top left, in front of
-- tile B, another app's, which covers that corner and more. Tile C is a
-- third app's, on the right. `how` is "start" for a rule the window opened
-- under, or "later" for one added on the Floating page after it tiled
-- (wm.set_float_rules). `more` adds windows before the float is placed.
-- `config` is start()'s, over the rules. Returns a point on B outside the
-- float, and a point on the float.
local function rule_float(how, more, config)
    local a = fake.new()
    local float_rule = { app = "com.example.a", action = "float" }
    a.add(1, { app = "com.example.b", pid = 2 })
    a.add(2, { app = "com.example.c", pid = 3 })
    if how == "later" then
        a.add(3, { app = "com.example.a", pid = 1 })
    end
    config = config or {}
    config.rules = how == "start" and { float_rule } or nil
    local wm = wm_mod.new(a, config)
    wm:sync()
    wm:retile()
    if how == "start" then
        a.add(3, { app = "com.example.a", pid = 1 })
        wm:sync()
    else
        wm:set_float_rules({ float_rule })
    end
    t.eq(wm.windows[3].floating, true, "the rule floats it")
    if more then
        more(a, wm)
    end
    a.wins[3].frame = { x = 0, y = 25, w = 600, h = 400 }
    a.raise(3)
    wm:retile()
    local ffm = ffm_mod.new(wm, a)
    wm.ffm = ffm
    local move = ffm.move
    function ffm.move(self, x, y, ...)
        a.px, a.py = x, y
        return move(self, x, y, ...)
    end
    t.eq(a.ordered()[1], 3, "the float is in front")
    local b = a.wins[1].frame
    t.eq(b.x < 600 and b.y < 425, true, "B covers the float's corner")
    return a, wm, ffm, { 700, 800 }, { 100, 100 }
end

t.test("a tile under a rule's float isn't focused by the pointer, however it gets there", function()
    for _, how in ipairs({ "start", "later" }) do
        -- From the float onto B.
        local a, wm, ffm, onb, onf = rule_float(how)
        ffm:move(onf[1], onf[2])
        a.focus_ = 3
        wm:focused(3)
        a.calls = {}
        ffm:move(onb[1], onb[2])
        t.eq(focuses(a), {}, how .. ": from the float")
        t.eq(a.ordered()[1], 3, how .. ": the float stays in front")
        -- From C, through a gap at the display's edge, onto B.
        a, wm, ffm, onb = rule_float(how)
        ffm:move(1500, 500)
        a.focus_ = 2
        wm:focused(2)
        a.calls = {}
        ffm:move(1500, 1079) -- below the work area: the Dock
        ffm:move(1500, 500)
        a.wins[1].frame.w = a.wins[1].frame.w - 100 -- a gap beside B
        ffm:move(a.wins[1].frame.w + 50, 500)
        ffm:move(onb[1], onb[2])
        t.eq(focuses(a), {}, how .. ": from the gap")
        -- After the stacking changed under a still pointer.
        a, wm, ffm, onb = rule_float(how)
        a.focus_ = 2
        ffm:move(1500, 500)
        a.px, a.py = onb[1], onb[2]
        wm:raise_floats(wm.current) -- resyncs
        a.calls = {}
        ffm:move(onb[1] + 1, onb[2])
        ffm:move(onb[1] + 2, onb[2])
        t.eq(focuses(a), {}, how .. ": after a resync")
    end
end)

-- B defers to its app's dialog (prefer_dialog), but B is still the window
-- under the pointer: focusing the dialog activates B's app, which can bring
-- B forward with it.
t.test("B's own dialog isn't focused either while B is under another app's float", function()
    local a, wm, ffm, onb = rule_float("later", function(a, wm)
        -- B's app's dialog, on the right, over C.
        a.add(4, { subrole = "AXDialog", app = "com.example.b", pid = 2 })
        wm:sync()
    end)
    a.wins[4].frame = { x = 1400, y = 600, w = 300, h = 200 }
    a.focus_ = 2
    ffm:move(1500, 300) -- C
    a.calls = {}
    ffm:move(onb[1], onb[2])
    t.eq(ffm:prefer_dialog(1), 4, "B defers to its dialog")
    t.eq(focuses(a), {})
end)

t.test("another app's dialog clear of the float is still focused", function()
    local a, wm, ffm, _, onf = rule_float("later", function(a, wm)
        a.add(4, { subrole = "AXDialog", app = "com.example.c", pid = 3 })
        wm:sync()
    end)
    a.wins[4].frame = { x = 1400, y = 600, w = 300, h = 200 }
    a.raise(4)
    ffm:move(onf[1], onf[2])
    a.focus_ = 3
    wm:focused(3)
    a.calls = {}
    ffm:move(1500, 700) -- C's dialog
    t.eq(focuses(a), { "focus 4" })
end)

t.test("closing a window passes over the one under the pointer if it would bury a float", function()
    local a, wm, ffm, onb = rule_float("later", function(a, wm)
        a.add(4, { app = "com.example.d", pid = 4 })
        wm:sync()
    end)
    wm:retile()
    a.wins[3].frame = { x = 0, y = 25, w = 600, h = 400 }
    a.raise(3)
    a.focus(4)
    wm:focused(4)
    a.px, a.py = onb[1], onb[2]
    a.calls = {}
    a.drop(4)
    wm:schedule()
    a.tick()
    t.eq(a.ordered()[1], 3, "the float stays in front")
    t.eq(a.focus_ ~= 1, true, "B isn't focused")
    t.eq(a.focus_ ~= nil, true, "something has focus")
end)

-- The report's layout with B, the tile under the float, the window you
-- were in: focused by a click, then the float went back over it, as tide
-- raises the floats after any focus.
local function b_was_yours(config)
    local a, wm, ffm, onb, onf = rule_float("later", nil, config)
    a.focus_ = 1
    wm:focused(1)
    t.eq(a.ordered()[1], 3, "the float went back in front")
    t.eq(wm.mru[wm.current][1], 1, "B is the last used")
    a.calls = {}
    return a, wm, ffm, onb, onf
end

local function focused_b(a)
    for _, c in ipairs(a.calls) do
        if c == "focus 1" then
            return true
        end
    end
    return false
end

t.test("switching back to a workspace passes over a tile under another app's float", function()
    local a, wm = b_was_yours()
    local home = wm.current
    wm:show("2", nil, true)
    a.calls = {}
    wm:show(home)
    t.eq(focused_b(a), false, "B isn't focused")
    t.eq(a.focus_ ~= nil, true, "something has focus")
    t.eq(a.ordered()[1], 3, "the float stays in front")
end)

t.test("a window restored after a switch isn't focused if it would bury another app's float", function()
    -- A slow restore is minimize mode's.
    local a, wm = b_was_yours({ hide = "minimize" })
    local home = wm.current
    wm:show("2", nil, true)
    local unmin = a.unminimize
    a.unminimize = function(id)
        a.calls[#a.calls + 1] = "unminimize " .. id
    end
    a.calls = {}
    wm:show(home)
    t.eq(wm.focus_after, 1, "B is waited for")
    a.unminimize = unmin
    for _, id in ipairs({ 1, 2, 3 }) do
        a.wins[id].minimized = false
    end
    a.raise(3)
    wm:unminimized(1)
    t.eq(focused_b(a), false, "B isn't focused")
    t.eq(a.focus_ ~= nil, true, "something has focus")
end)

t.test("minimizing a window passes over a tile under another app's float", function()
    local a, wm = b_was_yours()
    wm:focus_window(2) -- a key moves focus to C
    wm:focused(2)
    a.raise(3)
    wm.mru[wm.current] = { 2, 1, 3 }
    a.calls = {}
    wm:act("minimize")
    t.eq(focused_b(a), false, "B isn't focused")
    t.eq(a.focus_, 3)
end)

t.test("focus handed back from a thief passes over a tile under another app's float", function()
    local a, wm = b_was_yours()
    a.add(4, { app = "com.example.d", pid = 4, frame = { x = 1500, y = 900, w = 100, h = 100 } })
    wm:sync()
    a.focus_ = 1
    wm:focused(1)
    a.raise(3)
    a.clock = 100
    a.calls = {}
    a.focus_ = 4 -- an app activating itself
    wm:focused(4)
    t.eq(focused_b(a), false, "B isn't focused")
    t.eq(a.focus_ ~= 4, true, "the thief doesn't keep it")
    t.eq(a.ordered()[1], 3, "the float stays in front")
end)

-- The thief is on the same workspace, next in its last-used list after
-- the tile under the float: focus mustn't go to it, or tide's own ask
-- would let its next grab through the guard.
t.test("focus handed back past a tile under a float never goes to the thief", function()
    local a, wm = b_was_yours()
    a.add(4, { app = "com.example.d", pid = 4, frame = { x = 1500, y = 900, w = 100, h = 100 } })
    wm:sync()
    a.focus_ = 1
    wm:focused(1)
    a.raise(3)
    wm.mru[wm.current] = { 1, 4, 3, 2 }
    a.clock = 100
    a.calls = {}
    a.focus_ = 4 -- an app activating itself
    wm:focused(4)
    t.eq(a.calls[1], "focus 3", "the float, the next that will do")
    for _, q in ipairs(wm.asked) do
        t.eq(q.id ~= 4 and q.app ~= "com.example.d", true, "the thief isn't asked for")
    end
end)

t.test("going back to a window no float covers is unchanged", function()
    local a, wm = b_was_yours()
    a.wins[3].frame = { x = 1500, y = 900, w = 100, h = 100 } -- over C, clear of B
    wm:focus_unburied(1)
    t.eq(a.calls[1], "focus 1")
end)

t.test("with nothing else to go to, the tile under the float is focused after all", function()
    local a, wm = b_was_yours()
    a.wins[2].minimized = true -- C, in the tray
    wm.mru[wm.current] = { 1, 2 } -- the float never had focus
    wm:focus_unburied(1)
    t.eq(a.calls[1], "focus 1")
end)

-- How many times Accessibility was asked what's under the pointer.
local function counting(a)
    local real = a.window_at
    a.asked = 0
    function a.window_at(...)
        a.asked = a.asked + 1
        return real(...)
    end
end

t.test("over one of tide's own windows, nothing asks what's under the pointer", function()
    local a, wm, ffm = setup()
    counting(a)
    -- The settings window, over window 2.
    wm:own_window("settings", function()
        return { x = 1200, y = 300, w = 400, h = 400 }
    end)
    ffm:move(1300, 500)
    t.eq(a.asked, 0)
    t.eq(focuses(a), {})
    a.px, a.py = 1300, 500
    ffm:resync()
    t.eq(a.asked, 0, "nor a resync after a raise")
end)

t.test("a window of tide's that just went still counts a moment, while macOS takes it away", function()
    local a, wm, ffm = setup()
    counting(a)
    wm:own_window("launcher", { x = 0, y = 0, w = 3000, h = 2000 })
    a.clock = 100
    wm:own_window("launcher", nil)
    a.px, a.py = 1500, 500
    a.clock = 100.2
    ffm:resync()
    t.eq(a.asked, 0, "just closed")
    a.clock = 101
    ffm:resync()
    t.eq(a.asked, 1, "gone a second later")
end)

t.test("a resync off every work area, over the bar or the Dock, asks nothing either", function()
    local a, wm, ffm = setup()
    counting(a)
    a.px, a.py = 500, -5
    ffm:resync()
    t.eq(a.asked, 0)
end)

t.test("a resync skipped off the work area still forgets the window it was over", function()
    local a, wm, ffm = setup()
    ffm:move(500, -5) -- up into the bar, from window 1
    wm:act("focus", 1) -- Super+J to window 2; the raise resyncs
    a.calls = {}
    ffm:move(500, 500) -- back down into window 1
    t.eq(focuses(a), { "focus 1" })
end)

t.test("the pointer onto another display's empty desktop takes the keys there", function()
    local a, wm, ffm = setup()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    t.eq(wm:current_screen(), "A")
    a.pointer_uuid = "B"
    ffm:move(2500, 500)
    t.eq(wm:current_screen(), "B", "a launch opens there")
    t.eq(focuses(a), {}, "focus stays put")
    -- Back into a window on A: focus follows, and the keys with it.
    a.pointer_uuid = "A"
    ffm:move(1500, 500)
    t.eq(focuses(a), { "focus 2" })
    t.eq(wm:current_screen(), "A")
end)

t.test("back from an empty desktop into the window that kept focus, the keys come back too", function()
    local a, wm, ffm = setup()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.pointer_uuid = "B"
    ffm:move(2500, 500)
    t.eq(wm:current_screen(), "B")
    a.pointer_uuid = "A"
    ffm:move(500, 500) -- window 1, focused all along
    t.eq(focuses(a), {})
    t.eq(wm:current_screen(), "A")
end)

t.done("ffm")
