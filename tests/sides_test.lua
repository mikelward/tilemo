-- Super+Left/Right and Super+Shift+Left/Right in the window manager, across
-- the fake's displays (direction_test.lua has the rule's geometry).
local t = require("t")
local fake = require("fake")
local wm_mod = require("tide.wm")

-- A second display to the right of A, bigger and 200 px higher.
local function add_b(a)
    a.screens_[2] = {
        uuid = "B",
        area = { x = 1920, y = -175, w = 2560, h = 1415 },
        full = { x = 1920, y = -200, w = 2560, h = 1440 },
    }
end

-- Windows `on_a` on A and `on_b` on B, each by its id.
local function setup(on_a, on_b)
    local a = fake.new()
    if on_b then
        add_b(a)
    end
    for _, id in ipairs(on_a) do
        a.add(id, {})
    end
    for _, id in ipairs(on_b or {}) do
        a.add(id, { frame = { x = 2000, y = 100, w = 800, h = 600 } })
    end
    local wm = wm_mod.new(a, { workspaces = { "in" } })
    wm:sync()
    wm:reconcile()
    wm:retile()
    a.calls = {}
    return a, wm
end

-- The ids in `ids`, left to right by where they are now.
local function left_to_right(a, ids)
    local out = { table.unpack(ids) }
    table.sort(out, function(p, q)
        return a.wins[p].frame.x < a.wins[q].frame.x
    end)
    return out
end

t.test("Super+Left and Right select the window that way on this display", function()
    local a, wm = setup({ 1, 2 })
    local l, r = table.unpack(left_to_right(a, { 1, 2 }))
    a.focus_ = l
    wm:act("select", 1)
    t.eq(a.focus_, r)
    wm:act("select", 1)
    t.eq(a.focus_, r, "nothing past the right edge with one display")
    wm:act("select", -1)
    t.eq(a.focus_, l)
end)

t.test("at a display's edge they go on to the next display that way", function()
    local a, wm = setup({ 1 }, { 2 })
    t.eq(wm.current, "in")
    t.eq(wm.windows[2].ws, "in", "one workspace across both displays")
    t.eq(wm.windows[2].screen, "B")
    a.focus_ = 1
    wm:act("select", 1)
    t.eq(a.focus_, 2)
    t.eq(wm:current_screen(), "B")
    wm:act("select", -1)
    t.eq(a.focus_, 1)
end)

t.test("at the edge they go to a window at the near side of the next display, not a taller one beyond", function()
    -- Tile on A: the master on the left, full height, and two stacked at
    -- A's right edge. From B's one window, as tall as A, the master would
    -- share the most height.
    local a, wm = setup({ 1, 2, 3 }, { 4 })
    local master = wm:part("in", "A").order[1]
    a.focus_ = 4
    wm:act("select", -1)
    t.eq(wm:current_screen(), "A")
    t.eq(a.focus_ ~= master, true, "a stack window, not the master")
    local f = a.wins[a.focus_].frame
    t.eq(f.x + f.w, 1920, "at A's right edge")
end)

t.test("a display that way with nothing on it takes the keys", function()
    local a, wm = setup({ 1 }, {})
    a.focus_ = 1
    wm:act("select", 1)
    t.eq(a.focus_, 1, "focus stays")
    t.eq(wm:current_screen(), "B")
end)

t.test("selecting the focused window back from an empty display brings the keys back", function()
    local a, wm = setup({ 1 }, {})
    a.focus_ = 1
    wm:act("select", 1)
    t.eq(wm:current_screen(), "B")
    wm:act("select", -1)
    t.eq(a.focus_, 1)
    t.eq(wm:current_screen(), "A", "the keys are back on A")
    wm:act("select", 1)
    t.eq(wm:current_screen(), "B", "and Super+Right goes on to B again")
end)

t.test("an app key for the focused window brings the keys back from an empty display", function()
    local a, wm = setup({ 1 }, {})
    a.focus_ = 1
    wm:act("select", 1)
    wm:activate(1)
    t.eq(wm:current_screen(), "A")
end)

t.test("Super+Shift+Left and Right swap the window with the one that way", function()
    local a, wm = setup({ 1, 2 })
    local l, r = table.unpack(left_to_right(a, { 1, 2 }))
    a.focus_ = l
    wm:act("move_side", 1)
    t.eq(left_to_right(a, { 1, 2 }), { r, l })
    t.eq(a.focus_, l)
end)

t.test("at the edge, the window moves to the next display, onto its near side, with focus", function()
    local a, wm = setup({ 1 }, { 2 })
    a.focus_ = 1
    wm:act("move_side", 1)
    t.eq(wm.windows[1].ws, "in", "it stays in its workspace")
    t.eq(wm.windows[1].screen, "B")
    t.eq(wm:part("in", "B").order, { 1, 2 })
    t.eq(wm:part("in", "A").order, {})
    t.eq(a.wins[1].minimized or false, false)
    t.eq(a.focus_, 1)
    t.eq(a.wins[1].frame.x >= 1920, true)
    t.eq(left_to_right(a, { 1, 2 }), { 1, 2 }, "moving right, it lands on the left")
    -- And back: moving left, it lands on A's right, here A's only tile.
    wm:act("move_side", -1)
    t.eq(wm.windows[1].screen, "A")
    t.eq(a.wins[1].frame.x < 1920, true)
end)

t.test("moving left onto a display lands the window on its right", function()
    local a, wm = setup({ 1 }, { 2 })
    a.focus_ = 2
    wm:act("move_side", -1)
    t.eq(wm.windows[2].screen, "A")
    t.eq(left_to_right(a, { 1, 2 }), { 1, 2 })
    t.eq(a.focus_, 2)
end)

t.test("past the last display, Super+Shift+Right does nothing", function()
    local a, wm = setup({ 1 }, { 2 })
    a.focus_ = 2
    wm:act("move_side", 1)
    t.eq(wm.windows[2].screen, "B")
end)

-- Whatever the layout, a window moved onto a display lands at the edge it
-- came in by, though tile order isn't left to right (threecol's third
-- tile is on the left).
for _, mode in ipairs({ "tile", "threecol", "twocol" }) do
    t.test("moving right onto a display in " .. mode .. " lands on its left edge", function()
        local a, wm = setup({ 1 }, { 2, 3, 4 })
        wm:part("in", "B").mode = mode
        wm:retile()
        a.focus_ = 1
        wm:act("move_side", 1)
        t.eq(wm.windows[1].screen, "B")
        t.eq(a.wins[1].frame.x, 1920)
        t.eq(a.focus_, 1)
    end)

    t.test("moving left onto a display in " .. mode .. " lands on its right edge", function()
        local a, wm = setup({ 1, 2, 3 }, { 4 })
        wm:part("in", "A").mode = mode
        wm:retile()
        a.focus_ = 4
        wm:act("move_side", -1)
        t.eq(wm.windows[4].screen, "A")
        local f = a.wins[4].frame
        t.eq(f.x + f.w, 1920)
        t.eq(a.focus_, 4)
    end)
end

t.test("layout keys act on the display Super+Right left the keys on, not the focused tile's", function()
    local a, wm = setup({ 1 }, {})
    a.focus_ = 1
    wm:act("select", 1)
    t.eq(wm:current_screen(), "B")
    wm:act("monocle")
    wm:act("mfact", 1)
    wm:act("nmaster", 1)
    t.eq(wm:part("in", "B").mode, "monocle")
    t.eq(wm:part("in", "A").mode, "tile", "A's part is left alone")
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.55)
    t.eq(wm:part("in", "A").opts.tile.nmaster, 1)
    wm:act("layout", "twocol")
    t.eq(wm:part("in", "B").mode, "twocol")
    t.eq(wm:part("in", "A").mode, "tile")
end)

t.test("after a switch to an empty workspace, layout keys act on it, not the one focus stayed on", function()
    local a, wm = setup({ 1 }, nil)
    a.focus_ = 1
    -- Window 1 is parked on "in", and the focus leaves it for Hammerspoon.
    wm:show("web", nil, true)
    t.eq(a.focus_, nil)
    wm:act("monocle")
    wm:act("mfact", 1)
    t.eq(wm:part("web", "A").mode, "monocle")
    t.eq(wm:part("in", "A").mode, "tile", "the hidden workspace's part is left alone")
    t.eq(wm:part("in", "A").opts.tile.mfact, 0.55)
end)

-- A float on A, focused: window 1 floated with Super+Shift+F, at `frame`.
-- `small` makes B half A's size, to A's right, instead of add_b's.
local function float_on_a(frame, small)
    local a, wm = setup({ 1 }, { 2 })
    if small then
        a.screens_[2] = {
            uuid = "B",
            area = { x = 1920, y = 25, w = 960, h = 515 },
            full = { x = 1920, y = 0, w = 960, h = 540 },
        }
    end
    a.focus_ = 1
    wm:act("toggle_float")
    a.wins[1].frame = frame
    return a, wm
end

t.test("Super+Shift+Right moves a float onto the next display at the same spot, with focus", function()
    -- A twentieth across A's area and a fifth down.
    local a, wm = float_on_a({ x = 96, y = 25 + 211, w = 400, h = 300 })
    wm:act("move_side", 1)
    t.eq(a.wins[1].frame, { x = 1920 + 128, y = -175 + 283, w = 400, h = 300 }, "the same share of B's area")
    t.eq(wm.windows[1].floating, true, "still floating")
    t.eq(wm.windows[1].ws, "in", "in its workspace")
    t.eq(wm.windows[1].screen, "B", "on B's part of it")
    t.eq(wm:part("in", "B").order, { 2 }, "not tiled there")
    t.eq(a.focus_, 1, "focus follows it")
    wm:act("move_side", 1)
    t.eq(a.wins[1].frame.x, 2048, "past the last display, nothing")
    t.eq(wm.windows[1].screen, "B")
    wm:act("move_side", -1)
    t.eq(a.wins[1].frame, { x = 96, y = 25 + 211, w = 400, h = 300 }, "and back")
    t.eq(wm.windows[1].screen, "A")
end)

t.test("a float in the top left of a display lands in the top left of a smaller one", function()
    local a, wm = float_on_a({ x = 96, y = 25 + 211, w = 400, h = 300 }, true)
    wm:act("move_side", 1)
    t.eq(a.wins[1].frame, { x = 1920 + 48, y = 25 + 103, w = 400, h = 300 })
end)

t.test("a float in the bottom right of a display lands in the bottom right of a smaller one", function()
    local a, wm = float_on_a({ x = 1420, y = 680, w = 500, h = 400 }, true)
    wm:act("move_side", 1)
    t.eq(a.wins[1].frame, { x = 1920 + 960 - 500, y = 540 - 400, w = 500, h = 400 }, "held at B's corner")
end)

t.test("a float too big for the next display shrinks to fit inside it", function()
    local a, wm = float_on_a({ x = 100, y = 100, w = 1200, h = 800 }, true)
    wm:act("move_side", 1)
    t.eq(a.wins[1].frame, { x = 1920, y = 25, w = 960, h = 515 }, "B's whole area")
    t.eq(wm.windows[1].floating, true, "still floating")
end)

t.done("sides")
