local t = require("t")
local mouse = require("timo.mouse")

local F = { x = 100, y = 100, w = 400, h = 300 }

t.test("a move drag follows the pointer", function()
    local d = mouse.grab("move", F, 150, 150)
    t.eq(mouse.update(d, 250, 120), { x = 200, y = 70, w = 400, h = 300 })
end)

t.test("a resize moves the edges nearest where it started", function()
    local d = mouse.grab("resize", F, 450, 380) -- bottom right
    t.eq(mouse.update(d, 500, 400), { x = 100, y = 100, w = 450, h = 320 })
    d = mouse.grab("resize", F, 120, 120) -- top left
    t.eq(mouse.update(d, 100, 90), { x = 80, y = 70, w = 420, h = 330 })
end)

t.test("a resize never goes below the minimum size", function()
    local d = mouse.grab("resize", F, 450, 380)
    local b = mouse.update(d, -1000, -1000)
    t.eq(b.w, mouse.MIN)
    t.eq(b.h, mouse.MIN)
    d = mouse.grab("resize", F, 120, 120)
    b = mouse.update(d, 2000, 2000)
    t.eq(b, { x = 400, y = 300, w = 100, h = 100 }, "the far edges stay put")
end)

local AREA = { x = 0, y = 0, w = 1000, h = 800 }

t.test("in tile, dragging the master's right edge sets the split", function()
    local old = { x = 0, y = 0, w = 550, h = 800 }
    local new = { x = 0, y = 0, w = 600, h = 800 }
    t.eq(mouse.mfact_for("tile", { nmaster = 1 }, 1, 3, AREA, old, new), 0.6)
end)

t.test("in tile, dragging a stack window's left edge sets the split", function()
    local old = { x = 550, y = 0, w = 450, h = 400 }
    local new = { x = 500, y = 0, w = 500, h = 400 }
    t.eq(mouse.mfact_for("tile", { nmaster = 1 }, 2, 3, AREA, old, new), 0.5)
end)

t.test("an edge the split doesn't control changes nothing", function()
    local old = { x = 550, y = 0, w = 450, h = 400 }
    local new = { x = 550, y = 0, w = 450, h = 450 }
    t.eq(mouse.mfact_for("tile", { nmaster = 1 }, 2, 3, AREA, old, new), nil)
    t.eq(mouse.mfact_for("monocle", {}, 1, 3, AREA, old, new), nil)
end)

t.test("in threecol, a master or side width sets the split", function()
    local old = { x = 250, y = 0, w = 500, h = 800 }
    t.eq(mouse.mfact_for("threecol", { nmaster = 1 }, 1, 3, AREA, old, { x = 200, y = 0, w = 600, h = 800 }), 0.6)
    t.eq(mouse.mfact_for("threecol", { nmaster = 1 }, 2, 3, AREA, { x = 750, y = 0, w = 250, h = 800 },
        { x = 700, y = 0, w = 300, h = 800 }), 0.4)
end)

t.test("in threecol, a dragged master edge lands where it was dropped", function()
    -- A master spanning 250..750 whose right edge goes to 800, the left
    -- staying put: recentered at 0.6, its right edge is at 800.
    local old = { x = 250, y = 0, w = 500, h = 800 }
    local new = { x = 250, y = 0, w = 550, h = 800 }
    t.eq(mouse.mfact_for("threecol", { nmaster = 1 }, 1, 3, AREA, old, new), 0.6)
    new = { x = 150, y = 0, w = 600, h = 800 }
    t.eq(mouse.mfact_for("threecol", { nmaster = 1 }, 1, 3, AREA, old, new), 0.7, "left edge to 150")
end)

t.test("in threecol, a left-hand stack window's inner edge is its right", function()
    local old = { x = 0, y = 0, w = 250, h = 800 }
    local new = { x = 0, y = 0, w = 200, h = 800 }
    t.eq(mouse.mfact_for("threecol", { nmaster = 1 }, 3, 3, AREA, old, new), 0.6)
end)

t.test("in twocol, the last master's right edge sets the split", function()
    local old = { x = 360, y = 0, w = 360, h = 800 }
    local new = { x = 360, y = 0, w = 440, h = 800 }
    t.eq(mouse.mfact_for("twocol", { nmaster = 2 }, 2, 3, AREA, old, new), 0.8)
end)

t.test("in twocol, a later master's left edge sets the split too", function()
    -- Two masters at 0.72: the second spans 360..720. Its left edge to 350
    -- puts the boundary at 0.70 / 2.
    local old = { x = 360, y = 0, w = 360, h = 800 }
    local new = { x = 350, y = 0, w = 370, h = 800 }
    t.eq(mouse.mfact_for("twocol", { nmaster = 2 }, 2, 3, AREA, old, new), 0.7)
end)

t.test("three columns with no stack: dragging a master's edge sets no split", function()
    local area = { x = 0, y = 0, w = 1000, h = 800 }
    local old = { x = 0, y = 0, w = 1000, h = 400 }
    local new = { x = 0, y = 0, w = 900, h = 400 }
    t.eq(mouse.mfact_for("threecol", { nmaster = 2 }, 1, 2, area, old, new), nil)
end)

t.test("dragging a lone window's edge sets its width, kept centered", function()
    local area = { x = 0, y = 0, w = 1000, h = 800 }
    local old = { x = 0, y = 0, w = 1000, h = 800 }
    t.eq(mouse.single_width_for(area, old, { x = 0, y = 0, w = 800, h = 800 }), 0.6)
    t.eq(mouse.single_width_for(area, old, { x = 150, y = 0, w = 850, h = 800 }), 0.7)
    t.eq(mouse.single_width_for(area, old, { x = 0, y = 10, w = 1000, h = 700 }), nil)
end)

t.done("mouse")
