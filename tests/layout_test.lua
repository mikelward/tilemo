local t = require("t")
local layout = require("tilemo.layout")

local HD = { x = 0, y = 25, w = 1920, h = 1055 }
local UW = { x = 0, y = 25, w = 3440, h = 1415 }

t.test("a workspace starts in tile, or threecol on an ultrawide", function()
    t.eq(layout.new(1, HD).mode, "tile")
    t.eq(layout.new(1, UW).mode, "threecol")
end)

t.test("new windows join the end of the stack by default", function()
    local ws = layout.new(1, HD)
    layout.insert(ws, 1)
    layout.insert(ws, 2)
    layout.insert(ws, 3)
    t.eq(ws.order, { 1, 2, 3 })
end)

t.test("new_window places a window at the top, after the focused one, or as master", function()
    local function with(where, focused)
        local cfg = layout.copy(layout.defaults)
        cfg.new_window = where
        local ws = layout.new(1, HD, cfg)
        ws.order = { 1, 2, 3 }
        layout.insert(ws, 9, focused, cfg)
        return ws.order
    end
    t.eq(with("top"), { 1, 9, 2, 3 }, "top")
    t.eq(with("next", 2), { 1, 2, 9, 3 }, "next")
    t.eq(with("master"), { 9, 1, 2, 3 }, "master")
end)

t.test("inserting a window twice keeps one copy", function()
    local ws = layout.new(1, HD)
    layout.insert(ws, 1)
    layout.insert(ws, 1)
    t.eq(ws.order, { 1 })
end)

t.test("neighbor wraps both ways", function()
    t.eq(layout.neighbor({ 1, 2, 3 }, 3, 1), 1)
    t.eq(layout.neighbor({ 1, 2, 3 }, 1, -1), 3)
    t.eq(layout.neighbor({ 1, 2, 3 }, 7, 1), 1, "unknown window starts at the master")
    t.eq(layout.neighbor({}, 1, 1), nil)
end)

t.test("move swaps with the neighbor in the visible order", function()
    local ws = layout.new(1, HD)
    ws.order = { 1, 2, 3, 4 }
    -- 3 is minimized, so moving 2 down passes it.
    layout.move(ws, { 1, 2, 4 }, 2, 1)
    t.eq(ws.order, { 1, 4, 3, 2 })
end)

t.test("swap_master: others swap with the master, and the master with the one before it", function()
    local ws = layout.new(1, HD)
    ws.order = { 1, 2, 3 }
    layout.swap_master(ws, ws.order, 3)
    t.eq(ws.order, { 3, 2, 1 })
    layout.swap_master(ws, ws.order, 3)
    t.eq(ws.order, { 1, 2, 3 }, "back with 1, the master before it, not 2")
    layout.swap_master(ws, ws.order, 1)
    t.eq(ws.order, { 3, 2, 1 }, "and again")
    -- With the master before gone, the next, as dwm's zoom.
    ws.prev_master = 9
    layout.swap_master(ws, ws.order, 3)
    t.eq(ws.order, { 2, 3, 1 })
end)

t.test("mfact stays between 0.1 and 0.9", function()
    local ws = layout.new(1, HD)
    for _ = 1, 40 do
        layout.mfact(ws, 0.025)
    end
    t.eq(ws.opts.tile.mfact, 0.9)
end)

t.test("nmaster never drops below one", function()
    local ws = layout.new(1, HD)
    layout.nmaster(ws, -5)
    t.eq(ws.opts.tile.nmaster, 1)
end)

t.test("cycle steps through tile, threecol and twocol", function()
    local ws = layout.new(1, HD)
    layout.cycle(ws, 1)
    t.eq(ws.mode, "threecol")
    layout.cycle(ws, 1)
    t.eq(ws.mode, "twocol")
    layout.cycle(ws, 1)
    t.eq(ws.mode, "tile")
    layout.cycle(ws, -1)
    t.eq(ws.mode, "twocol")
end)

t.test("monocle toggles back to the mode before it", function()
    local ws = layout.new(1, UW)
    layout.toggle_monocle(ws)
    t.eq(ws.mode, "monocle")
    layout.toggle_monocle(ws)
    t.eq(ws.mode, "threecol")
end)

t.test("arrange keys tide's boxes by window", function()
    local ws = layout.new(1, HD)
    local boxes = layout.arrange(ws, HD, { 7, 8 })
    t.eq(boxes[7], { x = 0, y = 25, w = 1056, h = 1055 })
    t.eq(boxes[8], { x = 1056, y = 25, w = 864, h = 1055 })
end)

t.test("a lone window on an ultrawide is centered at 80%", function()
    local ws = layout.new(1, UW)
    local b = layout.arrange(ws, UW, { 7 })[7]
    t.eq(b.w, 2752)
    t.eq(b.x, 344)
end)

t.done("layout")
