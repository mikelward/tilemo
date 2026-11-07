local t = require("t")
local park = require("tide.park")

local A = { x = 0, y = 0, w = 1920, h = 1080 }
local size = { w = 800, h = 600 }

-- How much of `box` shows on display `d`, as width times height.
local function shown(box, d)
    local w = math.min(box.x + box.w, d.x + d.w) - math.max(box.x, d.x)
    local h = math.min(box.y + box.h, d.y + d.h) - math.max(box.y, d.y)
    return math.max(0, w) * math.max(0, h)
end

t.test("one display: the window's top-left sits 1 pt inside the bottom-right corner", function()
    local box, corner = park.spot(A, { A }, size)
    t.eq(box, { x = 1919, y = 1079, w = 800, h = 600 })
    t.eq(corner, "bottom-right")
    t.eq(shown(box, A), 1, "a 1 pt sliver shows")
end)

t.test("a display to the right: the window parks bottom-left, clear of it", function()
    local B = { x = 1920, y = 0, w = 2560, h = 1440 }
    local box, corner = park.spot(A, { A, B }, size)
    t.eq(corner, "bottom-left")
    t.eq(box, { x = 1 - 800, y = 1079, w = 800, h = 600 })
    t.eq(shown(box, B), 0, "nothing on the display beside")
    t.eq(shown(box, A), 1, "a sliver on its own")
end)

t.test("the display on the right parks bottom-right, away from the one on its left", function()
    local B = { x = 1920, y = 0, w = 2560, h = 1440 }
    local box, corner = park.spot(B, { A, B }, size)
    t.eq(corner, "bottom-right")
    t.eq(box, { x = 4479, y = 1439, w = 800, h = 600 })
    t.eq(shown(box, A), 0)
end)

t.test("a display below: the window parks top-right, clear of it", function()
    local B = { x = 0, y = 1080, w = 1920, h = 1080 }
    local box, corner = park.spot(A, { A, B }, size)
    -- Bottom-left would reach down onto B too.
    t.eq(corner, "top-right")
    t.eq(box, { x = 1919, y = 1 - 600, w = 800, h = 600 })
    t.eq(shown(box, B), 0)
end)

t.test("a display wedged in, with others right and below, parks top-left", function()
    local right = { x = 1920, y = 0, w = 1920, h = 1080 }
    local below = { x = 0, y = 1080, w = 1920, h = 1080 }
    local box, corner = park.spot(A, { A, right, below }, size)
    t.eq(corner, "top-left")
    t.eq(box, { x = 1 - 800, y = 1 - 600, w = 800, h = 600 })
    t.eq(shown(box, right) + shown(box, below), 0)
end)

t.test("with every corner against another display, it falls back to bottom-right", function()
    local around = { A }
    for _, d in ipairs({
        { x = -1920, y = -1080 }, { x = 0, y = -1080 }, { x = 1920, y = -1080 },
        { x = -1920, y = 0 }, { x = 1920, y = 0 },
        { x = -1920, y = 1080 }, { x = 0, y = 1080 }, { x = 1920, y = 1080 },
    }) do
        around[#around + 1] = { x = d.x, y = d.y, w = 1920, h = 1080 }
    end
    local box, corner = park.spot(A, around, size)
    t.eq(corner, "bottom-right")
    t.eq(box, { x = 1919, y = 1079, w = 800, h = 600 })
end)

t.test("a display that only touches at an edge doesn't count as overlapped", function()
    -- B starts just past where a bottom-right park ends.
    local B = { x = 1919 + 800, y = 0, w = 1000, h = 1080 }
    local _, corner = park.spot(A, { A, B }, size)
    t.eq(corner, "bottom-right")
end)

t.test("a parked frame reads as hidden; one on screen doesn't", function()
    local box = park.spot(A, { A }, size)
    t.eq(park.hidden(box, { A }), true, "parked")
    t.eq(park.hidden({ x = 100, y = 100, w = 800, h = 600 }, { A }), false, "on screen")
    t.eq(park.hidden({ x = 1900, y = 1060, w = 800, h = 600 }, { A }), false, "a corner showing")
    t.eq(park.hidden({ x = 5000, y = 5000, w = 800, h = 600 }, { A }), true, "off every display")
    t.eq(park.hidden(nil, { A }), false, "no frame")
end)

t.done("park")
